const std = @import("std");
const geometry = @import("geometry");
const canvas = @import("root.zig");
const drawing_model = @import("drawing.zig");
const hash_model = @import("hash.zig");
const token_model = @import("tokens.zig");
const equality_model = @import("equality.zig");

const Error = canvas.Error;
const ObjectId = canvas.ObjectId;
const ImageId = canvas.ImageId;
const FontId = canvas.FontId;
const CanvasCommand = canvas.CanvasCommand;
const DisplayList = canvas.DisplayList;
const ReferenceImage = canvas.ReferenceImage;
const Affine = drawing_model.Affine;
const Fill = drawing_model.Fill;
const Stroke = drawing_model.Stroke;
const Radius = drawing_model.Radius;
const PathElement = drawing_model.PathElement;
const Easing = token_model.Easing;
const SpringToken = token_model.SpringToken;

const RenderImagePlanner = canvas.RenderImagePlanner;
const RenderLayerPlanner = canvas.RenderLayerPlanner;
const RenderImageCachePlanner = canvas.RenderImageCachePlanner;
const RenderResourceCachePlanner = canvas.RenderResourceCachePlanner;
const RenderLayerCachePlanner = canvas.RenderLayerCachePlanner;
const VisualEffectCachePlanner = canvas.VisualEffectCachePlanner;
const optionalRectsEqual = equality_model.optionalRectsEqual;

pub const max_render_state_stack: usize = 32;
const path_geometry_curve_segments: usize = 12;
const resourceHashTag = hash_model.resourceHashTag;
const resourceHashBytes = hash_model.resourceHashBytes;
const resourceHashU64 = hash_model.resourceHashU64;
const resourceHashUsize = hash_model.resourceHashUsize;
const resourceHashEnum = hash_model.resourceHashEnum;
const resourceHashF32 = hash_model.resourceHashF32;
const resourceHashPoint = hash_model.resourceHashPoint;
const resourceHashOptionalObjectId = hash_model.resourceHashOptionalObjectId;
const resourceHashAffine = hash_model.resourceHashAffine;
const resourceHashPath = hash_model.resourceHashPath;

pub const RenderState = struct {
    opacity: f32 = 1,
    clip: ?geometry.RectF = null,
    transform: Affine = .{},
};

pub const RenderCommand = struct {
    command: CanvasCommand,
    id: ?ObjectId = null,
    opacity: f32 = 1,
    clip: ?geometry.RectF = null,
    transform: Affine = .{},
    local_bounds: geometry.RectF,
    bounds: geometry.RectF,
};

pub const CanvasRenderOverride = struct {
    id: ObjectId,
    opacity: ?f32 = null,
    transform: ?Affine = null,
};

pub const CanvasRenderAnimation = struct {
    id: ObjectId,
    start_ns: u64 = 0,
    duration_ms: u32 = 0,
    easing: Easing = .standard,
    spring: SpringToken = .{},
    from_opacity: ?f32 = null,
    to_opacity: ?f32 = null,
    from_transform: ?Affine = null,
    to_transform: ?Affine = null,
};

pub fn sampleCanvasRenderAnimations(animations: []const CanvasRenderAnimation, timestamp_ns: u64, output: []CanvasRenderOverride) Error![]const CanvasRenderOverride {
    var len: usize = 0;
    for (animations) |animation| {
        if (animation.id == 0) continue;
        const progress = motionProgress(animation, timestamp_ns);
        const opacity = sampleAnimatedF32(animation.from_opacity, animation.to_opacity, progress);
        const transform = sampleAnimatedAffine(animation.from_transform, animation.to_transform, progress);
        if (opacity == null and transform == null) continue;
        if (len >= output.len) return error.RenderOverrideListFull;
        output[len] = .{
            .id = animation.id,
            .opacity = opacity,
            .transform = transform,
        };
        len += 1;
    }
    return output[0..len];
}

pub fn motionProgress(animation: CanvasRenderAnimation, timestamp_ns: u64) f32 {
    const raw = rawMotionProgress(animation.start_ns, animation.duration_ms, timestamp_ns);
    return easedMotionProgress(animation.easing, animation.spring, raw);
}

fn rawMotionProgress(start_ns: u64, duration_ms: u32, timestamp_ns: u64) f32 {
    if (duration_ms == 0) return 1;
    if (timestamp_ns <= start_ns) return 0;
    const duration_ns = @as(u64, duration_ms) * 1_000_000;
    const elapsed_ns = timestamp_ns - start_ns;
    if (elapsed_ns >= duration_ns) return 1;
    return @as(f32, @floatFromInt(elapsed_ns)) / @as(f32, @floatFromInt(duration_ns));
}

fn easedMotionProgress(easing: Easing, spring: SpringToken, progress: f32) f32 {
    const t = std.math.clamp(progress, 0, 1);
    return switch (easing) {
        .linear => t,
        .standard => t * t * (3 - 2 * t),
        .emphasized => 1 - std.math.pow(f32, 1 - t, 3),
        .spring => springMotionProgress(t, spring),
    };
}

fn springMotionProgress(progress: f32, spring: SpringToken) f32 {
    if (progress <= 0) return 0;
    if (progress >= 1) return 1;
    const mass = @max(0.001, spring.mass);
    const stiffness = @max(1, spring.stiffness);
    const damping = @max(0.001, spring.damping);
    const omega = @sqrt(stiffness / mass);
    const decay = @exp(-damping * progress / (mass * 24));
    return std.math.clamp(1 - decay * @cos(omega * progress), 0, 1);
}

