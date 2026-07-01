const std = @import("std");
const geometry = @import("geometry");
const canvas = @import("canvas");
const validation = @import("validation.zig");
const canvas_frame_helpers = @import("canvas_frame.zig");
const canvas_limits = @import("canvas_limits.zig");
const canvas_widget_runtime = @import("canvas_widget_runtime.zig");
const view_widget_scroll = @import("view_widget_scroll.zig");
const view_widget_text = @import("view_widget_text.zig");
const widget_bridge = @import("widget_bridge.zig");
const platform = @import("../platform/root.zig");

pub const CanvasWidgetDisplayListChrome = struct {
    prefix_command_count: usize = 0,
    suffix_command_count: usize = 0,
    reserved_command_count: usize = 0,
};

const validateCommandName = validation.validateCommandName;

const max_canvas_commands_per_view = canvas_limits.max_canvas_commands_per_view;
const max_canvas_gradient_stops_per_view = canvas_limits.max_canvas_gradient_stops_per_view;
const max_canvas_path_elements_per_view = canvas_limits.max_canvas_path_elements_per_view;
const max_canvas_glyphs_per_view = canvas_limits.max_canvas_glyphs_per_view;
const max_canvas_text_bytes_per_view = canvas_limits.max_canvas_text_bytes_per_view;
const max_canvas_render_animations_per_view = canvas_limits.max_canvas_render_animations_per_view;
const max_canvas_render_animation_dirty_bounds_per_view = canvas_limits.max_canvas_render_animation_dirty_bounds_per_view;
const max_canvas_render_overrides_per_view = canvas_limits.max_canvas_render_overrides_per_view;
const max_canvas_pipelines_per_view = canvas_limits.max_canvas_pipelines_per_view;
const max_canvas_path_geometries_per_view = canvas_limits.max_canvas_path_geometries_per_view;
const max_canvas_images_per_view = canvas_limits.max_canvas_images_per_view;
const max_canvas_layers_per_view = canvas_limits.max_canvas_layers_per_view;
const max_canvas_resources_per_view = canvas_limits.max_canvas_resources_per_view;
const max_canvas_visual_effects_per_view = canvas_limits.max_canvas_visual_effects_per_view;
const max_canvas_text_layouts_per_view = canvas_limits.max_canvas_text_layouts_per_view;
const max_canvas_widget_nodes_per_view = canvas_limits.max_canvas_widget_nodes_per_view;
const max_canvas_widget_semantics_per_view = canvas_limits.max_canvas_widget_semantics_per_view;
const max_canvas_widget_text_bytes_per_view = canvas_limits.max_canvas_widget_text_bytes_per_view;
const max_canvas_widget_source_text_entries_per_view = canvas_limits.max_canvas_widget_source_text_entries_per_view;

const appendCanvasSummaryChange = canvas_frame_helpers.appendCanvasSummaryChange;
const unionRects = canvas_frame_helpers.unionRects;
const canvasWidgetEscapeKey = canvas_frame_helpers.canvasWidgetEscapeKey;
const findCanvasRenderOverrideIndex = canvas_frame_helpers.findCanvasRenderOverrideIndex;
const canvasRenderOverrideNoop = canvas_frame_helpers.canvasRenderOverrideNoop;
const canvasRenderAnimationFinalOverrideNoop = canvas_frame_helpers.canvasRenderAnimationFinalOverrideNoop;
const canvasRenderAnimationActive = canvas_frame_helpers.canvasRenderAnimationActive;
const platformCanvasFrameProfileRisk = canvas_frame_helpers.platformCanvasFrameProfileRisk;

const CanvasWidgetScrollReconcileEntry = canvas_widget_runtime.CanvasWidgetScrollReconcileEntry;
const CanvasWidgetControlReconcileEntry = canvas_widget_runtime.CanvasWidgetControlReconcileEntry;
const CanvasWidgetTextReconcileEntry = canvas_widget_runtime.CanvasWidgetTextReconcileEntry;
const CanvasWidgetSourceTextEntry = canvas_widget_runtime.CanvasWidgetSourceTextEntry;
const CanvasWidgetStepDirection = canvas_widget_runtime.CanvasWidgetStepDirection;
const canvasWidgetInteractionTargetExists = canvas_widget_runtime.canvasWidgetInteractionTargetExists;
const canvasWidgetLayoutNodeHidden = canvas_widget_runtime.canvasWidgetLayoutNodeHidden;
const canvasWidgetLayoutNodeFrameVisible = canvas_widget_runtime.canvasWidgetLayoutNodeFrameVisible;
const canvasWidgetLayoutNodeClippedBounds = canvas_widget_runtime.canvasWidgetLayoutNodeClippedBounds;
const canvasWidgetDismissibleSurfaceKind = canvas_widget_runtime.canvasWidgetDismissibleSurfaceKind;
const canvasWidgetEditableTextKind = canvas_widget_runtime.canvasWidgetEditableTextKind;
const canvasWidgetSingleLineTextKind = canvas_widget_runtime.canvasWidgetSingleLineTextKind;
const canvasWidgetResizableMinWidth = canvas_widget_runtime.canvasWidgetResizableMinWidth;
const collectCanvasWidgetControlReconcileEntries = canvas_widget_runtime.collectCanvasWidgetControlReconcileEntries;
const collectCanvasWidgetScrollReconcileEntries = canvas_widget_runtime.collectCanvasWidgetScrollReconcileEntries;
const canvasWidgetScrollStateForLayoutNode = canvas_widget_runtime.canvasWidgetScrollStateForLayoutNode;
const collectCanvasWidgetTextReconcileEntries = canvas_widget_runtime.collectCanvasWidgetTextReconcileEntries;
const canvasWidgetSourceTextFingerprint = canvas_widget_runtime.canvasWidgetSourceTextFingerprint;
const canvasWidgetLayoutNodeWithControlReconcileState = canvas_widget_runtime.canvasWidgetLayoutNodeWithControlReconcileState;
const canvasWidgetLayoutNodeWithTextReconcileState = canvas_widget_runtime.canvasWidgetLayoutNodeWithTextReconcileState;
const canvasWidgetLayoutNodeWithSourceSemantics = canvas_widget_runtime.canvasWidgetLayoutNodeWithSourceSemantics;
const applyCanvasWidgetSourceScrollSemantics = canvas_widget_runtime.applyCanvasWidgetSourceScrollSemantics;
const clampCanvasWidgetLayoutScrollOffsets = canvas_widget_runtime.clampCanvasWidgetLayoutScrollOffsets;
const clampCanvasWidgetLayoutTextOffsets = canvas_widget_runtime.clampCanvasWidgetLayoutTextOffsets;
const canvasWidgetBooleanSelected = canvas_widget_runtime.canvasWidgetBooleanSelected;
const canvasWidgetSwitchControlKind = canvas_widget_runtime.canvasWidgetSwitchControlKind;
const canvasWidgetSelectableSelected = canvas_widget_runtime.canvasWidgetSelectableSelected;
const canvasWidgetSelectionClearsSiblings = canvas_widget_runtime.canvasWidgetSelectionClearsSiblings;

const platformCursorFromCanvas = widget_bridge.platformCursorFromCanvas;

fn copyInto(buffer: []u8, value: []const u8) ![]const u8 {
    if (value.len > buffer.len) return error.NoSpaceLeft;
    @memcpy(buffer[0..value.len], value);
    return buffer[0..value.len];
}

pub const CanvasWidgetScrollSource = view_widget_scroll.CanvasWidgetScrollSource;

pub const CanvasWidgetToggleAnimation = struct {
    id: canvas.ObjectId,
    selected: bool,
    travel: f32,
    dirty_bounds: ?geometry.RectF,
};

pub const CanvasRenderAnimationDirtyBounds = struct {
    id: canvas.ObjectId,
    bounds: ?geometry.RectF,
};

pub const CanvasResourceCounts = struct {
    command_count: usize = 0,
    gradient_stop_count: usize = 0,
    path_element_count: usize = 0,
    glyph_count: usize = 0,
    text_byte_count: usize = 0,

    pub fn fromDisplayList(display_list: canvas.DisplayList) anyerror!CanvasResourceCounts {
        var counts: CanvasResourceCounts = .{};
        try addCanvasCount(&counts.command_count, display_list.commands.len, max_canvas_commands_per_view, error.CanvasCommandLimitReached);
        for (display_list.commands) |command| try counts.addCommand(command);
        return counts;
    }

    pub fn addCommand(self: *CanvasResourceCounts, command: canvas.CanvasCommand) anyerror!void {
        switch (command) {
            .push_clip, .pop_clip, .push_opacity, .pop_opacity, .transform, .draw_image, .blur => {},
            .fill_rect => |value| try self.addFill(value.fill),
            .stroke_rect => |value| try self.addStroke(value.stroke),
            .fill_rounded_rect => |value| try self.addFill(value.fill),
            .draw_line => |value| try self.addStroke(value.stroke),
            .fill_path => |value| {
                try addCanvasCount(&self.path_element_count, value.elements.len, max_canvas_path_elements_per_view, error.CanvasPathElementLimitReached);
                try self.addFill(value.fill);
            },
            .stroke_path => |value| {
                try addCanvasCount(&self.path_element_count, value.elements.len, max_canvas_path_elements_per_view, error.CanvasPathElementLimitReached);
                try self.addStroke(value.stroke);
            },
            .draw_text => |value| {
                try addCanvasCount(&self.text_byte_count, value.text.len, max_canvas_text_bytes_per_view, error.CanvasTextTooLarge);
                try addCanvasCount(&self.glyph_count, value.glyphs.len, max_canvas_glyphs_per_view, error.CanvasGlyphLimitReached);
            },
            .shadow => |value| {
                _ = value;
            },
        }
    }

    pub fn addStroke(self: *CanvasResourceCounts, stroke: canvas.Stroke) anyerror!void {
        try self.addFill(stroke.fill);
    }

    pub fn addFill(self: *CanvasResourceCounts, fill: canvas.Fill) anyerror!void {
        switch (fill) {
            .color => {},
            .linear_gradient => |gradient| try addCanvasCount(&self.gradient_stop_count, gradient.stops.len, max_canvas_gradient_stops_per_view, error.CanvasGradientStopLimitReached),
        }
    }
};

