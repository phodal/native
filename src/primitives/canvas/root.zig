const std = @import("std");
const geometry = @import("geometry");
const json = @import("json");

pub const Error = error{
    DisplayListFull,
};

pub const ObjectId = u64;
pub const ImageId = u64;
pub const FontId = u64;

pub const Color = struct {
    r: f32 = 0,
    g: f32 = 0,
    b: f32 = 0,
    a: f32 = 1,

    pub fn rgba(r: f32, g: f32, b: f32, a: f32) Color {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    pub fn rgb8(r: u8, g: u8, b: u8) Color {
        return rgba8(r, g, b, 255);
    }

    pub fn rgba8(r: u8, g: u8, b: u8, a: u8) Color {
        return .{
            .r = @as(f32, @floatFromInt(r)) / 255.0,
            .g = @as(f32, @floatFromInt(g)) / 255.0,
            .b = @as(f32, @floatFromInt(b)) / 255.0,
            .a = @as(f32, @floatFromInt(a)) / 255.0,
        };
    }
};

pub const Affine = struct {
    a: f32 = 1,
    b: f32 = 0,
    c: f32 = 0,
    d: f32 = 1,
    tx: f32 = 0,
    ty: f32 = 0,

    pub fn identity() Affine {
        return .{};
    }

    pub fn translate(x: f32, y: f32) Affine {
        return .{ .tx = x, .ty = y };
    }

    pub fn scale(x: f32, y: f32) Affine {
        return .{ .a = x, .d = y };
    }
};

pub const Radius = struct {
    top_left: f32 = 0,
    top_right: f32 = 0,
    bottom_right: f32 = 0,
    bottom_left: f32 = 0,

    pub fn all(value: f32) Radius {
        return .{
            .top_left = value,
            .top_right = value,
            .bottom_right = value,
            .bottom_left = value,
        };
    }
};

pub const GradientStop = struct {
    offset: f32,
    color: Color,
};

pub const LinearGradient = struct {
    start: geometry.PointF,
    end: geometry.PointF,
    stops: []const GradientStop = &.{},
};

pub const Fill = union(enum) {
    color: Color,
    linear_gradient: LinearGradient,
};

pub const Stroke = struct {
    fill: Fill,
    width: f32 = 1,
};

pub const Clip = struct {
    id: ObjectId = 0,
    rect: geometry.RectF,
    radius: Radius = .{},
};

pub const FillRect = struct {
    id: ObjectId = 0,
    rect: geometry.RectF,
    fill: Fill,
};

pub const StrokeRect = struct {
    id: ObjectId = 0,
    rect: geometry.RectF,
    radius: Radius = .{},
    stroke: Stroke,
};

pub const FillRoundedRect = struct {
    id: ObjectId = 0,
    rect: geometry.RectF,
    radius: Radius,
    fill: Fill,
};

pub const Line = struct {
    id: ObjectId = 0,
    from: geometry.PointF,
    to: geometry.PointF,
    stroke: Stroke,
};

pub const PathVerb = enum {
    move_to,
    line_to,
    quad_to,
    cubic_to,
    close,
};

pub const PathElement = struct {
    verb: PathVerb,
    points: [3]geometry.PointF = [_]geometry.PointF{geometry.PointF.zero()} ** 3,
};

pub const FillPath = struct {
    id: ObjectId = 0,
    elements: []const PathElement = &.{},
    fill: Fill,
};

pub const StrokePath = struct {
    id: ObjectId = 0,
    elements: []const PathElement = &.{},
    stroke: Stroke,
};

pub const ImageFit = enum {
    stretch,
    contain,
    cover,
};

pub const DrawImage = struct {
    id: ObjectId = 0,
    image_id: ImageId,
    src: ?geometry.RectF = null,
    dst: geometry.RectF,
    opacity: f32 = 1,
    fit: ImageFit = .stretch,
};

pub const Glyph = struct {
    id: u32,
    x: f32,
    y: f32,
    advance: f32 = 0,
};

pub const DrawText = struct {
    id: ObjectId = 0,
    font_id: FontId = 0,
    size: f32,
    origin: geometry.PointF,
    color: Color,
    text: []const u8 = "",
    glyphs: []const Glyph = &.{},
};

pub const Shadow = struct {
    id: ObjectId = 0,
    rect: geometry.RectF,
    radius: Radius = .{},
    offset: geometry.OffsetF = .{},
    blur: f32 = 0,
    spread: f32 = 0,
    color: Color,
};

pub const Blur = struct {
    id: ObjectId = 0,
    rect: geometry.RectF,
    radius: f32 = 0,
};

pub const CanvasCommand = union(enum) {
    push_clip: Clip,
    pop_clip,
    push_opacity: f32,
    pop_opacity,
    transform: Affine,
    fill_rect: FillRect,
    stroke_rect: StrokeRect,
    fill_rounded_rect: FillRoundedRect,
    draw_line: Line,
    fill_path: FillPath,
    stroke_path: StrokePath,
    draw_image: DrawImage,
    draw_text: DrawText,
    shadow: Shadow,
    blur: Blur,
};

pub const DisplayList = struct {
    commands: []const CanvasCommand = &.{},

    pub fn writeJson(self: DisplayList, writer: anytype) !void {
        try writer.writeAll("{\"commands\":[");
        for (self.commands, 0..) |command, index| {
            if (index > 0) try writer.writeByte(',');
            try writeCommandJson(command, writer);
        }
        try writer.writeAll("]}");
    }

    pub fn commandCount(self: DisplayList) usize {
        return self.commands.len;
    }
};

pub const Builder = struct {
    commands: []CanvasCommand,
    len: usize = 0,

    pub fn init(commands: []CanvasCommand) Builder {
        return .{ .commands = commands };
    }

    pub fn reset(self: *Builder) void {
        self.len = 0;
    }

    pub fn displayList(self: *const Builder) DisplayList {
        return .{ .commands = self.commands[0..self.len] };
    }

    pub fn append(self: *Builder, command: CanvasCommand) Error!void {
        if (self.len >= self.commands.len) return error.DisplayListFull;
        self.commands[self.len] = command;
        self.len += 1;
    }

    pub fn pushClip(self: *Builder, clip: Clip) Error!void {
        try self.append(.{ .push_clip = clip });
    }

    pub fn popClip(self: *Builder) Error!void {
        try self.append(.pop_clip);
    }

    pub fn pushOpacity(self: *Builder, opacity: f32) Error!void {
        try self.append(.{ .push_opacity = opacity });
    }

    pub fn popOpacity(self: *Builder) Error!void {
        try self.append(.pop_opacity);
    }

    pub fn transform(self: *Builder, value: Affine) Error!void {
        try self.append(.{ .transform = value });
    }

    pub fn fillRect(self: *Builder, value: FillRect) Error!void {
        try self.append(.{ .fill_rect = value });
    }

    pub fn strokeRect(self: *Builder, value: StrokeRect) Error!void {
        try self.append(.{ .stroke_rect = value });
    }

    pub fn fillRoundedRect(self: *Builder, value: FillRoundedRect) Error!void {
        try self.append(.{ .fill_rounded_rect = value });
    }

    pub fn drawLine(self: *Builder, value: Line) Error!void {
        try self.append(.{ .draw_line = value });
    }

    pub fn fillPath(self: *Builder, value: FillPath) Error!void {
        try self.append(.{ .fill_path = value });
    }

    pub fn strokePath(self: *Builder, value: StrokePath) Error!void {
        try self.append(.{ .stroke_path = value });
    }

    pub fn drawImage(self: *Builder, value: DrawImage) Error!void {
        try self.append(.{ .draw_image = value });
    }

    pub fn drawText(self: *Builder, value: DrawText) Error!void {
        try self.append(.{ .draw_text = value });
    }

    pub fn shadow(self: *Builder, value: Shadow) Error!void {
        try self.append(.{ .shadow = value });
    }

    pub fn blur(self: *Builder, value: Blur) Error!void {
        try self.append(.{ .blur = value });
    }
};

fn writeCommandJson(command: CanvasCommand, writer: anytype) !void {
    try writer.writeAll("{\"op\":");
    try json.writeString(writer, @tagName(command));
    switch (command) {
        .push_clip => |value| {
            try writer.print(",\"id\":{d},\"rect\":", .{value.id});
            try writeRectJson(value.rect, writer);
            try writer.writeAll(",\"radius\":");
            try writeRadiusJson(value.radius, writer);
        },
        .pop_clip, .pop_opacity => {},
        .push_opacity => |value| try writer.print(",\"opacity\":{d}", .{value}),
        .transform => |value| {
            try writer.writeAll(",\"matrix\":");
            try writeAffineJson(value, writer);
        },
        .fill_rect => |value| {
            try writer.print(",\"id\":{d},\"rect\":", .{value.id});
            try writeRectJson(value.rect, writer);
            try writer.writeAll(",\"fill\":");
            try writeFillJson(value.fill, writer);
        },
        .stroke_rect => |value| {
            try writer.print(",\"id\":{d},\"rect\":", .{value.id});
            try writeRectJson(value.rect, writer);
            try writer.writeAll(",\"radius\":");
            try writeRadiusJson(value.radius, writer);
            try writer.writeAll(",\"stroke\":");
            try writeStrokeJson(value.stroke, writer);
        },
        .fill_rounded_rect => |value| {
            try writer.print(",\"id\":{d},\"rect\":", .{value.id});
            try writeRectJson(value.rect, writer);
            try writer.writeAll(",\"radius\":");
            try writeRadiusJson(value.radius, writer);
            try writer.writeAll(",\"fill\":");
            try writeFillJson(value.fill, writer);
        },
        .draw_line => |value| {
            try writer.print(",\"id\":{d},\"from\":", .{value.id});
            try writePointJson(value.from, writer);
            try writer.writeAll(",\"to\":");
            try writePointJson(value.to, writer);
            try writer.writeAll(",\"stroke\":");
            try writeStrokeJson(value.stroke, writer);
        },
        .fill_path => |value| {
            try writer.print(",\"id\":{d},\"path\":", .{value.id});
            try writePathJson(value.elements, writer);
            try writer.writeAll(",\"fill\":");
            try writeFillJson(value.fill, writer);
        },
        .stroke_path => |value| {
            try writer.print(",\"id\":{d},\"path\":", .{value.id});
            try writePathJson(value.elements, writer);
            try writer.writeAll(",\"stroke\":");
            try writeStrokeJson(value.stroke, writer);
        },
        .draw_image => |value| {
            try writer.print(",\"id\":{d},\"image\":{d},\"dst\":", .{ value.id, value.image_id });
            try writeRectJson(value.dst, writer);
            try writer.writeAll(",\"src\":");
            if (value.src) |src| {
                try writeRectJson(src, writer);
            } else {
                try writer.writeAll("null");
            }
            try writer.print(",\"opacity\":{d},\"fit\":", .{value.opacity});
            try json.writeString(writer, @tagName(value.fit));
        },
        .draw_text => |value| {
            try writer.print(",\"id\":{d},\"font\":{d},\"size\":{d},\"origin\":", .{ value.id, value.font_id, value.size });
            try writePointJson(value.origin, writer);
            try writer.writeAll(",\"color\":");
            try writeColorJson(value.color, writer);
            try writer.writeAll(",\"text\":");
            try json.writeString(writer, value.text);
            try writer.writeAll(",\"glyphs\":");
            try writeGlyphsJson(value.glyphs, writer);
        },
        .shadow => |value| {
            try writer.print(",\"id\":{d},\"rect\":", .{value.id});
            try writeRectJson(value.rect, writer);
            try writer.writeAll(",\"radius\":");
            try writeRadiusJson(value.radius, writer);
            try writer.print(",\"offset\":[{d},{d}],\"blur\":{d},\"spread\":{d},\"color\":", .{ value.offset.dx, value.offset.dy, value.blur, value.spread });
            try writeColorJson(value.color, writer);
        },
        .blur => |value| {
            try writer.print(",\"id\":{d},\"rect\":", .{value.id});
            try writeRectJson(value.rect, writer);
            try writer.print(",\"radius\":{d}", .{value.radius});
        },
    }
    try writer.writeByte('}');
}

fn writeRectJson(rect: geometry.RectF, writer: anytype) !void {
    try writer.print("[{d},{d},{d},{d}]", .{ rect.x, rect.y, rect.width, rect.height });
}

fn writePointJson(point: geometry.PointF, writer: anytype) !void {
    try writer.print("[{d},{d}]", .{ point.x, point.y });
}

fn writeColorJson(color: Color, writer: anytype) !void {
    try writer.print("[{d},{d},{d},{d}]", .{ color.r, color.g, color.b, color.a });
}

fn writeRadiusJson(radius: Radius, writer: anytype) !void {
    try writer.print("[{d},{d},{d},{d}]", .{ radius.top_left, radius.top_right, radius.bottom_right, radius.bottom_left });
}

fn writeAffineJson(matrix: Affine, writer: anytype) !void {
    try writer.print("[{d},{d},{d},{d},{d},{d}]", .{ matrix.a, matrix.b, matrix.c, matrix.d, matrix.tx, matrix.ty });
}

fn writeFillJson(fill: Fill, writer: anytype) !void {
    switch (fill) {
        .color => |color| {
            try writer.writeAll("{\"kind\":\"color\",\"color\":");
            try writeColorJson(color, writer);
            try writer.writeByte('}');
        },
        .linear_gradient => |gradient| {
            try writer.writeAll("{\"kind\":\"linear_gradient\",\"start\":");
            try writePointJson(gradient.start, writer);
            try writer.writeAll(",\"end\":");
            try writePointJson(gradient.end, writer);
            try writer.writeAll(",\"stops\":[");
            for (gradient.stops, 0..) |stop, index| {
                if (index > 0) try writer.writeByte(',');
                try writer.print("{{\"offset\":{d},\"color\":", .{stop.offset});
                try writeColorJson(stop.color, writer);
                try writer.writeByte('}');
            }
            try writer.writeAll("]}");
        },
    }
}

fn writeStrokeJson(stroke: Stroke, writer: anytype) !void {
    try writer.writeAll("{\"width\":");
    try writer.print("{d}", .{stroke.width});
    try writer.writeAll(",\"fill\":");
    try writeFillJson(stroke.fill, writer);
    try writer.writeByte('}');
}

fn writePathJson(elements: []const PathElement, writer: anytype) !void {
    try writer.writeByte('[');
    for (elements, 0..) |element, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.writeAll("{\"verb\":");
        try json.writeString(writer, @tagName(element.verb));
        try writer.writeAll(",\"points\":[");
        const point_count: usize = switch (element.verb) {
            .move_to, .line_to => 1,
            .quad_to => 2,
            .cubic_to => 3,
            .close => 0,
        };
        for (element.points[0..point_count], 0..) |point, point_index| {
            if (point_index > 0) try writer.writeByte(',');
            try writePointJson(point, writer);
        }
        try writer.writeAll("]}");
    }
    try writer.writeByte(']');
}

