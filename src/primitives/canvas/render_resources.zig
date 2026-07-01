const std = @import("std");
const geometry = @import("geometry");
const canvas = @import("root.zig");
const drawing_model = @import("drawing.zig");
const hash_model = @import("hash.zig");
const text_model = @import("text.zig");
const equality_model = @import("equality.zig");

const Error = canvas.Error;
const ObjectId = canvas.ObjectId;
const ImageId = canvas.ImageId;
const FontId = canvas.FontId;
const ReferenceImage = canvas.ReferenceImage;
const Affine = drawing_model.Affine;
const LinearGradient = drawing_model.LinearGradient;
const Fill = drawing_model.Fill;
const Stroke = drawing_model.Stroke;
const Radius = drawing_model.Radius;
const DrawImage = drawing_model.DrawImage;
const Shadow = drawing_model.Shadow;
const Blur = drawing_model.Blur;
const Glyph = text_model.Glyph;
const DrawText = text_model.DrawText;
const TextLayoutOptions = text_model.TextLayoutOptions;
const shadowBounds = drawing_model.shadowBounds;
const textBounds = text_model.textBounds;
const optionalRectsEqual = equality_model.optionalRectsEqual;

const resourceHashTag = hash_model.resourceHashTag;
const resourceHashBytes = hash_model.resourceHashBytes;
const resourceHashU8 = hash_model.resourceHashU8;
const resourceHashU32 = hash_model.resourceHashU32;
const resourceHashU64 = hash_model.resourceHashU64;
const resourceHashUsize = hash_model.resourceHashUsize;
const resourceHashEnum = hash_model.resourceHashEnum;
const resourceHashF32 = hash_model.resourceHashF32;
const resourceHashPoint = hash_model.resourceHashPoint;
const resourceHashRect = hash_model.resourceHashRect;
const resourceHashOptionalRect = hash_model.resourceHashOptionalRect;
const resourceHashOptionalObjectId = hash_model.resourceHashOptionalObjectId;
const resourceHashAffine = hash_model.resourceHashAffine;
const resourceHashRadius = hash_model.resourceHashRadius;
const resourceHashColor = hash_model.resourceHashColor;
const resourceHashPath = hash_model.resourceHashPath;

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

pub const RenderImagePlanner = struct {
    images: []RenderImage,
    image_resources: []const ReferenceImage = &.{},
    len: usize = 0,

    pub fn init(images: []RenderImage) RenderImagePlanner {
        return .{ .images = images };
    }

    pub fn reset(self: *RenderImagePlanner) void {
        self.len = 0;
    }

    pub fn build(self: *RenderImagePlanner, render_plan: anytype) Error!RenderImagePlan {
        self.reset();
        for (render_plan.commands, 0..) |command, index| {
            try self.consume(command, index);
        }
        return .{ .images = self.images[0..self.len] };
    }

    fn consume(self: *RenderImagePlanner, command: anytype, index: usize) Error!void {
        switch (command.command) {
            .draw_image => |value| try self.appendOrExtend(value, command, index),
            else => {},
        }
    }

    fn appendOrExtend(self: *RenderImagePlanner, image: DrawImage, command: anytype, index: usize) Error!void {
        const resource = findReferenceImage(self.image_resources, image.image_id);
        const fingerprint = renderImageFingerprintForResource(image.image_id, resource);
        if (findRenderImage(self.images[0..self.len], image.image_id, fingerprint)) |existing_index| {
            const existing = &self.images[existing_index];
            existing.draw_count += 1;
            existing.id = if (existing.id == command.id) existing.id else null;
            existing.bounds = geometry.RectF.unionWith(existing.bounds.normalized(), command.bounds.normalized());
            return;
        }

        if (self.len >= self.images.len) return error.ImageListFull;
        self.images[self.len] = .{
            .image_id = image.image_id,
            .command_index = index,
            .id = command.id,
            .draw_count = 1,
            .bounds = command.bounds,
            .width = if (resource) |value| value.width else 0,
            .height = if (resource) |value| value.height else 0,
            .pixels = if (resource) |value| value.pixels else &.{},
            .fingerprint = fingerprint,
        };
        self.len += 1;
    }
};

