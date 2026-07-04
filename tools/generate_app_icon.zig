//! Default app-icon generator: renders the SDK's default macOS app icon
//! from vector geometry through the same path rasterizer the reference
//! renderer uses, so the icon regenerates from source — no opaque
//! binary-only asset checked in anywhere.
//!
//! The design follows Apple's macOS icon grid: a 1024x1024 canvas with a
//! centered 824x824 rounded-rect "squircle" plate (corner radius 185.4),
//! a subtle baked drop shadow, a vertical blue-violet gradient adjacent
//! to the design-token accent (#1447e6 light / #193cb8 dark), and a
//! neutral layered-surface mark: two offset rounded sheets, the back one
//! translucent. No letterforms, no wordmark.
//!
//! Regenerate everything with ONE command from the repo root:
//!
//!   zig build generate-icon
//!
//! which runs this tool (iconset PNGs + assets/icon.png + assets/icon.ico
//! + assets/icon.svg), assembles assets/icon.icns via `iconutil`, syncs
//! the CLI's embedded copy (src/tooling/default_icon.icns), and
//! round-trips the .icns for validation.
//!
//! Usage: generate-app-icon <iconset-dir> <png-path> <ico-path> <svg-path>

const std = @import("std");
const native_sdk = @import("native_sdk");

const canvas = native_sdk.canvas;
const geometry = native_sdk.geometry;
const vector = canvas.vector;
const PointF = geometry.PointF;
const Affine = canvas.Affine;

// ---------------------------------------------------------------------------
// Design constants (1024 design grid)
// ---------------------------------------------------------------------------

/// Design canvas — Apple's macOS icon grid is specified at 1024x1024.
const design_size: f32 = 1024;
/// Master raster size; every shipped size is an area-average downsample
/// of this, so edges get supersampled antialiasing on top of the
/// rasterizer's own coverage AA.
const master_size: usize = 2048;

/// The icon plate: Apple's grid centers an 824x824 rounded rect on the
/// 1024 canvas (100px margins) with a 185.4px corner radius.
const plate = RoundedRect{ .x = 100, .y = 100, .w = 824, .h = 824, .r = 185.4 };

/// Baked drop shadow (macOS icons carry their own shadow; the system
/// does not add one in the Dock).
const shadow_offset_y: f32 = 12;
const shadow_sigma: f32 = 16;
const shadow_alpha: f32 = 0.30;

/// Vertical plate gradient, token-palette-adjacent: a lifted blue at the
/// top falling to the dark-scheme accent at the bottom, bracketing the
/// #1447e6 primary identity.
const gradient_top = [3]f32{ 82.0 / 255.0, 124.0 / 255.0, 248.0 / 255.0 };
const gradient_bottom = [3]f32{ 23.0 / 255.0, 55.0 / 255.0, 186.0 / 255.0 };

/// The mark: two layered "surface" sheets, offset along the diagonal so
/// the union is centered on the canvas. The back sheet is translucent
/// white; the front sheet is opaque white.
const back_sheet = RoundedRect{ .x = 372, .y = 272, .w = 380, .h = 380, .r = 84 };
const front_sheet = RoundedRect{ .x = 272, .y = 372, .w = 380, .h = 380, .r = 84 };
const back_sheet_alpha: f32 = 0.52;

/// Shipped raster sizes. The .iconset slots and the .ico directory both
/// draw from this set.
const output_sizes = [_]usize{ 16, 32, 48, 64, 128, 256, 512, 1024 };

const iconset_slots = [_]struct { name: []const u8, size: usize }{
    .{ .name = "icon_16x16.png", .size = 16 },
    .{ .name = "icon_16x16@2x.png", .size = 32 },
    .{ .name = "icon_32x32.png", .size = 32 },
    .{ .name = "icon_32x32@2x.png", .size = 64 },
    .{ .name = "icon_128x128.png", .size = 128 },
    .{ .name = "icon_128x128@2x.png", .size = 256 },
    .{ .name = "icon_256x256.png", .size = 256 },
    .{ .name = "icon_256x256@2x.png", .size = 512 },
    .{ .name = "icon_512x512.png", .size = 512 },
    .{ .name = "icon_512x512@2x.png", .size = 1024 },
};

