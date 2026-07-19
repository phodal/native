//! Standalone SVG export for a Native SDK canvas scene.
//!
//! Vector mode keeps geometry, nested rounded clips, transforms, opacity,
//! gradients, image resources, and TrueType glyph outlines editable. Some
//! canvas effects have no faithful portable SVG equivalent; auto mode uses
//! the deterministic reference renderer for scenes containing backdrop blur
//! and embeds that result as a PNG inside the SVG document.

const std = @import("std");
const geometry = @import("geometry");
const canvas = @import("root.zig");

pub const Error = error{
    InvalidSceneSize,
    InvalidImageResource,
    MissingImageResource,
    UnsupportedVectorEffect,
};

pub const RenderMode = enum {
    /// Prefer editable vector output and switch to the reference renderer
    /// only for effects that SVG cannot represent faithfully.
    auto,
    /// Require editable vector output. Unsupported effects fail loudly.
    vector,
    /// Render the complete display list with the deterministic CPU renderer
    /// and embed its RGBA result as a PNG in the SVG document.
    reference_raster,
};

pub const MissingImagePolicy = enum {
    /// A display-list image without a deterministic resource is an error.
    fail,
    /// Omit absent and presentation-only images deliberately.
    omit,
};

/// Resources borrowed by a scene. These are the same deterministic image and
/// parsed-font types consumed by `CanvasFrame` and `ReferenceRenderSurface`,
/// so runtimes do not need a second export-only registry.
pub const Resources = struct {
    images: []const canvas.ReferenceImage = &.{},
    fonts: []const canvas.ReferenceFont = &.{},
};

/// App-neutral export boundary. Any Native SDK app that can produce a
/// `DisplayList` can construct this value; `fromFrame` is the zero-copy path
/// for retained runtimes.
pub const Scene = struct {
    display_list: canvas.DisplayList,
    size: geometry.SizeF,
    resources: Resources = .{},

    pub fn fromFrame(frame: *const canvas.CanvasFrame) Scene {
        return .{
            .display_list = frame.display_list,
            .size = frame.surface_size,
            .resources = .{
                .images = frame.image_resources,
                .fonts = frame.font_resources,
            },
        };
    }
};

pub const Options = struct {
    mode: RenderMode = .auto,
    missing_images: MissingImagePolicy = .fail,
    background: ?canvas.Color = null,
    title: []const u8 = "Native SDK interface",
    description: []const u8 = "Rendered from a Native SDK display list.",
};

pub fn write(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    scene: Scene,
    options: Options,
) !void {
    try validateScene(scene, options);
    const mode: RenderMode = switch (options.mode) {
        .auto => if (containsBackdropBlur(scene.display_list)) .reference_raster else .vector,
        else => options.mode,
    };
    switch (mode) {
        .auto => unreachable,
        .vector => try writeVector(allocator, writer, scene, options),
        .reference_raster => try writeReferenceRaster(allocator, writer, scene, options),
    }
}

fn validateScene(scene: Scene, options: Options) !void {
    if (!std.math.isFinite(scene.size.width) or !std.math.isFinite(scene.size.height) or
        scene.size.width <= 0 or scene.size.height <= 0)
    {
        return error.InvalidSceneSize;
    }
    if (options.mode == .vector and containsBackdropBlur(scene.display_list)) {
        return error.UnsupportedVectorEffect;
    }

    var clip_depth: usize = 0;
    var opacity_depth: usize = 0;
    for (scene.display_list.commands) |command| switch (command) {
        .push_clip => {
            if (clip_depth >= canvas.max_render_state_stack) return error.RenderStackOverflow;
            clip_depth += 1;
        },
        .pop_clip => {
            if (clip_depth == 0) return error.RenderStackUnderflow;
            clip_depth -= 1;
        },
        .push_opacity => {
            if (opacity_depth >= canvas.max_render_state_stack) return error.RenderStackOverflow;
            opacity_depth += 1;
        },
        .pop_opacity => {
            if (opacity_depth == 0) return error.RenderStackUnderflow;
            opacity_depth -= 1;
        },
        .draw_image => |image| {
            const resource = findImage(scene.resources.images, image.image_id);
            if (resource == null) {
                if (options.missing_images == .fail) return error.MissingImageResource;
            } else {
                _ = try canvas.png.pixelByteLen(resource.?.width, resource.?.height);
                if (resource.?.pixels.len < resource.?.width * resource.?.height * 4) {
                    return error.InvalidImageResource;
                }
            }
        },
        else => {},
    };
}