pub const RenderImageCachePlanner = struct {
    entries: []RenderImageCacheEntry,
    actions: []RenderImageCacheAction,
    entry_len: usize = 0,
    action_len: usize = 0,

    pub fn init(entries: []RenderImageCacheEntry, actions: []RenderImageCacheAction) RenderImageCachePlanner {
        return .{ .entries = entries, .actions = actions };
    }

    pub fn reset(self: *RenderImageCachePlanner) void {
        self.entry_len = 0;
        self.action_len = 0;
    }

    pub fn build(self: *RenderImageCachePlanner, image_plan: RenderImagePlan, previous: []const RenderImageCacheEntry, frame_index: u64) Error!RenderImageCachePlan {
        self.reset();
        for (image_plan.images, 0..) |image, image_index| {
            const key = renderImageKey(image);
            if (findRenderImageCacheEntry(self.entries[0..self.entry_len], key) != null) continue;

            const previous_index = findRenderImageCacheEntry(previous, key);
            try self.appendAction(.{
                .kind = if (previous_index == null) .upload else .retain,
                .key = key,
                .image_index = image_index,
                .cache_index = previous_index,
            });
            try self.appendEntry(.{
                .key = key,
                .last_used_frame = frame_index,
            });
        }

        for (previous, 0..) |entry, cache_index| {
            if (findRenderImageCacheEntry(self.entries[0..self.entry_len], entry.key) != null) continue;
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

    fn appendEntry(self: *RenderImageCachePlanner, entry: RenderImageCacheEntry) Error!void {
        if (self.entry_len >= self.entries.len) return error.ImageCacheListFull;
        self.entries[self.entry_len] = entry;
        self.entry_len += 1;
    }

    fn appendAction(self: *RenderImageCachePlanner, action: RenderImageCacheAction) Error!void {
        if (self.action_len >= self.actions.len) return error.ImageCacheListFull;
        self.actions[self.action_len] = action;
        self.action_len += 1;
    }
};

fn renderImageKey(image: RenderImage) RenderImageKey {
    return .{
        .image_id = image.image_id,
        .fingerprint = image.fingerprint,
    };
}

fn findRenderImage(images: []const RenderImage, image_id: ImageId, fingerprint: u64) ?usize {
    for (images, 0..) |image, index| {
        if (image.image_id == image_id and image.fingerprint == fingerprint) return index;
    }
    return null;
}

fn findRenderImageCacheEntry(entries: []const RenderImageCacheEntry, key: RenderImageKey) ?usize {
    for (entries, 0..) |entry, index| {
        if (renderImageKeysEqual(entry.key, key)) return index;
    }
    return null;
}

fn renderImageKeysEqual(a: RenderImageKey, b: RenderImageKey) bool {
    return a.image_id == b.image_id and
        a.fingerprint == b.fingerprint;
}

fn findReferenceImage(images: []const ReferenceImage, id: ImageId) ?ReferenceImage {
    for (images) |image| {
        if (image.id == id) return image;
    }
    return null;
}

pub fn drawImageFingerprint(image: DrawImage) u64 {
    var hash = resourceHashTag("image");
    hash = resourceHashU64(hash, image.image_id);
    hash = resourceHashOptionalRect(hash, image.src);
    hash = resourceHashEnum(hash, @intFromEnum(image.fit));
    hash = resourceHashEnum(hash, @intFromEnum(image.sampling));
    return hash;
}

pub fn renderImageFingerprint(image_id: ImageId) u64 {
    return resourceHashU64(resourceHashTag("image_texture"), image_id);
}

pub fn renderImageFingerprintForResource(image_id: ImageId, image: ?ReferenceImage) u64 {
    const value = image orelse return renderImageFingerprint(image_id);
    var hash = renderImageFingerprint(image_id);
    hash = resourceHashUsize(hash, value.width);
    hash = resourceHashUsize(hash, value.height);
    hash = resourceHashBytes(hash, value.pixels);
    return hash;
}

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

pub const RenderResourcePlanner = struct {
    resources: []RenderResource,
    len: usize = 0,

    pub fn init(resources: []RenderResource) RenderResourcePlanner {
        return .{ .resources = resources };
    }

    pub fn reset(self: *RenderResourcePlanner) void {
        self.len = 0;
    }

    pub fn build(self: *RenderResourcePlanner, display_list: anytype) Error!RenderResourcePlan {
        self.reset();
        for (display_list.commands, 0..) |command, index| {
            try self.consume(command, index);
        }
        return .{ .resources = self.resources[0..self.len] };
    }

    fn consume(self: *RenderResourcePlanner, command: anytype, index: usize) Error!void {
        switch (command) {
            .push_clip, .pop_clip, .push_opacity, .pop_opacity, .transform => {},
            .fill_rect => |value| try self.consumeFill(value.fill, index, value.id, command.bounds()),
            .stroke_rect => |value| try self.consumeStroke(value.stroke, index, value.id, command.bounds()),
            .fill_rounded_rect => |value| try self.consumeFill(value.fill, index, value.id, command.bounds()),
            .draw_line => |value| try self.consumeStroke(value.stroke, index, value.id, command.bounds()),
            .fill_path => |value| try self.consumeFill(value.fill, index, value.id, command.bounds()),
            .stroke_path => |value| try self.consumeStroke(value.stroke, index, value.id, command.bounds()),
            .draw_image => |value| try self.append(.{
                .kind = .image,
                .command_index = index,
                .id = nonZeroObjectId(value.id),
                .bounds = value.dst.normalized(),
                .image_id = value.image_id,
                .fingerprint = drawImageFingerprint(value),
            }),
            .draw_text => |value| try self.append(.{
                .kind = .glyph_run,
                .command_index = index,
                .id = nonZeroObjectId(value.id),
                .bounds = textBounds(value),
                .font_id = value.font_id,
                .glyph_count = value.glyphs.len,
                .text_len = value.text.len,
                .fingerprint = drawTextFingerprint(value),
            }),
            .shadow => |value| try self.append(.{
                .kind = .shadow,
                .command_index = index,
                .id = nonZeroObjectId(value.id),
                .bounds = shadowBounds(value),
                .fingerprint = shadowFingerprint(value),
            }),
            .blur => |value| try self.append(.{
                .kind = .blur,
                .command_index = index,
                .id = nonZeroObjectId(value.id),
                .bounds = value.rect.normalized().inflate(geometry.InsetsF.all(nonNegative(value.radius))),
                .fingerprint = blurFingerprint(value),
            }),
        }
    }

    fn consumeStroke(self: *RenderResourcePlanner, stroke: Stroke, index: usize, id: ObjectId, bounds: ?geometry.RectF) Error!void {
        try self.consumeFill(stroke.fill, index, id, bounds);
    }

    fn consumeFill(self: *RenderResourcePlanner, fill: Fill, index: usize, id: ObjectId, bounds: ?geometry.RectF) Error!void {
        switch (fill) {
            .color => {},
            .linear_gradient => |gradient| try self.append(.{
                .kind = .linear_gradient,
                .command_index = index,
                .id = nonZeroObjectId(id),
                .bounds = bounds,
                .gradient_stop_count = gradient.stops.len,
                .fingerprint = linearGradientFingerprint(gradient),
            }),
        }
    }

    fn append(self: *RenderResourcePlanner, resource: RenderResource) Error!void {
        if (self.len >= self.resources.len) return error.RenderResourceListFull;
        self.resources[self.len] = resource;
        self.len += 1;
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

pub const RenderResourceCachePlanner = struct {
    entries: []RenderResourceCacheEntry,
    actions: []RenderResourceCacheAction,
    entry_len: usize = 0,
    action_len: usize = 0,

    pub fn init(entries: []RenderResourceCacheEntry, actions: []RenderResourceCacheAction) RenderResourceCachePlanner {
        return .{ .entries = entries, .actions = actions };
    }

    pub fn reset(self: *RenderResourceCachePlanner) void {
        self.entry_len = 0;
        self.action_len = 0;
    }

    pub fn build(self: *RenderResourceCachePlanner, resource_plan: RenderResourcePlan, previous: []const RenderResourceCacheEntry, frame_index: u64) Error!RenderResourceCachePlan {
        self.reset();
        for (resource_plan.resources, 0..) |resource, resource_index| {
            const key = renderResourceKey(resource);
            if (findRenderResourceCacheEntry(self.entries[0..self.entry_len], key) != null) continue;

            const previous_index = findRenderResourceCacheEntry(previous, key);
            try self.appendAction(.{
                .kind = if (previous_index == null) .upload else .retain,
                .key = key,
                .resource_index = resource_index,
                .cache_index = previous_index,
            });
            try self.appendEntry(.{
                .key = key,
                .last_used_frame = frame_index,
            });
        }

        for (previous, 0..) |entry, cache_index| {
            if (findRenderResourceCacheEntry(self.entries[0..self.entry_len], entry.key) != null) continue;
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

    fn appendEntry(self: *RenderResourceCachePlanner, entry: RenderResourceCacheEntry) Error!void {
        if (self.entry_len >= self.entries.len) return error.RenderResourceCacheListFull;
        self.entries[self.entry_len] = entry;
        self.entry_len += 1;
    }

    fn appendAction(self: *RenderResourceCachePlanner, action: RenderResourceCacheAction) Error!void {
        if (self.action_len >= self.actions.len) return error.RenderResourceCacheListFull;
        self.actions[self.action_len] = action;
        self.action_len += 1;
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

pub const RenderLayerPlanner = struct {
    layers: []RenderLayer,
    len: usize = 0,

    pub fn init(layers: []RenderLayer) RenderLayerPlanner {
        return .{ .layers = layers };
    }

    pub fn reset(self: *RenderLayerPlanner) void {
        self.len = 0;
    }

    pub fn build(self: *RenderLayerPlanner, render_plan: anytype) Error!RenderLayerPlan {
        self.reset();
        for (render_plan.commands, 0..) |command, index| {
            try self.consume(command, index);
        }
        return .{ .layers = self.layers[0..self.len] };
    }

    fn consume(self: *RenderLayerPlanner, command: anytype, index: usize) Error!void {
        if (!renderCommandNeedsLayer(command)) return;

        if (self.len > 0 and renderLayerCanExtend(self.layers[self.len - 1], command, index)) {
            const layer = &self.layers[self.len - 1];
            layer.command_count += 1;
            layer.id = if (layer.id == command.id) layer.id else null;
            layer.bounds = geometry.RectF.unionWith(layer.bounds.normalized(), command.bounds.normalized());
            layer.fingerprint = renderLayerFingerprintAppend(layer.fingerprint, command);
            return;
        }

        if (self.len >= self.layers.len) return error.LayerListFull;
        self.layers[self.len] = .{
            .command_start = index,
            .command_count = 1,
            .id = command.id,
            .bounds = command.bounds,
            .opacity = command.opacity,
            .clip = command.clip,
            .transform = command.transform,
            .fingerprint = renderLayerFingerprint(command),
        };
        self.len += 1;
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

pub const RenderLayerCachePlanner = struct {
    entries: []RenderLayerCacheEntry,
    actions: []RenderLayerCacheAction,
    entry_len: usize = 0,
    action_len: usize = 0,

    pub fn init(entries: []RenderLayerCacheEntry, actions: []RenderLayerCacheAction) RenderLayerCachePlanner {
        return .{ .entries = entries, .actions = actions };
    }

    pub fn reset(self: *RenderLayerCachePlanner) void {
        self.entry_len = 0;
        self.action_len = 0;
    }

    pub fn build(self: *RenderLayerCachePlanner, layer_plan: RenderLayerPlan, previous: []const RenderLayerCacheEntry, frame_index: u64) Error!RenderLayerCachePlan {
        self.reset();
        for (layer_plan.layers, 0..) |layer, layer_index| {
            const key = renderLayerKey(layer);
            if (findRenderLayerCacheEntry(self.entries[0..self.entry_len], key) != null) continue;

            const previous_index = findRenderLayerCacheEntry(previous, key);
            try self.appendAction(.{
                .kind = if (previous_index == null) .upload else .retain,
                .key = key,
                .layer_index = layer_index,
                .cache_index = previous_index,
            });
            try self.appendEntry(.{
                .key = key,
                .last_used_frame = frame_index,
            });
        }

        for (previous, 0..) |entry, cache_index| {
            if (findRenderLayerCacheEntry(self.entries[0..self.entry_len], entry.key) != null) continue;
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

    fn appendEntry(self: *RenderLayerCachePlanner, entry: RenderLayerCacheEntry) Error!void {
        if (self.entry_len >= self.entries.len) return error.LayerCacheListFull;
        self.entries[self.entry_len] = entry;
        self.entry_len += 1;
    }

    fn appendAction(self: *RenderLayerCachePlanner, action: RenderLayerCacheAction) Error!void {
        if (self.action_len >= self.actions.len) return error.LayerCacheListFull;
        self.actions[self.action_len] = action;
        self.action_len += 1;
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

pub const VisualEffectPlanner = struct {
    effects: []VisualEffect,
    len: usize = 0,

    pub fn init(effects: []VisualEffect) VisualEffectPlanner {
        return .{ .effects = effects };
    }

    pub fn reset(self: *VisualEffectPlanner) void {
        self.len = 0;
    }

    pub fn build(self: *VisualEffectPlanner, display_list: anytype) Error!VisualEffectPlan {
        self.reset();
        for (display_list.commands, 0..) |command, index| {
            try self.consume(command, index);
        }
        return .{ .effects = self.effects[0..self.len] };
    }

    fn consume(self: *VisualEffectPlanner, command: anytype, index: usize) Error!void {
        switch (command) {
            .shadow => |value| try self.append(.{
                .kind = .shadow,
                .command_index = index,
                .id = nonZeroObjectId(value.id),
                .bounds = shadowBounds(value),
                .radius = value.radius,
                .offset = value.offset,
                .blur = nonNegative(value.blur),
                .spread = value.spread,
                .fingerprint = shadowFingerprint(value),
            }),
            .blur => |value| try self.append(.{
                .kind = .blur,
                .command_index = index,
                .id = nonZeroObjectId(value.id),
                .bounds = value.rect.normalized().inflate(geometry.InsetsF.all(nonNegative(value.radius))),
                .blur = nonNegative(value.radius),
                .fingerprint = blurFingerprint(value),
            }),
            else => {},
        }
    }

    fn append(self: *VisualEffectPlanner, effect: VisualEffect) Error!void {
        if (self.len >= self.effects.len) return error.VisualEffectListFull;
        self.effects[self.len] = effect;
        self.len += 1;
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

pub const VisualEffectCachePlanner = struct {
    entries: []VisualEffectCacheEntry,
    actions: []VisualEffectCacheAction,
    entry_len: usize = 0,
    action_len: usize = 0,

    pub fn init(entries: []VisualEffectCacheEntry, actions: []VisualEffectCacheAction) VisualEffectCachePlanner {
        return .{ .entries = entries, .actions = actions };
    }

    pub fn reset(self: *VisualEffectCachePlanner) void {
        self.entry_len = 0;
        self.action_len = 0;
    }

    pub fn build(self: *VisualEffectCachePlanner, effect_plan: VisualEffectPlan, previous: []const VisualEffectCacheEntry, frame_index: u64) Error!VisualEffectCachePlan {
        self.reset();
        for (effect_plan.effects, 0..) |effect, effect_index| {
            const key = visualEffectKey(effect);
            if (findVisualEffectCacheEntry(self.entries[0..self.entry_len], key) != null) continue;

            const previous_index = findVisualEffectCacheEntry(previous, key);
            try self.appendAction(.{
                .kind = if (previous_index == null) .upload else .retain,
                .key = key,
                .effect_index = effect_index,
                .cache_index = previous_index,
            });
            try self.appendEntry(.{
                .key = key,
                .last_used_frame = frame_index,
            });
        }

        for (previous, 0..) |entry, cache_index| {
            if (findVisualEffectCacheEntry(self.entries[0..self.entry_len], entry.key) != null) continue;
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

    fn appendEntry(self: *VisualEffectCachePlanner, entry: VisualEffectCacheEntry) Error!void {
        if (self.entry_len >= self.entries.len) return error.VisualEffectCacheListFull;
        self.entries[self.entry_len] = entry;
        self.entry_len += 1;
    }

    fn appendAction(self: *VisualEffectCachePlanner, action: VisualEffectCacheAction) Error!void {
        if (self.action_len >= self.actions.len) return error.VisualEffectCacheListFull;
        self.actions[self.action_len] = action;
        self.action_len += 1;
    }
};

fn renderCommandNeedsLayer(command: anytype) bool {
    return command.opacity != 1 or command.clip != null or !affinesEqual(command.transform, Affine.identity());
}

fn renderLayerCanExtend(layer: RenderLayer, command: anytype, index: usize) bool {
    return layer.command_start + layer.command_count == index and
        layer.opacity == command.opacity and
        optionalRectsEqual(layer.clip, command.clip) and
        affinesEqual(layer.transform, command.transform);
}

fn renderResourceKey(resource: RenderResource) RenderResourceKey {
    return .{
        .kind = resource.kind,
        .id = resource.id,
        .command_index = if (resource.id == null and resource.kind != .image) resource.command_index else 0,
        .image_id = resource.image_id,
        .font_id = resource.font_id,
        .fingerprint = resource.fingerprint,
    };
}

fn findRenderResourceCacheEntry(entries: []const RenderResourceCacheEntry, key: RenderResourceKey) ?usize {
    for (entries, 0..) |entry, index| {
        if (renderResourceKeysEqual(entry.key, key)) return index;
    }
    return null;
}

fn renderResourceKeysEqual(a: RenderResourceKey, b: RenderResourceKey) bool {
    return a.kind == b.kind and
        a.id == b.id and
        a.command_index == b.command_index and
        a.image_id == b.image_id and
        a.font_id == b.font_id and
        a.fingerprint == b.fingerprint;
}

fn renderLayerKey(layer: RenderLayer) RenderLayerKey {
    return .{
        .id = layer.id,
        .command_start = if (layer.id == null) layer.command_start else 0,
        .fingerprint = layer.fingerprint,
    };
}

fn findRenderLayerCacheEntry(entries: []const RenderLayerCacheEntry, key: RenderLayerKey) ?usize {
    for (entries, 0..) |entry, index| {
        if (renderLayerKeysEqual(entry.key, key)) return index;
    }
    return null;
}

fn renderLayerKeysEqual(a: RenderLayerKey, b: RenderLayerKey) bool {
    return a.id == b.id and
        a.command_start == b.command_start and
        a.fingerprint == b.fingerprint;
}

fn renderLayerFingerprint(command: anytype) u64 {
    var hash = resourceHashTag("layer");
    hash = resourceHashF32(hash, command.opacity);
    hash = resourceHashOptionalRect(hash, command.clip);
    hash = resourceHashAffine(hash, command.transform);
    return renderLayerFingerprintAppend(hash, command);
}

fn renderLayerFingerprintAppend(hash: u64, command: anytype) u64 {
    return resourceHashU64(hash, renderCommandFingerprint(command));
}

fn renderCommandFingerprint(command: anytype) u64 {
    var hash = resourceHashTag("render_command");
    hash = resourceHashOptionalObjectId(hash, command.id);
    hash = resourceHashRect(hash, command.local_bounds);
    hash = resourceHashRect(hash, command.bounds);
    return resourceHashCanvasCommand(hash, command.command);
}

fn visualEffectKey(effect: VisualEffect) VisualEffectKey {
    return .{
        .kind = effect.kind,
        .id = effect.id,
        .command_index = if (effect.id == null) effect.command_index else 0,
        .fingerprint = effect.fingerprint,
    };
}

fn findVisualEffectCacheEntry(entries: []const VisualEffectCacheEntry, key: VisualEffectKey) ?usize {
    for (entries, 0..) |entry, index| {
        if (visualEffectKeysEqual(entry.key, key)) return index;
    }
    return null;
}

fn visualEffectKeysEqual(a: VisualEffectKey, b: VisualEffectKey) bool {
    return a.kind == b.kind and
        a.id == b.id and
        a.command_index == b.command_index and
        a.fingerprint == b.fingerprint;
}

fn linearGradientFingerprint(gradient: LinearGradient) u64 {
    var hash = resourceHashTag("linear_gradient");
    hash = resourceHashPoint(hash, gradient.start);
    hash = resourceHashPoint(hash, gradient.end);
    hash = resourceHashUsize(hash, gradient.stops.len);
    for (gradient.stops) |stop| {
        hash = resourceHashF32(hash, stop.offset);
        hash = resourceHashColor(hash, stop.color);
    }
    return hash;
}

fn drawTextFingerprint(text: DrawText) u64 {
    var hash = resourceHashTag("glyph_run");
    hash = resourceHashU64(hash, text.font_id);
    hash = resourceHashF32(hash, text.size);
    hash = resourceHashPoint(hash, text.origin);
    hash = resourceHashBytes(hash, text.text);
    hash = resourceHashUsize(hash, text.glyphs.len);
    for (text.glyphs) |glyph| {
        hash = resourceHashU32(hash, glyph.id);
        hash = resourceHashU64(hash, glyphFontId(text.font_id, glyph));
        hash = resourceHashF32(hash, glyph.x);
        hash = resourceHashF32(hash, glyph.y);
        hash = resourceHashF32(hash, glyph.advance);
        hash = resourceHashUsize(hash, glyph.text_start);
        hash = resourceHashUsize(hash, glyph.text_len);
    }
    hash = resourceHashOptionalTextLayoutOptions(hash, text.text_layout);
    return hash;
}

fn glyphFontId(run_font_id: FontId, glyph: Glyph) FontId {
    return if (glyph.font_id == 0) run_font_id else glyph.font_id;
}

fn shadowFingerprint(shadow: Shadow) u64 {
    var hash = resourceHashTag("shadow");
    hash = resourceHashRect(hash, shadow.rect);
    hash = resourceHashRadius(hash, shadow.radius);
    hash = resourceHashF32(hash, shadow.offset.dx);
    hash = resourceHashF32(hash, shadow.offset.dy);
    hash = resourceHashF32(hash, shadow.blur);
    hash = resourceHashF32(hash, shadow.spread);
    hash = resourceHashColor(hash, shadow.color);
    return hash;
}

fn blurFingerprint(blur: Blur) u64 {
    var hash = resourceHashTag("blur");
    hash = resourceHashRect(hash, blur.rect);
    hash = resourceHashF32(hash, blur.radius);
    return hash;
}

fn resourceHashOptionalTextLayoutOptions(hash: u64, options: ?TextLayoutOptions) u64 {
    if (options) |value| {
        var next = resourceHashU8(hash, 1);
        next = resourceHashF32(next, nonNegative(value.max_width));
        next = resourceHashF32(next, nonNegative(value.line_height));
        next = resourceHashEnum(next, @intFromEnum(value.wrap));
        next = resourceHashEnum(next, @intFromEnum(value.alignment));
        return next;
    }
    return resourceHashU8(hash, 0);
}

fn resourceHashCanvasCommand(hash: u64, command: anytype) u64 {
    var next = resourceHashBytes(hash, @tagName(command));
    switch (command) {
        .push_clip => |value| {
            next = resourceHashOptionalObjectId(next, nonZeroObjectId(value.id));
            next = resourceHashRect(next, value.rect);
            next = resourceHashRadius(next, value.radius);
        },
        .pop_clip, .push_opacity, .pop_opacity, .transform => {},
        .fill_rect => |value| {
            next = resourceHashOptionalObjectId(next, nonZeroObjectId(value.id));
            next = resourceHashRect(next, value.rect);
            next = resourceHashFill(next, value.fill);
        },
        .stroke_rect => |value| {
            next = resourceHashOptionalObjectId(next, nonZeroObjectId(value.id));
            next = resourceHashRect(next, value.rect);
            next = resourceHashRadius(next, value.radius);
            next = resourceHashStroke(next, value.stroke);
        },
        .fill_rounded_rect => |value| {
            next = resourceHashOptionalObjectId(next, nonZeroObjectId(value.id));
            next = resourceHashRect(next, value.rect);
            next = resourceHashRadius(next, value.radius);
            next = resourceHashFill(next, value.fill);
        },
        .draw_line => |value| {
            next = resourceHashOptionalObjectId(next, nonZeroObjectId(value.id));
            next = resourceHashPoint(next, value.from);
            next = resourceHashPoint(next, value.to);
            next = resourceHashStroke(next, value.stroke);
        },
        .fill_path => |value| {
            next = resourceHashOptionalObjectId(next, nonZeroObjectId(value.id));
            next = resourceHashPath(next, value.elements);
            next = resourceHashFill(next, value.fill);
        },
        .stroke_path => |value| {
            next = resourceHashOptionalObjectId(next, nonZeroObjectId(value.id));
            next = resourceHashPath(next, value.elements);
            next = resourceHashStroke(next, value.stroke);
        },
        .draw_image => |value| {
            next = resourceHashOptionalObjectId(next, nonZeroObjectId(value.id));
            next = resourceHashU64(next, drawImageFingerprint(value));
            next = resourceHashRect(next, value.dst);
            next = resourceHashF32(next, value.opacity);
        },
        .draw_text => |value| {
            next = resourceHashOptionalObjectId(next, nonZeroObjectId(value.id));
            next = resourceHashU64(next, drawTextFingerprint(value));
            next = resourceHashColor(next, value.color);
        },
        .shadow => |value| {
            next = resourceHashOptionalObjectId(next, nonZeroObjectId(value.id));
            next = resourceHashU64(next, shadowFingerprint(value));
        },
        .blur => |value| {
            next = resourceHashOptionalObjectId(next, nonZeroObjectId(value.id));
            next = resourceHashU64(next, blurFingerprint(value));
        },
    }
    return next;
}

fn resourceHashFill(hash: u64, fill: Fill) u64 {
    return switch (fill) {
        .color => |color| resourceHashColor(resourceHashBytes(hash, "color"), color),
        .linear_gradient => |gradient| resourceHashU64(resourceHashBytes(hash, "linear_gradient"), linearGradientFingerprint(gradient)),
    };
}

fn resourceHashStroke(hash: u64, stroke: Stroke) u64 {
    var next = resourceHashF32(resourceHashBytes(hash, "stroke"), stroke.width);
    next = resourceHashFill(next, stroke.fill);
    return next;
}

fn nonZeroObjectId(id: ObjectId) ?ObjectId {
    return if (id == 0) null else id;
}

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