const ico_sizes = [_]usize{ 16, 32, 48, 64, 128, 256 };

const RoundedRect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    r: f32,
};

// ---------------------------------------------------------------------------
// Rasterization helpers
// ---------------------------------------------------------------------------

const MaskSink = struct {
    mask: []f32,
    width: usize,

    pub fn pixel(self: *MaskSink, x: i32, y: i32, coverage: f32) void {
        if (x < 0 or y < 0) return;
        const xu: usize = @intCast(x);
        const yu: usize = @intCast(y);
        if (xu >= self.width) return;
        const index = yu * self.width + xu;
        if (index >= self.mask.len) return;
        self.mask[index] = @min(1, self.mask[index] + coverage);
    }
};

/// Fill `mask` with the coverage of a rounded rect given in design
/// coordinates, scaled to the master raster.
fn rasterizeRoundedRect(mask: []f32, rect: RoundedRect, offset_y: f32) !void {
    const scale = @as(f32, @floatFromInt(master_size)) / design_size;
    var builder = vector.PathBuilder(64){};
    const x0 = rect.x;
    const y0 = rect.y + offset_y;
    const x1 = rect.x + rect.w;
    const y1 = rect.y + rect.h + offset_y;
    const r = rect.r;
    try builder.moveTo(PointF.init(x0 + r, y0));
    try builder.lineTo(PointF.init(x1 - r, y0));
    try builder.arcTo(r, r, 0, false, true, PointF.init(x1, y0 + r));
    try builder.lineTo(PointF.init(x1, y1 - r));
    try builder.arcTo(r, r, 0, false, true, PointF.init(x1 - r, y1));
    try builder.lineTo(PointF.init(x0 + r, y1));
    try builder.arcTo(r, r, 0, false, true, PointF.init(x0, y1 - r));
    try builder.lineTo(PointF.init(x0, y0 + r));
    try builder.arcTo(r, r, 0, false, true, PointF.init(x0 + r, y0));
    try builder.close();

    @memset(mask, 0);
    var sink = MaskSink{ .mask = mask, .width = master_size };
    const clip = vector.ClipRect{
        .x0 = 0,
        .y0 = 0,
        .x1 = @intCast(master_size),
        .y1 = @intCast(master_size),
    };
    try vector.fillPath(
        builder.slice(),
        Affine.scale(scale, scale),
        .nonzero,
        vector.default_tolerance,
        clip,
        &sink,
    );
}

/// Composite `mask` over the premultiplied RGBA f32 canvas with a solid
/// color. `alpha` scales the mask.
fn compositeSolid(pixels: []f32, mask: []const f32, r: f32, g: f32, b: f32, alpha: f32) void {
    for (mask, 0..) |coverage, i| {
        if (coverage <= 0) continue;
        const sa = coverage * alpha;
        const inv = 1 - sa;
        const base = i * 4;
        pixels[base + 0] = r * sa + pixels[base + 0] * inv;
        pixels[base + 1] = g * sa + pixels[base + 1] * inv;
        pixels[base + 2] = b * sa + pixels[base + 2] * inv;
        pixels[base + 3] = sa + pixels[base + 3] * inv;
    }
}