fn containsBackdropBlur(display_list: canvas.DisplayList) bool {
    for (display_list.commands) |command| switch (command) {
        .blur => |blur| if (blur.radius > 0) return true,
        else => {},
    };
    return false;
}

fn writeVector(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    scene: Scene,
    options: Options,
) !void {
    try writeDocumentOpen(writer, scene, options);
    try writeDefs(allocator, writer, scene);
    if (options.background) |background| {
        try writer.print("  <rect width=\"{d}\" height=\"{d}\" ", .{ scene.size.width, scene.size.height });
        try writeColorAttribute(writer, "fill", background);
        try writer.writeAll("/>\n");
    }

    var transform = canvas.Affine.identity();
    var opacity: f32 = 1;
    var clip_ids: [canvas.max_render_state_stack]usize = undefined;
    var clip_len: usize = 0;
    var opacity_stack: [canvas.max_render_state_stack]f32 = undefined;
    var opacity_len: usize = 0;

    for (scene.display_list.commands, 0..) |command, index| switch (command) {
        .push_clip => {
            clip_ids[clip_len] = index;
            clip_len += 1;
        },
        .pop_clip => clip_len -= 1,
        .push_opacity => |value| {
            opacity_stack[opacity_len] = opacity;
            opacity_len += 1;
            opacity *= std.math.clamp(value, 0, 1);
        },
        .pop_opacity => {
            opacity_len -= 1;
            opacity = opacity_stack[opacity_len];
        },
        .transform => |value| transform = transform.multiply(value),
        else => try writeVectorCommand(
            allocator,
            writer,
            command,
            index,
            transform,
            opacity,
            clip_ids[0..clip_len],
            scene.resources,
            options.missing_images,
        ),
    };
    try writer.writeAll("</svg>\n");
}

fn writeReferenceRaster(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    scene: Scene,
    options: Options,
) !void {
    const width = try rasterExtent(scene.size.width);
    const height = try rasterExtent(scene.size.height);
    const pixel_len = try canvas.png.pixelByteLen(width, height);
    const pixels = try allocator.alloc(u8, pixel_len);
    defer allocator.free(pixels);
    const scratch = try allocator.alloc(u8, pixel_len);
    defer allocator.free(scratch);

    const render_commands = try allocator.alloc(canvas.RenderCommand, scene.display_list.commands.len);
    defer allocator.free(render_commands);
    const plan = try scene.display_list.renderPlan(render_commands);
    var surface = try canvas.ReferenceRenderSurface.initWithScratch(width, height, pixels, scratch);
    surface = surface.withImages(scene.resources.images).withFonts(scene.resources.fonts);
    try surface.renderPass(.{
        .surface_size = scene.size,
        .scale = 1,
        .full_repaint = true,
        .commands = plan.commands,
    }, options.background orelse canvas.Color.rgba(0, 0, 0, 0));

    const png_len = try canvas.png.encodedRgba8ByteLen(width, height);
    const encoded = try allocator.alloc(u8, png_len);
    defer allocator.free(encoded);
    var png_writer = std.Io.Writer.fixed(encoded);
    try canvas.png.writeRgba8(&png_writer, width, height, pixels);

    try writeDocumentOpen(writer, scene, options);
    try writer.print(
        "  <image x=\"0\" y=\"0\" width=\"{d}\" height=\"{d}\" preserveAspectRatio=\"none\" href=\"data:image/png;base64,",
        .{ scene.size.width, scene.size.height },
    );
    try writeBase64(writer, png_writer.buffered());
    try writer.writeAll("\"/>\n</svg>\n");
}

