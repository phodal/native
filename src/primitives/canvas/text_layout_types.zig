const geometry = @import("geometry");
const canvas = @import("root.zig");
const drawing_model = @import("drawing.zig");
const text_atlas = @import("text_atlas.zig");
const text_metrics = @import("text_metrics.zig");

const ObjectId = canvas.ObjectId;
const FontId = canvas.FontId;
const Color = drawing_model.Color;
pub const Glyph = text_atlas.Glyph;

pub const DrawText = struct {
    id: ObjectId = 0,
    font_id: FontId = 0,
    size: f32,
    origin: geometry.PointF,
    color: Color,
    text: []const u8 = "",
    glyphs: []const Glyph = &.{},
    text_layout: ?TextLayoutOptions = null,
};

pub const TextWrap = enum {
    none,
    word,
    character,
};

pub const TextAlign = enum {
    start,
    center,
    end,
};

pub const TextLayoutOptions = struct {
    max_width: f32 = 0,
    line_height: f32 = 0,
    wrap: TextWrap = .word,
    alignment: TextAlign = .start,
    /// Optional injected measurement used for line breaking, caret, and
    /// hit-test geometry. Null falls back to the deterministic estimator.
    /// Deliberately excluded from equality, hashing, and serialization:
    /// it is process-local layout context, not drawn content.
    measure: ?*const text_metrics.TextMeasureProvider = null,
};

pub const TextLine = struct {
    text_start: usize = 0,
    text_len: usize = 0,
    glyph_start: usize = 0,
    glyph_len: usize = 0,
    bounds: geometry.RectF = .{},
    baseline: f32 = 0,
};

pub const TextLayout = struct {
    lines: []const TextLine = &.{},
    bounds: ?geometry.RectF = null,

    pub fn lineCount(self: TextLayout) usize {
        return self.lines.len;
    }
};

pub const TextLayoutKey = struct {
    font_id: FontId = 0,
    size: f32 = 0,
    origin: geometry.PointF = .{},
    max_width: f32 = 0,
    line_height: f32 = 0,
    wrap: TextWrap = .word,
    alignment: TextAlign = .start,
    text_len: usize = 0,
    glyph_count: usize = 0,
    fingerprint: u64 = 0,
};
