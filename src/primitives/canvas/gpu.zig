const geometry = @import("geometry");
const canvas = @import("root.zig");
const drawing_model = @import("drawing.zig");
const text_model = @import("text.zig");
const render_model = @import("render.zig");

const Error = canvas.Error;
const ObjectId = canvas.ObjectId;
const ImageId = canvas.ImageId;
const FontId = canvas.FontId;
const Affine = drawing_model.Affine;
const Color = drawing_model.Color;
const Radius = drawing_model.Radius;
const LinearGradient = drawing_model.LinearGradient;
const PathElement = drawing_model.PathElement;
const ImageFit = drawing_model.ImageFit;
const ImageSampling = drawing_model.ImageSampling;
const Glyph = text_model.Glyph;
const TextLayoutOptions = text_model.TextLayoutOptions;
const GlyphAtlasCacheAction = text_model.GlyphAtlasCacheAction;
const TextLayoutCacheAction = text_model.TextLayoutCacheAction;
const RenderPipelineKind = render_model.RenderPipelineKind;
const RenderBatch = render_model.RenderBatch;
const RenderPipelineCacheAction = render_model.RenderPipelineCacheAction;
const RenderPathGeometryCacheAction = render_model.RenderPathGeometryCacheAction;
const RenderImage = render_model.RenderImage;
const RenderImageCacheAction = render_model.RenderImageCacheAction;
const RenderLayerCacheAction = render_model.RenderLayerCacheAction;
const RenderResourceCacheAction = render_model.RenderResourceCacheAction;
const VisualEffectCacheAction = render_model.VisualEffectCacheAction;

pub const CanvasRenderPassLoadAction = enum {
    skip,
    load,
    clear,
};

pub const RenderEncoderBeginPass = struct {
    load_action: CanvasRenderPassLoadAction = .skip,
    surface_size: geometry.SizeF = .{},
    scale: f32 = 1,
    dirty_bounds: ?geometry.RectF = null,
};

pub const RenderEncoderCommand = union(enum) {
    begin_pass: RenderEncoderBeginPass,
    set_scissor: geometry.RectF,
    pipeline_cache: RenderPipelineCacheAction,
    path_geometry_cache: RenderPathGeometryCacheAction,
    image_cache: RenderImageCacheAction,
    layer_cache: RenderLayerCacheAction,
    resource_cache: RenderResourceCacheAction,
    visual_effect_cache: VisualEffectCacheAction,
    glyph_atlas_cache: GlyphAtlasCacheAction,
    text_layout_cache: TextLayoutCacheAction,
    bind_pipeline: RenderPipelineKind,
    draw_batch: RenderBatch,
    end_pass,
};

pub const RenderEncoderPlan = struct {
    commands: []const RenderEncoderCommand = &.{},

    pub fn commandCount(self: RenderEncoderPlan) usize {
        return self.commands.len;
    }

    pub fn cacheActionCount(self: RenderEncoderPlan) usize {
        var count: usize = 0;
        for (self.commands) |command| {
            switch (command) {
                .pipeline_cache, .path_geometry_cache, .image_cache, .layer_cache, .resource_cache, .visual_effect_cache, .glyph_atlas_cache, .text_layout_cache => count += 1,
                else => {},
            }
        }
        return count;
    }

    pub fn bindPipelineCount(self: RenderEncoderPlan) usize {
        var count: usize = 0;
        for (self.commands) |command| {
            switch (command) {
                .bind_pipeline => count += 1,
                else => {},
            }
        }
        return count;
    }

    pub fn drawBatchCount(self: RenderEncoderPlan) usize {
        var count: usize = 0;
        for (self.commands) |command| {
            switch (command) {
                .draw_batch => count += 1,
                else => {},
            }
        }
        return count;
    }
};

pub const CanvasGpuCommandKind = enum {
    fill_rect_solid,
    fill_rect_gradient,
    fill_rounded_rect_solid,
    fill_rounded_rect_gradient,
    stroke_rect_solid,
    stroke_rect_gradient,
    draw_line_solid,
    draw_line_gradient,
    fill_path,
    stroke_path,
    draw_image,
    draw_text,
    shadow,
    blur,
    unsupported,
};

pub const CanvasGpuRoundedRect = struct {
    rect: geometry.RectF = .{},
    radius: Radius = .{},
};

pub const CanvasGpuStrokeRect = struct {
    rect: geometry.RectF = .{},
    radius: Radius = .{},
    width: f32 = 1,
};

pub const CanvasGpuLine = struct {
    from: geometry.PointF = .{},
    to: geometry.PointF = .{},
    width: f32 = 1,
};

pub const CanvasGpuShape = union(enum) {
    none,
    rect: geometry.RectF,
    rounded_rect: CanvasGpuRoundedRect,
    stroke_rect: CanvasGpuStrokeRect,
    line: CanvasGpuLine,
    path: []const PathElement,
};

pub const CanvasGpuPaint = union(enum) {
    none,
    color: Color,
    linear_gradient: LinearGradient,
};