fn sampleAnimatedF32(from: ?f32, to: ?f32, progress: f32) ?f32 {
    const start = from orelse return null;
    const end = to orelse return null;
    return start + (end - start) * progress;
}

fn sampleAnimatedAffine(from: ?Affine, to: ?Affine, progress: f32) ?Affine {
    const start = from orelse return null;
    const end = to orelse return null;
    return .{
        .a = start.a + (end.a - start.a) * progress,
        .b = start.b + (end.b - start.b) * progress,
        .c = start.c + (end.c - start.c) * progress,
        .d = start.d + (end.d - start.d) * progress,
        .tx = start.tx + (end.tx - start.tx) * progress,
        .ty = start.ty + (end.ty - start.ty) * progress,
    };
}

pub const RenderPlan = struct {
    commands: []const RenderCommand = &.{},
    bounds: ?geometry.RectF = null,

    pub fn commandCount(self: RenderPlan) usize {
        return self.commands.len;
    }

    pub fn batchPlan(self: RenderPlan, output: []RenderBatch) Error!RenderBatchPlan {
        var planner = RenderBatchPlanner.init(output);
        return planner.build(self);
    }

    pub fn pathGeometryPlan(self: RenderPlan, output: []RenderPathGeometry) Error!RenderPathGeometryPlan {
        var planner = RenderPathGeometryPlanner.init(output);
        return planner.build(self);
    }

    pub fn imagePlan(self: RenderPlan, output: []RenderImage) Error!RenderImagePlan {
        return self.imagePlanWithResources(&.{}, output);
    }

    pub fn imagePlanWithResources(self: RenderPlan, image_resources: []const ReferenceImage, output: []RenderImage) Error!RenderImagePlan {
        var planner = RenderImagePlanner.init(output);
        planner.image_resources = image_resources;
        return planner.build(self);
    }

    pub fn layerPlan(self: RenderPlan, output: []RenderLayer) Error!RenderLayerPlan {
        var planner = RenderLayerPlanner.init(output);
        return planner.build(self);
    }
};

pub const RenderPlanner = struct {
    commands: []RenderCommand,
    len: usize = 0,
    state: RenderState = .{},
    bounds_value: ?geometry.RectF = null,
    clip_stack: [max_render_state_stack]?geometry.RectF = undefined,
    clip_stack_len: usize = 0,
    opacity_stack: [max_render_state_stack]f32 = undefined,
    opacity_stack_len: usize = 0,

    pub fn init(commands: []RenderCommand) RenderPlanner {
        return .{ .commands = commands };
    }

    pub fn reset(self: *RenderPlanner) void {
        self.len = 0;
        self.state = .{};
        self.bounds_value = null;
        self.clip_stack_len = 0;
        self.opacity_stack_len = 0;
    }

    pub fn build(self: *RenderPlanner, display_list: DisplayList) Error!RenderPlan {
        self.reset();
        for (display_list.commands) |command| {
            try self.consume(command);
        }
        return .{
            .commands = self.commands[0..self.len],
            .bounds = self.bounds_value,
        };
    }

    fn consume(self: *RenderPlanner, command: CanvasCommand) Error!void {
        switch (command) {
            .push_clip => |clip| try self.pushClip(clip),
            .pop_clip => try self.popClip(),
            .push_opacity => |opacity| try self.pushOpacity(opacity),
            .pop_opacity => try self.popOpacity(),
            .transform => |transform| self.state.transform = self.state.transform.multiply(transform),
            else => try self.appendDrawCommand(command),
        }
    }

    fn pushClip(self: *RenderPlanner, clip: drawing_model.Clip) Error!void {
        if (self.clip_stack_len >= self.clip_stack.len) return error.RenderStackOverflow;
        self.clip_stack[self.clip_stack_len] = self.state.clip;
        self.clip_stack_len += 1;

        const transformed_clip = self.state.transform.transformRect(clip.rect);
        self.state.clip = if (self.state.clip) |existing|
            geometry.RectF.intersection(existing, transformed_clip)
        else
            transformed_clip;
    }

    fn popClip(self: *RenderPlanner) Error!void {
        if (self.clip_stack_len == 0) return error.RenderStackUnderflow;
        self.clip_stack_len -= 1;
        self.state.clip = self.clip_stack[self.clip_stack_len];
    }

    fn pushOpacity(self: *RenderPlanner, opacity: f32) Error!void {
        if (self.opacity_stack_len >= self.opacity_stack.len) return error.RenderStackOverflow;
        self.opacity_stack[self.opacity_stack_len] = self.state.opacity;
        self.opacity_stack_len += 1;
        self.state.opacity *= std.math.clamp(opacity, 0, 1);
    }

    fn popOpacity(self: *RenderPlanner) Error!void {
        if (self.opacity_stack_len == 0) return error.RenderStackUnderflow;
        self.opacity_stack_len -= 1;
        self.state.opacity = self.opacity_stack[self.opacity_stack_len];
    }

    fn appendDrawCommand(self: *RenderPlanner, command: CanvasCommand) Error!void {
        if (self.state.opacity <= 0) return;
        const command_bounds = command.bounds() orelse return;
        const transformed_bounds = self.state.transform.transformRect(command_bounds);
        const clipped_bounds = if (self.state.clip) |clip|
            geometry.RectF.intersection(clip, transformed_bounds)
        else
            transformed_bounds;
        if (clipped_bounds.isEmpty()) return;
        if (self.len >= self.commands.len) return error.RenderListFull;

        self.commands[self.len] = .{
            .command = command,
            .id = command.objectId(),
            .opacity = self.state.opacity,
            .clip = self.state.clip,
            .transform = self.state.transform,
            .local_bounds = command_bounds,
            .bounds = clipped_bounds,
        };
        self.len += 1;
        self.bounds_value = unionOptionalBounds(self.bounds_value, clipped_bounds);
    }
};