pub const CanvasDisplayListScratch = struct {
    gradient_stops: [max_canvas_gradient_stops_per_view]canvas.GradientStop = undefined,
    gradient_stop_count: usize = 0,
    path_elements: [max_canvas_path_elements_per_view]canvas.PathElement = undefined,
    path_element_count: usize = 0,
    glyphs: [max_canvas_glyphs_per_view]canvas.Glyph = undefined,
    glyph_count: usize = 0,
    text_bytes: [max_canvas_text_bytes_per_view]u8 = undefined,
    text_len: usize = 0,

    pub fn appendCopiedCommand(self: *CanvasDisplayListScratch, builder: *canvas.Builder, command: canvas.CanvasCommand) anyerror!void {
        try builder.append(try self.copyCanvasCommand(command));
    }

    pub fn copyCanvasCommand(self: *CanvasDisplayListScratch, command: canvas.CanvasCommand) anyerror!canvas.CanvasCommand {
        return switch (command) {
            .push_clip => |value| .{ .push_clip = value },
            .pop_clip => .pop_clip,
            .push_opacity => |value| .{ .push_opacity = value },
            .pop_opacity => .pop_opacity,
            .transform => |value| .{ .transform = value },
            .fill_rect => |value| blk: {
                var copy = value;
                copy.fill = try self.copyCanvasFill(value.fill);
                break :blk .{ .fill_rect = copy };
            },
            .stroke_rect => |value| blk: {
                var copy = value;
                copy.stroke = try self.copyCanvasStroke(value.stroke);
                break :blk .{ .stroke_rect = copy };
            },
            .fill_rounded_rect => |value| blk: {
                var copy = value;
                copy.fill = try self.copyCanvasFill(value.fill);
                break :blk .{ .fill_rounded_rect = copy };
            },
            .draw_line => |value| blk: {
                var copy = value;
                copy.stroke = try self.copyCanvasStroke(value.stroke);
                break :blk .{ .draw_line = copy };
            },
            .fill_path => |value| blk: {
                var copy = value;
                copy.elements = try self.copyCanvasPathElements(value.elements);
                copy.fill = try self.copyCanvasFill(value.fill);
                break :blk .{ .fill_path = copy };
            },
            .stroke_path => |value| blk: {
                var copy = value;
                copy.elements = try self.copyCanvasPathElements(value.elements);
                copy.stroke = try self.copyCanvasStroke(value.stroke);
                break :blk .{ .stroke_path = copy };
            },
            .draw_image => |value| .{ .draw_image = value },
            .draw_text => |value| blk: {
                var copy = value;
                copy.text = try self.copyCanvasText(value.text);
                copy.glyphs = try self.copyCanvasGlyphs(value.glyphs);
                break :blk .{ .draw_text = copy };
            },
            .shadow => |value| .{ .shadow = value },
            .blur => |value| .{ .blur = value },
        };
    }

    pub fn copyCanvasStroke(self: *CanvasDisplayListScratch, stroke: canvas.Stroke) anyerror!canvas.Stroke {
        var copy = stroke;
        copy.fill = try self.copyCanvasFill(stroke.fill);
        return copy;
    }

    pub fn copyCanvasFill(self: *CanvasDisplayListScratch, fill: canvas.Fill) anyerror!canvas.Fill {
        return switch (fill) {
            .color => |color| .{ .color = color },
            .linear_gradient => |gradient| .{ .linear_gradient = .{
                .start = gradient.start,
                .end = gradient.end,
                .stops = try self.copyCanvasGradientStops(gradient.stops),
            } },
        };
    }

    pub fn copyCanvasGradientStops(self: *CanvasDisplayListScratch, stops: []const canvas.GradientStop) anyerror![]const canvas.GradientStop {
        const end = self.gradient_stop_count + stops.len;
        if (end > self.gradient_stops.len) return error.CanvasGradientStopLimitReached;
        const start = self.gradient_stop_count;
        @memcpy(self.gradient_stops[start..end], stops);
        self.gradient_stop_count = end;
        return self.gradient_stops[start..end];
    }

    pub fn copyCanvasPathElements(self: *CanvasDisplayListScratch, elements: []const canvas.PathElement) anyerror![]const canvas.PathElement {
        const end = self.path_element_count + elements.len;
        if (end > self.path_elements.len) return error.CanvasPathElementLimitReached;
        const start = self.path_element_count;
        @memcpy(self.path_elements[start..end], elements);
        self.path_element_count = end;
        return self.path_elements[start..end];
    }

    pub fn copyCanvasGlyphs(self: *CanvasDisplayListScratch, glyphs: []const canvas.Glyph) anyerror![]const canvas.Glyph {
        const end = self.glyph_count + glyphs.len;
        if (end > self.glyphs.len) return error.CanvasGlyphLimitReached;
        const start = self.glyph_count;
        @memcpy(self.glyphs[start..end], glyphs);
        self.glyph_count = end;
        return self.glyphs[start..end];
    }

    pub fn copyCanvasText(self: *CanvasDisplayListScratch, text: []const u8) anyerror![]const u8 {
        const end = self.text_len + text.len;
        if (end > self.text_bytes.len) return error.CanvasTextTooLarge;
        const start = self.text_len;
        @memcpy(self.text_bytes[start..end], text);
        self.text_len = end;
        return self.text_bytes[start..end];
    }
};

fn addCanvasCount(value: *usize, amount: usize, max_value: usize, comptime failure: anyerror) anyerror!void {
    if (amount > max_value or value.* > max_value - amount) return failure;
    value.* += amount;
}

pub fn canvasRenderAnimationStartNsForView(view: *const RuntimeView) u64 {
    return @max(view.gpu_input_timestamp_ns, view.gpu_timestamp_ns);
}

pub const PresentedCanvasCommand = struct {
    id: ?canvas.ObjectId = null,
    bounds: ?geometry.RectF = null,
};

