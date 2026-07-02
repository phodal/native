const support = @import("test_support.zig");
const std = support.std;
const geometry = support.geometry;
const canvas = support.canvas;
const automation = support.automation;
const platform = support.platform;
const App = support.App;
const TestHarness = support.TestHarness;

fn readAutomationFile(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
    var file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    var read_buffer: [4096]u8 = undefined;
    var reader = file.reader(io, &read_buffer);
    return reader.interface.allocRemaining(allocator, .limited(8 * 1024 * 1024));
}

fn installScreenshotWidgets(harness: anytype) !void {
    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(0, 0, 240, 140),
    });

    const controls = [_]canvas.Widget{
        .{
            .id = 2,
            .kind = .checkbox,
            .frame = geometry.RectF.init(10, 10, 120, 28),
            .text = "Live",
        },
        .{
            .id = 3,
            .kind = .toggle,
            .frame = geometry.RectF.init(10, 48, 120, 28),
            .text = "Alerts",
            .state = .{ .selected = true },
        },
        .{
            .id = 4,
            .kind = .text,
            .frame = geometry.RectF.init(10, 88, 200, 32),
            .text = "Screenshot fixture",
        },
    };
    var nodes: [4]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &controls }, geometry.RectF.init(0, 0, 240, 140), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);
    _ = try harness.runtime.emitCanvasWidgetDisplayList(1, "canvas", .{});
}

fn encodeScreenshotPng(allocator: std.mem.Allocator, harness: anytype) ![]u8 {
    const pixel_size = try harness.runtime.canvasScreenshotPixelSize(1, "canvas", null);
    const pixels = try allocator.alloc(u8, pixel_size.byte_len);
    defer allocator.free(pixels);
    const scratch = try allocator.alloc(u8, pixel_size.byte_len);
    defer allocator.free(scratch);
    const screenshot = try harness.runtime.renderCanvasScreenshot(1, "canvas", null, pixels, scratch);
    const encoded = try allocator.alloc(u8, try canvas.png.encodedRgba8ByteLen(screenshot.width, screenshot.height));
    errdefer allocator.free(encoded);
    var writer = std.Io.Writer.fixed(encoded);
    try canvas.png.writeRgba8(&writer, screenshot.width, screenshot.height, screenshot.rgba8);
    try std.testing.expectEqual(encoded.len, writer.buffered().len);
    return encoded;
}

test "runtime renders byte-identical screenshots for an unchanged scene" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-canvas-screenshot-deterministic", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
        }
    };

    const harness = try TestHarness().create(std.testing.allocator, .{});
    defer harness.destroy(std.testing.allocator);
    harness.null_platform.gpu_surfaces = true;
    var app_state: TestApp = .{};
    const app = app_state.app();
    try harness.start(app);
    try installScreenshotWidgets(harness);

    const first = try encodeScreenshotPng(std.testing.allocator, harness);
    defer std.testing.allocator.free(first);
    const second = try encodeScreenshotPng(std.testing.allocator, harness);
    defer std.testing.allocator.free(second);
    try std.testing.expectEqualSlices(u8, first, second);

    // The scene is visually plausible: decoded pixels are not one flat color.
    const raw = try std.testing.allocator.alloc(u8, 140 * (1 + 240 * 4));
    defer std.testing.allocator.free(raw);
    const decoded = try canvas.png.decodeRgba8(first, raw);
    try std.testing.expectEqual(@as(usize, 240), decoded.width);
    try std.testing.expectEqual(@as(usize, 140), decoded.height);
    var distinct = false;
    const first_pixel = decoded.rgba8[0..4];
    var offset: usize = 4;
    while (offset < decoded.rgba8.len) : (offset += 4) {
        if (!std.mem.eql(u8, first_pixel, decoded.rgba8[offset .. offset + 4])) {
            distinct = true;
            break;
        }
    }
    try std.testing.expect(distinct);

    // Toggling a widget changes the retained scene and thus the screenshot.
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_down,
        .x = 82,
        .y = 20,
    } });
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_up,
        .x = 82,
        .y = 20,
    } });
    const changed = try encodeScreenshotPng(std.testing.allocator, harness);
    defer std.testing.allocator.free(changed);
    try std.testing.expect(!std.mem.eql(u8, first, changed));
}

test "automation screenshot command publishes a parseable png artifact" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-canvas-screenshot-automation", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
        }
    };

    const directory = ".zig-cache/test-canvas-screenshot-automation";
    std.Io.Dir.cwd().deleteTree(std.testing.io, directory) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, directory) catch {};

    const harness = try TestHarness().create(std.testing.allocator, .{});
    defer harness.destroy(std.testing.allocator);
    harness.null_platform.gpu_surfaces = true;
    harness.runtime.options.automation = automation.Server.init(std.testing.io, directory, "Screenshot");
    var app_state: TestApp = .{};
    const app = app_state.app();
    try harness.start(app);
    try installScreenshotWidgets(harness);

    try harness.runtime.dispatchAutomationCommand(app, "screenshot canvas");
    const artifact_path = directory ++ "/screenshot-canvas.png";
    const first = try readAutomationFile(std.testing.allocator, std.testing.io, artifact_path);
    defer std.testing.allocator.free(first);

    const raw = try std.testing.allocator.alloc(u8, 140 * (1 + 240 * 4));
    defer std.testing.allocator.free(raw);
    const decoded = try canvas.png.decodeRgba8(first, raw);
    try std.testing.expectEqual(@as(usize, 240), decoded.width);
    try std.testing.expectEqual(@as(usize, 140), decoded.height);

    // A second capture of the unchanged scene is byte-identical.
    try harness.runtime.dispatchAutomationCommand(app, "screenshot canvas");
    const second = try readAutomationFile(std.testing.allocator, std.testing.io, artifact_path);
    defer std.testing.allocator.free(second);
    try std.testing.expectEqualSlices(u8, first, second);

    // An explicit scale renders scaled pixel dimensions.
    try harness.runtime.dispatchAutomationCommand(app, "screenshot canvas 2");
    const scaled = try readAutomationFile(std.testing.allocator, std.testing.io, artifact_path);
    defer std.testing.allocator.free(scaled);
    const scaled_raw = try std.testing.allocator.alloc(u8, 280 * (1 + 480 * 4));
    defer std.testing.allocator.free(scaled_raw);
    const scaled_decoded = try canvas.png.decodeRgba8(scaled, scaled_raw);
    try std.testing.expectEqual(@as(usize, 480), scaled_decoded.width);
    try std.testing.expectEqual(@as(usize, 280), scaled_decoded.height);
}