fn rasterExtent(value: f32) Error!usize {
    const rounded: f64 = @ceil(@as(f64, value));
    // f32 values can be much larger than usize. Check in f64 before the
    // integer conversion so a hostile or accidentally huge raster scene
    // returns a protocol error instead of trapping.
    if (rounded <= 0 or rounded >= @as(f64, @floatFromInt(std.math.maxInt(usize)))) return error.InvalidSceneSize;
    return @intFromFloat(rounded);
}

fn writeDocumentOpen(writer: *std.Io.Writer, scene: Scene, options: Options) !void {
    try writer.print(
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{d}\" height=\"{d}\" viewBox=\"0 0 {d} {d}\" role=\"img\" aria-labelledby=\"native-svg-title native-svg-description\" shape-rendering=\"geometricPrecision\">\n",
        .{ scene.size.width, scene.size.height, scene.size.width, scene.size.height },
    );
    try writer.writeAll("  <title id=\"native-svg-title\">");
    try writeXmlText(writer, options.title);
    try writer.writeAll("</title>\n  <desc id=\"native-svg-description\">");
    try writeXmlText(writer, options.description);
    try writer.writeAll("</desc>\n  <!-- Generated from a Native SDK canvas scene. Do not edit by hand. -->\n");
}

fn writeDefs(allocator: std.mem.Allocator, writer: *std.Io.Writer, scene: Scene) !void {
    try writer.writeAll("  <defs>\n");
    for (scene.resources.images, 0..) |image, image_index| {
        if (image.presentation_only or firstImageIndex(scene.resources.images, image.id) != image_index or
            !displayListUsesImage(scene.display_list, image.id)) continue;
        const png_len = try canvas.png.encodedRgba8ByteLen(image.width, image.height);
        const encoded = try allocator.alloc(u8, png_len);
        defer allocator.free(encoded);
        var png_writer = std.Io.Writer.fixed(encoded);
        try canvas.png.writeRgba8(&png_writer, image.width, image.height, image.pixels);
        try writer.print(
            "    <image id=\"native-image-{d}\" width=\"{d}\" height=\"{d}\" href=\"data:image/png;base64,",
            .{ image.id, image.width, image.height },
        );
        try writeBase64(writer, png_writer.buffered());
        try writer.writeAll("\"/>\n");
    }

    var transform = canvas.Affine.identity();
    for (scene.display_list.commands, 0..) |command, index| {
        switch (command) {
            .transform => |value| transform = transform.multiply(value),
            .push_clip => |clip| {
                try writer.print("    <clipPath id=\"clip-{d}\" clipPathUnits=\"userSpaceOnUse\"><path d=\"", .{index});
                try writeRoundedRectPath(writer, clip.rect, clip.radius);
                try writer.writeAll("\"");
                if (!isIdentity(transform)) try writeTransformAttribute(writer, transform);
                try writer.writeAll("/></clipPath>\n");
            },
            .draw_image => |image| if (hasRadius(image.radius)) {
                try writer.print("    <clipPath id=\"image-clip-{d}\" clipPathUnits=\"userSpaceOnUse\"><path d=\"", .{index});
                try writeRoundedRectPath(writer, image.dst, image.radius);
                try writer.writeAll("\"/></clipPath>\n");
            },
            .shadow => |shadow| {
                const bounds = command.bounds().?.normalized();
                try writer.print(
                    "    <filter id=\"shadow-{d}\" filterUnits=\"userSpaceOnUse\" x=\"{d}\" y=\"{d}\" width=\"{d}\" height=\"{d}\" color-interpolation-filters=\"sRGB\"><feGaussianBlur stdDeviation=\"{d}\"/></filter>\n",
                    .{ index, bounds.x, bounds.y, bounds.width, bounds.height, @max(0, shadow.blur * 0.5) },
                );
            },
            else => {},
        }
        if (commandGradient(command)) |gradient| {
            try writer.print(
                "    <linearGradient id=\"gradient-{d}\" gradientUnits=\"userSpaceOnUse\" x1=\"{d}\" y1=\"{d}\" x2=\"{d}\" y2=\"{d}\">\n",
                .{ index, gradient.start.x, gradient.start.y, gradient.end.x, gradient.end.y },
            );
            for (gradient.stops) |stop| {
                try writer.print("      <stop offset=\"{d}\" ", .{std.math.clamp(stop.offset, 0, 1)});
                try writeColorAttribute(writer, "stop-color", stop.color);
                try writer.writeAll("/>\n");
            }
            try writer.writeAll("    </linearGradient>\n");
        }
    }
    try writer.writeAll("  </defs>\n");
}