pub const RuntimeView = struct {
    id: platform.ViewId = 0,
    window_id: platform.WindowId = 1,
    label: []const u8 = "",
    kind: platform.ViewKind = .toolbar,
    parent: ?[]const u8 = null,
    frame: geometry.RectF = geometry.RectF.init(0, 0, 0, 0),
    layer: i32 = 0,
    visible: bool = true,
    enabled: bool = true,
    role: []const u8 = "",
    accessibility_label: []const u8 = "",
    text: []const u8 = "",
    command: []const u8 = "",
    transparent: bool = false,
    bridge_enabled: bool = false,
    gpu_size: geometry.SizeF = geometry.SizeF.init(0, 0),
    gpu_scale_factor: f32 = 1,
    gpu_frame_index: u64 = 0,
    gpu_timestamp_ns: u64 = 0,
    gpu_frame_interval_ns: u64 = platform.default_gpu_frame_interval_ns,
    gpu_pending_input_timestamp_ns: u64 = 0,
    gpu_input_timestamp_ns: u64 = 0,
    gpu_input_latency_ns: u64 = 0,
    gpu_input_latency_budget_ns: u64 = platform.default_gpu_frame_interval_ns,
    gpu_input_latency_budget_custom: bool = false,
    gpu_input_latency_budget_exceeded_count: usize = 0,
    gpu_input_latency_budget_ok: bool = true,
    gpu_surface_created_timestamp_ns: u64 = 0,
    gpu_first_frame_latency_ns: u64 = 0,
    gpu_first_frame_latency_budget_ns: u64 = platform.default_gpu_first_frame_latency_budget_ns,
    gpu_first_frame_latency_budget_exceeded_count: usize = 0,
    gpu_first_frame_latency_budget_ok: bool = true,
    gpu_first_frame_latency_recorded: bool = false,
    gpu_frame_nonblank: bool = false,
    gpu_sample_color: u32 = 0,
    gpu_backend: platform.GpuSurfaceBackend = .none,
    gpu_pixel_format: platform.GpuSurfacePixelFormat = .none,
    gpu_present_mode: platform.GpuSurfacePresentMode = .none,
    gpu_alpha_mode: platform.GpuSurfaceAlphaMode = .none,
    gpu_color_space: platform.GpuSurfaceColorSpace = .none,
    gpu_vsync: bool = false,
    gpu_status: platform.GpuSurfaceStatus = .unavailable,
    canvas_commands: [max_canvas_commands_per_view]canvas.CanvasCommand = undefined,
    canvas_command_count: usize = 0,
    canvas_revision: u64 = 0,
    canvas_gradient_stops: [max_canvas_gradient_stops_per_view]canvas.GradientStop = undefined,
    canvas_gradient_stop_count: usize = 0,
    canvas_path_elements: [max_canvas_path_elements_per_view]canvas.PathElement = undefined,
    canvas_path_element_count: usize = 0,
    canvas_glyphs: [max_canvas_glyphs_per_view]canvas.Glyph = undefined,
    canvas_glyph_count: usize = 0,
    canvas_text_bytes: [max_canvas_text_bytes_per_view]u8 = undefined,
    canvas_text_len: usize = 0,
    canvas_display_list_widget_owned: bool = false,
    canvas_widget_display_list_prefix_count: usize = 0,
    canvas_widget_display_list_suffix_count: usize = 0,
    canvas_widget_display_list_reserved_count: usize = 0,
    presented_canvas_valid: bool = false,
    presented_canvas_revision: u64 = 0,
    presented_canvas_surface_size: geometry.SizeF = geometry.SizeF.init(0, 0),
    presented_canvas_scale: f32 = 1,
    presented_canvas_commands: [max_canvas_commands_per_view]PresentedCanvasCommand = undefined,
    presented_canvas_command_count: usize = 0,
    presented_canvas_has_unkeyed: bool = false,
    canvas_render_animations: [max_canvas_render_animations_per_view]canvas.CanvasRenderAnimation = undefined,
    canvas_render_animation_count: usize = 0,
    canvas_render_animation_dirty_bounds: [max_canvas_render_animation_dirty_bounds_per_view]CanvasRenderAnimationDirtyBounds = undefined,
    canvas_render_animation_dirty_bounds_count: usize = 0,
    canvas_frame_render_overrides: [max_canvas_render_overrides_per_view]canvas.CanvasRenderOverride = undefined,
    canvas_frame_render_override_count: usize = 0,
    canvas_frame_path_geometry_cache: [max_canvas_path_geometries_per_view]canvas.RenderPathGeometryCacheEntry = undefined,
    canvas_frame_path_geometry_cache_count: usize = 0,
    canvas_frame_image_cache: [max_canvas_images_per_view]canvas.RenderImageCacheEntry = undefined,
    canvas_frame_image_cache_count: usize = 0,
    canvas_frame_layer_cache: [max_canvas_layers_per_view]canvas.RenderLayerCacheEntry = undefined,
    canvas_frame_layer_cache_count: usize = 0,
    canvas_frame_resource_cache: [max_canvas_resources_per_view]canvas.RenderResourceCacheEntry = undefined,
    canvas_frame_resource_cache_count: usize = 0,
    canvas_frame_visual_effect_cache: [max_canvas_visual_effects_per_view]canvas.VisualEffectCacheEntry = undefined,
    canvas_frame_visual_effect_cache_count: usize = 0,
    canvas_frame_glyph_atlas_cache: [max_canvas_glyphs_per_view]canvas.GlyphAtlasCacheEntry = undefined,
    canvas_frame_glyph_atlas_cache_count: usize = 0,
    canvas_frame_text_layout_cache: [max_canvas_text_layouts_per_view]canvas.TextLayoutCacheEntry = undefined,
    canvas_frame_text_layout_cache_count: usize = 0,
    canvas_frame_pipeline_cache: [max_canvas_pipelines_per_view]canvas.RenderPipelineCacheEntry = undefined,
    canvas_frame_pipeline_cache_count: usize = 0,
    canvas_frame_requires_render: bool = false,
    canvas_frame_full_repaint: bool = false,
    canvas_frame_batch_count: usize = 0,
    canvas_frame_encoder_command_count: usize = 0,
    canvas_frame_encoder_cache_action_count: usize = 0,
    canvas_frame_encoder_bind_pipeline_count: usize = 0,
    canvas_frame_encoder_draw_batch_count: usize = 0,
    canvas_frame_pipeline_count: usize = 0,
    canvas_frame_pipeline_upload_count: usize = 0,
    canvas_frame_pipeline_retain_count: usize = 0,
    canvas_frame_pipeline_evict_count: usize = 0,
    canvas_frame_path_geometry_count: usize = 0,
    canvas_frame_path_geometry_vertex_count: usize = 0,
    canvas_frame_path_geometry_index_count: usize = 0,
    canvas_frame_path_geometry_upload_count: usize = 0,
    canvas_frame_path_geometry_retain_count: usize = 0,
    canvas_frame_path_geometry_evict_count: usize = 0,
    canvas_frame_image_count: usize = 0,
    canvas_frame_image_upload_count: usize = 0,
    canvas_frame_image_retain_count: usize = 0,
    canvas_frame_image_evict_count: usize = 0,
    canvas_frame_layer_count: usize = 0,
    canvas_frame_layer_opacity_count: usize = 0,
    canvas_frame_layer_clip_count: usize = 0,
    canvas_frame_layer_transform_count: usize = 0,
    canvas_frame_layer_upload_count: usize = 0,
    canvas_frame_layer_retain_count: usize = 0,
    canvas_frame_layer_evict_count: usize = 0,
    canvas_frame_resource_count: usize = 0,
    canvas_frame_resource_upload_count: usize = 0,
    canvas_frame_resource_retain_count: usize = 0,
    canvas_frame_resource_evict_count: usize = 0,
    canvas_frame_visual_effect_count: usize = 0,
    canvas_frame_visual_effect_shadow_count: usize = 0,
    canvas_frame_visual_effect_blur_count: usize = 0,
    canvas_frame_visual_effect_upload_count: usize = 0,
    canvas_frame_visual_effect_retain_count: usize = 0,
    canvas_frame_visual_effect_evict_count: usize = 0,
    canvas_frame_glyph_atlas_entry_count: usize = 0,
    canvas_frame_glyph_atlas_upload_count: usize = 0,
    canvas_frame_glyph_atlas_retain_count: usize = 0,
    canvas_frame_glyph_atlas_evict_count: usize = 0,
    canvas_frame_text_layout_count: usize = 0,
    canvas_frame_text_layout_line_count: usize = 0,
    canvas_frame_text_layout_upload_count: usize = 0,
    canvas_frame_text_layout_retain_count: usize = 0,
    canvas_frame_text_layout_evict_count: usize = 0,
    canvas_frame_gpu_packet_command_count: usize = 0,
    canvas_frame_gpu_packet_cache_action_count: usize = 0,
    canvas_frame_gpu_packet_cached_resource_command_count: usize = 0,
    canvas_frame_gpu_packet_unsupported_command_count: usize = 0,
    canvas_frame_gpu_packet_representable: bool = true,
    canvas_frame_change_count: usize = 0,
    canvas_frame_budget: canvas.CanvasFrameBudget = .{},
    canvas_frame_budget_status: canvas.CanvasFrameBudgetStatus = .{},
    canvas_frame_dirty_bounds: ?geometry.RectF = null,
    canvas_frame_profile_work_units: usize = 0,
    canvas_frame_profile_risk: platform.CanvasFrameProfileRisk = .idle,
    canvas_frame_profile_surface_area: f32 = 0,
    canvas_frame_profile_dirty_area: f32 = 0,
    canvas_frame_profile_dirty_ratio: f32 = 0,
    widget_layout_nodes: [max_canvas_widget_nodes_per_view]canvas.WidgetLayoutNode = undefined,
    widget_layout_node_count: usize = 0,
    widget_semantics_nodes: [max_canvas_widget_semantics_per_view]canvas.WidgetSemanticsNode = undefined,
    widget_semantics_node_count: usize = 0,
    widget_revision: u64 = 0,
    widget_tokens: canvas.DesignTokens = .{},
    widget_scroll_states: [max_canvas_widget_nodes_per_view]canvas.ScrollState = undefined,
    widget_source_text_entries: [max_canvas_widget_source_text_entries_per_view]CanvasWidgetSourceTextEntry = undefined,
    widget_source_text_count: usize = 0,
    canvas_widget_focused_id: canvas.ObjectId = 0,
    canvas_widget_focus_visible_id: canvas.ObjectId = 0,
    canvas_widget_hovered_id: canvas.ObjectId = 0,
    canvas_widget_pressed_id: canvas.ObjectId = 0,
    canvas_widget_cursor: platform.Cursor = .arrow,
    widget_text_bytes: [max_canvas_widget_text_bytes_per_view]u8 = undefined,
    widget_text_len: usize = 0,
    focused: bool = false,
    open: bool = false,
    label_storage: [platform.max_view_label_bytes]u8 = undefined,
    parent_storage: [platform.max_view_label_bytes]u8 = undefined,
    role_storage: [platform.max_view_role_bytes]u8 = undefined,
    accessibility_label_storage: [platform.max_view_accessibility_label_bytes]u8 = undefined,
    text_storage: [platform.max_view_text_bytes]u8 = undefined,
    command_storage: [platform.max_view_command_bytes]u8 = undefined,

    const CanvasWidgetTextMethods = view_widget_text.RuntimeViewCanvasWidgetText(RuntimeView);
    pub const applyCanvasWidgetTextEdit = CanvasWidgetTextMethods.applyCanvasWidgetTextEdit;
    pub const canvasWidgetKeyboardTextEdit = CanvasWidgetTextMethods.canvasWidgetKeyboardTextEdit;
    pub const canEditCanvasWidgetText = CanvasWidgetTextMethods.canEditCanvasWidgetText;
    pub const applyCanvasWidgetTextPointer = CanvasWidgetTextMethods.applyCanvasWidgetTextPointer;
    pub const rewriteCanvasWidgetTextStorage = CanvasWidgetTextMethods.rewriteCanvasWidgetTextStorage;
    pub const setCanvasWidgetTextValue = CanvasWidgetTextMethods.setCanvasWidgetTextValue;

    const CanvasWidgetScrollMethods = view_widget_scroll.RuntimeViewCanvasWidgetScroll(RuntimeView);
    pub const canvasWidgetKineticScrollActive = CanvasWidgetScrollMethods.canvasWidgetKineticScrollActive;
    pub const applyCanvasWidgetScrollRoute = CanvasWidgetScrollMethods.applyCanvasWidgetScrollRoute;
    pub const deepestCanvasWidgetScrollIndex = CanvasWidgetScrollMethods.deepestCanvasWidgetScrollIndex;
    pub const canvasWidgetScrollState = CanvasWidgetScrollMethods.canvasWidgetScrollState;
    pub const canvasWidgetScrollCanConsume = CanvasWidgetScrollMethods.canvasWidgetScrollCanConsume;
    pub const applyCanvasWidgetScroll = CanvasWidgetScrollMethods.applyCanvasWidgetScroll;
    pub const applyCanvasWidgetTextareaScroll = CanvasWidgetScrollMethods.applyCanvasWidgetTextareaScroll;
    pub const applyCanvasWidgetScrollKeyboardTarget = CanvasWidgetScrollMethods.applyCanvasWidgetScrollKeyboardTarget;
    pub const stepCanvasWidgetKineticScroll = CanvasWidgetScrollMethods.stepCanvasWidgetKineticScroll;
    pub const canvasWidgetScrollContentExtent = CanvasWidgetScrollMethods.canvasWidgetScrollContentExtent;
    pub const translateCanvasWidgetScrollDescendants = CanvasWidgetScrollMethods.translateCanvasWidgetScrollDescendants;
    pub const scrollCanvasTextareaCaretIntoView = CanvasWidgetScrollMethods.scrollCanvasTextareaCaretIntoView;

    pub fn info(self: RuntimeView) platform.ViewInfo {
        return .{
            .id = self.id,
            .window_id = self.window_id,
            .label = self.label,
            .kind = self.kind,
            .parent = self.parent,
            .frame = self.frame,
            .layer = self.layer,
            .visible = self.visible,
            .enabled = self.enabled,
            .role = self.role,
            .accessibility_label = self.accessibility_label,
            .text = self.text,
            .command = self.command,
            .url = "",
            .transparent = self.transparent,
            .bridge_enabled = self.bridge_enabled,
            .gpu_size = self.gpu_size,
            .gpu_scale_factor = self.gpu_scale_factor,
            .gpu_frame_index = self.gpu_frame_index,
            .gpu_timestamp_ns = self.gpu_timestamp_ns,
            .gpu_frame_interval_ns = self.gpu_frame_interval_ns,
            .gpu_input_timestamp_ns = self.gpu_input_timestamp_ns,
            .gpu_input_latency_ns = self.gpu_input_latency_ns,
            .gpu_input_latency_budget_ns = self.gpu_input_latency_budget_ns,
            .gpu_input_latency_budget_exceeded_count = self.gpu_input_latency_budget_exceeded_count,
            .gpu_input_latency_budget_ok = self.gpu_input_latency_budget_ok,
            .gpu_first_frame_latency_ns = self.gpu_first_frame_latency_ns,
            .gpu_first_frame_latency_budget_ns = self.gpu_first_frame_latency_budget_ns,
            .gpu_first_frame_latency_budget_exceeded_count = self.gpu_first_frame_latency_budget_exceeded_count,
            .gpu_first_frame_latency_budget_ok = self.gpu_first_frame_latency_budget_ok,
            .gpu_frame_nonblank = self.gpu_frame_nonblank,
            .gpu_sample_color = self.gpu_sample_color,
            .gpu_backend = self.gpu_backend,
            .gpu_pixel_format = self.gpu_pixel_format,
            .gpu_present_mode = self.gpu_present_mode,
            .gpu_alpha_mode = self.gpu_alpha_mode,
            .gpu_color_space = self.gpu_color_space,
            .gpu_vsync = self.gpu_vsync,
            .gpu_status = self.gpu_status,
            .canvas_revision = self.canvas_revision,
            .canvas_command_count = self.canvas_command_count,
            .canvas_frame_requires_render = self.canvas_frame_requires_render,
            .canvas_frame_full_repaint = self.canvas_frame_full_repaint,
            .canvas_frame_batch_count = self.canvas_frame_batch_count,
            .canvas_frame_encoder_command_count = self.canvas_frame_encoder_command_count,
            .canvas_frame_encoder_cache_action_count = self.canvas_frame_encoder_cache_action_count,
            .canvas_frame_encoder_bind_pipeline_count = self.canvas_frame_encoder_bind_pipeline_count,
            .canvas_frame_encoder_draw_batch_count = self.canvas_frame_encoder_draw_batch_count,
            .canvas_frame_pipeline_count = self.canvas_frame_pipeline_count,
            .canvas_frame_pipeline_upload_count = self.canvas_frame_pipeline_upload_count,
            .canvas_frame_pipeline_retain_count = self.canvas_frame_pipeline_retain_count,
            .canvas_frame_pipeline_evict_count = self.canvas_frame_pipeline_evict_count,
            .canvas_frame_path_geometry_count = self.canvas_frame_path_geometry_count,
            .canvas_frame_path_geometry_vertex_count = self.canvas_frame_path_geometry_vertex_count,
            .canvas_frame_path_geometry_index_count = self.canvas_frame_path_geometry_index_count,
            .canvas_frame_path_geometry_upload_count = self.canvas_frame_path_geometry_upload_count,
            .canvas_frame_path_geometry_retain_count = self.canvas_frame_path_geometry_retain_count,
            .canvas_frame_path_geometry_evict_count = self.canvas_frame_path_geometry_evict_count,
            .canvas_frame_image_count = self.canvas_frame_image_count,
            .canvas_frame_image_upload_count = self.canvas_frame_image_upload_count,
            .canvas_frame_image_retain_count = self.canvas_frame_image_retain_count,
            .canvas_frame_image_evict_count = self.canvas_frame_image_evict_count,
            .canvas_frame_layer_count = self.canvas_frame_layer_count,
            .canvas_frame_layer_opacity_count = self.canvas_frame_layer_opacity_count,
            .canvas_frame_layer_clip_count = self.canvas_frame_layer_clip_count,
            .canvas_frame_layer_transform_count = self.canvas_frame_layer_transform_count,
            .canvas_frame_layer_upload_count = self.canvas_frame_layer_upload_count,
            .canvas_frame_layer_retain_count = self.canvas_frame_layer_retain_count,
            .canvas_frame_layer_evict_count = self.canvas_frame_layer_evict_count,
            .canvas_frame_resource_count = self.canvas_frame_resource_count,
            .canvas_frame_resource_upload_count = self.canvas_frame_resource_upload_count,
            .canvas_frame_resource_retain_count = self.canvas_frame_resource_retain_count,
            .canvas_frame_resource_evict_count = self.canvas_frame_resource_evict_count,
            .canvas_frame_visual_effect_count = self.canvas_frame_visual_effect_count,
            .canvas_frame_visual_effect_shadow_count = self.canvas_frame_visual_effect_shadow_count,
            .canvas_frame_visual_effect_blur_count = self.canvas_frame_visual_effect_blur_count,
            .canvas_frame_visual_effect_upload_count = self.canvas_frame_visual_effect_upload_count,
            .canvas_frame_visual_effect_retain_count = self.canvas_frame_visual_effect_retain_count,
            .canvas_frame_visual_effect_evict_count = self.canvas_frame_visual_effect_evict_count,
            .canvas_frame_glyph_atlas_entry_count = self.canvas_frame_glyph_atlas_entry_count,
            .canvas_frame_glyph_atlas_upload_count = self.canvas_frame_glyph_atlas_upload_count,
            .canvas_frame_glyph_atlas_retain_count = self.canvas_frame_glyph_atlas_retain_count,
            .canvas_frame_glyph_atlas_evict_count = self.canvas_frame_glyph_atlas_evict_count,
            .canvas_frame_text_layout_count = self.canvas_frame_text_layout_count,
            .canvas_frame_text_layout_line_count = self.canvas_frame_text_layout_line_count,
            .canvas_frame_text_layout_upload_count = self.canvas_frame_text_layout_upload_count,
            .canvas_frame_text_layout_retain_count = self.canvas_frame_text_layout_retain_count,
            .canvas_frame_text_layout_evict_count = self.canvas_frame_text_layout_evict_count,
            .canvas_frame_gpu_packet_command_count = self.canvas_frame_gpu_packet_command_count,
            .canvas_frame_gpu_packet_cache_action_count = self.canvas_frame_gpu_packet_cache_action_count,
            .canvas_frame_gpu_packet_cached_resource_command_count = self.canvas_frame_gpu_packet_cached_resource_command_count,
            .canvas_frame_gpu_packet_unsupported_command_count = self.canvas_frame_gpu_packet_unsupported_command_count,
            .canvas_frame_gpu_packet_representable = self.canvas_frame_gpu_packet_representable,
            .canvas_frame_change_count = self.canvas_frame_change_count,
            .canvas_frame_budget_exceeded_count = self.canvas_frame_budget_status.exceededCount(),
            .canvas_frame_budget_ok = self.canvas_frame_budget_status.ok(),
            .canvas_frame_dirty_bounds = self.canvas_frame_dirty_bounds,
            .canvas_frame_profile_work_units = self.canvas_frame_profile_work_units,
            .canvas_frame_profile_risk = self.canvas_frame_profile_risk,
            .canvas_frame_profile_surface_area = self.canvas_frame_profile_surface_area,
            .canvas_frame_profile_dirty_area = self.canvas_frame_profile_dirty_area,
            .canvas_frame_profile_dirty_ratio = self.canvas_frame_profile_dirty_ratio,
            .widget_revision = self.widget_revision,
            .widget_node_count = self.widget_layout_node_count,
            .widget_semantics_count = self.widget_semantics_node_count,
            .cursor = self.canvas_widget_cursor,
            .focused = self.focused,
            .open = self.open,
        };
    }

    pub fn recordGpuSurfaceInputTimestamp(self: *RuntimeView, timestamp_ns: u64) void {
        if (timestamp_ns == 0) return;
        self.gpu_pending_input_timestamp_ns = timestamp_ns;
        self.gpu_input_timestamp_ns = timestamp_ns;
    }

    pub fn recordGpuSurfaceInputLatencyForFrame(self: *RuntimeView, timestamp_ns: u64) void {
        const input_timestamp_ns = self.gpu_pending_input_timestamp_ns;
        if (input_timestamp_ns == 0 or timestamp_ns < input_timestamp_ns) return;
        self.gpu_pending_input_timestamp_ns = 0;
        self.gpu_input_timestamp_ns = input_timestamp_ns;
        self.gpu_input_latency_ns = timestamp_ns - input_timestamp_ns;
        self.refreshGpuSurfaceInputLatencyBudgetStatus();
    }

    pub fn refreshGpuSurfaceInputLatencyBudgetStatus(self: *RuntimeView) void {
        self.gpu_input_latency_budget_exceeded_count = if (self.gpu_input_latency_budget_ns > 0 and self.gpu_input_latency_ns > self.gpu_input_latency_budget_ns) 1 else 0;
        self.gpu_input_latency_budget_ok = self.gpu_input_latency_budget_exceeded_count == 0;
    }

    pub fn recordGpuSurfaceFrameInterval(self: *RuntimeView, frame_interval_ns: u64) void {
        const normalized = if (frame_interval_ns > 0) frame_interval_ns else platform.default_gpu_frame_interval_ns;
        self.gpu_frame_interval_ns = normalized;
        if (!self.gpu_input_latency_budget_custom) {
            self.gpu_input_latency_budget_ns = normalized;
            self.refreshGpuSurfaceInputLatencyBudgetStatus();
        }
    }

    pub fn recordGpuSurfaceFirstFrameLatency(self: *RuntimeView, timestamp_ns: u64) void {
        if (self.gpu_first_frame_latency_recorded) return;
        if (self.gpu_surface_created_timestamp_ns == 0 or timestamp_ns < self.gpu_surface_created_timestamp_ns) return;
        self.gpu_first_frame_latency_recorded = true;
        self.gpu_first_frame_latency_ns = timestamp_ns - self.gpu_surface_created_timestamp_ns;
        self.refreshGpuSurfaceFirstFrameLatencyBudgetStatus();
    }

    pub fn refreshGpuSurfaceFirstFrameLatencyBudgetStatus(self: *RuntimeView) void {
        self.gpu_first_frame_latency_budget_exceeded_count = if (self.gpu_first_frame_latency_budget_ns > 0 and self.gpu_first_frame_latency_ns > self.gpu_first_frame_latency_budget_ns) 1 else 0;
        self.gpu_first_frame_latency_budget_ok = self.gpu_first_frame_latency_budget_exceeded_count == 0;
    }

    pub fn copyRuntimeStateFrom(self: *RuntimeView, source: *const RuntimeView) void {
        self.* = source.*;
        self.label = copyInto(&self.label_storage, source.label) catch unreachable;
        self.parent = if (source.parent) |parent| copyInto(&self.parent_storage, parent) catch unreachable else null;
        self.role = copyInto(&self.role_storage, source.role) catch unreachable;
        self.accessibility_label = copyInto(&self.accessibility_label_storage, source.accessibility_label) catch unreachable;
        self.text = copyInto(&self.text_storage, source.text) catch unreachable;
        self.command = copyInto(&self.command_storage, source.command) catch unreachable;
        self.copyCanvasDisplayList(source.canvasDisplayList()) catch unreachable;
        self.canvas_revision = source.canvas_revision;
        self.copyPresentedCanvasSummaryFrom(source);
        self.copyWidgetLayoutTree(source.widgetLayoutTree()) catch unreachable;
        self.widget_revision = source.widget_revision;
        @memcpy(self.widget_scroll_states[0..source.widget_layout_node_count], source.widget_scroll_states[0..source.widget_layout_node_count]);
    }

    pub fn canvasDisplayList(self: *const RuntimeView) canvas.DisplayList {
        return .{ .commands = self.canvas_commands[0..self.canvas_command_count] };
    }

    pub fn validateCanvasWidgetDisplayListChrome(self: *const RuntimeView, chrome: CanvasWidgetDisplayListChrome) anyerror!void {
        if (chrome.prefix_command_count > self.canvas_command_count) return error.InvalidCommand;
        if (chrome.suffix_command_count > self.canvas_command_count - chrome.prefix_command_count) return error.InvalidCommand;
        if (chrome.reserved_command_count > max_canvas_commands_per_view) return error.CanvasCommandLimitReached;
    }

    pub fn canvasFrameResourceCache(self: *const RuntimeView) []const canvas.RenderResourceCacheEntry {
        return self.canvas_frame_resource_cache[0..self.canvas_frame_resource_cache_count];
    }

    pub fn canvasFramePathGeometryCache(self: *const RuntimeView) []const canvas.RenderPathGeometryCacheEntry {
        return self.canvas_frame_path_geometry_cache[0..self.canvas_frame_path_geometry_cache_count];
    }

    pub fn canvasFrameImageCache(self: *const RuntimeView) []const canvas.RenderImageCacheEntry {
        return self.canvas_frame_image_cache[0..self.canvas_frame_image_cache_count];
    }

    pub fn canvasFrameLayerCache(self: *const RuntimeView) []const canvas.RenderLayerCacheEntry {
        return self.canvas_frame_layer_cache[0..self.canvas_frame_layer_cache_count];
    }

    pub fn canvasFrameVisualEffectCache(self: *const RuntimeView) []const canvas.VisualEffectCacheEntry {
        return self.canvas_frame_visual_effect_cache[0..self.canvas_frame_visual_effect_cache_count];
    }

    pub fn canvasRenderAnimations(self: *const RuntimeView) []const canvas.CanvasRenderAnimation {
        return self.canvas_render_animations[0..self.canvas_render_animation_count];
    }

    pub fn canvasFrameRenderOverrides(self: *const RuntimeView) []const canvas.CanvasRenderOverride {
        return self.canvas_frame_render_overrides[0..self.canvas_frame_render_override_count];
    }

    pub fn canvasFramePipelineCache(self: *const RuntimeView) []const canvas.RenderPipelineCacheEntry {
        return self.canvas_frame_pipeline_cache[0..self.canvas_frame_pipeline_cache_count];
    }

    pub fn canvasFrameGlyphAtlasCache(self: *const RuntimeView) []const canvas.GlyphAtlasCacheEntry {
        return self.canvas_frame_glyph_atlas_cache[0..self.canvas_frame_glyph_atlas_cache_count];
    }

    pub fn canvasFrameTextLayoutCache(self: *const RuntimeView) []const canvas.TextLayoutCacheEntry {
        return self.canvas_frame_text_layout_cache[0..self.canvas_frame_text_layout_cache_count];
    }

    pub fn widgetLayoutTree(self: *const RuntimeView) canvas.WidgetLayoutTree {
        return .{ .nodes = self.widget_layout_nodes[0..self.widget_layout_node_count] };
    }

    pub fn widgetSemantics(self: *const RuntimeView) []const canvas.WidgetSemanticsNode {
        return self.widget_semantics_nodes[0..self.widget_semantics_node_count];
    }

    pub fn copyCanvasDisplayList(self: *RuntimeView, display_list: canvas.DisplayList) anyerror!void {
        _ = try CanvasResourceCounts.fromDisplayList(display_list);
        if (display_list.commands.len > 0 and display_list.commands.ptr == self.canvas_commands[0..].ptr) {
            self.canvas_revision += 1;
            return;
        }

        self.canvas_command_count = 0;
        self.canvas_gradient_stop_count = 0;
        self.canvas_path_element_count = 0;
        self.canvas_glyph_count = 0;
        self.canvas_text_len = 0;

        for (display_list.commands) |command| {
            self.canvas_commands[self.canvas_command_count] = try self.copyCanvasCommand(command);
            self.canvas_command_count += 1;
        }
        self.canvas_revision += 1;
    }

    pub fn copyCanvasFrameResourceCache(self: *RuntimeView, entries: []const canvas.RenderResourceCacheEntry) anyerror!void {
        if (entries.len > self.canvas_frame_resource_cache.len) return error.RenderResourceListFull;
        @memcpy(self.canvas_frame_resource_cache[0..entries.len], entries);
        self.canvas_frame_resource_cache_count = entries.len;
    }

    pub fn copyCanvasFramePathGeometryCache(self: *RuntimeView, entries: []const canvas.RenderPathGeometryCacheEntry) anyerror!void {
        if (entries.len > self.canvas_frame_path_geometry_cache.len) return error.PathGeometryListFull;
        @memcpy(self.canvas_frame_path_geometry_cache[0..entries.len], entries);
        self.canvas_frame_path_geometry_cache_count = entries.len;
    }

    pub fn copyCanvasFrameImageCache(self: *RuntimeView, entries: []const canvas.RenderImageCacheEntry) anyerror!void {
        if (entries.len > self.canvas_frame_image_cache.len) return error.ImageListFull;
        @memcpy(self.canvas_frame_image_cache[0..entries.len], entries);
        self.canvas_frame_image_cache_count = entries.len;
    }

    pub fn copyCanvasFrameLayerCache(self: *RuntimeView, entries: []const canvas.RenderLayerCacheEntry) anyerror!void {
        if (entries.len > self.canvas_frame_layer_cache.len) return error.LayerListFull;
        @memcpy(self.canvas_frame_layer_cache[0..entries.len], entries);
        self.canvas_frame_layer_cache_count = entries.len;
    }

    pub fn copyCanvasFrameVisualEffectCache(self: *RuntimeView, entries: []const canvas.VisualEffectCacheEntry) anyerror!void {
        if (entries.len > self.canvas_frame_visual_effect_cache.len) return error.VisualEffectListFull;
        @memcpy(self.canvas_frame_visual_effect_cache[0..entries.len], entries);
        self.canvas_frame_visual_effect_cache_count = entries.len;
    }

    pub fn copyCanvasRenderAnimations(self: *RuntimeView, animations: []const canvas.CanvasRenderAnimation) anyerror!void {
        if (animations.len > self.canvas_render_animations.len) return error.RenderAnimationListFull;
        @memcpy(self.canvas_render_animations[0..animations.len], animations);
        self.canvas_render_animation_count = animations.len;
        self.canvas_render_animation_dirty_bounds_count = 0;
    }

    pub fn replaceCanvasRenderAnimation(self: *RuntimeView, animation: canvas.CanvasRenderAnimation) anyerror!void {
        if (animation.id == 0) return error.InvalidViewOptions;
        var index: usize = 0;
        while (index < self.canvas_render_animation_count) : (index += 1) {
            if (self.canvas_render_animations[index].id == animation.id) {
                self.canvas_render_animations[index] = animation;
                return;
            }
        }
        if (self.canvas_render_animation_count >= self.canvas_render_animations.len) return error.RenderAnimationListFull;
        self.canvas_render_animations[self.canvas_render_animation_count] = animation;
        self.canvas_render_animation_count += 1;
    }

    pub fn removeCanvasRenderAnimation(self: *RuntimeView, id: canvas.ObjectId) void {
        var len: usize = 0;
        for (self.canvasRenderAnimations()) |animation| {
            if (animation.id == id) continue;
            self.canvas_render_animations[len] = animation;
            len += 1;
        }
        self.canvas_render_animation_count = len;
        self.removeCanvasRenderAnimationDirtyBounds(id);
    }

    pub fn replaceCanvasRenderAnimationDirtyBounds(self: *RuntimeView, id: canvas.ObjectId, bounds: ?geometry.RectF) anyerror!void {
        if (id == 0) return error.InvalidViewOptions;
        if (bounds == null) {
            self.removeCanvasRenderAnimationDirtyBounds(id);
            return;
        }
        for (self.canvas_render_animation_dirty_bounds[0..self.canvas_render_animation_dirty_bounds_count]) |*entry| {
            if (entry.id == id) {
                entry.bounds = bounds;
                return;
            }
        }
        if (self.canvas_render_animation_dirty_bounds_count >= self.canvas_render_animation_dirty_bounds.len) return error.RenderAnimationListFull;
        self.canvas_render_animation_dirty_bounds[self.canvas_render_animation_dirty_bounds_count] = .{
            .id = id,
            .bounds = bounds,
        };
        self.canvas_render_animation_dirty_bounds_count += 1;
    }

    pub fn removeCanvasRenderAnimationDirtyBounds(self: *RuntimeView, id: canvas.ObjectId) void {
        var len: usize = 0;
        for (self.canvas_render_animation_dirty_bounds[0..self.canvas_render_animation_dirty_bounds_count]) |entry| {
            if (entry.id == id) continue;
            self.canvas_render_animation_dirty_bounds[len] = entry;
            len += 1;
        }
        self.canvas_render_animation_dirty_bounds_count = len;
    }

    pub fn canvasRenderAnimationDirtyBoundsForOverrides(
        self: *const RuntimeView,
        previous: []const canvas.CanvasRenderOverride,
        next: []const canvas.CanvasRenderOverride,
    ) ?geometry.RectF {
        var bounds: ?geometry.RectF = null;
        for (self.canvas_render_animation_dirty_bounds[0..self.canvas_render_animation_dirty_bounds_count]) |entry| {
            if (findCanvasRenderOverrideIndex(previous, entry.id) == null and findCanvasRenderOverrideIndex(next, entry.id) == null) continue;
            bounds = unionRects(bounds, entry.bounds);
        }
        return bounds;
    }

    pub fn copyCanvasFrameRenderOverrides(self: *RuntimeView, overrides: []const canvas.CanvasRenderOverride) anyerror!void {
        if (overrides.len > self.canvas_frame_render_overrides.len) return error.RenderOverrideListFull;
        @memcpy(self.canvas_frame_render_overrides[0..overrides.len], overrides);
        self.canvas_frame_render_override_count = overrides.len;
    }

    pub fn compactCanvasFrameRenderOverrideNoops(self: *RuntimeView) void {
        var len: usize = 0;
        for (self.canvasFrameRenderOverrides()) |override| {
            if (canvasRenderOverrideNoop(override)) continue;
            self.canvas_frame_render_overrides[len] = override;
            len += 1;
        }
        self.canvas_frame_render_override_count = len;
    }

    pub fn sampleCanvasRenderAnimations(self: *const RuntimeView, timestamp_ns: u64, output: []canvas.CanvasRenderOverride) anyerror![]const canvas.CanvasRenderOverride {
        return canvas.sampleCanvasRenderAnimations(self.canvasRenderAnimations(), timestamp_ns, output);
    }

    pub fn pruneCompletedNoopCanvasRenderAnimations(self: *RuntimeView, timestamp_ns: u64) bool {
        var len: usize = 0;
        var pruned = false;
        for (self.canvasRenderAnimations()) |animation| {
            if (!canvasRenderAnimationActive(animation, timestamp_ns) and canvasRenderAnimationFinalOverrideNoop(animation)) {
                pruned = true;
                self.removeCanvasRenderAnimationDirtyBounds(animation.id);
                continue;
            }
            self.canvas_render_animations[len] = animation;
            len += 1;
        }
        self.canvas_render_animation_count = len;
        return pruned;
    }

    pub fn canvasRenderAnimationsActive(self: *const RuntimeView, timestamp_ns: u64) bool {
        for (self.canvasRenderAnimations()) |animation| {
            if (canvasRenderAnimationActive(animation, timestamp_ns)) return true;
        }
        return false;
    }

    pub fn copyCanvasFramePipelineCache(self: *RuntimeView, entries: []const canvas.RenderPipelineCacheEntry) anyerror!void {
        if (entries.len > self.canvas_frame_pipeline_cache.len) return error.RenderPipelineCacheListFull;
        @memcpy(self.canvas_frame_pipeline_cache[0..entries.len], entries);
        self.canvas_frame_pipeline_cache_count = entries.len;
    }

    pub fn copyCanvasFrameGlyphAtlasCache(self: *RuntimeView, entries: []const canvas.GlyphAtlasCacheEntry) anyerror!void {
        if (entries.len > self.canvas_frame_glyph_atlas_cache.len) return error.GlyphAtlasListFull;
        @memcpy(self.canvas_frame_glyph_atlas_cache[0..entries.len], entries);
        self.canvas_frame_glyph_atlas_cache_count = entries.len;
    }

    pub fn copyCanvasFrameTextLayoutCache(self: *RuntimeView, entries: []const canvas.TextLayoutCacheEntry) anyerror!void {
        const count = @min(entries.len, self.canvas_frame_text_layout_cache.len);
        @memcpy(self.canvas_frame_text_layout_cache[0..count], entries[0..count]);
        self.canvas_frame_text_layout_cache_count = count;
    }

    pub fn recordCanvasFrame(self: *RuntimeView, frame: canvas.CanvasFrame) void {
        const render_pass = frame.renderPass();
        const gpu_packet_summary = frame.gpuPacketSummary();
        self.canvas_frame_requires_render = frame.requiresRender();
        self.canvas_frame_full_repaint = frame.full_repaint;
        self.canvas_frame_batch_count = frame.batch_plan.batchCount();
        self.canvas_frame_encoder_command_count = render_pass.encoderCommandCount();
        self.canvas_frame_encoder_cache_action_count = render_pass.encoderCacheActionCount();
        self.canvas_frame_encoder_bind_pipeline_count = render_pass.encoderBindPipelineCount();
        self.canvas_frame_encoder_draw_batch_count = render_pass.encoderDrawBatchCount();
        self.canvas_frame_pipeline_count = frame.pipeline_cache_plan.entryCount();
        self.canvas_frame_pipeline_upload_count = frame.pipeline_cache_plan.uploadCount();
        self.canvas_frame_pipeline_retain_count = frame.pipeline_cache_plan.retainCount();
        self.canvas_frame_pipeline_evict_count = frame.pipeline_cache_plan.evictCount();
        self.canvas_frame_path_geometry_count = frame.path_geometry_plan.geometryCount();
        self.canvas_frame_path_geometry_vertex_count = frame.path_geometry_plan.vertexCount();
        self.canvas_frame_path_geometry_index_count = frame.path_geometry_plan.indexCount();
        self.canvas_frame_path_geometry_upload_count = frame.path_geometry_cache_plan.uploadCount();
        self.canvas_frame_path_geometry_retain_count = frame.path_geometry_cache_plan.retainCount();
        self.canvas_frame_path_geometry_evict_count = frame.path_geometry_cache_plan.evictCount();
        self.canvas_frame_image_count = frame.image_plan.imageCount();
        self.canvas_frame_image_upload_count = frame.image_cache_plan.uploadCount();
        self.canvas_frame_image_retain_count = frame.image_cache_plan.retainCount();
        self.canvas_frame_image_evict_count = frame.image_cache_plan.evictCount();
        self.canvas_frame_layer_count = frame.layer_plan.layerCount();
        self.canvas_frame_layer_opacity_count = frame.layer_plan.opacityLayerCount();
        self.canvas_frame_layer_clip_count = frame.layer_plan.clipLayerCount();
        self.canvas_frame_layer_transform_count = frame.layer_plan.transformLayerCount();
        self.canvas_frame_layer_upload_count = frame.layer_cache_plan.uploadCount();
        self.canvas_frame_layer_retain_count = frame.layer_cache_plan.retainCount();
        self.canvas_frame_layer_evict_count = frame.layer_cache_plan.evictCount();
        self.canvas_frame_resource_count = frame.resource_plan.resourceCount();
        self.canvas_frame_resource_upload_count = frame.resource_cache_plan.uploadCount();
        self.canvas_frame_resource_retain_count = frame.resource_cache_plan.retainCount();
        self.canvas_frame_resource_evict_count = frame.resource_cache_plan.evictCount();
        self.canvas_frame_visual_effect_count = frame.visual_effect_plan.effectCount();
        self.canvas_frame_visual_effect_shadow_count = frame.visual_effect_plan.shadowCount();
        self.canvas_frame_visual_effect_blur_count = frame.visual_effect_plan.blurCount();
        self.canvas_frame_visual_effect_upload_count = frame.visual_effect_cache_plan.uploadCount();
        self.canvas_frame_visual_effect_retain_count = frame.visual_effect_cache_plan.retainCount();
        self.canvas_frame_visual_effect_evict_count = frame.visual_effect_cache_plan.evictCount();
        self.canvas_frame_glyph_atlas_entry_count = frame.glyph_atlas_plan.entryCount();
        self.canvas_frame_glyph_atlas_upload_count = frame.glyph_atlas_cache_plan.uploadCount();
        self.canvas_frame_glyph_atlas_retain_count = frame.glyph_atlas_cache_plan.retainCount();
        self.canvas_frame_glyph_atlas_evict_count = frame.glyph_atlas_cache_plan.evictCount();
        self.canvas_frame_text_layout_count = frame.text_layout_plan.planCount();
        self.canvas_frame_text_layout_line_count = frame.text_layout_plan.lineCount();
        self.canvas_frame_text_layout_upload_count = frame.text_layout_cache_plan.uploadCount();
        self.canvas_frame_text_layout_retain_count = frame.text_layout_cache_plan.retainCount();
        self.canvas_frame_text_layout_evict_count = frame.text_layout_cache_plan.evictCount();
        self.canvas_frame_gpu_packet_command_count = gpu_packet_summary.command_count;
        self.canvas_frame_gpu_packet_cache_action_count = gpu_packet_summary.cache_action_count;
        self.canvas_frame_gpu_packet_cached_resource_command_count = gpu_packet_summary.cached_resource_command_count;
        self.canvas_frame_gpu_packet_unsupported_command_count = gpu_packet_summary.unsupported_command_count;
        self.canvas_frame_gpu_packet_representable = gpu_packet_summary.fullyRepresentable();
        self.canvas_frame_change_count = frame.changes.len;
        self.canvas_frame_budget = frame.budget;
        self.canvas_frame_budget_status = frame.budgetStatus();
        self.canvas_frame_dirty_bounds = frame.dirty_bounds;
        const profile = frame.profile();
        self.canvas_frame_profile_work_units = profile.work_units;
        self.canvas_frame_profile_risk = platformCanvasFrameProfileRisk(profile.risk);
        self.canvas_frame_profile_surface_area = profile.surface_area;
        self.canvas_frame_profile_dirty_area = profile.dirty_area;
        self.canvas_frame_profile_dirty_ratio = profile.dirty_ratio;
    }

    pub fn recordCanvasFramePresentationComplete(self: *RuntimeView, frame: canvas.CanvasFrame) void {
        if (!self.presented_canvas_valid or self.presented_canvas_revision != self.canvas_revision) return;
        self.recordCanvasFrame(.{
            .frame_index = frame.frame_index,
            .timestamp_ns = frame.timestamp_ns,
            .surface_size = frame.surface_size,
            .scale = frame.scale,
            .display_list = self.canvasDisplayList(),
            .changes = &.{},
            .budget = frame.budget,
        });
    }

    pub fn refreshCanvasFrameBudgetStatus(self: *RuntimeView) void {
        self.canvas_frame_budget_status = self.canvas_frame_budget.status(.{
            .command_count = self.canvas_command_count,
            .batch_count = self.canvas_frame_batch_count,
            .encoder_command_count = self.canvas_frame_encoder_command_count,
            .encoder_cache_action_count = self.canvas_frame_encoder_cache_action_count,
            .encoder_bind_pipeline_count = self.canvas_frame_encoder_bind_pipeline_count,
            .encoder_draw_batch_count = self.canvas_frame_encoder_draw_batch_count,
            .pipeline_count = self.canvas_frame_pipeline_count,
            .pipeline_upload_count = self.canvas_frame_pipeline_upload_count,
            .pipeline_retain_count = self.canvas_frame_pipeline_retain_count,
            .pipeline_evict_count = self.canvas_frame_pipeline_evict_count,
            .path_geometry_count = self.canvas_frame_path_geometry_count,
            .path_geometry_vertex_count = self.canvas_frame_path_geometry_vertex_count,
            .path_geometry_index_count = self.canvas_frame_path_geometry_index_count,
            .path_geometry_upload_count = self.canvas_frame_path_geometry_upload_count,
            .path_geometry_retain_count = self.canvas_frame_path_geometry_retain_count,
            .path_geometry_evict_count = self.canvas_frame_path_geometry_evict_count,
            .image_count = self.canvas_frame_image_count,
            .image_upload_count = self.canvas_frame_image_upload_count,
            .image_retain_count = self.canvas_frame_image_retain_count,
            .image_evict_count = self.canvas_frame_image_evict_count,
            .layer_count = self.canvas_frame_layer_count,
            .layer_opacity_count = self.canvas_frame_layer_opacity_count,
            .layer_clip_count = self.canvas_frame_layer_clip_count,
            .layer_transform_count = self.canvas_frame_layer_transform_count,
            .layer_upload_count = self.canvas_frame_layer_upload_count,
            .layer_retain_count = self.canvas_frame_layer_retain_count,
            .layer_evict_count = self.canvas_frame_layer_evict_count,
            .resource_count = self.canvas_frame_resource_count,
            .resource_upload_count = self.canvas_frame_resource_upload_count,
            .resource_retain_count = self.canvas_frame_resource_retain_count,
            .resource_evict_count = self.canvas_frame_resource_evict_count,
            .visual_effect_count = self.canvas_frame_visual_effect_count,
            .visual_effect_shadow_count = self.canvas_frame_visual_effect_shadow_count,
            .visual_effect_blur_count = self.canvas_frame_visual_effect_blur_count,
            .visual_effect_upload_count = self.canvas_frame_visual_effect_upload_count,
            .visual_effect_retain_count = self.canvas_frame_visual_effect_retain_count,
            .visual_effect_evict_count = self.canvas_frame_visual_effect_evict_count,
            .glyph_atlas_entry_count = self.canvas_frame_glyph_atlas_entry_count,
            .glyph_atlas_upload_count = self.canvas_frame_glyph_atlas_upload_count,
            .glyph_atlas_retain_count = self.canvas_frame_glyph_atlas_retain_count,
            .glyph_atlas_evict_count = self.canvas_frame_glyph_atlas_evict_count,
            .text_layout_count = self.canvas_frame_text_layout_count,
            .text_layout_line_count = self.canvas_frame_text_layout_line_count,
            .text_layout_upload_count = self.canvas_frame_text_layout_upload_count,
            .text_layout_retain_count = self.canvas_frame_text_layout_retain_count,
            .text_layout_evict_count = self.canvas_frame_text_layout_evict_count,
            .change_count = self.canvas_frame_change_count,
            .full_repaint = self.canvas_frame_full_repaint,
            .requires_render = self.canvas_frame_requires_render,
            .dirty_bounds = self.canvas_frame_dirty_bounds,
        });
    }

    pub fn copyPresentedCanvasSummary(self: *RuntimeView, display_list: canvas.DisplayList, surface_size: geometry.SizeF, scale: f32) anyerror!void {
        _ = try CanvasResourceCounts.fromDisplayList(display_list);

        self.presented_canvas_valid = true;
        self.presented_canvas_surface_size = surface_size;
        self.presented_canvas_scale = scale;
        self.presented_canvas_command_count = 0;
        self.presented_canvas_has_unkeyed = false;

        for (display_list.commands) |command| {
            if (self.presented_canvas_command_count >= self.presented_canvas_commands.len) return error.CanvasCommandLimitReached;
            const id = command.objectId();
            self.presented_canvas_commands[self.presented_canvas_command_count] = .{
                .id = id,
                .bounds = command.bounds(),
            };
            if (id == null and command.bounds() != null) self.presented_canvas_has_unkeyed = true;
            self.presented_canvas_command_count += 1;
        }
        self.presented_canvas_revision = self.canvas_revision;
    }

    pub fn copyPresentedCanvasSummaryFrom(self: *RuntimeView, source: *const RuntimeView) void {
        self.presented_canvas_valid = source.presented_canvas_valid;
        self.presented_canvas_command_count = source.presented_canvas_command_count;
        self.presented_canvas_revision = source.presented_canvas_revision;
        self.presented_canvas_surface_size = source.presented_canvas_surface_size;
        self.presented_canvas_scale = source.presented_canvas_scale;
        self.presented_canvas_has_unkeyed = source.presented_canvas_has_unkeyed;
        @memcpy(self.presented_canvas_commands[0..source.presented_canvas_command_count], source.presented_canvas_commands[0..source.presented_canvas_command_count]);
    }

    pub fn currentCanvasHasUnkeyed(self: *const RuntimeView) bool {
        for (self.canvasDisplayList().commands) |command| {
            if (command.objectId() == null and command.bounds() != null) return true;
        }
        return false;
    }

    pub fn diffPresentedCanvasSummary(self: *const RuntimeView, output: []canvas.DiffChange) anyerror![]const canvas.DiffChange {
        if (self.canvas_revision == self.presented_canvas_revision) return output[0..0];

        var len: usize = 0;
        for (self.presented_canvas_commands[0..self.presented_canvas_command_count]) |previous| {
            const id = previous.id orelse continue;
            if (self.currentCanvasCommandById(id) == null) {
                try appendCanvasSummaryChange(output, &len, .{
                    .kind = .removed,
                    .id = id,
                    .dirty_bounds = previous.bounds,
                });
            }
        }

        for (self.canvasDisplayList().commands, 0..) |command, index| {
            const id = command.objectId() orelse continue;
            const bounds = command.bounds();
            if (self.presentedCanvasCommandById(id)) |previous| {
                try appendCanvasSummaryChange(output, &len, .{
                    .kind = .changed,
                    .id = id,
                    .previous_index = previous.index,
                    .next_index = index,
                    .dirty_bounds = unionRects(previous.command.bounds, bounds),
                });
            } else {
                try appendCanvasSummaryChange(output, &len, .{
                    .kind = .added,
                    .id = id,
                    .next_index = index,
                    .dirty_bounds = bounds,
                });
            }
        }

        return output[0..len];
    }

    pub fn currentCanvasCommandById(self: *const RuntimeView, id: canvas.ObjectId) ?canvas.CommandRef {
        for (self.canvasDisplayList().commands, 0..) |command, index| {
            if (command.objectId() == id) return .{ .index = index, .command = command };
        }
        return null;
    }

    const PresentedCanvasCommandRef = struct {
        index: usize,
        command: PresentedCanvasCommand,
    };

    pub fn presentedCanvasCommandById(self: *const RuntimeView, id: canvas.ObjectId) ?PresentedCanvasCommandRef {
        for (self.presented_canvas_commands[0..self.presented_canvas_command_count], 0..) |command, index| {
            if (command.id == id) return .{ .index = index, .command = command };
        }
        return null;
    }

    pub fn widgetSourceTextEntries(self: *const RuntimeView) []const CanvasWidgetSourceTextEntry {
        return self.widget_source_text_entries[0..self.widget_source_text_count];
    }

    pub fn copyCanvasWidgetSourceText(self: *RuntimeView, layout: canvas.WidgetLayoutTree) anyerror!void {
        var entries: [max_canvas_widget_source_text_entries_per_view]CanvasWidgetSourceTextEntry = undefined;
        var entry_count: usize = 0;

        for (layout.nodes) |node| {
            if (node.widget.id == 0 or !canvasWidgetEditableTextKind(node.widget.kind)) continue;
            if (entry_count >= entries.len) break;
            const source_text = canvasWidgetSourceTextFingerprint(node.widget.text);
            entries[entry_count] = .{
                .id = node.widget.id,
                .kind = node.widget.kind,
                .text_len = source_text.len,
                .text_hash = source_text.hash,
            };
            entry_count += 1;
        }

        @memcpy(self.widget_source_text_entries[0..entry_count], entries[0..entry_count]);
        self.widget_source_text_count = entry_count;
    }

    pub fn copyWidgetLayoutTree(self: *RuntimeView, layout: canvas.WidgetLayoutTree) anyerror!void {
        if (layout.nodes.len > self.widget_layout_nodes.len) return error.WidgetNodeLimitReached;
        if (layout.nodes.len > 0 and layout.nodes.ptr == self.widget_layout_nodes[0..].ptr) {
            self.widget_revision += 1;
            return;
        }

        var source_semantics_entries: [max_canvas_widget_semantics_per_view]canvas.WidgetSemanticsNode = undefined;
        const source_semantics = try layout.collectSemantics(&source_semantics_entries);
        var previous_control_entries: [max_canvas_widget_nodes_per_view]CanvasWidgetControlReconcileEntry = undefined;
        const previous_control_states = collectCanvasWidgetControlReconcileEntries(
            self.widgetLayoutTree().nodes,
            &previous_control_entries,
        );
        var previous_scroll_entries: [max_canvas_widget_nodes_per_view]CanvasWidgetScrollReconcileEntry = undefined;
        const previous_scroll_states = collectCanvasWidgetScrollReconcileEntries(
            self.widgetLayoutTree().nodes,
            self.widget_scroll_states[0..self.widget_layout_node_count],
            &previous_scroll_entries,
        );
        var previous_text_entries: [max_canvas_widget_nodes_per_view]CanvasWidgetTextReconcileEntry = undefined;
        var previous_text_bytes: [max_canvas_widget_text_bytes_per_view]u8 = undefined;
        var previous_text_len: usize = 0;
        const previous_text_states = try collectCanvasWidgetTextReconcileEntries(
            self.widgetLayoutTree().nodes,
            self.widgetSourceTextEntries(),
            &previous_text_entries,
            &previous_text_bytes,
            &previous_text_len,
        );

        self.widget_layout_node_count = 0;
        self.widget_semantics_node_count = 0;
        self.widget_text_len = 0;

        for (layout.nodes, 0..) |node, layout_index| {
            const text_reconciled = canvasWidgetLayoutNodeWithTextReconcileState(node, layout, layout_index, previous_text_states);
            const text_copy = try self.copyWidgetLayoutNode(text_reconciled, source_semantics);
            const copy = canvasWidgetLayoutNodeWithControlReconcileState(text_copy, layout, layout_index, previous_control_states);
            self.widget_layout_nodes[self.widget_layout_node_count] = copy;
            self.widget_scroll_states[self.widget_layout_node_count] = canvasWidgetScrollStateForLayoutNode(copy, previous_scroll_states);
            self.widget_layout_node_count += 1;
        }

        clampCanvasWidgetLayoutScrollOffsets(
            self.widget_layout_nodes[0..self.widget_layout_node_count],
            self.widget_scroll_states[0..self.widget_layout_node_count],
        );
        clampCanvasWidgetLayoutTextOffsets(
            self.widget_layout_nodes[0..self.widget_layout_node_count],
            self.widget_tokens,
        );

        const semantics = try self.widgetLayoutTree().collectSemantics(&self.widget_semantics_nodes);
        applyCanvasWidgetSourceScrollSemantics(self.widget_semantics_nodes[0..semantics.len], source_semantics);
        self.widget_semantics_node_count = semantics.len;
        if (self.canvas_widget_focused_id != 0 and self.widgetLayoutTree().focusTargetById(self.canvas_widget_focused_id) == null) {
            self.canvas_widget_focused_id = 0;
            self.canvas_widget_focus_visible_id = 0;
        }
        if (self.canvas_widget_focus_visible_id != 0 and (self.canvas_widget_focus_visible_id != self.canvas_widget_focused_id or self.widgetLayoutTree().focusTargetById(self.canvas_widget_focus_visible_id) == null)) {
            self.canvas_widget_focus_visible_id = 0;
        }
        if (self.canvas_widget_hovered_id != 0 and !canvasWidgetInteractionTargetExists(self.widgetLayoutTree(), self.canvas_widget_hovered_id)) {
            self.canvas_widget_hovered_id = 0;
        }
        if (self.canvas_widget_pressed_id != 0 and !canvasWidgetInteractionTargetExists(self.widgetLayoutTree(), self.canvas_widget_pressed_id)) {
            self.canvas_widget_pressed_id = 0;
        }
        self.canvas_widget_cursor = self.canvasWidgetCursorForId(self.canvas_widget_hovered_id);
        self.widget_revision += 1;
    }

    pub fn canvasWidgetCursorForId(self: *const RuntimeView, id: canvas.ObjectId) platform.Cursor {
        const index = self.canvasWidgetNodeIndexById(id) orelse return .arrow;
        const node = self.widget_layout_nodes[index];
        return platformCursorFromCanvas(canvas.cursorForWidgetTarget(node.widget.kind, node.widget.state));
    }

    pub fn canvasWidgetRenderState(self: *const RuntimeView) canvas.WidgetRenderState {
        const focused_id: ?canvas.ObjectId = if (!self.focused or self.canvas_widget_focused_id == 0) null else self.canvas_widget_focused_id;
        return .{
            .focused_id = focused_id,
            .focus_visible_id = if (focused_id) |id| if (self.canvas_widget_focus_visible_id == id) id else null else null,
            .hovered_id = if (self.canvas_widget_hovered_id == 0) null else self.canvas_widget_hovered_id,
            .pressed_id = if (self.canvas_widget_pressed_id == 0) null else self.canvas_widget_pressed_id,
        };
    }

    pub fn reconcileCanvasWidgetRenderStateAfterScroll(self: *RuntimeView, point: ?geometry.PointF) void {
        const layout = self.widgetLayoutTree();
        if (self.canvas_widget_focused_id != 0 and layout.focusTargetById(self.canvas_widget_focused_id) == null) {
            self.canvas_widget_focused_id = 0;
            self.canvas_widget_focus_visible_id = 0;
        }
        if (self.canvas_widget_focus_visible_id != 0 and (self.canvas_widget_focus_visible_id != self.canvas_widget_focused_id or layout.focusTargetById(self.canvas_widget_focus_visible_id) == null)) {
            self.canvas_widget_focus_visible_id = 0;
        }

        var next_hovered_id = self.canvas_widget_hovered_id;
        var next_cursor = self.canvas_widget_cursor;

        if (point) |value| {
            const hit = layout.hitTestWithTokens(value, self.widget_tokens);
            next_hovered_id = if (hit) |target| target.id else 0;
            next_cursor = platformCursorFromCanvas(layout.cursorForHit(hit));
        } else if (!canvasWidgetInteractionTargetExists(layout, next_hovered_id)) {
            next_hovered_id = 0;
            next_cursor = .arrow;
        }

        var next_pressed_id = self.canvas_widget_pressed_id;
        if (!canvasWidgetInteractionTargetExists(layout, next_pressed_id)) {
            next_pressed_id = 0;
        }

        self.canvas_widget_hovered_id = next_hovered_id;
        self.canvas_widget_pressed_id = next_pressed_id;
        self.canvas_widget_cursor = next_cursor;
    }

    pub fn dismissCanvasWidgetSurfaceForFocusedTarget(self: *RuntimeView, focused_id: canvas.ObjectId) anyerror!?geometry.RectF {
        const focused_index = self.canvasWidgetNodeIndexById(focused_id) orelse return null;
        const focused_widget = self.widget_layout_nodes[focused_index].widget;
        if (canvasWidgetEditableTextKind(focused_widget.kind) and focused_widget.text_composition != null) return null;

        return self.dismissCanvasWidgetSurfaceForTargetIndex(focused_index);
    }

    pub fn dismissCanvasWidgetSurfaceForTarget(self: *RuntimeView, target_id: canvas.ObjectId) anyerror!?geometry.RectF {
        const target_index = self.canvasWidgetNodeIndexById(target_id) orelse return null;
        return self.dismissCanvasWidgetSurfaceForTargetIndex(target_index);
    }

    pub fn dismissCanvasWidgetSurfaceForTargetIndex(self: *RuntimeView, target_index: usize) anyerror!?geometry.RectF {
        const surface_index = self.canvasWidgetDismissibleSurfaceIndexForTarget(target_index) orelse return null;
        return self.dismissCanvasWidgetSurfaceAtIndex(surface_index);
    }

    pub fn dismissCanvasWidgetSurfaceForPointerOutsideFocusedTarget(self: *RuntimeView, focused_id: canvas.ObjectId, route: []const canvas.WidgetEventRouteEntry) anyerror!?geometry.RectF {
        const focused_index = self.canvasWidgetNodeIndexById(focused_id) orelse return null;
        const surface_index = self.canvasWidgetDismissibleSurfaceIndexForTarget(focused_index) orelse return null;
        if (self.canvasWidgetRouteDescendsFromIndex(route, surface_index)) return null;
        return self.dismissCanvasWidgetSurfaceAtIndex(surface_index);
    }

    pub fn dismissCanvasWidgetSurfaceAtIndex(self: *RuntimeView, surface_index: usize) anyerror!?geometry.RectF {
        if (surface_index >= self.widget_layout_node_count) return null;
        const surface = self.widget_layout_nodes[surface_index].widget;
        if (surface.semantics.hidden) return null;
        const dirty = self.canvasWidgetDirtyBounds(surface_index, surface.frame) orelse surface.frame;
        self.widget_layout_nodes[surface_index].widget.semantics.hidden = true;
        if (self.canvasWidgetIdDescendsFromIndex(self.canvas_widget_focused_id, surface_index)) {
            self.canvas_widget_focused_id = 0;
            self.canvas_widget_focus_visible_id = 0;
        }
        if (self.canvasWidgetIdDescendsFromIndex(self.canvas_widget_focus_visible_id, surface_index)) self.canvas_widget_focus_visible_id = 0;
        if (self.canvasWidgetIdDescendsFromIndex(self.canvas_widget_hovered_id, surface_index)) {
            self.canvas_widget_hovered_id = 0;
            self.canvas_widget_cursor = .arrow;
        }
        if (self.canvasWidgetIdDescendsFromIndex(self.canvas_widget_pressed_id, surface_index)) self.canvas_widget_pressed_id = 0;

        try self.refreshCanvasWidgetSemantics();
        self.widget_revision += 1;
        return dirty;
    }

    pub fn canvasWidgetDismissibleSurfaceIndexForTarget(self: *const RuntimeView, target_index: usize) ?usize {
        if (target_index >= self.widget_layout_node_count) return null;
        var current: ?usize = target_index;
        while (current) |index| {
            if (index >= self.widget_layout_node_count) return null;
            const widget = self.widget_layout_nodes[index].widget;
            if (canvasWidgetDismissibleSurfaceKind(widget.kind) and !widget.semantics.hidden) return index;
            current = self.widget_layout_nodes[index].parent_index;
        }
        return null;
    }

    pub fn canvasWidgetRouteDescendsFromIndex(self: *const RuntimeView, route: []const canvas.WidgetEventRouteEntry, ancestor_index: usize) bool {
        for (route) |entry| {
            if (self.canvasWidgetNodeIndexDescendsFrom(entry.node_index, ancestor_index)) return true;
        }
        return false;
    }

    pub fn canvasWidgetScopedFocusTarget(self: *const RuntimeView, current_id: canvas.ObjectId, direction: canvas.WidgetFocusDirection) ?canvas.WidgetFocusTarget {
        const current_index = self.canvasWidgetNodeIndexById(current_id) orelse return null;
        const surface_index = self.canvasWidgetDismissibleSurfaceIndexForTarget(current_index) orelse return null;
        return self.canvasWidgetFocusTargetInScope(surface_index, current_index, direction);
    }

    pub fn canvasWidgetFocusTargetInScope(
        self: *const RuntimeView,
        surface_index: usize,
        current_index: usize,
        direction: canvas.WidgetFocusDirection,
    ) ?canvas.WidgetFocusTarget {
        if (surface_index >= self.widget_layout_node_count or current_index >= self.widget_layout_node_count) return null;
        return switch (direction) {
            .forward => self.canvasWidgetForwardFocusTargetInScope(surface_index, current_index),
            .backward => self.canvasWidgetBackwardFocusTargetInScope(surface_index, current_index),
            .left, .right, .up, .down => null,
        };
    }

    pub fn canvasWidgetForwardFocusTargetInScope(self: *const RuntimeView, surface_index: usize, current_index: usize) ?canvas.WidgetFocusTarget {
        var index = current_index + 1;
        while (index < self.widget_layout_node_count) : (index += 1) {
            if (self.canvasWidgetFocusTargetAtScopedIndex(surface_index, index)) |target| return target;
        }
        index = surface_index;
        while (index <= current_index and index < self.widget_layout_node_count) : (index += 1) {
            if (self.canvasWidgetFocusTargetAtScopedIndex(surface_index, index)) |target| return target;
        }
        return null;
    }

    pub fn canvasWidgetBackwardFocusTargetInScope(self: *const RuntimeView, surface_index: usize, current_index: usize) ?canvas.WidgetFocusTarget {
        var index = current_index;
        while (index > 0) {
            index -= 1;
            if (self.canvasWidgetFocusTargetAtScopedIndex(surface_index, index)) |target| return target;
        }
        index = self.widget_layout_node_count;
        while (index > current_index) {
            index -= 1;
            if (self.canvasWidgetFocusTargetAtScopedIndex(surface_index, index)) |target| return target;
        }
        return null;
    }

    pub fn canvasWidgetFocusTargetAtScopedIndex(self: *const RuntimeView, surface_index: usize, index: usize) ?canvas.WidgetFocusTarget {
        if (!self.canvasWidgetNodeIndexDescendsFrom(index, surface_index)) return null;
        const id = self.widget_layout_nodes[index].widget.id;
        return self.widgetLayoutTree().focusTargetById(id);
    }

    pub fn canvasWidgetIdDescendsFromIndex(self: *const RuntimeView, id: canvas.ObjectId, ancestor_index: usize) bool {
        const index = self.canvasWidgetNodeIndexById(id) orelse return false;
        return self.canvasWidgetNodeIndexDescendsFrom(index, ancestor_index);
    }

    pub fn canvasWidgetNodeIndexDescendsFrom(self: *const RuntimeView, node_index: usize, ancestor_index: usize) bool {
        if (node_index >= self.widget_layout_node_count or ancestor_index >= self.widget_layout_node_count) return false;
        var current: ?usize = node_index;
        while (current) |index| {
            if (index >= self.widget_layout_node_count) return false;
            if (index == ancestor_index) return true;
            current = self.widget_layout_nodes[index].parent_index;
        }
        return false;
    }

    pub fn canvasWidgetNodeIndexById(self: *const RuntimeView, id: canvas.ObjectId) ?usize {
        if (id == 0) return null;
        for (self.widget_layout_nodes[0..self.widget_layout_node_count], 0..) |node, index| {
            if (node.widget.id == id) return index;
        }
        return null;
    }

    pub fn canvasWidgetCommand(self: *const RuntimeView, id: canvas.ObjectId) ?[]const u8 {
        const index = self.canvasWidgetNodeIndexById(id) orelse return null;
        const widget = self.widget_layout_nodes[index].widget;
        if (widget.command.len == 0) return null;
        return widget.command;
    }

    pub fn canvasWidgetStepKey(self: *const RuntimeView, id: canvas.ObjectId, direction: CanvasWidgetStepDirection) []const u8 {
        const index = self.canvasWidgetNodeIndexById(id) orelse return switch (direction) {
            .increment => "arrowright",
            .decrement => "arrowleft",
        };
        return switch (self.widget_layout_nodes[index].widget.kind) {
            .grid, .scroll_view, .list, .data_grid, .table => switch (direction) {
                .increment => "pagedown",
                .decrement => "pageup",
            },
            else => switch (direction) {
                .increment => "arrowright",
                .decrement => "arrowleft",
            },
        };
    }

    pub fn canvasWidgetToggleAnimation(self: *const RuntimeView, id: canvas.ObjectId) ?CanvasWidgetToggleAnimation {
        const index = self.canvasWidgetNodeIndexById(id) orelse return null;
        const widget = self.widget_layout_nodes[index].widget;
        if (!canvasWidgetSwitchControlKind(widget.kind) or widget.state.disabled) return null;
        const travel = canvas.toggleWidgetKnobTravel(widget, self.widget_tokens);
        if (travel <= 0) return null;
        return .{
            .id = id,
            .selected = canvasWidgetBooleanSelected(widget),
            .travel = travel,
            .dirty_bounds = self.canvasWidgetDirtyBounds(index, widget.frame),
        };
    }

    pub fn canvasWidgetToggleAnimationForPointer(
        self: *const RuntimeView,
        pointer: canvas.WidgetPointerEvent,
        target: ?canvas.WidgetHit,
        pressed_id: canvas.ObjectId,
    ) ?CanvasWidgetToggleAnimation {
        if (pointer.phase != .up or pressed_id == 0) return null;
        const hit = target orelse return null;
        if (!canvasWidgetSwitchControlKind(hit.kind) or hit.id != pressed_id) return null;
        if (!hit.bounds.normalized().containsPoint(pointer.point)) return null;
        return self.canvasWidgetToggleAnimation(pressed_id);
    }

    pub fn canvasWidgetToggleAnimationForKeyboard(self: *const RuntimeView, id: canvas.ObjectId, keyboard: canvas.WidgetKeyboardEvent) ?CanvasWidgetToggleAnimation {
        if (keyboard.phase != .key_down or keyboard.modifiers.hasNavigationModifier()) return null;
        if (!canvas.isWidgetActivationKey(keyboard.key)) return null;
        return self.canvasWidgetToggleAnimation(id);
    }

    pub fn applyCanvasWidgetControlPointer(self: *RuntimeView, pointer: canvas.WidgetPointerEvent, target: ?canvas.WidgetHit, pressed_id: canvas.ObjectId) anyerror!?geometry.RectF {
        return switch (pointer.phase) {
            .down => if (target) |hit| try self.applyCanvasWidgetSliderValue(hit.id, pointer.point) else null,
            .move => if (pressed_id != 0) blk: {
                if (try self.applyCanvasWidgetSliderValue(pressed_id, pointer.point)) |dirty| break :blk dirty;
                break :blk try self.applyCanvasWidgetResizableDelta(pressed_id, pointer.delta.dx);
            } else null,
            .up => blk: {
                if (pressed_id == 0) break :blk null;
                if (try self.applyCanvasWidgetSliderValue(pressed_id, pointer.point)) |dirty| break :blk dirty;
                const hit = target orelse break :blk null;
                if (!hit.bounds.normalized().containsPoint(pointer.point)) break :blk null;
                if (hit.id != pressed_id) break :blk null;
                if (try self.toggleCanvasWidgetBooleanControl(pressed_id)) |dirty| break :blk dirty;
                break :blk try self.setCanvasWidgetSelected(pressed_id, true);
            },
            .hover, .cancel, .wheel => null,
        };
    }

    pub fn applyCanvasWidgetResizableDelta(self: *RuntimeView, id: canvas.ObjectId, delta_x: f32) anyerror!?geometry.RectF {
        if (!std.math.isFinite(delta_x) or delta_x == 0) return null;
        const index = self.canvasWidgetNodeIndexById(id) orelse return null;
        const widget = self.widget_layout_nodes[index].widget;
        if (widget.kind != .resizable or widget.state.disabled) return null;
        if (!std.math.isFinite(widget.frame.width)) return null;

        const previous_frame = self.widget_layout_nodes[index].frame;
        const min_width = canvasWidgetResizableMinWidth(widget);
        const next_width = @max(min_width, previous_frame.width + delta_x);
        if (next_width == previous_frame.width) return null;

        self.widget_layout_nodes[index].frame.width = next_width;
        self.widget_layout_nodes[index].widget.frame.width = next_width;
        try self.refreshCanvasWidgetSemantics();
        self.widget_revision += 1;
        const dirty = unionRects(previous_frame, self.widget_layout_nodes[index].frame) orelse self.widget_layout_nodes[index].frame;
        return self.canvasWidgetDirtyBounds(index, dirty);
    }

    pub fn applyCanvasWidgetControlKeyboard(self: *RuntimeView, id: canvas.ObjectId, keyboard: canvas.WidgetKeyboardEvent) anyerror!?geometry.RectF {
        const index = self.canvasWidgetNodeIndexById(id) orelse return null;
        const widget = self.widget_layout_nodes[index].widget;

        const intent = canvas.widgetKeyboardControlIntent(widget, keyboard) orelse return null;
        return self.applyCanvasWidgetControlIntent(index, intent);
    }

    pub fn applyCanvasWidgetControlIntent(self: *RuntimeView, index: usize, intent: canvas.WidgetControlIntent) anyerror!?geometry.RectF {
        if (index >= self.widget_layout_node_count) return null;
        const id = self.widget_layout_nodes[index].widget.id;
        return switch (intent.kind) {
            .toggle => try self.toggleCanvasWidgetBooleanControl(id),
            .set_value => if (intent.value) |next_value| try self.setCanvasWidgetValue(index, next_value) else null,
            .select => try self.setCanvasWidgetSelected(id, true),
            .scroll_to_start => try self.applyCanvasWidgetScrollKeyboardTarget(index, .start),
            .scroll_to_end => try self.applyCanvasWidgetScrollKeyboardTarget(index, .end),
            .scroll_by => try self.applyCanvasWidgetScroll(index, intent.delta, .discrete, false),
            .press => null,
        };
    }

    pub fn applyCanvasWidgetSliderValue(self: *RuntimeView, id: canvas.ObjectId, point: geometry.PointF) anyerror!?geometry.RectF {
        const index = self.canvasWidgetNodeIndexById(id) orelse return null;
        const widget = self.widget_layout_nodes[index].widget;
        if (widget.kind != .slider or widget.state.disabled or widget.frame.width <= 0) return null;

        const next_value = std.math.clamp((point.x - widget.frame.x) / widget.frame.width, 0, 1);
        return self.setCanvasWidgetValue(index, next_value);
    }

    pub fn toggleCanvasWidgetBooleanControl(self: *RuntimeView, id: canvas.ObjectId) anyerror!?geometry.RectF {
        const index = self.canvasWidgetNodeIndexById(id) orelse return null;
        const widget = self.widget_layout_nodes[index].widget;
        if ((widget.kind != .accordion and widget.kind != .checkbox and widget.kind != .toggle_button and !canvasWidgetSwitchControlKind(widget.kind)) or widget.state.disabled) return null;

        const selected = canvasWidgetBooleanSelected(widget);
        self.widget_layout_nodes[index].widget.state.selected = !selected;
        self.widget_layout_nodes[index].widget.value = if (!selected) 1 else 0;
        try self.refreshCanvasWidgetSemantics();
        self.widget_revision += 1;
        return self.canvasWidgetDirtyBounds(index, widget.frame);
    }

    pub fn setCanvasWidgetSelected(self: *RuntimeView, id: canvas.ObjectId, selected: bool) anyerror!?geometry.RectF {
        const index = self.canvasWidgetNodeIndexById(id) orelse return null;
        const widget = self.widget_layout_nodes[index].widget;
        if (widget.state.disabled) return null;
        switch (widget.kind) {
            .list_item, .menu_item, .data_cell, .segmented_control, .radio => {},
            else => return null,
        }

        var dirty: ?geometry.RectF = null;
        var changed = false;
        if (selected and canvasWidgetSelectionClearsSiblings(widget.kind)) {
            const parent_index = self.widget_layout_nodes[index].parent_index;
            for (self.widget_layout_nodes[0..self.widget_layout_node_count], 0..) |*node, sibling_index| {
                if (sibling_index == index) continue;
                if (node.parent_index != parent_index or node.widget.kind != widget.kind) continue;
                if (!canvasWidgetSelectableSelected(node.widget)) continue;
                node.widget.state.selected = false;
                node.widget.value = 0;
                dirty = unionRects(dirty, self.canvasWidgetDirtyBounds(sibling_index, node.frame));
                changed = true;
            }
        }

        const target_value: f32 = if (selected) 1 else 0;
        if (self.widget_layout_nodes[index].widget.state.selected != selected or self.widget_layout_nodes[index].widget.value != target_value) {
            dirty = unionRects(dirty, self.canvasWidgetDirtyBounds(index, self.widget_layout_nodes[index].frame));
            changed = true;
        }
        if (!changed) return null;
        self.widget_layout_nodes[index].widget.state.selected = selected;
        self.widget_layout_nodes[index].widget.value = target_value;
        try self.refreshCanvasWidgetSemantics();
        self.widget_revision += 1;
        return dirty orelse self.widget_layout_nodes[index].frame;
    }

    pub fn setCanvasWidgetValue(self: *RuntimeView, index: usize, value: f32) anyerror!?geometry.RectF {
        if (index >= self.widget_layout_node_count) return null;
        const widget = self.widget_layout_nodes[index].widget;
        const next_value = std.math.clamp(value, 0, 1);
        if (next_value == widget.value) return null;
        self.widget_layout_nodes[index].widget.value = next_value;
        try self.refreshCanvasWidgetSemantics();
        self.widget_revision += 1;
        return self.canvasWidgetDirtyBounds(index, widget.frame);
    }

    pub fn refreshCanvasWidgetSemantics(self: *RuntimeView) anyerror!void {
        const semantics = try self.widgetLayoutTree().collectSemantics(&self.widget_semantics_nodes);
        self.widget_semantics_node_count = semantics.len;
    }

    pub fn canvasWidgetDirtyBounds(self: *const RuntimeView, node_index: usize, bounds: geometry.RectF) ?geometry.RectF {
        return canvasWidgetLayoutNodeClippedBounds(self.widgetLayoutTree(), node_index, bounds);
    }

    pub fn copyWidgetLayoutNode(self: *RuntimeView, node: canvas.WidgetLayoutNode, source_semantics: []const canvas.WidgetSemanticsNode) anyerror!canvas.WidgetLayoutNode {
        var copy = node;
        if (node.widget.command.len > 0) try validateCommandName(node.widget.command);
        copy.widget.text = try self.copyWidgetText(node.widget.text);
        copy.widget.command = try self.copyWidgetText(node.widget.command);
        copy.widget.semantics.label = try self.copyWidgetText(node.widget.semantics.label);
        copy = canvasWidgetLayoutNodeWithSourceSemantics(copy, source_semantics);
        copy.widget.children = &.{};
        return copy;
    }

    pub fn copyCanvasCommand(self: *RuntimeView, command: canvas.CanvasCommand) anyerror!canvas.CanvasCommand {
        return switch (command) {
            .push_clip => |value| .{ .push_clip = value },
            .pop_clip => .pop_clip,
            .push_opacity => |value| .{ .push_opacity = value },
            .pop_opacity => .pop_opacity,
            .transform => |value| .{ .transform = value },
            .fill_rect => |value| blk: {
                var copy = value;
                copy.fill = try self.copyCanvasFill(value.fill);
                break :blk .{ .fill_rect = copy };
            },
            .stroke_rect => |value| blk: {
                var copy = value;
                copy.stroke = try self.copyCanvasStroke(value.stroke);
                break :blk .{ .stroke_rect = copy };
            },
            .fill_rounded_rect => |value| blk: {
                var copy = value;
                copy.fill = try self.copyCanvasFill(value.fill);
                break :blk .{ .fill_rounded_rect = copy };
            },
            .draw_line => |value| blk: {
                var copy = value;
                copy.stroke = try self.copyCanvasStroke(value.stroke);
                break :blk .{ .draw_line = copy };
            },
            .fill_path => |value| blk: {
                var copy = value;
                copy.elements = try self.copyCanvasPathElements(value.elements);
                copy.fill = try self.copyCanvasFill(value.fill);
                break :blk .{ .fill_path = copy };
            },
            .stroke_path => |value| blk: {
                var copy = value;
                copy.elements = try self.copyCanvasPathElements(value.elements);
                copy.stroke = try self.copyCanvasStroke(value.stroke);
                break :blk .{ .stroke_path = copy };
            },
            .draw_image => |value| .{ .draw_image = value },
            .draw_text => |value| blk: {
                var copy = value;
                copy.text = try self.copyCanvasText(value.text);
                copy.glyphs = try self.copyCanvasGlyphs(value.glyphs);
                break :blk .{ .draw_text = copy };
            },
            .shadow => |value| .{ .shadow = value },
            .blur => |value| .{ .blur = value },
        };
    }

    pub fn copyCanvasStroke(self: *RuntimeView, stroke: canvas.Stroke) anyerror!canvas.Stroke {
        var copy = stroke;
        copy.fill = try self.copyCanvasFill(stroke.fill);
        return copy;
    }

    pub fn copyCanvasFill(self: *RuntimeView, fill: canvas.Fill) anyerror!canvas.Fill {
        return switch (fill) {
            .color => |color| .{ .color = color },
            .linear_gradient => |gradient| .{ .linear_gradient = .{
                .start = gradient.start,
                .end = gradient.end,
                .stops = try self.copyCanvasGradientStops(gradient.stops),
            } },
        };
    }

    pub fn copyCanvasGradientStops(self: *RuntimeView, stops: []const canvas.GradientStop) anyerror![]const canvas.GradientStop {
        const end = self.canvas_gradient_stop_count + stops.len;
        if (end > self.canvas_gradient_stops.len) return error.CanvasGradientStopLimitReached;
        const start = self.canvas_gradient_stop_count;
        @memcpy(self.canvas_gradient_stops[start..end], stops);
        self.canvas_gradient_stop_count = end;
        return self.canvas_gradient_stops[start..end];
    }

    pub fn copyCanvasPathElements(self: *RuntimeView, elements: []const canvas.PathElement) anyerror![]const canvas.PathElement {
        const end = self.canvas_path_element_count + elements.len;
        if (end > self.canvas_path_elements.len) return error.CanvasPathElementLimitReached;
        const start = self.canvas_path_element_count;
        @memcpy(self.canvas_path_elements[start..end], elements);
        self.canvas_path_element_count = end;
        return self.canvas_path_elements[start..end];
    }

    pub fn copyCanvasGlyphs(self: *RuntimeView, glyphs: []const canvas.Glyph) anyerror![]const canvas.Glyph {
        const end = self.canvas_glyph_count + glyphs.len;
        if (end > self.canvas_glyphs.len) return error.CanvasGlyphLimitReached;
        const start = self.canvas_glyph_count;
        @memcpy(self.canvas_glyphs[start..end], glyphs);
        self.canvas_glyph_count = end;
        return self.canvas_glyphs[start..end];
    }

    pub fn copyCanvasText(self: *RuntimeView, text: []const u8) anyerror![]const u8 {
        const end = self.canvas_text_len + text.len;
        if (end > self.canvas_text_bytes.len) return error.CanvasTextTooLarge;
        const start = self.canvas_text_len;
        @memcpy(self.canvas_text_bytes[start..end], text);
        self.canvas_text_len = end;
        return self.canvas_text_bytes[start..end];
    }

    pub fn copyWidgetText(self: *RuntimeView, text: []const u8) anyerror![]const u8 {
        const end = self.widget_text_len + text.len;
        if (end > self.widget_text_bytes.len) return error.WidgetTextTooLarge;
        const start = self.widget_text_len;
        @memcpy(self.widget_text_bytes[start..end], text);
        self.widget_text_len = end;
        return self.widget_text_bytes[start..end];
    }
};