pub const RenderPipelineKind = enum {
    solid,
    linear_gradient,
    image,
    glyph_run,
    path,
    shadow,
    blur,
};

pub const RenderBatch = struct {
    pipeline: RenderPipelineKind,
    command_start: usize = 0,
    command_count: usize = 0,
    opacity: f32 = 1,
    clip: ?geometry.RectF = null,
    bounds: geometry.RectF = .{},
};

pub const RenderBatchPlan = struct {
    batches: []const RenderBatch = &.{},
    bounds: ?geometry.RectF = null,

    pub fn batchCount(self: RenderBatchPlan) usize {
        return self.batches.len;
    }

    pub fn cachePlan(self: RenderBatchPlan, previous: []const RenderPipelineCacheEntry, frame_index: u64, entries: []RenderPipelineCacheEntry, actions: []RenderPipelineCacheAction) Error!RenderPipelineCachePlan {
        var planner = RenderPipelineCachePlanner.init(entries, actions);
        return planner.build(self, previous, frame_index);
    }
};

pub const RenderBatchPlanner = struct {
    batches: []RenderBatch,
    len: usize = 0,

    pub fn init(batches: []RenderBatch) RenderBatchPlanner {
        return .{ .batches = batches };
    }

    pub fn reset(self: *RenderBatchPlanner) void {
        self.len = 0;
    }

    pub fn build(self: *RenderBatchPlanner, render_plan: RenderPlan) Error!RenderBatchPlan {
        self.reset();
        for (render_plan.commands, 0..) |command, index| {
            try self.consume(command, index);
        }
        return .{
            .batches = self.batches[0..self.len],
            .bounds = render_plan.bounds,
        };
    }

    fn consume(self: *RenderBatchPlanner, command: RenderCommand, index: usize) Error!void {
        const pipeline = renderPipelineKind(command.command);
        if (self.len > 0 and renderBatchCanExtend(self.batches[self.len - 1], command, pipeline, index)) {
            const batch = &self.batches[self.len - 1];
            batch.command_count += 1;
            batch.bounds = geometry.RectF.unionWith(batch.bounds.normalized(), command.bounds.normalized());
            return;
        }

        if (self.len >= self.batches.len) return error.RenderBatchListFull;
        self.batches[self.len] = .{
            .pipeline = pipeline,
            .command_start = index,
            .command_count = 1,
            .opacity = command.opacity,
            .clip = command.clip,
            .bounds = command.bounds,
        };
        self.len += 1;
    }
};

pub const RenderPipelineCacheEntry = struct {
    pipeline: RenderPipelineKind,
    last_used_frame: u64 = 0,
};

pub const RenderPipelineCacheActionKind = enum {
    upload,
    retain,
    evict,
};

pub const RenderPipelineCacheAction = struct {
    kind: RenderPipelineCacheActionKind,
    pipeline: RenderPipelineKind,
    batch_index: ?usize = null,
    cache_index: ?usize = null,
};

pub const RenderPipelineCachePlan = struct {
    entries: []const RenderPipelineCacheEntry = &.{},
    actions: []const RenderPipelineCacheAction = &.{},

    pub fn entryCount(self: RenderPipelineCachePlan) usize {
        return self.entries.len;
    }

    pub fn actionCount(self: RenderPipelineCachePlan) usize {
        return self.actions.len;
    }

    pub fn uploadCount(self: RenderPipelineCachePlan) usize {
        return self.actionCountByKind(.upload);
    }

    pub fn retainCount(self: RenderPipelineCachePlan) usize {
        return self.actionCountByKind(.retain);
    }

    pub fn evictCount(self: RenderPipelineCachePlan) usize {
        return self.actionCountByKind(.evict);
    }

    fn actionCountByKind(self: RenderPipelineCachePlan, kind: RenderPipelineCacheActionKind) usize {
        var count: usize = 0;
        for (self.actions) |action| {
            if (action.kind == kind) count += 1;
        }
        return count;
    }
};