fn writeVectorCommand(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    command: canvas.CanvasCommand,
    index: usize,
    transform: canvas.Affine,
    opacity: f32,
    clip_ids: []const usize,
    resources: Resources,
    missing_images: MissingImagePolicy,
) !void {
    for (clip_ids) |clip_id| try writer.print("  <g clip-path=\"url(#clip-{d})\">", .{clip_id});
    try writer.writeAll("  <g");
    if (opacity < 1) try writer.print(" opacity=\"{d}\"", .{std.math.clamp(opacity, 0, 1)});
    if (!isIdentity(transform)) try writeTransformAttribute(writer, transform);
    try writer.writeAll(">");

    switch (command) {
        .fill_rect => |value| {
            const rect = value.rect.normalized();
            try writer.print("<rect x=\"{d}\" y=\"{d}\" width=\"{d}\" height=\"{d}\" ", .{ rect.x, rect.y, rect.width, rect.height });
            try writePaintAttribute(writer, "fill", value.fill, index);
            try writer.writeAll("/>");
        },
        .stroke_rect => |value| {
            try writer.writeAll("<path d=\"");
            try writeRoundedRectPath(writer, value.rect, value.radius);
            try writer.writeAll("\" fill=\"none\" ");
            try writeStrokeAttributes(writer, value.stroke, index, .butt);
            try writer.writeAll("/>");
        },
        .fill_rounded_rect => |value| {
            try writer.writeAll("<path d=\"");
            try writeRoundedRectPath(writer, value.rect, value.radius);
            try writer.writeAll("\" ");
            try writePaintAttribute(writer, "fill", value.fill, index);
            try writer.writeAll("/>");
        },
        .draw_line => |value| {
            try writer.print("<line x1=\"{d}\" y1=\"{d}\" x2=\"{d}\" y2=\"{d}\" ", .{ value.from.x, value.from.y, value.to.x, value.to.y });
            try writeStrokeAttributes(writer, value.stroke, index, .butt);
            try writer.writeAll("/>");
        },
        .fill_path => |value| {
            try writer.writeAll("<path d=\"");
            try writePathData(writer, value.elements);
            try writer.writeAll("\" ");
            try writePaintAttribute(writer, "fill", value.fill, index);
            try writer.writeAll("/>");
        },
        .stroke_path => |value| {
            try writer.writeAll("<path d=\"");
            try writePathData(writer, value.elements);
            try writer.writeAll("\" fill=\"none\" ");
            try writeStrokeAttributes(writer, value.stroke, index, value.cap);
            try writer.writeAll("/>");
        },
        .draw_text => |value| try writeText(allocator, writer, value, resources.fonts),
        .draw_image => |value| try writeImage(writer, value, index, resources.images, missing_images),
        .shadow => |value| {
            var rect = value.rect.normalized();
            const spread = @max(0, @abs(value.spread));
            rect.x += value.offset.dx - spread;
            rect.y += value.offset.dy - spread;
            rect.width += spread * 2;
            rect.height += spread * 2;
            try writer.writeAll("<path d=\"");
            try writeRoundedRectPath(writer, rect, value.radius);
            try writer.print("\" filter=\"url(#shadow-{d})\" ", .{index});
            try writeColorAttribute(writer, "fill", value.color);
            try writer.writeAll("/>");
        },
        .blur => return error.UnsupportedVectorEffect,
        .push_clip, .pop_clip, .push_opacity, .pop_opacity, .transform => unreachable,
    }

    try writer.writeAll("</g>");
    for (clip_ids) |_| try writer.writeAll("</g>");
    try writer.writeByte('\n');
}