/// Composite `mask` with a vertical linear gradient spanning the plate.
fn compositeVerticalGradient(pixels: []f32, mask: []const f32) void {
    const scale = @as(f32, @floatFromInt(master_size)) / design_size;
    const top_y = plate.y * scale;
    const span = plate.h * scale;
    var y: usize = 0;
    while (y < master_size) : (y += 1) {
        const t = std.math.clamp((@as(f32, @floatFromInt(y)) + 0.5 - top_y) / span, 0, 1);
        const r = gradient_top[0] + (gradient_bottom[0] - gradient_top[0]) * t;
        const g = gradient_top[1] + (gradient_bottom[1] - gradient_top[1]) * t;
        const b = gradient_top[2] + (gradient_bottom[2] - gradient_top[2]) * t;
        var x: usize = 0;
        while (x < master_size) : (x += 1) {
            const i = y * master_size + x;
            const coverage = mask[i];
            if (coverage <= 0) continue;
            const inv = 1 - coverage;
            const base = i * 4;
            pixels[base + 0] = r * coverage + pixels[base + 0] * inv;
            pixels[base + 1] = g * coverage + pixels[base + 1] * inv;
            pixels[base + 2] = b * coverage + pixels[base + 2] * inv;
            pixels[base + 3] = coverage + pixels[base + 3] * inv;
        }
    }
}

// ---------------------------------------------------------------------------
// Shadow blur: three box passes approximate a gaussian (Wells '86).
// ---------------------------------------------------------------------------

fn boxBlurPass(source: []const f32, dest: []f32, width: usize, height: usize, radius: usize, comptime horizontal: bool) void {
    const window = @as(f32, @floatFromInt(2 * radius + 1));
    const major = if (horizontal) height else width;
    const minor = if (horizontal) width else height;
    var line: usize = 0;
    while (line < major) : (line += 1) {
        var sum: f32 = 0;
        var i: usize = 0;
        while (i <= radius and i < minor) : (i += 1) sum += at(source, width, line, i, horizontal);
        var pos: usize = 0;
        while (pos < minor) : (pos += 1) {
            setAt(dest, width, line, pos, horizontal, sum / window);
            if (pos + radius + 1 < minor) sum += at(source, width, line, pos + radius + 1, horizontal);
            if (pos >= radius) sum -= at(source, width, line, pos - radius, horizontal);
        }
    }
}

inline fn at(buffer: []const f32, width: usize, line: usize, pos: usize, comptime horizontal: bool) f32 {
    return if (horizontal) buffer[line * width + pos] else buffer[pos * width + line];
}

inline fn setAt(buffer: []f32, width: usize, line: usize, pos: usize, comptime horizontal: bool, value: f32) void {
    if (horizontal) buffer[line * width + pos] = value else buffer[pos * width + line] = value;
}

/// Approximate a gaussian blur of `sigma` (master-raster pixels) with
/// three box passes per axis.
fn gaussianBlur(mask: []f32, scratch: []f32, sigma: f32) void {
    // Ideal box width for three passes: w = sqrt(12 sigma^2 / 3 + 1).
    const w = @sqrt(12.0 * sigma * sigma / 3.0 + 1.0);
    const radius: usize = @intFromFloat(@max(1, (w - 1) / 2));
    var pass: usize = 0;
    while (pass < 3) : (pass += 1) {
        boxBlurPass(mask, scratch, master_size, master_size, radius, true);
        boxBlurPass(scratch, mask, master_size, master_size, radius, false);
    }
}

// ---------------------------------------------------------------------------
// Downsampling: exact area average from the master raster.
// ---------------------------------------------------------------------------