pub const RenderPipelineCachePlanner = struct {
    entries: []RenderPipelineCacheEntry,
    actions: []RenderPipelineCacheAction,
    entry_len: usize = 0,
    action_len: usize = 0,

    pub fn init(entries: []RenderPipelineCacheEntry, actions: []RenderPipelineCacheAction) RenderPipelineCachePlanner {
        return .{ .entries = entries, .actions = actions };
    }

    pub fn reset(self: *RenderPipelineCachePlanner) void {
        self.entry_len = 0;
        self.action_len = 0;
    }

    pub fn build(self: *RenderPipelineCachePlanner, batch_plan: RenderBatchPlan, previous: []const RenderPipelineCacheEntry, frame_index: u64) Error!RenderPipelineCachePlan {
        self.reset();
        for (batch_plan.batches, 0..) |batch, batch_index| {
            if (findRenderPipelineCacheEntry(self.entries[0..self.entry_len], batch.pipeline) != null) continue;

            const previous_index = findRenderPipelineCacheEntry(previous, batch.pipeline);
            try self.appendAction(.{
                .kind = if (previous_index == null) .upload else .retain,
                .pipeline = batch.pipeline,
                .batch_index = batch_index,
                .cache_index = previous_index,
            });
            try self.appendEntry(.{
                .pipeline = batch.pipeline,
                .last_used_frame = frame_index,
            });
        }

        for (previous, 0..) |entry, cache_index| {
            if (findRenderPipelineCacheEntry(self.entries[0..self.entry_len], entry.pipeline) != null) continue;
            try self.appendAction(.{
                .kind = .evict,
                .pipeline = entry.pipeline,
                .cache_index = cache_index,
            });
        }

        return .{
            .entries = self.entries[0..self.entry_len],
            .actions = self.actions[0..self.action_len],
        };
    }

    fn appendEntry(self: *RenderPipelineCachePlanner, entry: RenderPipelineCacheEntry) Error!void {
        if (self.entry_len >= self.entries.len) return error.RenderPipelineCacheListFull;
        self.entries[self.entry_len] = entry;
        self.entry_len += 1;
    }

    fn appendAction(self: *RenderPipelineCachePlanner, action: RenderPipelineCacheAction) Error!void {
        if (self.action_len >= self.actions.len) return error.RenderPipelineCacheListFull;
        self.actions[self.action_len] = action;
        self.action_len += 1;
    }
};

fn findRenderPipelineCacheEntry(entries: []const RenderPipelineCacheEntry, pipeline: RenderPipelineKind) ?usize {
    for (entries, 0..) |entry, index| {
        if (entry.pipeline == pipeline) return index;
    }
    return null;
}

pub const RenderPathGeometryKind = enum {
    fill,
    stroke,
};

pub const RenderPathGeometry = struct {
    kind: RenderPathGeometryKind,
    command_index: usize = 0,
    id: ?ObjectId = null,
    bounds: geometry.RectF = .{},
    element_count: usize = 0,
    contour_count: usize = 0,
    line_segment_count: usize = 0,
    quadratic_segment_count: usize = 0,
    cubic_segment_count: usize = 0,
    flattened_segment_count: usize = 0,
    vertex_count: usize = 0,
    index_count: usize = 0,
    stroke_width: f32 = 0,
    fingerprint: u64 = 0,
};

pub const RenderPathGeometryPlan = struct {
    geometries: []const RenderPathGeometry = &.{},

    pub fn geometryCount(self: RenderPathGeometryPlan) usize {
        return self.geometries.len;
    }

    pub fn vertexCount(self: RenderPathGeometryPlan) usize {
        var count: usize = 0;
        for (self.geometries) |geometry_plan| count += geometry_plan.vertex_count;
        return count;
    }

    pub fn indexCount(self: RenderPathGeometryPlan) usize {
        var count: usize = 0;
        for (self.geometries) |geometry_plan| count += geometry_plan.index_count;
        return count;
    }

    pub fn cachePlan(self: RenderPathGeometryPlan, previous: []const RenderPathGeometryCacheEntry, frame_index: u64, entries: []RenderPathGeometryCacheEntry, actions: []RenderPathGeometryCacheAction) Error!RenderPathGeometryCachePlan {
        var planner = RenderPathGeometryCachePlanner.init(entries, actions);
        return planner.build(self, previous, frame_index);
    }
};

pub const RenderPathGeometryPlanner = struct {
    geometries: []RenderPathGeometry,
    len: usize = 0,

    pub fn init(geometries: []RenderPathGeometry) RenderPathGeometryPlanner {
        return .{ .geometries = geometries };
    }

    pub fn reset(self: *RenderPathGeometryPlanner) void {
        self.len = 0;
    }

    pub fn build(self: *RenderPathGeometryPlanner, render_plan: RenderPlan) Error!RenderPathGeometryPlan {
        self.reset();
        for (render_plan.commands, 0..) |command, index| {
            try self.consume(command, index);
        }
        return .{ .geometries = self.geometries[0..self.len] };
    }

    fn consume(self: *RenderPathGeometryPlanner, command: RenderCommand, index: usize) Error!void {
        switch (command.command) {
            .fill_path => |value| try self.consumePath(.fill, command, index, value.elements, 0),
            .stroke_path => |value| {
                const stroke_width = nonNegative(value.stroke.width) * referenceTransformScale(command.transform);
                if (stroke_width <= 0) return;
                try self.consumePath(.stroke, command, index, value.elements, stroke_width);
            },
            else => {},
        }
    }

    fn consumePath(self: *RenderPathGeometryPlanner, kind: RenderPathGeometryKind, command: RenderCommand, index: usize, elements: []const PathElement, stroke_width: f32) Error!void {
        const counts = analyzePathGeometry(elements, kind);
        if (counts.vertex_count == 0 or counts.index_count == 0) return;
        if (self.len >= self.geometries.len) return error.PathGeometryListFull;
        self.geometries[self.len] = .{
            .kind = kind,
            .command_index = index,
            .id = command.id,
            .bounds = command.bounds,
            .element_count = elements.len,
            .contour_count = counts.contour_count,
            .line_segment_count = counts.line_segment_count,
            .quadratic_segment_count = counts.quadratic_segment_count,
            .cubic_segment_count = counts.cubic_segment_count,
            .flattened_segment_count = counts.flattened_segment_count,
            .vertex_count = counts.vertex_count,
            .index_count = counts.index_count,
            .stroke_width = stroke_width,
            .fingerprint = renderPathGeometryFingerprint(command, kind, elements, stroke_width),
        };
        self.len += 1;
    }
};