fn writeImage(
    writer: *std.Io.Writer,
    value: canvas.DrawImage,
    index: usize,
    images: []const canvas.ReferenceImage,
    missing_images: MissingImagePolicy,
) !void {
    const image = findImage(images, value.image_id) orelse {
        if (missing_images == .fail) return error.MissingImageResource;
        try writer.print("<!-- omitted Native SDK image {d} -->", .{value.image_id});
        return;
    };
    const src = imageSourceRect(image, value.src) orelse return;
    const dst = value.dst.normalized();
    if (dst.isEmpty()) return;
    if (hasRadius(value.radius)) try writer.print("<g clip-path=\"url(#image-clip-{d})\">", .{index});
    try writer.print(
        "<svg x=\"{d}\" y=\"{d}\" width=\"{d}\" height=\"{d}\" viewBox=\"{d} {d} {d} {d}\" preserveAspectRatio=\"{s}\" overflow=\"hidden\" opacity=\"{d}\">",
        .{ dst.x, dst.y, dst.width, dst.height, src.x, src.y, src.width, src.height, imagePreserveAspectRatio(value.fit), std.math.clamp(value.opacity, 0, 1) },
    );
    try writer.print(
        "<use href=\"#native-image-{d}\" image-rendering=\"{s}\"/></svg>",
        .{ value.image_id, if (value.sampling == .nearest) "pixelated" else "auto" },
    );
    if (hasRadius(value.radius)) try writer.writeAll("</g>");
}

fn writeText(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    value: canvas.DrawText,
    fonts: []const canvas.ReferenceFont,
) !void {
    const line_capacity = @max(@as(usize, 1), value.text.len + value.glyphs.len + 1);
    const lines = try allocator.alloc(canvas.TextLine, line_capacity);
    defer allocator.free(lines);

    const layout = if (value.text_layout) |options|
        try canvas.layoutTextRun(value, options, lines)
    else blk: {
        const line_height = value.size * 1.25;
        lines[0] = .{
            .text_start = 0,
            .text_len = value.text.len,
            .glyph_start = 0,
            .glyph_len = value.glyphs.len,
            .bounds = .init(value.origin.x, value.origin.y - value.size, canvas.estimateTextWidthForFont(value.font_id, value.text, value.size), line_height),
            .baseline = value.origin.y,
        };
        break :blk canvas.TextLayout{ .lines = lines[0..1], .bounds = lines[0].bounds };
    };

    try writer.writeAll("<path d=\"");
    for (layout.lines) |line| try writeTextLine(writer, value, line, fonts);
    try writer.writeAll("\" ");
    try writeColorAttribute(writer, "fill", value.color);
    try writer.writeAll(" fill-rule=\"nonzero\"/>");
}