fn writeGlyphsJson(glyphs: []const Glyph, writer: anytype) !void {
    try writer.writeByte('[');
    for (glyphs, 0..) |glyph, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.print("{{\"id\":{d},\"x\":{d},\"y\":{d},\"advance\":{d}}}", .{ glyph.id, glyph.x, glyph.y, glyph.advance });
    }
    try writer.writeByte(']');
}

test "builder records replayable commands" {
    var commands: [8]CanvasCommand = undefined;
    var builder = Builder.init(&commands);

    try builder.pushClip(.{ .id = 1, .rect = geometry.RectF.init(0, 0, 320, 240), .radius = Radius.all(8) });
    try builder.pushOpacity(0.75);
    try builder.fillRoundedRect(.{
        .id = 2,
        .rect = geometry.RectF.init(12, 16, 180, 96),
        .radius = Radius.all(12),
        .fill = .{ .color = Color.rgb8(17, 24, 39) },
    });
    try builder.popOpacity();
    try builder.popClip();

    const display_list = builder.displayList();
    try std.testing.expectEqual(@as(usize, 5), display_list.commandCount());
    try std.testing.expect(display_list.commands[0] == .push_clip);
    try std.testing.expect(display_list.commands[2] == .fill_rounded_rect);
}

test "builder reports fixed buffer overflow" {
    var commands: [1]CanvasCommand = undefined;
    var builder = Builder.init(&commands);

    try builder.pushOpacity(1);
    try std.testing.expectError(error.DisplayListFull, builder.popOpacity());
}