pub const PathGeometryCounts = struct {
    contour_count: usize = 0,
    line_segment_count: usize = 0,
    quadratic_segment_count: usize = 0,
    cubic_segment_count: usize = 0,
    flattened_segment_count: usize = 0,
    vertex_count: usize = 0,
    index_count: usize = 0,
};

pub fn analyzePathGeometry(elements: []const PathElement, kind: RenderPathGeometryKind) PathGeometryCounts {
    var counts = PathGeometryCounts{};
    var has_current = false;

    for (elements) |element| {
        switch (element.verb) {
            .move_to => {
                counts.contour_count += 1;
                counts.vertex_count += 1;
                has_current = true;
            },
            .line_to => {
                if (!has_current) {
                    counts.contour_count += 1;
                    counts.vertex_count += 1;
                    has_current = true;
                    continue;
                }
                counts.line_segment_count += 1;
                counts.flattened_segment_count += 1;
                counts.vertex_count += 1;
            },
            .quad_to => {
                if (!has_current) continue;
                counts.quadratic_segment_count += 1;
                counts.flattened_segment_count += path_geometry_curve_segments;
                counts.vertex_count += path_geometry_curve_segments;
            },
            .cubic_to => {
                if (!has_current) continue;
                counts.cubic_segment_count += 1;
                counts.flattened_segment_count += path_geometry_curve_segments;
                counts.vertex_count += path_geometry_curve_segments;
            },
            .close => {
                if (!has_current) continue;
                counts.line_segment_count += 1;
                counts.flattened_segment_count += 1;
            },
        }
    }

    switch (kind) {
        .fill => {
            counts.index_count = if (counts.vertex_count >= 3) (counts.vertex_count - 2) * 3 else 0;
        },
        .stroke => {
            counts.vertex_count = counts.flattened_segment_count * 4;
            counts.index_count = counts.flattened_segment_count * 6;
        },
    }
    return counts;
}

fn renderBatchCanExtend(batch: RenderBatch, command: RenderCommand, pipeline: RenderPipelineKind, index: usize) bool {
    return batch.pipeline == pipeline and
        batch.command_start + batch.command_count == index and
        batch.opacity == command.opacity and
        optionalRectsEqual(batch.clip, command.clip);
}

fn renderPipelineKind(command: CanvasCommand) RenderPipelineKind {
    return switch (command) {
        .push_clip, .pop_clip, .push_opacity, .pop_opacity, .transform => .solid,
        .fill_rect => |value| renderPipelineForFill(value.fill),
        .stroke_rect => |value| renderPipelineForStroke(value.stroke),
        .fill_rounded_rect => |value| renderPipelineForFill(value.fill),
        .draw_line => |value| renderPipelineForStroke(value.stroke),
        .fill_path, .stroke_path => .path,
        .draw_image => .image,
        .draw_text => .glyph_run,
        .shadow => .shadow,
        .blur => .blur,
    };
}

fn renderPipelineForStroke(stroke: Stroke) RenderPipelineKind {
    return renderPipelineForFill(stroke.fill);
}

fn renderPipelineForFill(fill: Fill) RenderPipelineKind {
    return switch (fill) {
        .color => .solid,
        .linear_gradient => .linear_gradient,
    };
}

fn unionOptionalBounds(a: ?geometry.RectF, b: ?geometry.RectF) ?geometry.RectF {
    if (a) |left| {
        if (b) |right| return left.normalized().unionWith(right.normalized());
        return left;
    }
    return b;
}

fn renderPathGeometryKey(geometry_plan: RenderPathGeometry) RenderPathGeometryKey {
    return .{
        .kind = geometry_plan.kind,
        .id = geometry_plan.id,
        .command_index = if (geometry_plan.id == null) geometry_plan.command_index else 0,
        .fingerprint = geometry_plan.fingerprint,
    };
}

fn findRenderPathGeometryCacheEntry(entries: []const RenderPathGeometryCacheEntry, key: RenderPathGeometryKey) ?usize {
    for (entries, 0..) |entry, index| {
        if (renderPathGeometryKeysEqual(entry.key, key)) return index;
    }
    return null;
}

fn renderPathGeometryKeysEqual(a: RenderPathGeometryKey, b: RenderPathGeometryKey) bool {
    return a.kind == b.kind and
        a.id == b.id and
        a.command_index == b.command_index and
        a.fingerprint == b.fingerprint;
}

fn renderPathGeometryFingerprint(command: RenderCommand, kind: RenderPathGeometryKind, elements: []const PathElement, stroke_width: f32) u64 {
    var hash = resourceHashTag("path_geometry");
    hash = resourceHashBytes(hash, @tagName(kind));
    hash = resourceHashOptionalObjectId(hash, command.id);
    hash = resourceHashAffine(hash, command.transform);
    hash = resourceHashPath(hash, elements);
    hash = resourceHashF32(hash, stroke_width);
    return hash;
}