fn writeTextLine(
    writer: *std.Io.Writer,
    value: canvas.DrawText,
    line: canvas.TextLine,
    fonts: []const canvas.ReferenceFont,
) !void {
    if (line.glyph_len > 0 and line.glyph_start < value.glyphs.len) {
        const glyph_end = @min(value.glyphs.len, line.glyph_start + line.paintedGlyphLen());
        const first_x = value.glyphs[line.glyph_start].x;
        for (value.glyphs[line.glyph_start..glyph_end]) |glyph| {
            const start = @min(value.text.len, glyph.text_start);
            const end = @min(value.text.len, start + glyph.text_len);
            const bytes = value.text[start..end];
            const font_id = if (glyph.font_id == 0) value.font_id else glyph.font_id;
            const advance = if (glyph.advance > 0) glyph.advance else canvas.estimateTextAdvanceForBytes(font_id, bytes, value.size);
            try writeGlyph(writer, fonts, font_id, value.size, bytes, glyph.id, line.bounds.x + glyph.x - first_x, line.baseline + glyph.y, advance);
        }
    } else {
        const end = @min(value.text.len, line.text_start + line.paintedTextLen());
        var offset = @min(line.text_start, end);
        var x = line.bounds.x;
        while (offset < end) {
            const byte_len = @min(canvas.utf8SequenceLength(value.text[offset]), end - offset);
            const next = offset + byte_len;
            const bytes = value.text[offset..next];
            const advance = canvas.estimateTextAdvanceForBytes(value.font_id, bytes, value.size);
            try writeGlyph(writer, fonts, value.font_id, value.size, bytes, 0, x, line.baseline, advance);
            offset = next;
            x += advance;
        }
    }

    if (line.hasEllipsis()) {
        try writeGlyph(
            writer,
            fonts,
            value.font_id,
            value.size,
            canvas.text_ellipsis,
            0,
            line.bounds.x + line.bounds.width - line.ellipsis_advance,
            line.baseline,
            line.ellipsis_advance,
        );
    }
}

const glyph_path_capacity = @max(
    canvas.font_ttf.max_glyph_points + 3 * canvas.font_ttf.max_glyph_contours,
    canvas.font_ttf.max_composite_points + 3 * canvas.font_ttf.max_composite_contours,
);

fn writeGlyph(
    writer: *std.Io.Writer,
    fonts: []const canvas.ReferenceFont,
    font_id: canvas.FontId,
    size: f32,
    bytes: []const u8,
    explicit_glyph: u32,
    pen_x: f32,
    baseline: f32,
    cell_advance: f32,
) !void {
    const face = faceForFontId(fonts, font_id);
    const codepoint: ?u21 = if (bytes.len > 0) std.unicode.utf8Decode(bytes) catch null else null;
    const glyph: u16 = if (explicit_glyph > 0 and explicit_glyph <= std.math.maxInt(u16))
        @intCast(explicit_glyph)
    else if (codepoint) |value|
        face.glyphIndex(value)
    else
        0;
    if (glyph == 0) {
        try writeRectPath(writer, pen_x, baseline - size, cell_advance, size);
        return;
    }

    const natural_advance = size * (face.advance(glyph) / face.units_per_em);
    const inset = @max(0, (cell_advance - natural_advance) * 0.5);
    const scale = size / face.units_per_em;
    const transform = canvas.Affine{ .a = scale, .d = -scale, .tx = pen_x + inset, .ty = baseline };
    var path = canvas.vector.PathBuilder(glyph_path_capacity){};
    face.glyphOutline(glyph, transform, &path) catch {
        try writeRectPath(writer, pen_x, baseline - size, cell_advance, size);
        return;
    };
    try writePathData(writer, path.slice());
}

fn writePathData(writer: *std.Io.Writer, elements: []const canvas.PathElement) !void {
    for (elements) |element| switch (element.verb) {
        .move_to => try writer.print("M{d} {d}", .{ element.points[0].x, element.points[0].y }),
        .line_to => try writer.print("L{d} {d}", .{ element.points[0].x, element.points[0].y }),
        .quad_to => try writer.print("Q{d} {d} {d} {d}", .{ element.points[0].x, element.points[0].y, element.points[1].x, element.points[1].y }),
        .cubic_to => try writer.print("C{d} {d} {d} {d} {d} {d}", .{ element.points[0].x, element.points[0].y, element.points[1].x, element.points[1].y, element.points[2].x, element.points[2].y }),
        .close => try writer.writeByte('Z'),
    };
}

