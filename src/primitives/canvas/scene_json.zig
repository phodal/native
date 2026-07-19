//! Stable, app-neutral JSON boundary for Native SDK canvas scenes.
//!
//! The format owns the display list plus every deterministic resource needed
//! to replay it. It is deliberately independent from any application model or
//! platform host so build tools, other languages, and future exporters can all
//! exchange the same versioned document.

const std = @import("std");
const geometry = @import("geometry");
const json = @import("json");
const canvas = @import("root.zig");

pub const schema_name = "native.canvas.scene";
pub const schema_version: u32 = 1;

pub const max_commands: usize = 65_536;
pub const max_path_elements: usize = 262_144;
pub const max_gradient_stops: usize = 16_384;
pub const max_glyphs: usize = 262_144;
pub const max_resources: usize = 4_096;
pub const max_resource_bytes: usize = 64 * 1024 * 1024;

pub const Error = error{
    InvalidSceneJson,
    UnsupportedSceneSchema,
    UnsupportedSceneVersion,
    InvalidSceneValue,
    InvalidSceneResource,
    SceneTooComplex,
};

/// Parsed document. All slices and resource pointers borrow memory from the
/// allocator passed to `parse`; an arena is the natural owner for one render.
pub const Document = struct {
    scene: canvas.SvgScene,
    background: ?canvas.Color = null,
    title: []const u8 = "Native SDK interface",
    description: []const u8 = "Rendered from a Native SDK canvas scene.",

    pub fn svgOptions(self: Document) canvas.SvgOptions {
        return .{
            .background = self.background,
            .title = self.title,
            .description = self.description,
        };
    }
};

const Budget = struct {
    path_elements: usize = 0,
    gradient_stops: usize = 0,
    glyphs: usize = 0,
    resource_bytes: usize = 0,

    fn consume(counter: *usize, amount: usize, limit: usize) Error!void {
        counter.* = std.math.add(usize, counter.*, amount) catch return error.SceneTooComplex;
        if (counter.* > limit) return error.SceneTooComplex;
    }
};

pub fn parse(allocator: std.mem.Allocator, source: []const u8) !Document {
    const root = std.json.parseFromSliceLeaky(std.json.Value, allocator, source, .{}) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => return error.InvalidSceneJson,
    };
    if (root != .object) return error.InvalidSceneValue;

    const schema = try string(try required(root, "schema"));
    if (!std.mem.eql(u8, schema, schema_name)) return error.UnsupportedSceneSchema;
    const version = try unsigned(u32, try required(root, "version"));
    if (version != schema_version) return error.UnsupportedSceneVersion;

    const width = try number(try required(root, "width"));
    const height = try number(try required(root, "height"));
    if (width <= 0 or height <= 0) return error.InvalidSceneValue;

    var budget: Budget = .{};
    const display_list_value = try required(root, "displayList");
    const commands_value = try required(display_list_value, "commands");
    const command_items = try array(commands_value);
    if (command_items.len > max_commands) return error.SceneTooComplex;
    const commands = try allocator.alloc(canvas.CanvasCommand, command_items.len);
    for (command_items, 0..) |command, index| {
        commands[index] = try parseCommand(allocator, command, &budget);
    }

    var images: []const canvas.ReferenceImage = &.{};
    var fonts: []const canvas.ReferenceFont = &.{};
    if (member(root, "resources")) |resources| {
        if (resources != .object) return error.InvalidSceneValue;
        if (member(resources, "images")) |value| images = try parseImages(allocator, value, &budget);
        if (member(resources, "fonts")) |value| fonts = try parseFonts(allocator, value, &budget);
    }

    const background: ?canvas.Color = if (member(root, "background")) |value|
        if (value == .null) null else try parseColor(value)
    else
        null;
    const title = if (member(root, "title")) |value| try string(value) else "Native SDK interface";
    const description = if (member(root, "description")) |value| try string(value) else "Rendered from a Native SDK canvas scene.";

    return .{
        .scene = .{
            .display_list = .{ .commands = commands },
            .size = geometry.SizeF.init(width, height),
            .resources = .{ .images = images, .fonts = fonts },
        },
        .background = background,
        .title = title,
        .description = description,
    };
}