pub const RenderPathGeometryKey = struct {
    kind: RenderPathGeometryKind,
    id: ?ObjectId = null,
    command_index: usize = 0,
    fingerprint: u64 = 0,
};

pub const RenderPathGeometryCacheEntry = struct {
    key: RenderPathGeometryKey,
    last_used_frame: u64 = 0,
};

pub const RenderPathGeometryCacheActionKind = enum {
    upload,
    retain,
    evict,
};

pub const RenderPathGeometryCacheAction = struct {
    kind: RenderPathGeometryCacheActionKind,
    key: RenderPathGeometryKey,
    geometry_index: ?usize = null,
    cache_index: ?usize = null,
};

pub const RenderPathGeometryCachePlan = struct {
    entries: []const RenderPathGeometryCacheEntry = &.{},
    actions: []const RenderPathGeometryCacheAction = &.{},

    pub fn entryCount(self: RenderPathGeometryCachePlan) usize {
        return self.entries.len;
    }

    pub fn actionCount(self: RenderPathGeometryCachePlan) usize {
        return self.actions.len;
    }

    pub fn uploadCount(self: RenderPathGeometryCachePlan) usize {
        return self.actionCountByKind(.upload);
    }

    pub fn retainCount(self: RenderPathGeometryCachePlan) usize {
        return self.actionCountByKind(.retain);
    }

    pub fn evictCount(self: RenderPathGeometryCachePlan) usize {
        return self.actionCountByKind(.evict);
    }

    fn actionCountByKind(self: RenderPathGeometryCachePlan, kind: RenderPathGeometryCacheActionKind) usize {
        var count: usize = 0;
        for (self.actions) |action| {
            if (action.kind == kind) count += 1;
        }
        return count;
    }
};

pub const RenderPathGeometryCachePlanner = struct {
    entries: []RenderPathGeometryCacheEntry,
    actions: []RenderPathGeometryCacheAction,
    entry_len: usize = 0,
    action_len: usize = 0,

    pub fn init(entries: []RenderPathGeometryCacheEntry, actions: []RenderPathGeometryCacheAction) RenderPathGeometryCachePlanner {
        return .{ .entries = entries, .actions = actions };
    }

    pub fn reset(self: *RenderPathGeometryCachePlanner) void {
        self.entry_len = 0;
        self.action_len = 0;
    }

    pub fn build(self: *RenderPathGeometryCachePlanner, geometry_plan: RenderPathGeometryPlan, previous: []const RenderPathGeometryCacheEntry, frame_index: u64) Error!RenderPathGeometryCachePlan {
        self.reset();
        for (geometry_plan.geometries, 0..) |geometry_plan_item, geometry_index| {
            const key = renderPathGeometryKey(geometry_plan_item);
            if (findRenderPathGeometryCacheEntry(self.entries[0..self.entry_len], key) != null) continue;

            const previous_index = findRenderPathGeometryCacheEntry(previous, key);
            try self.appendAction(.{
                .kind = if (previous_index == null) .upload else .retain,
                .key = key,
                .geometry_index = geometry_index,
                .cache_index = previous_index,
            });
            try self.appendEntry(.{
                .key = key,
                .last_used_frame = frame_index,
            });
        }

        for (previous, 0..) |entry, cache_index| {
            if (findRenderPathGeometryCacheEntry(self.entries[0..self.entry_len], entry.key) != null) continue;
            try self.appendAction(.{
                .kind = .evict,
                .key = entry.key,
                .cache_index = cache_index,
            });
        }

        return .{
            .entries = self.entries[0..self.entry_len],
            .actions = self.actions[0..self.action_len],
        };
    }

    fn appendEntry(self: *RenderPathGeometryCachePlanner, entry: RenderPathGeometryCacheEntry) Error!void {
        if (self.entry_len >= self.entries.len) return error.PathGeometryCacheListFull;
        self.entries[self.entry_len] = entry;
        self.entry_len += 1;
    }

    fn appendAction(self: *RenderPathGeometryCachePlanner, action: RenderPathGeometryCacheAction) Error!void {
        if (self.action_len >= self.actions.len) return error.PathGeometryCacheListFull;
        self.actions[self.action_len] = action;
        self.action_len += 1;
    }
};

pub const RenderImage = struct {
    image_id: ImageId,
    command_index: usize = 0,
    id: ?ObjectId = null,
    draw_count: usize = 0,
    bounds: geometry.RectF = .{},
    width: usize = 0,
    height: usize = 0,
    pixels: []const u8 = &.{},
    fingerprint: u64 = 0,
};

pub const RenderImagePlan = struct {
    images: []const RenderImage = &.{},

    pub fn imageCount(self: RenderImagePlan) usize {
        return self.images.len;
    }

    pub fn drawCount(self: RenderImagePlan) usize {
        var count: usize = 0;
        for (self.images) |image| count += image.draw_count;
        return count;
    }

    pub fn cachePlan(self: RenderImagePlan, previous: []const RenderImageCacheEntry, frame_index: u64, entries: []RenderImageCacheEntry, actions: []RenderImageCacheAction) Error!RenderImageCachePlan {
        var planner = RenderImageCachePlanner.init(entries, actions);
        return planner.build(self, previous, frame_index);
    }
};

pub const RenderImageKey = struct {
    image_id: ImageId,
    fingerprint: u64 = 0,
};

pub const RenderImageCacheEntry = struct {
    key: RenderImageKey,
    last_used_frame: u64 = 0,
};