fn downsample(allocator: std.mem.Allocator, master: []const f32, size: usize) ![]u8 {
    const out = try allocator.alloc(u8, size * size * 4);
    const ratio = @as(f64, @floatFromInt(master_size)) / @as(f64, @floatFromInt(size));
    var oy: usize = 0;
    while (oy < size) : (oy += 1) {
        const sy0 = @as(f64, @floatFromInt(oy)) * ratio;
        const sy1 = @as(f64, @floatFromInt(oy + 1)) * ratio;
        var ox: usize = 0;
        while (ox < size) : (ox += 1) {
            const sx0 = @as(f64, @floatFromInt(ox)) * ratio;
            const sx1 = @as(f64, @floatFromInt(ox + 1)) * ratio;
            var acc = [4]f64{ 0, 0, 0, 0 };
            var area: f64 = 0;
            var sy: usize = @intFromFloat(@floor(sy0));
            while (sy < master_size and @as(f64, @floatFromInt(sy)) < sy1) : (sy += 1) {
                const cover_y = @min(sy1, @as(f64, @floatFromInt(sy + 1))) - @max(sy0, @as(f64, @floatFromInt(sy)));
                if (cover_y <= 0) continue;
                var sx: usize = @intFromFloat(@floor(sx0));
                while (sx < master_size and @as(f64, @floatFromInt(sx)) < sx1) : (sx += 1) {
                    const cover_x = @min(sx1, @as(f64, @floatFromInt(sx + 1))) - @max(sx0, @as(f64, @floatFromInt(sx)));
                    if (cover_x <= 0) continue;
                    const weight = cover_x * cover_y;
                    const base = (sy * master_size + sx) * 4;
                    acc[0] += master[base + 0] * weight;
                    acc[1] += master[base + 1] * weight;
                    acc[2] += master[base + 2] * weight;
                    acc[3] += master[base + 3] * weight;
                    area += weight;
                }
            }
            const base = (oy * size + ox) * 4;
            const alpha = if (area > 0) acc[3] / area else 0;
            // Un-premultiply for PNG straight-alpha storage.
            if (alpha > 0.0001) {
                out[base + 0] = quantize(acc[0] / area / alpha);
                out[base + 1] = quantize(acc[1] / area / alpha);
                out[base + 2] = quantize(acc[2] / area / alpha);
            } else {
                out[base + 0] = 0;
                out[base + 1] = 0;
                out[base + 2] = 0;
            }
            out[base + 3] = quantize(alpha);
        }
    }
    return out;
}

fn quantize(value: f64) u8 {
    return @intFromFloat(std.math.clamp(value * 255.0 + 0.5, 0, 255));
}

// ---------------------------------------------------------------------------
// Encoders
// ---------------------------------------------------------------------------

/// PNG encoder with real deflate compression (Up row filter + zlib via
/// std.compress.flate) — the canvas PNG writer deliberately emits stored
/// blocks for determinism, which is wrong for checked-in assets.
fn encodePng(allocator: std.mem.Allocator, rgba: []const u8, size: usize) ![]u8 {
    const flate = std.compress.flate;
    const row_len = 1 + size * 4;
    const raw = try allocator.alloc(u8, row_len * size);
    defer allocator.free(raw);
    var y: usize = 0;
    while (y < size) : (y += 1) {
        const row = raw[y * row_len ..][0..row_len];
        row[0] = 2; // Up filter
        const src = rgba[y * size * 4 ..][0 .. size * 4];
        if (y == 0) {
            @memcpy(row[1..], src);
        } else {
            const prev = rgba[(y - 1) * size * 4 ..][0 .. size * 4];
            for (src, prev, row[1..]) |current, above, *out| out.* = current -% above;
        }
    }

    const zlib_capacity = raw.len + raw.len / 8 + 1024;
    const zlib_buffer = try allocator.alloc(u8, zlib_capacity);
    defer allocator.free(zlib_buffer);
    var zlib_writer = std.Io.Writer.fixed(zlib_buffer);
    const window = try allocator.alloc(u8, flate.max_window_len * 2);
    defer allocator.free(window);
    var compress = try flate.Compress.init(&zlib_writer, window, .zlib, .default);
    try compress.writer.writeAll(raw);
    try compress.finish();
    const idat = zlib_writer.buffered();

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    try out.appendSlice(allocator, &canvas.png.signature);
    var ihdr: [13]u8 = undefined;
    std.mem.writeInt(u32, ihdr[0..4], @intCast(size), .big);
    std.mem.writeInt(u32, ihdr[4..8], @intCast(size), .big);
    ihdr[8] = 8; // bit depth
    ihdr[9] = 6; // truecolor with alpha
    ihdr[10] = 0;
    ihdr[11] = 0;
    ihdr[12] = 0;
    try appendChunk(&out, allocator, "IHDR", &ihdr);
    try appendChunk(&out, allocator, "IDAT", idat);
    try appendChunk(&out, allocator, "IEND", &.{});
    return out.toOwnedSlice(allocator);
}