fn writeRoundedRectPath(writer: *std.Io.Writer, rect_value: geometry.RectF, radius: canvas.Radius) !void {
    const rect = rect_value.normalized();
    const max_radius = @max(0, @min(rect.width, rect.height) * 0.5);
    const tl = std.math.clamp(radius.top_left, 0, max_radius);
    const tr = std.math.clamp(radius.top_right, 0, max_radius);
    const br = std.math.clamp(radius.bottom_right, 0, max_radius);
    const bl = std.math.clamp(radius.bottom_left, 0, max_radius);
    const right = rect.x + rect.width;
    const bottom = rect.y + rect.height;
    try writer.print("M{d} {d}H{d}", .{ rect.x + tl, rect.y, right - tr });
    if (tr > 0) try writer.print("A{d} {d} 0 0 1 {d} {d}", .{ tr, tr, right, rect.y + tr });
    try writer.print("V{d}", .{bottom - br});
    if (br > 0) try writer.print("A{d} {d} 0 0 1 {d} {d}", .{ br, br, right - br, bottom });
    try writer.print("H{d}", .{rect.x + bl});
    if (bl > 0) try writer.print("A{d} {d} 0 0 1 {d} {d}", .{ bl, bl, rect.x, bottom - bl });
    try writer.print("V{d}", .{rect.y + tl});
    if (tl > 0) try writer.print("A{d} {d} 0 0 1 {d} {d}", .{ tl, tl, rect.x + tl, rect.y });
    try writer.writeByte('Z');
}

fn writeRectPath(writer: *std.Io.Writer, x: f32, y: f32, width: f32, height: f32) !void {
    try writer.print("M{d} {d}H{d}V{d}H{d}Z", .{ x, y, x + width, y + height, x });
}

fn writeStrokeAttributes(writer: *std.Io.Writer, stroke: canvas.Stroke, gradient_id: usize, cap: canvas.LineCap) !void {
    try writePaintAttribute(writer, "stroke", stroke.fill, gradient_id);
    try writer.print("stroke-width=\"{d}\" stroke-linecap=\"{s}\" ", .{ @max(0, stroke.width), @tagName(cap) });
}

fn writePaintAttribute(writer: *std.Io.Writer, comptime name: []const u8, fill: canvas.Fill, gradient_id: usize) !void {
    switch (fill) {
        .color => |color| try writeColorAttribute(writer, name, color),
        .linear_gradient => try writer.print("{s}=\"url(#gradient-{d})\" ", .{ name, gradient_id }),
    }
}

fn writeColorAttribute(writer: *std.Io.Writer, comptime name: []const u8, color: canvas.Color) !void {
    try writer.print(
        "{s}=\"rgb({d},{d},{d})\" {s}-opacity=\"{d}\" ",
        .{ name, colorChannel(color.r), colorChannel(color.g), colorChannel(color.b), name, std.math.clamp(color.a, 0, 1) },
    );
}

fn writeTransformAttribute(writer: *std.Io.Writer, value: canvas.Affine) !void {
    try writer.print(
        " transform=\"matrix({d} {d} {d} {d} {d} {d})\"",
        .{ value.a, value.b, value.c, value.d, value.tx, value.ty },
    );
}

fn colorChannel(value: f32) u8 {
    return @intFromFloat(@round(std.math.clamp(value, 0, 1) * 255));
}

fn commandGradient(command: canvas.CanvasCommand) ?canvas.LinearGradient {
    const fill: ?canvas.Fill = switch (command) {
        .fill_rect => |value| value.fill,
        .stroke_rect => |value| value.stroke.fill,
        .fill_rounded_rect => |value| value.fill,
        .draw_line => |value| value.stroke.fill,
        .fill_path => |value| value.fill,
        .stroke_path => |value| value.stroke.fill,
        else => null,
    };
    if (fill) |value| return switch (value) {
        .color => null,
        .linear_gradient => |gradient| gradient,
    };
    return null;
}