test "display list serializes deterministically" {
    const stops = [_]GradientStop{
        .{ .offset = 0, .color = Color.rgb8(255, 255, 255) },
        .{ .offset = 1, .color = Color.rgb8(59, 130, 246) },
    };
    const glyphs = [_]Glyph{
        .{ .id = 42, .x = 12, .y = 28, .advance = 9 },
        .{ .id = 43, .x = 21, .y = 28, .advance = 8 },
    };

    var commands: [4]CanvasCommand = undefined;
    var builder = Builder.init(&commands);
    try builder.fillRect(.{
        .id = 10,
        .rect = geometry.RectF.init(0, 0, 360, 180),
        .fill = .{ .linear_gradient = .{
            .start = geometry.PointF.init(0, 0),
            .end = geometry.PointF.init(360, 180),
            .stops = &stops,
        } },
    });
    try builder.shadow(.{
        .id = 11,
        .rect = geometry.RectF.init(24, 24, 220, 96),
        .radius = Radius.all(16),
        .offset = .{ .dx = 0, .dy = 18 },
        .blur = 42,
        .spread = -8,
        .color = Color.rgba8(15, 23, 42, 48),
    });
    try builder.drawText(.{
        .id = 12,
        .font_id = 7,
        .size = 17,
        .origin = geometry.PointF.init(32, 52),
        .color = Color.rgb8(15, 23, 42),
        .text = "Hi",
        .glyphs = &glyphs,
    });

    var buffer: [2048]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try builder.displayList().writeJson(&writer);

    const expected =
        "{\"commands\":[{\"op\":\"fill_rect\",\"id\":10,\"rect\":[0,0,360,180],\"fill\":{\"kind\":\"linear_gradient\",\"start\":[0,0],\"end\":[360,180],\"stops\":[{\"offset\":0,\"color\":[1,1,1,1]},{\"offset\":1,\"color\":[0.23137255,0.50980395,0.9647059,1]}]}},{\"op\":\"shadow\",\"id\":11,\"rect\":[24,24,220,96],\"radius\":[16,16,16,16],\"offset\":[0,18],\"blur\":42,\"spread\":-8,\"color\":[0.05882353,0.09019608,0.16470589,0.1882353]},{\"op\":\"draw_text\",\"id\":12,\"font\":7,\"size\":17,\"origin\":[32,52],\"color\":[0.05882353,0.09019608,0.16470589,1],\"text\":\"Hi\",\"glyphs\":[{\"id\":42,\"x\":12,\"y\":28,\"advance\":9},{\"id\":43,\"x\":21,\"y\":28,\"advance\":8}]}]}";
    try std.testing.expectEqualStrings(expected, writer.buffered());
}