pub fn write(writer: *std.Io.Writer, document: Document) !void {
    try writer.writeAll("{\"schema\":");
    try json.writeString(writer, schema_name);
    try writer.print(",\"version\":{d},\"width\":{d},\"height\":{d},\"background\":", .{
        schema_version,
        document.scene.size.width,
        document.scene.size.height,
    });
    if (document.background) |background| {
        try writeColor(writer, background);
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"title\":");
    try json.writeString(writer, document.title);
    try writer.writeAll(",\"description\":");
    try json.writeString(writer, document.description);
    try writer.writeAll(",\"displayList\":");
    try document.scene.display_list.writeJson(writer);
    try writer.writeAll(",\"resources\":{\"images\":[");
    for (document.scene.resources.images, 0..) |image, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.print("{{\"id\":{d},\"width\":{d},\"height\":{d},\"contentFingerprint\":{d},\"presentationOnly\":{s},\"rgbaBase64\":\"", .{
            image.id,
            image.width,
            image.height,
            image.content_fingerprint,
            if (image.presentation_only) "true" else "false",
        });
        try std.base64.standard.Encoder.encodeWriter(writer, image.pixels);
        try writer.writeAll("\"}");
    }
    try writer.writeAll("],\"fonts\":[");
    for (document.scene.resources.fonts, 0..) |font, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.print("{{\"id\":{d},\"ttfBase64\":\"", .{font.id});
        try std.base64.standard.Encoder.encodeWriter(writer, font.face.bytes);
        try writer.writeAll("\"}");
    }
    try writer.writeAll("]}}");
}

fn parseImages(allocator: std.mem.Allocator, value: std.json.Value, budget: *Budget) ![]const canvas.ReferenceImage {
    const items = try array(value);
    if (items.len > max_resources) return error.SceneTooComplex;
    const images = try allocator.alloc(canvas.ReferenceImage, items.len);
    for (items, 0..) |item, index| {
        if (item != .object) return error.InvalidSceneResource;
        const id = try unsigned(canvas.ImageId, try required(item, "id"));
        for (images[0..index]) |existing| if (existing.id == id) return error.InvalidSceneResource;
        const width = try unsigned(usize, try required(item, "width"));
        const height = try unsigned(usize, try required(item, "height"));
        if (width == 0 or height == 0) return error.InvalidSceneResource;
        const pixel_count = std.math.mul(usize, width, height) catch return error.InvalidSceneResource;
        const expected_len = std.math.mul(usize, pixel_count, 4) catch return error.InvalidSceneResource;
        const encoded = try string(try required(item, "rgbaBase64"));
        const pixels = try decodeBase64(allocator, encoded, budget);
        if (pixels.len != expected_len) return error.InvalidSceneResource;
        images[index] = .{
            .id = id,
            .width = width,
            .height = height,
            .pixels = pixels,
            .content_fingerprint = if (member(item, "contentFingerprint")) |field| try unsigned(u64, field) else 0,
            .presentation_only = if (member(item, "presentationOnly")) |field| try boolean(field) else false,
        };
    }
    return images;
}

fn parseFonts(allocator: std.mem.Allocator, value: std.json.Value, budget: *Budget) ![]const canvas.ReferenceFont {
    const items = try array(value);
    if (items.len > max_resources) return error.SceneTooComplex;
    const fonts = try allocator.alloc(canvas.ReferenceFont, items.len);
    for (items, 0..) |item, index| {
        if (item != .object) return error.InvalidSceneResource;
        const id = try unsigned(canvas.FontId, try required(item, "id"));
        for (fonts[0..index]) |existing| if (existing.id == id) return error.InvalidSceneResource;
        const encoded = try string(try required(item, "ttfBase64"));
        const bytes = try decodeBase64(allocator, encoded, budget);
        const face = try allocator.create(canvas.font_ttf.Face);
        face.* = canvas.font_ttf.Face.parse(bytes) catch return error.InvalidSceneResource;
        fonts[index] = .{ .id = id, .face = face };
    }
    return fonts;
}

fn decodeBase64(allocator: std.mem.Allocator, encoded: []const u8, budget: *Budget) ![]u8 {
    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(encoded) catch return error.InvalidSceneResource;
    try Budget.consume(&budget.resource_bytes, decoded_len, max_resource_bytes);
    const decoded = try allocator.alloc(u8, decoded_len);
    std.base64.standard.Decoder.decode(decoded, encoded) catch return error.InvalidSceneResource;
    return decoded;
}

