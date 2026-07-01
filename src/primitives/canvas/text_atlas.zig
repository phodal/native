const std = @import("std");
const canvas = @import("root.zig");
const text_interaction = @import("text_interaction.zig");

const Error = canvas.Error;
const FontId = canvas.FontId;
const default_glyph_atlas_cache_retention_frames = canvas.default_glyph_atlas_cache_retention_frames;
const isUtf8ContinuationByte = text_interaction.isUtf8ContinuationByte;
const nextTextOffset = text_interaction.nextTextOffset;
const utf8SequenceLength = text_interaction.utf8SequenceLength;

pub const Glyph = struct {
    id: u32,
    font_id: FontId = 0,
    x: f32,
    y: f32,
    advance: f32 = 0,
    text_start: usize = 0,
    text_len: usize = 0,
};

pub const GlyphAtlasKey = struct {
    font_id: FontId = 0,
    glyph_id: u32 = 0,
    size: f32 = 0,
    subpixel_x: u8 = 0,
    subpixel_y: u8 = 0,
};

pub const GlyphAtlasEntry = struct {
    key: GlyphAtlasKey,
    command_index: usize,
    glyph_index: usize,
};

pub const GlyphAtlasPlan = struct {
    entries: []const GlyphAtlasEntry = &.{},

    pub fn entryCount(self: GlyphAtlasPlan) usize {
        return self.entries.len;
    }

    pub fn cachePlan(self: GlyphAtlasPlan, previous: []const GlyphAtlasCacheEntry, frame_index: u64, entries: []GlyphAtlasCacheEntry, actions: []GlyphAtlasCacheAction) Error!GlyphAtlasCachePlan {
        return self.cachePlanWithRetention(previous, frame_index, default_glyph_atlas_cache_retention_frames, entries, actions);
    }

    pub fn cachePlanWithRetention(self: GlyphAtlasPlan, previous: []const GlyphAtlasCacheEntry, frame_index: u64, retention_frames: u64, entries: []GlyphAtlasCacheEntry, actions: []GlyphAtlasCacheAction) Error!GlyphAtlasCachePlan {
        var planner = GlyphAtlasCachePlanner.init(entries, actions);
        return planner.build(self, previous, frame_index, retention_frames);
    }
};

pub const GlyphAtlasPlanner = struct {
    entries: []GlyphAtlasEntry,
    len: usize = 0,

    pub fn init(entries: []GlyphAtlasEntry) GlyphAtlasPlanner {
        return .{ .entries = entries };
    }

    pub fn reset(self: *GlyphAtlasPlanner) void {
        self.len = 0;
    }

    pub fn build(self: *GlyphAtlasPlanner, display_list: anytype) Error!GlyphAtlasPlan {
        self.reset();
        for (display_list.commands, 0..) |command, command_index| {
            switch (command) {
                .draw_text => |value| try self.consumeText(value, command_index),
                else => {},
            }
        }
        return .{ .entries = self.entries[0..self.len] };
    }

    fn consumeText(self: *GlyphAtlasPlanner, text: anytype, command_index: usize) Error!void {
        if (text.glyphs.len > 0) {
            for (text.glyphs, 0..) |glyph, glyph_index| {
                const key = GlyphAtlasKey{
                    .font_id = glyphFontId(text.font_id, glyph),
                    .glyph_id = glyph.id,
                    .size = text.size,
                    .subpixel_x = subpixelBucket(text.origin.x + glyph.x),
                    .subpixel_y = subpixelBucket(text.origin.y + glyph.y),
                };
                try self.appendUnique(key, command_index, glyph_index);
            }
            return;
        }

        var text_offset: usize = 0;
        var scalar_index: usize = 0;
        while (text_offset < text.text.len) {
            const next_offset = nextTextOffset(text.text, text_offset);
            defer {
                text_offset = next_offset;
                scalar_index += 1;
            }
            if (isPlanTextSpace(text.text[text_offset])) continue;

            const key = GlyphAtlasKey{
                .font_id = text.font_id,
                .glyph_id = fallbackGlyphId(text.text[text_offset..next_offset]),
                .size = text.size,
                .subpixel_x = subpixelBucket(text.origin.x + @as(f32, @floatFromInt(scalar_index)) * text.size * 0.5),
                .subpixel_y = subpixelBucket(text.origin.y),
            };
            try self.appendUnique(key, command_index, scalar_index);
        }
    }

    fn appendUnique(self: *GlyphAtlasPlanner, key: GlyphAtlasKey, command_index: usize, glyph_index: usize) Error!void {
        for (self.entries[0..self.len]) |entry| {
            if (glyphAtlasKeysEqual(entry.key, key)) return;
        }
        if (self.len >= self.entries.len) return error.GlyphAtlasListFull;
        self.entries[self.len] = .{
            .key = key,
            .command_index = command_index,
            .glyph_index = glyph_index,
        };
        self.len += 1;
    }
};

pub const GlyphAtlasCacheEntry = struct {
    key: GlyphAtlasKey,
    last_used_frame: u64 = 0,
};

pub const GlyphAtlasCacheActionKind = enum {
    upload,
    retain,
    evict,
};

pub const GlyphAtlasCacheAction = struct {
    kind: GlyphAtlasCacheActionKind,
    key: GlyphAtlasKey,
    atlas_index: ?usize = null,
    cache_index: ?usize = null,
};

