//! `native svg`: file-oriented adapters over the app-neutral canvas scene
//! protocol. Parsing and SVG generation remain public canvas APIs; this file
//! only owns CLI arguments and filesystem diagnostics.

const std = @import("std");
const canvas = @import("canvas");

pub const max_scene_file_bytes: usize = 64 * 1024 * 1024;

const RenderArgs = struct {
    input_path: []const u8,
    output_path: []const u8,
    mode: canvas.SvgRenderMode = .auto,
    missing_images: canvas.SvgMissingImagePolicy = .fail,
};

pub fn run(allocator: std.mem.Allocator, io: std.Io, args: []const []const u8) !void {
    if ((args.len == 1 and isHelp(args[0])) or (args.len == 2 and std.mem.eql(u8, args[0], "render") and isHelp(args[1]))) {
        usage();
        return;
    }
    const parsed = parseRenderArgs(args) catch {
        usage();
        return error.InvalidArguments;
    };

    const source = if (std.mem.eql(u8, parsed.input_path, "-")) source: {
        var stdin_buffer: [64 * 1024]u8 = undefined;
        var stdin_reader = std.Io.File.stdin().reader(io, &stdin_buffer);
        break :source stdin_reader.interface.allocRemaining(allocator, .limited(max_scene_file_bytes)) catch |err| {
            std.debug.print("native svg: cannot read stdin: {s}\n", .{@errorName(err)});
            return error.CommandFailed;
        };
    } else std.Io.Dir.cwd().readFileAlloc(io, parsed.input_path, allocator, .limited(max_scene_file_bytes)) catch |err| {
        std.debug.print("native svg: cannot read {s}: {s}\n", .{ parsed.input_path, @errorName(err) });
        return error.CommandFailed;
    };

    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    render(allocator, source, &output.writer, .{
        .mode = parsed.mode,
        .missing_images = parsed.missing_images,
    }) catch |err| {
        printRenderError(parsed.input_path, err);
        return error.CommandFailed;
    };

    if (std.mem.eql(u8, parsed.output_path, "-")) {
        var stdout_buffer: [64 * 1024]u8 = undefined;
        var stdout_writer = std.Io.File.stdout().writerStreaming(io, &stdout_buffer);
        stdout_writer.interface.writeAll(output.written()) catch |err| {
            std.debug.print("native svg: cannot write stdout: {s}\n", .{@errorName(err)});
            return error.CommandFailed;
        };
        stdout_writer.interface.flush() catch |err| {
            std.debug.print("native svg: cannot flush stdout: {s}\n", .{@errorName(err)});
            return error.CommandFailed;
        };
    } else {
        std.Io.Dir.cwd().writeFile(io, .{ .sub_path = parsed.output_path, .data = output.written() }) catch |err| {
            std.debug.print("native svg: cannot write {s}: {s}\n", .{ parsed.output_path, @errorName(err) });
            return error.CommandFailed;
        };
    }
    std.debug.print("rendered {s} -> {s} ({d} bytes)\n", .{ parsed.input_path, parsed.output_path, output.written().len });
}

pub const RenderOptions = struct {
    mode: canvas.SvgRenderMode = .auto,
    missing_images: canvas.SvgMissingImagePolicy = .fail,
};

/// Pure conversion seam used by the CLI and embeddable tooling tests.
pub fn render(
    allocator: std.mem.Allocator,
    source: []const u8,
    writer: *std.Io.Writer,
    overrides: RenderOptions,
) !void {
    const document = try canvas.parseSceneJson(allocator, source);
    var options = document.svgOptions();
    options.mode = overrides.mode;
    options.missing_images = overrides.missing_images;
    try canvas.writeSvg(allocator, writer, document.scene, options);
}

fn parseRenderArgs(args: []const []const u8) !RenderArgs {
    if (args.len == 0 or !std.mem.eql(u8, args[0], "render")) return error.InvalidArguments;
    var input_path: ?[]const u8 = null;
    var output_path: ?[]const u8 = null;
    var mode: canvas.SvgRenderMode = .auto;
    var missing_images: canvas.SvgMissingImagePolicy = .fail;
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output")) {
            index += 1;
            if (index >= args.len or output_path != null) return error.InvalidArguments;
            output_path = args[index];
        } else if (std.mem.eql(u8, arg, "--mode")) {
            index += 1;
            if (index >= args.len) return error.InvalidArguments;
            mode = parseMode(args[index]) orelse return error.InvalidArguments;
        } else if (std.mem.eql(u8, arg, "--missing-images")) {
            index += 1;
            if (index >= args.len) return error.InvalidArguments;
            missing_images = parseMissingImages(args[index]) orelse return error.InvalidArguments;
        } else if (std.mem.startsWith(u8, arg, "-") and !std.mem.eql(u8, arg, "-")) {
            return error.InvalidArguments;
        } else if (input_path == null) {
            input_path = arg;
        } else {
            return error.InvalidArguments;
        }
    }
    return .{
        .input_path = input_path orelse return error.InvalidArguments,
        .output_path = output_path orelse return error.InvalidArguments,
        .mode = mode,
        .missing_images = missing_images,
    };
}