fn parseCommand(allocator: std.mem.Allocator, value: std.json.Value, budget: *Budget) !canvas.CanvasCommand {
    if (value != .object) return error.InvalidSceneValue;
    const op = try string(try required(value, "op"));
    if (std.mem.eql(u8, op, "push_clip")) return .{ .push_clip = .{
        .id = try optionalUnsigned(canvas.ObjectId, value, "id", 0),
        .rect = try parseRect(try required(value, "rect")),
        .radius = try parseRadius(try required(value, "radius")),
    } };
    if (std.mem.eql(u8, op, "pop_clip")) return .pop_clip;
    if (std.mem.eql(u8, op, "push_opacity")) return .{ .push_opacity = try number(try required(value, "opacity")) };
    if (std.mem.eql(u8, op, "pop_opacity")) return .pop_opacity;
    if (std.mem.eql(u8, op, "transform")) return .{ .transform = try parseAffine(try required(value, "matrix")) };
    if (std.mem.eql(u8, op, "fill_rect")) return .{ .fill_rect = .{
        .id = try optionalUnsigned(canvas.ObjectId, value, "id", 0),
        .rect = try parseRect(try required(value, "rect")),
        .fill = try parseFill(allocator, try required(value, "fill"), budget),
    } };
    if (std.mem.eql(u8, op, "stroke_rect")) return .{ .stroke_rect = .{
        .id = try optionalUnsigned(canvas.ObjectId, value, "id", 0),
        .rect = try parseRect(try required(value, "rect")),
        .radius = try parseRadius(try required(value, "radius")),
        .stroke = try parseStroke(allocator, try required(value, "stroke"), budget),
    } };
    if (std.mem.eql(u8, op, "fill_rounded_rect")) return .{ .fill_rounded_rect = .{
        .id = try optionalUnsigned(canvas.ObjectId, value, "id", 0),
        .rect = try parseRect(try required(value, "rect")),
        .radius = try parseRadius(try required(value, "radius")),
        .fill = try parseFill(allocator, try required(value, "fill"), budget),
    } };
    if (std.mem.eql(u8, op, "draw_line")) return .{ .draw_line = .{
        .id = try optionalUnsigned(canvas.ObjectId, value, "id", 0),
        .from = try parsePoint(try required(value, "from")),
        .to = try parsePoint(try required(value, "to")),
        .stroke = try parseStroke(allocator, try required(value, "stroke"), budget),
    } };
    if (std.mem.eql(u8, op, "fill_path")) return .{ .fill_path = .{
        .id = try optionalUnsigned(canvas.ObjectId, value, "id", 0),
        .elements = try parsePath(allocator, try required(value, "path"), budget),
        .fill = try parseFill(allocator, try required(value, "fill"), budget),
    } };
    if (std.mem.eql(u8, op, "stroke_path")) return .{ .stroke_path = .{
        .id = try optionalUnsigned(canvas.ObjectId, value, "id", 0),
        .elements = try parsePath(allocator, try required(value, "path"), budget),
        .stroke = try parseStroke(allocator, try required(value, "stroke"), budget),
        .cap = if (member(value, "cap")) |field| try parseEnum(canvas.LineCap, field) else .butt,
    } };
    if (std.mem.eql(u8, op, "draw_image")) return .{ .draw_image = .{
        .id = try optionalUnsigned(canvas.ObjectId, value, "id", 0),
        .image_id = try unsigned(canvas.ImageId, try required(value, "image")),
        .dst = try parseRect(try required(value, "dst")),
        .src = if ((try required(value, "src")) == .null) null else try parseRect(try required(value, "src")),
        .opacity = try number(try required(value, "opacity")),
        .fit = try parseEnum(canvas.ImageFit, try required(value, "fit")),
        .sampling = try parseEnum(canvas.ImageSampling, try required(value, "sampling")),
        .radius = if (member(value, "radius")) |field| try parseRadius(field) else .{},
    } };
    if (std.mem.eql(u8, op, "draw_text")) return .{ .draw_text = .{
        .id = try optionalUnsigned(canvas.ObjectId, value, "id", 0),
        .font_id = try unsigned(canvas.FontId, try required(value, "font")),
        .size = try number(try required(value, "size")),
        .origin = try parsePoint(try required(value, "origin")),
        .color = try parseColor(try required(value, "color")),
        .text = try string(try required(value, "text")),
        .glyphs = try parseGlyphs(allocator, try required(value, "glyphs"), budget),
        .text_layout = if (member(value, "layout")) |field| try parseTextLayout(field) else null,
    } };
    if (std.mem.eql(u8, op, "shadow")) return .{ .shadow = .{
        .id = try optionalUnsigned(canvas.ObjectId, value, "id", 0),
        .rect = try parseRect(try required(value, "rect")),
        .radius = try parseRadius(try required(value, "radius")),
        .offset = try parseOffset(try required(value, "offset")),
        .blur = try number(try required(value, "blur")),
        .spread = try number(try required(value, "spread")),
        .color = try parseColor(try required(value, "color")),
    } };
    if (std.mem.eql(u8, op, "blur")) return .{ .blur = .{
        .id = try optionalUnsigned(canvas.ObjectId, value, "id", 0),
        .rect = try parseRect(try required(value, "rect")),
        .radius = try number(try required(value, "radius")),
    } };
    return error.InvalidSceneValue;
}