fn appendChunk(list: *std.ArrayList(u8), allocator: std.mem.Allocator, kind: *const [4]u8, data: []const u8) !void {
    try appendU32Big(list, allocator, @intCast(data.len));
    try list.appendSlice(allocator, kind);
    try list.appendSlice(allocator, data);
    var crc = std.hash.Crc32.init();
    crc.update(kind);
    crc.update(data);
    try appendU32Big(list, allocator, crc.final());
}

fn appendU32Big(list: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u32) !void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, value, .big);
    try list.appendSlice(allocator, &bytes);
}

/// ICO container with PNG-compressed entries (supported since Vista).
fn writeIco(allocator: std.mem.Allocator, io: std.Io, path: []const u8, pngs: []const []const u8, sizes: []const usize) !void {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    const count: u16 = @intCast(pngs.len);
    try appendU16(&out, allocator, 0); // reserved
    try appendU16(&out, allocator, 1); // type: icon
    try appendU16(&out, allocator, count);
    var offset: u32 = 6 + 16 * @as(u32, count);
    for (pngs, sizes) |png_bytes, size| {
        const dim: u8 = if (size >= 256) 0 else @intCast(size);
        try out.append(allocator, dim); // width
        try out.append(allocator, dim); // height
        try out.append(allocator, 0); // palette
        try out.append(allocator, 0); // reserved
        try appendU16(&out, allocator, 1); // planes
        try appendU16(&out, allocator, 32); // bpp
        try appendU32(&out, allocator, @intCast(png_bytes.len));
        try appendU32(&out, allocator, offset);
        offset += @intCast(png_bytes.len);
    }
    for (pngs) |png_bytes| try out.appendSlice(allocator, png_bytes);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = out.items });
}

fn appendU16(list: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u16) !void {
    var bytes: [2]u8 = undefined;
    std.mem.writeInt(u16, &bytes, value, .little);
    try list.appendSlice(allocator, &bytes);
}

fn appendU32(list: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u32) !void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, value, .little);
    try list.appendSlice(allocator, &bytes);
}

/// SVG mirror of the same geometry, for design handoff and preview.
fn writeSvg(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !void {
    const svg = try std.fmt.allocPrint(allocator,
        \\<!-- Generated by `zig build generate-icon` (tools/generate_app_icon.zig). Edit the tool, not this file. -->
        \\<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
        \\  <defs>
        \\    <linearGradient id="plate" x1="0" y1="0" x2="0" y2="1">
        \\      <stop offset="0" stop-color="{s}"/>
        \\      <stop offset="1" stop-color="{s}"/>
        \\    </linearGradient>
        \\    <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
        \\      <feDropShadow dx="0" dy="{d}" stdDeviation="{d}" flood-color="#000000" flood-opacity="{d}"/>
        \\    </filter>
        \\  </defs>
        \\  <rect x="{d}" y="{d}" width="{d}" height="{d}" rx="{d}" fill="url(#plate)" filter="url(#shadow)"/>
        \\  <rect x="{d}" y="{d}" width="{d}" height="{d}" rx="{d}" fill="#ffffff" fill-opacity="{d}"/>
        \\  <rect x="{d}" y="{d}" width="{d}" height="{d}" rx="{d}" fill="#ffffff"/>
        \\</svg>
        \\
    , .{
        hexColor(gradient_top),
        hexColor(gradient_bottom),
        shadow_offset_y,
        shadow_sigma,
        shadow_alpha,
        plate.x,
        plate.y,
        plate.w,
        plate.h,
        plate.r,
        back_sheet.x,
        back_sheet.y,
        back_sheet.w,
        back_sheet.h,
        back_sheet.r,
        back_sheet_alpha,
        front_sheet.x,
        front_sheet.y,
        front_sheet.w,
        front_sheet.h,
        front_sheet.r,
    });
    defer allocator.free(svg);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = svg });
}