fn faceForFontId(fonts: []const canvas.ReferenceFont, font_id: canvas.FontId) *const canvas.font_ttf.Face {
    for (fonts) |font| if (font.id == font_id) return font.face;
    if (font_id == canvas.default_mono_font_id) return &canvas.font_ttf.geist_mono;
    return &canvas.font_ttf.geist_regular;
}

fn findImage(images: []const canvas.ReferenceImage, id: canvas.ImageId) ?canvas.ReferenceImage {
    for (images) |image| {
        if (image.presentation_only) continue;
        if (image.id == id) return image;
    }
    return null;
}

fn firstImageIndex(images: []const canvas.ReferenceImage, id: canvas.ImageId) usize {
    for (images, 0..) |image, index| {
        if (!image.presentation_only and image.id == id) return index;
    }
    return images.len;
}

fn displayListUsesImage(display_list: canvas.DisplayList, id: canvas.ImageId) bool {
    for (display_list.commands) |command| switch (command) {
        .draw_image => |image| if (image.image_id == id) return true,
        else => {},
    };
    return false;
}

fn imageSourceRect(image: canvas.ReferenceImage, requested: ?geometry.RectF) ?geometry.RectF {
    const full = geometry.RectF.init(0, 0, @floatFromInt(image.width), @floatFromInt(image.height));
    const clipped = geometry.RectF.intersection(if (requested) |value| value.normalized() else full, full);
    return if (clipped.isEmpty()) null else clipped;
}

fn imagePreserveAspectRatio(fit: canvas.ImageFit) []const u8 {
    return switch (fit) {
        .stretch => "none",
        .contain => "xMidYMid meet",
        .cover => "xMidYMid slice",
    };
}

fn hasRadius(radius: canvas.Radius) bool {
    return radius.top_left > 0 or radius.top_right > 0 or radius.bottom_right > 0 or radius.bottom_left > 0;
}

fn isIdentity(value: canvas.Affine) bool {
    return value.a == 1 and value.b == 0 and value.c == 0 and value.d == 1 and value.tx == 0 and value.ty == 0;
}

fn writeBase64(writer: *std.Io.Writer, bytes: []const u8) !void {
    const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    var index: usize = 0;
    while (index + 3 <= bytes.len) : (index += 3) {
        const value = (@as(u24, bytes[index]) << 16) | (@as(u24, bytes[index + 1]) << 8) | bytes[index + 2];
        try writer.writeByte(alphabet[@intCast((value >> 18) & 0x3f)]);
        try writer.writeByte(alphabet[@intCast((value >> 12) & 0x3f)]);
        try writer.writeByte(alphabet[@intCast((value >> 6) & 0x3f)]);
        try writer.writeByte(alphabet[@intCast(value & 0x3f)]);
    }
    const remaining = bytes.len - index;
    if (remaining == 1) {
        const value = @as(u16, bytes[index]) << 8;
        try writer.writeByte(alphabet[@intCast((value >> 10) & 0x3f)]);
        try writer.writeByte(alphabet[@intCast((value >> 4) & 0x3f)]);
        try writer.writeAll("==");
    } else if (remaining == 2) {
        const value = (@as(u24, bytes[index]) << 16) | (@as(u24, bytes[index + 1]) << 8);
        try writer.writeByte(alphabet[@intCast((value >> 18) & 0x3f)]);
        try writer.writeByte(alphabet[@intCast((value >> 12) & 0x3f)]);
        try writer.writeByte(alphabet[@intCast((value >> 6) & 0x3f)]);
        try writer.writeByte('=');
    }
}

fn writeXmlText(writer: *std.Io.Writer, value: []const u8) !void {
    for (value) |byte| switch (byte) {
        '&' => try writer.writeAll("&amp;"),
        '<' => try writer.writeAll("&lt;"),
        '>' => try writer.writeAll("&gt;"),
        else => try writer.writeByte(byte),
    };
}