pub const RenderImageCacheActionKind = enum {
    upload,
    retain,
    evict,
};

pub const RenderImageCacheAction = struct {
    kind: RenderImageCacheActionKind,
    key: RenderImageKey,
    image_index: ?usize = null,
    cache_index: ?usize = null,
};

pub const RenderImageCachePlan = struct {
    entries: []const RenderImageCacheEntry = &.{},
    actions: []const RenderImageCacheAction = &.{},

    pub fn entryCount(self: RenderImageCachePlan) usize {
        return self.entries.len;
    }

    pub fn actionCount(self: RenderImageCachePlan) usize {
        return self.actions.len;
    }

    pub fn uploadCount(self: RenderImageCachePlan) usize {
        return self.actionCountByKind(.upload);
    }

    pub fn retainCount(self: RenderImageCachePlan) usize {
        return self.actionCountByKind(.retain);
    }

    pub fn evictCount(self: RenderImageCachePlan) usize {
        return self.actionCountByKind(.evict);
    }

    fn actionCountByKind(self: RenderImageCachePlan, kind: RenderImageCacheActionKind) usize {
        var count: usize = 0;
        for (self.actions) |action| {
            if (action.kind == kind) count += 1;
        }
        return count;
    }
};

pub const RenderResourceKind = enum {
    linear_gradient,
    image,
    glyph_run,
    shadow,
    blur,
};

pub const RenderResource = struct {
    kind: RenderResourceKind,
    command_index: usize,
    id: ?ObjectId = null,
    bounds: ?geometry.RectF = null,
    image_id: ImageId = 0,
    font_id: FontId = 0,
    gradient_stop_count: usize = 0,
    glyph_count: usize = 0,
    text_len: usize = 0,
    fingerprint: u64 = 0,
};

pub const RenderResourcePlan = struct {
    resources: []const RenderResource = &.{},

    pub fn resourceCount(self: RenderResourcePlan) usize {
        return self.resources.len;
    }

    pub fn cachePlan(self: RenderResourcePlan, previous: []const RenderResourceCacheEntry, frame_index: u64, entries: []RenderResourceCacheEntry, actions: []RenderResourceCacheAction) Error!RenderResourceCachePlan {
        var planner = RenderResourceCachePlanner.init(entries, actions);
        return planner.build(self, previous, frame_index);
    }
};

pub const RenderResourceKey = struct {
    kind: RenderResourceKind,
    id: ?ObjectId = null,
    command_index: usize = 0,
    image_id: ImageId = 0,
    font_id: FontId = 0,
    fingerprint: u64 = 0,
};

pub const RenderResourceCacheEntry = struct {
    key: RenderResourceKey,
    last_used_frame: u64 = 0,
};

pub const RenderResourceCacheActionKind = enum {
    upload,
    retain,
    evict,
};

pub const RenderResourceCacheAction = struct {
    kind: RenderResourceCacheActionKind,
    key: RenderResourceKey,
    resource_index: ?usize = null,
    cache_index: ?usize = null,
};

pub const RenderResourceCachePlan = struct {
    entries: []const RenderResourceCacheEntry = &.{},
    actions: []const RenderResourceCacheAction = &.{},

    pub fn entryCount(self: RenderResourceCachePlan) usize {
        return self.entries.len;
    }

    pub fn actionCount(self: RenderResourceCachePlan) usize {
        return self.actions.len;
    }

    pub fn uploadCount(self: RenderResourceCachePlan) usize {
        return self.actionCountByKind(.upload);
    }

    pub fn retainCount(self: RenderResourceCachePlan) usize {
        return self.actionCountByKind(.retain);
    }

    pub fn evictCount(self: RenderResourceCachePlan) usize {
        return self.actionCountByKind(.evict);
    }

    fn actionCountByKind(self: RenderResourceCachePlan, kind: RenderResourceCacheActionKind) usize {
        var count: usize = 0;
        for (self.actions) |action| {
            if (action.kind == kind) count += 1;
        }
        return count;
    }
};

pub const RenderLayer = struct {
    command_start: usize = 0,
    command_count: usize = 0,
    id: ?ObjectId = null,
    bounds: geometry.RectF = .{},
    opacity: f32 = 1,
    clip: ?geometry.RectF = null,
    transform: Affine = .{},
    fingerprint: u64 = 0,
};

pub const RenderLayerPlan = struct {
    layers: []const RenderLayer = &.{},

    pub fn layerCount(self: RenderLayerPlan) usize {
        return self.layers.len;
    }

    pub fn opacityLayerCount(self: RenderLayerPlan) usize {
        var count: usize = 0;
        for (self.layers) |layer| {
            if (layer.opacity != 1) count += 1;
        }
        return count;
    }

    pub fn clipLayerCount(self: RenderLayerPlan) usize {
        var count: usize = 0;
        for (self.layers) |layer| {
            if (layer.clip != null) count += 1;
        }
        return count;
    }

    pub fn transformLayerCount(self: RenderLayerPlan) usize {
        var count: usize = 0;
        for (self.layers) |layer| {
            if (!affinesEqual(layer.transform, Affine.identity())) count += 1;
        }
        return count;
    }

    pub fn cachePlan(self: RenderLayerPlan, previous: []const RenderLayerCacheEntry, frame_index: u64, entries: []RenderLayerCacheEntry, actions: []RenderLayerCacheAction) Error!RenderLayerCachePlan {
        var planner = RenderLayerCachePlanner.init(entries, actions);
        return planner.build(self, previous, frame_index);
    }
};