fn parseFill(allocator: std.mem.Allocator, value: std.json.Value, budget: *Budget) !canvas.Fill {
    const kind = try string(try required(value, "kind"));
    if (std.mem.eql(u8, kind, "color")) return .{ .color = try parseColor(try required(value, "color")) };
    if (std.mem.eql(u8, kind, "linear_gradient")) {
        const stop_items = try array(try required(value, "stops"));
        try Budget.consume(&budget.gradient_stops, stop_items.len, max_gradient_stops);
        const stops = try allocator.alloc(canvas.GradientStop, stop_items.len);
        for (stop_items, 0..) |stop, index| stops[index] = .{
            .offset = try number(try required(stop, "offset")),
            .color = try parseColor(try required(stop, "color")),
        };
        return .{ .linear_gradient = .{
            .start = try parsePoint(try required(value, "start")),
            .end = try parsePoint(try required(value, "end")),
            .stops = stops,
        } };
    }
    return error.InvalidSceneValue;
}

fn parseStroke(allocator: std.mem.Allocator, value: std.json.Value, budget: *Budget) !canvas.Stroke {
    return .{
        .width = try number(try required(value, "width")),
        .fill = try parseFill(allocator, try required(value, "fill"), budget),
    };
}

fn parsePath(allocator: std.mem.Allocator, value: std.json.Value, budget: *Budget) ![]const canvas.PathElement {
    const items = try array(value);
    try Budget.consume(&budget.path_elements, items.len, max_path_elements);
    const elements = try allocator.alloc(canvas.PathElement, items.len);
    for (items, 0..) |item, index| {
        const verb = try parseEnum(canvas.PathVerb, try required(item, "verb"));
        const point_count: usize = switch (verb) {
            .move_to, .line_to => 1,
            .quad_to => 2,
            .cubic_to => 3,
            .close => 0,
        };
        const points = try array(try required(item, "points"));
        if (points.len != point_count) return error.InvalidSceneValue;
        elements[index] = .{ .verb = verb };
        for (points, 0..) |point, point_index| elements[index].points[point_index] = try parsePoint(point);
    }
    return elements;
}

fn parseGlyphs(allocator: std.mem.Allocator, value: std.json.Value, budget: *Budget) ![]const canvas.Glyph {
    const items = try array(value);
    try Budget.consume(&budget.glyphs, items.len, max_glyphs);
    const glyphs = try allocator.alloc(canvas.Glyph, items.len);
    for (items, 0..) |item, index| glyphs[index] = .{
        .id = try unsigned(u32, try required(item, "id")),
        .font_id = try optionalUnsigned(canvas.FontId, item, "font", 0),
        .x = try number(try required(item, "x")),
        .y = try number(try required(item, "y")),
        .advance = try number(try required(item, "advance")),
        .text_start = try optionalUnsigned(usize, item, "textStart", 0),
        .text_len = try optionalUnsigned(usize, item, "textLen", 0),
    };
    return glyphs;
}