pub const CanvasGpuImage = struct {
    image_id: ImageId = 0,
    src: ?geometry.RectF = null,
    dst: geometry.RectF = .{},
    opacity: f32 = 1,
    fit: ImageFit = .stretch,
    sampling: ImageSampling = .linear,
};

pub const CanvasGpuText = struct {
    font_id: FontId = 0,
    size: f32 = 0,
    origin: geometry.PointF = .{},
    color: Color = .{},
    text: []const u8 = "",
    glyphs: []const Glyph = &.{},
    text_layout: ?TextLayoutOptions = null,
};

pub const CanvasGpuShadow = struct {
    rect: geometry.RectF = .{},
    radius: Radius = .{},
    offset: geometry.OffsetF = .{},
    blur: f32 = 0,
    spread: f32 = 0,
    color: Color = .{},
};

pub const CanvasGpuBlur = struct {
    rect: geometry.RectF = .{},
    radius: f32 = 0,
};

pub const CanvasGpuEffect = union(enum) {
    none,
    shadow: CanvasGpuShadow,
    blur: CanvasGpuBlur,
};

pub const CanvasGpuCommand = struct {
    command_index: usize,
    id: ?ObjectId = null,
    kind: CanvasGpuCommandKind,
    pipeline: ?RenderPipelineKind = null,
    bounds: geometry.RectF = .{},
    shape: CanvasGpuShape = .none,
    paint: CanvasGpuPaint = .none,
    stroke_width: f32 = 0,
    image: ?CanvasGpuImage = null,
    text: ?CanvasGpuText = null,
    effect: CanvasGpuEffect = .none,
    clip: ?geometry.RectF = null,
    opacity: f32 = 1,
    transform: Affine = .{},
    uses_path_geometry: bool = false,
    uses_image: bool = false,
    uses_resource: bool = false,
    uses_visual_effect: bool = false,
    uses_glyph_atlas: bool = false,
    uses_text_layout: bool = false,

    pub fn supported(self: CanvasGpuCommand) bool {
        return self.kind != .unsupported;
    }

    pub fn usesCachedResource(self: CanvasGpuCommand) bool {
        return self.uses_path_geometry or
            self.uses_image or
            self.uses_resource or
            self.uses_visual_effect or
            self.uses_glyph_atlas or
            self.uses_text_layout;
    }
};

pub const CanvasGpuPacket = struct {
    frame_index: u64 = 0,
    timestamp_ns: u64 = 0,
    load_action: CanvasRenderPassLoadAction = .skip,
    surface_size: geometry.SizeF = .{},
    scale: f32 = 1,
    scissor: ?geometry.RectF = null,
    images: []const RenderImage = &.{},
    image_actions: []const RenderImageCacheAction = &.{},
    commands: []const CanvasGpuCommand = &.{},
    batch_count: usize = 0,
    pipeline_action_count: usize = 0,
    path_geometry_count: usize = 0,
    path_geometry_action_count: usize = 0,
    image_count: usize = 0,
    image_action_count: usize = 0,
    layer_count: usize = 0,
    layer_action_count: usize = 0,
    resource_count: usize = 0,
    resource_action_count: usize = 0,
    visual_effect_count: usize = 0,
    visual_effect_action_count: usize = 0,
    glyph_atlas_entry_count: usize = 0,
    glyph_atlas_action_count: usize = 0,
    text_layout_count: usize = 0,
    text_layout_line_count: usize = 0,
    text_layout_action_count: usize = 0,
    unsupported_command_count: usize = 0,

    pub fn requiresRender(self: CanvasGpuPacket) bool {
        return self.load_action != .skip;
    }

    pub fn commandCount(self: CanvasGpuPacket) usize {
        return self.commands.len;
    }

    pub fn cacheActionCount(self: CanvasGpuPacket) usize {
        return self.pipeline_action_count +
            self.path_geometry_action_count +
            self.image_action_count +
            self.layer_action_count +
            self.resource_action_count +
            self.visual_effect_action_count +
            self.glyph_atlas_action_count +
            self.text_layout_action_count;
    }

    pub fn cachedResourceCommandCount(self: CanvasGpuPacket) usize {
        var count: usize = 0;
        for (self.commands) |command| {
            if (command.usesCachedResource()) count += 1;
        }
        return count;
    }

    pub fn fullyRepresentable(self: CanvasGpuPacket) bool {
        return self.unsupported_command_count == 0;
    }

    pub fn writeJson(self: CanvasGpuPacket, writer: anytype) !void {
        try canvas.writeCanvasGpuPacketJson(self, writer);
    }
};

pub const CanvasGpuPacketSummary = struct {
    load_action: CanvasRenderPassLoadAction = .skip,
    command_count: usize = 0,
    cache_action_count: usize = 0,
    cached_resource_command_count: usize = 0,
    unsupported_command_count: usize = 0,

    pub fn requiresRender(self: CanvasGpuPacketSummary) bool {
        return self.load_action != .skip;
    }

    pub fn fullyRepresentable(self: CanvasGpuPacketSummary) bool {
        return self.unsupported_command_count == 0;
    }
};