fn parseMode(value: []const u8) ?canvas.SvgRenderMode {
    if (std.mem.eql(u8, value, "auto")) return .auto;
    if (std.mem.eql(u8, value, "vector")) return .vector;
    if (std.mem.eql(u8, value, "raster") or std.mem.eql(u8, value, "reference-raster")) return .reference_raster;
    return null;
}

fn parseMissingImages(value: []const u8) ?canvas.SvgMissingImagePolicy {
    if (std.mem.eql(u8, value, "fail")) return .fail;
    if (std.mem.eql(u8, value, "omit")) return .omit;
    return null;
}

fn isHelp(value: []const u8) bool {
    return std.mem.eql(u8, value, "--help") or std.mem.eql(u8, value, "-h") or std.mem.eql(u8, value, "help");
}

fn printRenderError(path: []const u8, err: anyerror) void {
    const message = switch (err) {
        error.InvalidSceneJson => "malformed JSON",
        error.UnsupportedSceneSchema => "unsupported scene schema",
        error.UnsupportedSceneVersion => "unsupported scene version",
        error.InvalidSceneValue => "invalid scene value or command",
        error.InvalidSceneResource => "invalid image or font resource",
        error.SceneTooComplex => "scene exceeds the bounded protocol limits",
        error.MissingImageResource => "a display-list image has no deterministic resource (use --missing-images omit to omit it explicitly)",
        error.UnsupportedVectorEffect => "vector mode cannot preserve an effect (use --mode auto or raster)",
        else => @errorName(err),
    };
    std.debug.print("native svg: cannot render {s}: {s}\n", .{ path, message });
}

fn usage() void {
    std.debug.print(
        \\usage: native svg render <scene.json|-> -o <output.svg|-> [--mode auto|vector|raster] [--missing-images fail|omit]
        \\
        \\The input is a native.canvas.scene JSON document (version 1). Auto mode
        \\keeps portable commands as vectors and reference-rasterizes effects that
        \\SVG cannot reproduce faithfully.
        \\
    , .{});
}

test "SVG CLI parses explicit render policies" {
    const args = try parseRenderArgs(&.{ "render", "scene.json", "--mode", "reference-raster", "--missing-images", "omit", "-o", "out.svg" });
    try std.testing.expectEqualStrings("scene.json", args.input_path);
    try std.testing.expectEqualStrings("out.svg", args.output_path);
    try std.testing.expectEqual(canvas.SvgRenderMode.reference_raster, args.mode);
    try std.testing.expectEqual(canvas.SvgMissingImagePolicy.omit, args.missing_images);
    const pipes = try parseRenderArgs(&.{ "render", "-", "-o", "-" });
    try std.testing.expectEqualStrings("-", pipes.input_path);
    try std.testing.expectEqualStrings("-", pipes.output_path);
    try std.testing.expectError(error.InvalidArguments, parseRenderArgs(&.{ "render", "scene.json", "--mode", "pdf", "-o", "out.svg" }));
    try std.testing.expectError(error.InvalidArguments, parseRenderArgs(&.{ "render", "scene.json" }));
}

test "SVG CLI renders a scene document through the public converter" {
    const source =
        "{\"schema\":\"native.canvas.scene\",\"version\":1,\"width\":40,\"height\":24," ++
        "\"title\":\"CLI & scene\",\"displayList\":{\"commands\":[" ++
        "{\"op\":\"fill_rect\",\"id\":1,\"rect\":[0,0,40,24],\"fill\":{\"kind\":\"color\",\"color\":[0.1,0.2,0.3,1]}}]}}";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try render(arena.allocator(), source, &output.writer, .{ .mode = .vector });
    try std.testing.expect(std.mem.startsWith(u8, output.written(), "<svg"));
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "CLI &amp; scene") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "<rect") != null);
}