fn parseTextLayout(value: std.json.Value) !canvas.TextLayoutOptions {
    return .{
        .max_width = try number(try required(value, "maxWidth")),
        .line_height = try number(try required(value, "lineHeight")),
        .wrap = try parseEnum(canvas.TextWrap, try required(value, "wrap")),
        .alignment = try parseEnum(canvas.TextAlign, try required(value, "align")),
        .overflow = try parseEnum(canvas.TextOverflow, try required(value, "overflow")),
    };
}

fn parseRect(value: std.json.Value) !geometry.RectF {
    const values = try exactArray(value, 4);
    return .init(try number(values[0]), try number(values[1]), try number(values[2]), try number(values[3]));
}

fn parsePoint(value: std.json.Value) !geometry.PointF {
    const values = try exactArray(value, 2);
    return .init(try number(values[0]), try number(values[1]));
}

fn parseOffset(value: std.json.Value) !geometry.OffsetF {
    const values = try exactArray(value, 2);
    return .{ .dx = try number(values[0]), .dy = try number(values[1]) };
}

fn parseColor(value: std.json.Value) !canvas.Color {
    const values = try exactArray(value, 4);
    return .rgba(try number(values[0]), try number(values[1]), try number(values[2]), try number(values[3]));
}

fn parseRadius(value: std.json.Value) !canvas.Radius {
    const values = try exactArray(value, 4);
    return .{
        .top_left = try number(values[0]),
        .top_right = try number(values[1]),
        .bottom_right = try number(values[2]),
        .bottom_left = try number(values[3]),
    };
}

fn parseAffine(value: std.json.Value) !canvas.Affine {
    const values = try exactArray(value, 6);
    return .{
        .a = try number(values[0]),
        .b = try number(values[1]),
        .c = try number(values[2]),
        .d = try number(values[3]),
        .tx = try number(values[4]),
        .ty = try number(values[5]),
    };
}

fn exactArray(value: std.json.Value, expected: usize) Error![]const std.json.Value {
    const values = try array(value);
    if (values.len != expected) return error.InvalidSceneValue;
    return values;
}

fn parseEnum(comptime T: type, value: std.json.Value) Error!T {
    return std.meta.stringToEnum(T, try string(value)) orelse error.InvalidSceneValue;
}

fn member(value: std.json.Value, name: []const u8) ?std.json.Value {
    if (value != .object) return null;
    return value.object.get(name);
}

fn required(value: std.json.Value, name: []const u8) Error!std.json.Value {
    if (value != .object) return error.InvalidSceneValue;
    return value.object.get(name) orelse error.InvalidSceneValue;
}

fn string(value: std.json.Value) Error![]const u8 {
    if (value != .string) return error.InvalidSceneValue;
    return value.string;
}

fn array(value: std.json.Value) Error![]const std.json.Value {
    if (value != .array) return error.InvalidSceneValue;
    return value.array.items;
}

fn boolean(value: std.json.Value) Error!bool {
    if (value != .bool) return error.InvalidSceneValue;
    return value.bool;
}

fn number(value: std.json.Value) Error!f32 {
    const parsed: f64 = switch (value) {
        .integer => |integer| @floatFromInt(integer),
        .float => |float| float,
        .number_string => |text| std.fmt.parseFloat(f64, text) catch return error.InvalidSceneValue,
        else => return error.InvalidSceneValue,
    };
    if (!std.math.isFinite(parsed) or parsed > std.math.floatMax(f32) or parsed < -std.math.floatMax(f32)) return error.InvalidSceneValue;
    return @floatCast(parsed);
}

fn unsigned(comptime T: type, value: std.json.Value) Error!T {
    const parsed: u64 = switch (value) {
        .integer => |integer| if (integer >= 0) @intCast(integer) else return error.InvalidSceneValue,
        .number_string => |text| std.fmt.parseInt(u64, text, 10) catch return error.InvalidSceneValue,
        else => return error.InvalidSceneValue,
    };
    return std.math.cast(T, parsed) orelse error.InvalidSceneValue;
}

fn optionalUnsigned(comptime T: type, value: std.json.Value, name: []const u8, default: T) Error!T {
    return if (member(value, name)) |field| try unsigned(T, field) else default;
}

fn writeColor(writer: *std.Io.Writer, color: canvas.Color) !void {
    try writer.print("[{d},{d},{d},{d}]", .{ color.r, color.g, color.b, color.a });
}