pub const GlyphAtlasCachePlan = struct {
    entries: []const GlyphAtlasCacheEntry = &.{},
    actions: []const GlyphAtlasCacheAction = &.{},

    pub fn entryCount(self: GlyphAtlasCachePlan) usize {
        return self.entries.len;
    }

    pub fn actionCount(self: GlyphAtlasCachePlan) usize {
        return self.actions.len;
    }

    pub fn uploadCount(self: GlyphAtlasCachePlan) usize {
        return self.actionCountByKind(.upload);
    }

    pub fn retainCount(self: GlyphAtlasCachePlan) usize {
        return self.actionCountByKind(.retain);
    }

    pub fn evictCount(self: GlyphAtlasCachePlan) usize {
        return self.actionCountByKind(.evict);
    }

    fn actionCountByKind(self: GlyphAtlasCachePlan, kind: GlyphAtlasCacheActionKind) usize {
        var count: usize = 0;
        for (self.actions) |action| {
            if (action.kind == kind) count += 1;
        }
        return count;
    }
};

pub const GlyphAtlasCachePlanner = struct {
    entries: []GlyphAtlasCacheEntry,
    actions: []GlyphAtlasCacheAction,
    entry_len: usize = 0,
    action_len: usize = 0,

    pub fn init(entries: []GlyphAtlasCacheEntry, actions: []GlyphAtlasCacheAction) GlyphAtlasCachePlanner {
        return .{ .entries = entries, .actions = actions };
    }

    pub fn reset(self: *GlyphAtlasCachePlanner) void {
        self.entry_len = 0;
        self.action_len = 0;
    }

    pub fn build(self: *GlyphAtlasCachePlanner, plan: GlyphAtlasPlan, previous: []const GlyphAtlasCacheEntry, frame_index: u64, retention_frames: u64) Error!GlyphAtlasCachePlan {
        self.reset();

        for (plan.entries, 0..) |entry, atlas_index| {
            if (findGlyphAtlasCacheEntry(self.entries[0..self.entry_len], entry.key) != null) continue;

            const previous_index = findGlyphAtlasCacheEntry(previous, entry.key);
            try self.appendEntry(.{
                .key = entry.key,
                .last_used_frame = frame_index,
            });
            try self.appendAction(.{
                .kind = if (previous_index == null) .upload else .retain,
                .key = entry.key,
                .atlas_index = atlas_index,
                .cache_index = previous_index,
            });
        }

        for (previous, 0..) |entry, previous_index| {
            if (findGlyphAtlasCacheEntry(self.entries[0..self.entry_len], entry.key) != null) continue;
            if (shouldRetainUnusedCacheEntry(frame_index, entry.last_used_frame, retention_frames) and self.hasEntryCapacity()) {
                try self.appendEntry(entry);
                try self.appendAction(.{
                    .kind = .retain,
                    .key = entry.key,
                    .cache_index = previous_index,
                });
            } else {
                try self.appendAction(.{
                    .kind = .evict,
                    .key = entry.key,
                    .cache_index = previous_index,
                });
            }
        }

        return .{
            .entries = self.entries[0..self.entry_len],
            .actions = self.actions[0..self.action_len],
        };
    }

    fn appendEntry(self: *GlyphAtlasCachePlanner, entry: GlyphAtlasCacheEntry) Error!void {
        if (self.entry_len >= self.entries.len) return error.GlyphAtlasCacheListFull;
        self.entries[self.entry_len] = entry;
        self.entry_len += 1;
    }

    fn hasEntryCapacity(self: *GlyphAtlasCachePlanner) bool {
        return self.entry_len < self.entries.len;
    }

    fn appendAction(self: *GlyphAtlasCachePlanner, action: GlyphAtlasCacheAction) Error!void {
        if (self.action_len >= self.actions.len) return error.GlyphAtlasCacheListFull;
        self.actions[self.action_len] = action;
        self.action_len += 1;
    }
};

pub fn fallbackGlyphId(bytes: []const u8) u32 {
    if (bytes.len == 0) return 0;
    const first = bytes[0];
    const len = utf8SequenceLength(first);
    if (len == 1 or len > bytes.len) return first;

    var value: u32 = switch (len) {
        2 => @as(u32, first & 0x1f),
        3 => @as(u32, first & 0x0f),
        4 => @as(u32, first & 0x07),
        else => return first,
    };
    var index: usize = 1;
    while (index < len) : (index += 1) {
        const byte = bytes[index];
        if (!isUtf8ContinuationByte(byte)) return first;
        value = (value << 6) | @as(u32, byte & 0x3f);
    }
    return value;
}

fn glyphAtlasKeysEqual(a: GlyphAtlasKey, b: GlyphAtlasKey) bool {
    return a.font_id == b.font_id and
        a.glyph_id == b.glyph_id and
        a.size == b.size and
        a.subpixel_x == b.subpixel_x and
        a.subpixel_y == b.subpixel_y;
}

fn findGlyphAtlasCacheEntry(entries: []const GlyphAtlasCacheEntry, key: GlyphAtlasKey) ?usize {
    for (entries, 0..) |entry, index| {
        if (glyphAtlasKeysEqual(entry.key, key)) return index;
    }
    return null;
}

fn isPlanTextSpace(byte: u8) bool {
    return byte == '\n' or byte == '\r' or byte == '\t' or byte == ' ';
}

fn subpixelBucket(value: f32) u8 {
    const fraction = value - @floor(value);
    const scaled = @floor(fraction * 4.0);
    return @intFromFloat(std.math.clamp(scaled, 0, 3));
}

pub fn glyphFontId(run_font_id: FontId, glyph: Glyph) FontId {
    return if (glyph.font_id == 0) run_font_id else glyph.font_id;
}

fn shouldRetainUnusedCacheEntry(frame_index: u64, last_used_frame: u64, retention_frames: u64) bool {
    if (retention_frames == 0) return false;
    if (frame_index <= last_used_frame) return true;
    return frame_index - last_used_frame <= retention_frames;
}