pub const RenderLayerKey = struct {
    id: ?ObjectId = null,
    command_start: usize = 0,
    fingerprint: u64 = 0,
};

pub const RenderLayerCacheEntry = struct {
    key: RenderLayerKey,
    last_used_frame: u64 = 0,
};

pub const RenderLayerCacheActionKind = enum {
    upload,
    retain,
    evict,
};

pub const RenderLayerCacheAction = struct {
    kind: RenderLayerCacheActionKind,
    key: RenderLayerKey,
    layer_index: ?usize = null,
    cache_index: ?usize = null,
};

pub const RenderLayerCachePlan = struct {
    entries: []const RenderLayerCacheEntry = &.{},
    actions: []const RenderLayerCacheAction = &.{},

    pub fn entryCount(self: RenderLayerCachePlan) usize {
        return self.entries.len;
    }

    pub fn actionCount(self: RenderLayerCachePlan) usize {
        return self.actions.len;
    }

    pub fn uploadCount(self: RenderLayerCachePlan) usize {
        return self.actionCountByKind(.upload);
    }

    pub fn retainCount(self: RenderLayerCachePlan) usize {
        return self.actionCountByKind(.retain);
    }

    pub fn evictCount(self: RenderLayerCachePlan) usize {
        return self.actionCountByKind(.evict);
    }

    fn actionCountByKind(self: RenderLayerCachePlan, kind: RenderLayerCacheActionKind) usize {
        var count: usize = 0;
        for (self.actions) |action| {
            if (action.kind == kind) count += 1;
        }
        return count;
    }
};

pub const VisualEffectKind = enum {
    shadow,
    blur,
};

pub const VisualEffect = struct {
    kind: VisualEffectKind,
    command_index: usize,
    id: ?ObjectId = null,
    bounds: ?geometry.RectF = null,
    radius: Radius = .{},
    offset: geometry.OffsetF = .{},
    blur: f32 = 0,
    spread: f32 = 0,
    fingerprint: u64 = 0,
};

pub const VisualEffectPlan = struct {
    effects: []const VisualEffect = &.{},

    pub fn effectCount(self: VisualEffectPlan) usize {
        return self.effects.len;
    }

    pub fn shadowCount(self: VisualEffectPlan) usize {
        return self.effectCountByKind(.shadow);
    }

    pub fn blurCount(self: VisualEffectPlan) usize {
        return self.effectCountByKind(.blur);
    }

    pub fn cachePlan(self: VisualEffectPlan, previous: []const VisualEffectCacheEntry, frame_index: u64, entries: []VisualEffectCacheEntry, actions: []VisualEffectCacheAction) Error!VisualEffectCachePlan {
        var planner = VisualEffectCachePlanner.init(entries, actions);
        return planner.build(self, previous, frame_index);
    }

    fn effectCountByKind(self: VisualEffectPlan, kind: VisualEffectKind) usize {
        var count: usize = 0;
        for (self.effects) |effect| {
            if (effect.kind == kind) count += 1;
        }
        return count;
    }
};

pub const VisualEffectKey = struct {
    kind: VisualEffectKind,
    id: ?ObjectId = null,
    command_index: usize = 0,
    fingerprint: u64 = 0,
};

pub const VisualEffectCacheEntry = struct {
    key: VisualEffectKey,
    last_used_frame: u64 = 0,
};

pub const VisualEffectCacheActionKind = enum {
    upload,
    retain,
    evict,
};

pub const VisualEffectCacheAction = struct {
    kind: VisualEffectCacheActionKind,
    key: VisualEffectKey,
    effect_index: ?usize = null,
    cache_index: ?usize = null,
};

pub const VisualEffectCachePlan = struct {
    entries: []const VisualEffectCacheEntry = &.{},
    actions: []const VisualEffectCacheAction = &.{},

    pub fn entryCount(self: VisualEffectCachePlan) usize {
        return self.entries.len;
    }

    pub fn actionCount(self: VisualEffectCachePlan) usize {
        return self.actions.len;
    }

    pub fn uploadCount(self: VisualEffectCachePlan) usize {
        return self.actionCountByKind(.upload);
    }

    pub fn retainCount(self: VisualEffectCachePlan) usize {
        return self.actionCountByKind(.retain);
    }

    pub fn evictCount(self: VisualEffectCachePlan) usize {
        return self.actionCountByKind(.evict);
    }

    fn actionCountByKind(self: VisualEffectCachePlan, kind: VisualEffectCacheActionKind) usize {
        var count: usize = 0;
        for (self.actions) |action| {
            if (action.kind == kind) count += 1;
        }
        return count;
    }
};

fn affinesEqual(a: Affine, b: Affine) bool {
    return a.a == b.a and
        a.b == b.b and
        a.c == b.c and
        a.d == b.d and
        a.tx == b.tx and
        a.ty == b.ty;
}

fn referenceTransformScale(transform: Affine) f32 {
    const x_scale = @sqrt(transform.a * transform.a + transform.b * transform.b);
    const y_scale = @sqrt(transform.c * transform.c + transform.d * transform.d);
    return @max(0.0001, @max(x_scale, y_scale));
}

fn nonNegative(value: f32) f32 {
    return @max(0, value);
}
