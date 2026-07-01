const geometry = @import("geometry");
const canvas = @import("root.zig");
const drawing_model = @import("drawing.zig");
const text_model = @import("text.zig");

const ObjectId = u64;
const DisplayList = canvas.DisplayList;

const Affine = drawing_model.Affine;
const Clip = drawing_model.Clip;
const FillRect = drawing_model.FillRect;
const StrokeRect = drawing_model.StrokeRect;
const FillRoundedRect = drawing_model.FillRoundedRect;
const Line = drawing_model.Line;
const FillPath = drawing_model.FillPath;
const StrokePath = drawing_model.StrokePath;
const DrawImage = drawing_model.DrawImage;
const Shadow = drawing_model.Shadow;
const Blur = drawing_model.Blur;
const DrawText = text_model.DrawText;

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

    pub fn objectId(self: CanvasCommand) ?ObjectId {
        const id = switch (self) {
            .push_clip => |value| value.id,
            .fill_rect => |value| value.id,
            .stroke_rect => |value| value.id,
            .fill_rounded_rect => |value| value.id,
            .draw_line => |value| value.id,
            .fill_path => |value| value.id,
            .stroke_path => |value| value.id,
            .draw_image => |value| value.id,
            .draw_text => |value| value.id,
            .shadow => |value| value.id,
            .blur => |value| value.id,
            .pop_clip, .push_opacity, .pop_opacity, .transform => 0,
        };
        return if (id == 0) null else id;
    }

    pub fn bounds(self: CanvasCommand) ?geometry.RectF {
        return switch (self) {
            .push_clip => |value| value.rect.normalized(),
            .pop_clip, .push_opacity, .pop_opacity, .transform => null,
            .fill_rect => |value| value.rect.normalized(),
            .stroke_rect => |value| drawing_model.strokeBounds(value.rect, value.stroke.width),
            .fill_rounded_rect => |value| value.rect.normalized(),
            .draw_line => |value| drawing_model.strokeBounds(geometry.RectF.fromPoints(value.from, value.to), value.stroke.width),
            .fill_path => |value| drawing_model.pathBounds(value.elements),
            .stroke_path => |value| if (drawing_model.pathBounds(value.elements)) |rect| drawing_model.strokeBounds(rect, value.stroke.width) else null,
            .draw_image => |value| value.dst.normalized(),
            .draw_text => |value| text_model.textBounds(value),
            .shadow => |value| drawing_model.shadowBounds(value),
            .blur => |value| value.rect.normalized().inflate(geometry.InsetsF.all(nonNegative(value.radius))),
        };
    }
};

pub const CommandRef = struct {
    index: usize,
    command: CanvasCommand,
};

pub const DiffKind = enum {
    added,
    removed,
    changed,
    scene_changed,
};

pub const DiffChange = struct {
    kind: DiffKind,
    id: ?ObjectId = null,
    previous_index: ?usize = null,
    next_index: ?usize = null,
    dirty_bounds: ?geometry.RectF = null,
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

    pub fn append(self: *Builder, command: CanvasCommand) error{DisplayListFull}!void {
        if (self.len >= self.commands.len) return error.DisplayListFull;
        self.commands[self.len] = command;
        self.len += 1;
    }

    pub fn pushClip(self: *Builder, clip: Clip) error{DisplayListFull}!void {
        try self.append(.{ .push_clip = clip });
    }

    pub fn popClip(self: *Builder) error{DisplayListFull}!void {
        try self.append(.pop_clip);
    }

    pub fn pushOpacity(self: *Builder, opacity: f32) error{DisplayListFull}!void {
        try self.append(.{ .push_opacity = opacity });
    }

    pub fn popOpacity(self: *Builder) error{DisplayListFull}!void {
        try self.append(.pop_opacity);
    }

    pub fn transform(self: *Builder, value: Affine) error{DisplayListFull}!void {
        try self.append(.{ .transform = value });
    }

    pub fn fillRect(self: *Builder, value: FillRect) error{DisplayListFull}!void {
        try self.append(.{ .fill_rect = value });
    }

    pub fn strokeRect(self: *Builder, value: StrokeRect) error{DisplayListFull}!void {
        try self.append(.{ .stroke_rect = value });
    }

    pub fn fillRoundedRect(self: *Builder, value: FillRoundedRect) error{DisplayListFull}!void {
        try self.append(.{ .fill_rounded_rect = value });
    }

    pub fn drawLine(self: *Builder, value: Line) error{DisplayListFull}!void {
        try self.append(.{ .draw_line = value });
    }

    pub fn fillPath(self: *Builder, value: FillPath) error{DisplayListFull}!void {
        try self.append(.{ .fill_path = value });
    }

    pub fn strokePath(self: *Builder, value: StrokePath) error{DisplayListFull}!void {
        try self.append(.{ .stroke_path = value });
    }

    pub fn drawImage(self: *Builder, value: DrawImage) error{DisplayListFull}!void {
        try self.append(.{ .draw_image = value });
    }

    pub fn drawText(self: *Builder, value: DrawText) error{DisplayListFull}!void {
        try self.append(.{ .draw_text = value });
    }

    pub fn shadow(self: *Builder, value: Shadow) error{DisplayListFull}!void {
        try self.append(.{ .shadow = value });
    }

    pub fn blur(self: *Builder, value: Blur) error{DisplayListFull}!void {
        try self.append(.{ .blur = value });
    }
};

fn nonNegative(value: f32) f32 {
    return @max(0, value);
}