fn hexColor(rgb: [3]f32) [7]u8 {
    var out: [7]u8 = undefined;
    out[0] = '#';
    const digits = "0123456789abcdef";
    for (rgb, 0..) |channel, i| {
        const value: u8 = @intFromFloat(std.math.clamp(channel * 255.0 + 0.5, 0, 255));
        out[1 + i * 2] = digits[value >> 4];
        out[2 + i * 2] = digits[value & 15];
    }
    return out;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 5) usage();
    const iconset_dir = args[1];
    const png_path = args[2];
    const ico_path = args[3];
    const svg_path = args[4];

    const pixel_count = master_size * master_size;
    const master = try gpa.alloc(f32, pixel_count * 4);
    defer gpa.free(master);
    @memset(master, 0);
    const mask = try gpa.alloc(f32, pixel_count);
    defer gpa.free(mask);
    const scratch = try gpa.alloc(f32, pixel_count);
    defer gpa.free(scratch);

    const master_scale = @as(f32, @floatFromInt(master_size)) / design_size;

    // 1. Baked drop shadow under the plate.
    try rasterizeRoundedRect(mask, plate, shadow_offset_y);
    gaussianBlur(mask, scratch, shadow_sigma * master_scale);
    compositeSolid(master, mask, 0, 0, 0, shadow_alpha);

    // 2. The plate with its vertical gradient.
    try rasterizeRoundedRect(mask, plate, 0);
    compositeVerticalGradient(master, mask);

    // 3. Back surface sheet (translucent white).
    try rasterizeRoundedRect(mask, back_sheet, 0);
    compositeSolid(master, mask, 1, 1, 1, back_sheet_alpha);

    // 4. Front surface sheet (opaque white).
    try rasterizeRoundedRect(mask, front_sheet, 0);
    compositeSolid(master, mask, 1, 1, 1, 1);

    // Encode every shipped size once, keyed by size.
    var pngs: [output_sizes.len][]u8 = undefined;
    var encoded_count: usize = 0;
    defer for (pngs[0..encoded_count]) |bytes| gpa.free(bytes);
    for (output_sizes, 0..) |size, i| {
        const rgba = try downsample(gpa, master, size);
        defer gpa.free(rgba);
        pngs[i] = try encodePng(gpa, rgba, size);
        encoded_count += 1;
    }

    var cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, iconset_dir);
    for (iconset_slots) |slot| {
        const slot_path = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ iconset_dir, slot.name });
        defer gpa.free(slot_path);
        try cwd.writeFile(io, .{ .sub_path = slot_path, .data = pngs[sizeIndex(slot.size)] });
    }

    try cwd.writeFile(io, .{ .sub_path = png_path, .data = pngs[sizeIndex(1024)] });

    var ico_pngs: [ico_sizes.len][]const u8 = undefined;
    for (ico_sizes, 0..) |size, i| ico_pngs[i] = pngs[sizeIndex(size)];
    try writeIco(gpa, io, ico_path, &ico_pngs, &ico_sizes);

    try writeSvg(gpa, io, svg_path);

    std.debug.print("generated {s} ({d} slots), {s}, {s}, {s}\n", .{ iconset_dir, iconset_slots.len, png_path, ico_path, svg_path });
}

fn sizeIndex(size: usize) usize {
    for (output_sizes, 0..) |candidate, i| {
        if (candidate == size) return i;
    }
    unreachable;
}

fn usage() noreturn {
    std.debug.print("usage: generate-app-icon <iconset-dir> <png-path> <ico-path> <svg-path>\n", .{});
    std.process.exit(2);
}
