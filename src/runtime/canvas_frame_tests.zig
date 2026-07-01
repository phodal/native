const support = @import("test_support.zig");
const std = support.std;
const geometry = support.geometry;
const trace = support.trace;
const json = support.json;
const canvas = support.canvas;
const automation = support.automation;
const bridge = support.bridge;
const app_manifest = support.app_manifest;
const platform = support.platform;
const security = support.security;
const extensions = support.extensions;
const window_state = support.window_state;
const runtime_module = support.runtime_module;
const bridge_payload = support.bridge_payload;
const canvas_frame = support.canvas_frame;
const App = support.App;
const Runtime = support.Runtime;
const Options = support.Options;
const Event = support.Event;
const LifecycleEvent = support.LifecycleEvent;
const CommandEvent = support.CommandEvent;
const Command = support.Command;
const CommandSource = support.CommandSource;
const FrameDiagnostics = support.FrameDiagnostics;
const ShortcutEvent = support.ShortcutEvent;
const Appearance = support.Appearance;
const GpuFrame = support.GpuFrame;
const GpuSurfaceFrameEvent = support.GpuSurfaceFrameEvent;
const GpuSurfaceResizeEvent = support.GpuSurfaceResizeEvent;
const GpuSurfaceInputEvent = support.GpuSurfaceInputEvent;
const CanvasWidgetPointerEvent = support.CanvasWidgetPointerEvent;
const CanvasWidgetKeyboardEvent = support.CanvasWidgetKeyboardEvent;
const CanvasWidgetDisplayListChrome = support.CanvasWidgetDisplayListChrome;
const CanvasPresentationMode = support.CanvasPresentationMode;
const CanvasPresentationResult = support.CanvasPresentationResult;
const CanvasWidgetAccessibilityActionKind = support.CanvasWidgetAccessibilityActionKind;
const CanvasWidgetAccessibilityAction = support.CanvasWidgetAccessibilityAction;
const CanvasWidgetFileDropEvent = support.CanvasWidgetFileDropEvent;
const CanvasWidgetDragEvent = support.CanvasWidgetDragEvent;
const InvalidationReason = support.InvalidationReason;
const TestHarness = support.TestHarness;
const max_canvas_commands_per_view = support.max_canvas_commands_per_view;
const max_canvas_widget_nodes_per_view = support.max_canvas_widget_nodes_per_view;
const jsonStringField = support.jsonStringField;
const jsonNumberField = support.jsonNumberField;
const jsonBoolField = support.jsonBoolField;
const canvasRenderAnimationFinalOverrideNoop = support.canvasRenderAnimationFinalOverrideNoop;
const copyInto = support.copyInto;
const writeViewJson = support.writeViewJson;
const canvasFrameScratchStorage = support.canvasFrameScratchStorage;
const runtimeViewInfo = support.runtimeViewInfo;
const runtimeViewCanvasFrameRenderOverrides = support.runtimeViewCanvasFrameRenderOverrides;
const runtimeViewCanvasRenderAnimationDirtyBoundsForOverrides = support.runtimeViewCanvasRenderAnimationDirtyBoundsForOverrides;
const runtimeViewWidgetSemantics = support.runtimeViewWidgetSemantics;
const runtimeViewSetCanvasWidgetSelected = support.runtimeViewSetCanvasWidgetSelected;
const runtimeViewCanvasWidgetDirtyBounds = support.runtimeViewCanvasWidgetDirtyBounds;
const dispatchAutomationWidgetAction = support.dispatchAutomationWidgetAction;
const shellBoundsForWindow = support.shellBoundsForWindow;
const reloadWindows = support.reloadWindows;
const canvasWidgetSemanticsById = support.canvasWidgetSemanticsById;
const platformWidgetAccessibilityNodeById = support.platformWidgetAccessibilityNodeById;
const builtinBridgeErrorCode = support.builtinBridgeErrorCode;
const builtinBridgeErrorMessage = support.builtinBridgeErrorMessage;
const testViewByLabel = support.testViewByLabel;
const testCanvasWidgetPartId = support.testCanvasWidgetPartId;

test "runtime retains canvas display lists on GPU surface views" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-canvas", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
        }
    };

    var harness: TestHarness() = undefined;
    harness.init(.{});
    harness.null_platform.gpu_surfaces = true;
    var app_state: TestApp = .{};
    try harness.start(app_state.app());

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(0, 0, 320, 240),
    });

    var text_storage = [_]u8{ 'O', 'K' };
    var stops = [_]canvas.GradientStop{
        .{ .offset = 0, .color = canvas.Color.rgb8(255, 255, 255) },
        .{ .offset = 1, .color = canvas.Color.rgb8(37, 99, 235) },
    };
    var glyphs = [_]canvas.Glyph{
        .{ .id = 42, .x = 12, .y = 24, .advance = 9 },
    };
    var path = [_]canvas.PathElement{
        .{ .verb = .move_to, .points = .{ geometry.PointF.init(1, 2), geometry.PointF.zero(), geometry.PointF.zero() } },
        .{ .verb = .close },
    };
    var commands: [4]canvas.CanvasCommand = undefined;
    var builder = canvas.Builder.init(&commands);
    try builder.fillRect(.{
        .id = 1,
        .rect = geometry.RectF.init(0, 0, 320, 240),
        .fill = .{ .linear_gradient = .{
            .start = geometry.PointF.init(0, 0),
            .end = geometry.PointF.init(320, 240),
            .stops = &stops,
        } },
    });
    try builder.fillPath(.{
        .id = 2,
        .elements = &path,
        .fill = .{ .color = canvas.Color.rgb8(15, 23, 42) },
    });
    try builder.drawText(.{
        .id = 3,
        .font_id = 7,
        .size = 16,
        .origin = geometry.PointF.init(16, 32),
        .color = canvas.Color.rgb8(15, 23, 42),
        .text = text_storage[0..],
        .glyphs = &glyphs,
    });

    const info = try harness.runtime.setCanvasDisplayList(1, "canvas", builder.displayList());
    try std.testing.expectEqual(@as(u64, 1), info.canvas_revision);
    try std.testing.expectEqual(@as(usize, 3), info.canvas_command_count);

    text_storage[0] = 'N';
    stops[0].offset = 0.5;
    glyphs[0].id = 900;
    path[0].points[0] = geometry.PointF.init(99, 99);

    const retained = try harness.runtime.canvasDisplayList(1, "canvas");
    try std.testing.expectEqual(@as(usize, 3), retained.commandCount());
    switch (retained.commands[0]) {
        .fill_rect => |value| switch (value.fill) {
            .linear_gradient => |gradient| {
                try std.testing.expectEqual(@as(f32, 0), gradient.stops[0].offset);
                try std.testing.expectEqual(@as(f32, 1), gradient.stops[0].color.r);
            },
            else => return error.TestUnexpectedResult,
        },
        else => return error.TestUnexpectedResult,
    }
    switch (retained.commands[1]) {
        .fill_path => |value| try std.testing.expectEqual(@as(f32, 1), value.elements[0].points[0].x),
        else => return error.TestUnexpectedResult,
    }
    switch (retained.commands[2]) {
        .draw_text => |value| {
            try std.testing.expectEqualStrings("OK", value.text);
            try std.testing.expectEqual(@as(u32, 42), value.glyphs[0].id);
        },
        else => return error.TestUnexpectedResult,
    }

    const snapshot = harness.runtime.automationSnapshot("Canvas");
    const canvas_view = testViewByLabel(snapshot.views, "canvas").?;
    try std.testing.expectEqual(@as(u64, 1), canvas_view.canvas_revision);
    try std.testing.expectEqual(@as(usize, 3), canvas_view.canvas_command_count);

    var buffer: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try automation.snapshot.writeText(snapshot, &writer);
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "canvas_revision=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "canvas_commands=3") != null);
}

test "runtime builds canvas frame plans from retained GPU canvas state" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-canvas-frame", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
        }
    };

    var harness: TestHarness() = undefined;
    harness.init(.{});
    harness.null_platform.gpu_surfaces = true;
    var app_state: TestApp = .{};
    try harness.start(app_state.app());

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(0, 0, 320, 240),
    });

    const stops = [_]canvas.GradientStop{
        .{ .offset = 0, .color = canvas.Color.rgb8(255, 255, 255) },
        .{ .offset = 1, .color = canvas.Color.rgb8(24, 24, 27) },
    };
    const commands = [_]canvas.CanvasCommand{
        .{ .fill_rounded_rect = .{
            .id = 1,
            .rect = geometry.RectF.init(16, 16, 160, 72),
            .radius = canvas.Radius.all(12),
            .fill = .{ .linear_gradient = .{
                .start = geometry.PointF.init(16, 16),
                .end = geometry.PointF.init(176, 88),
                .stops = &stops,
            } },
        } },
        .{ .draw_text = .{
            .id = 2,
            .font_id = 5,
            .size = 14,
            .origin = geometry.PointF.init(28, 48),
            .color = canvas.Color.rgb8(15, 23, 42),
            .text = "OK",
        } },
    };
    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", .{ .commands = &commands });

    var render_commands: [4]canvas.RenderCommand = undefined;
    var render_batches: [4]canvas.RenderBatch = undefined;
    var resources: [4]canvas.RenderResource = undefined;
    var resource_cache_entries: [4]canvas.RenderResourceCacheEntry = undefined;
    var resource_cache_actions: [4]canvas.RenderResourceCacheAction = undefined;
    var glyphs: [4]canvas.GlyphAtlasEntry = undefined;
    var glyph_cache_entries: [4]canvas.GlyphAtlasCacheEntry = undefined;
    var glyph_cache_actions: [4]canvas.GlyphAtlasCacheAction = undefined;
    var changes: [4]canvas.DiffChange = undefined;
    const frame = try harness.runtime.canvasFramePlan(1, "canvas", null, .{
        .frame_index = 9,
        .timestamp_ns = 100,
    }, .{
        .render_commands = &render_commands,
        .render_batches = &render_batches,
        .resources = &resources,
        .resource_cache_entries = &resource_cache_entries,
        .resource_cache_actions = &resource_cache_actions,
        .glyph_atlas_entries = &glyphs,
        .glyph_atlas_cache_entries = &glyph_cache_entries,
        .glyph_atlas_cache_actions = &glyph_cache_actions,
        .changes = &changes,
    });

    try std.testing.expectEqual(@as(u64, 9), frame.frame_index);
    try std.testing.expectEqual(@as(u64, 100), frame.timestamp_ns);
    try std.testing.expectEqualDeep(geometry.SizeF.init(320, 240), frame.surface_size);
    try std.testing.expect(frame.full_repaint);
    try std.testing.expect(frame.requiresRender());
    try std.testing.expectEqual(@as(usize, 2), frame.display_list.commandCount());
    try std.testing.expectEqual(@as(usize, 2), frame.render_plan.commandCount());
    try std.testing.expectEqual(@as(usize, 2), frame.batch_plan.batchCount());
    try std.testing.expectEqual(@as(usize, 2), frame.resource_plan.resourceCount());
    try std.testing.expectEqual(@as(usize, 2), frame.glyph_atlas_cache_plan.uploadCount());
    try std.testing.expectEqual(@as(usize, 2), frame.resource_cache_plan.entryCount());
    try std.testing.expectEqual(@as(usize, 2), frame.resource_cache_plan.actionCount());
    try std.testing.expectEqual(canvas.RenderResourceCacheActionKind.upload, frame.resource_cache_plan.actions[0].kind);
    try std.testing.expectEqual(@as(usize, 2), frame.glyph_atlas_plan.entryCount());
    try std.testing.expectEqual(@as(usize, 0), frame.changes.len);
    try std.testing.expectEqualDeep(geometry.RectF.init(0, 0, 320, 240), frame.dirty_bounds.?);
}

test "runtime canvas frame plan computes incremental dirty from previous display list" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-canvas-frame-dirty", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
        }
    };

    var harness: TestHarness() = undefined;
    harness.init(.{});
    harness.null_platform.gpu_surfaces = true;
    var app_state: TestApp = .{};
    try harness.start(app_state.app());

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(10, 20, 320, 240),
    });

    const previous_commands = [_]canvas.CanvasCommand{
        .{ .fill_rect = .{ .id = 1, .rect = geometry.RectF.init(0, 0, 40, 40), .fill = .{ .color = canvas.Color.rgb8(255, 255, 255) } } },
    };
    const next_commands = [_]canvas.CanvasCommand{
        .{ .fill_rect = .{ .id = 1, .rect = geometry.RectF.init(20, 0, 40, 40), .fill = .{ .color = canvas.Color.rgb8(255, 255, 255) } } },
    };
    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", .{ .commands = &next_commands });

    var render_commands: [2]canvas.RenderCommand = undefined;
    var render_batches: [1]canvas.RenderBatch = undefined;
    var resources: [0]canvas.RenderResource = .{};
    var resource_cache_entries: [0]canvas.RenderResourceCacheEntry = .{};
    var resource_cache_actions: [0]canvas.RenderResourceCacheAction = .{};
    var glyphs: [0]canvas.GlyphAtlasEntry = .{};
    var changes: [2]canvas.DiffChange = undefined;
    const frame = try harness.runtime.canvasFramePlan(1, "canvas", .{ .commands = &previous_commands }, .{}, .{
        .render_commands = &render_commands,
        .render_batches = &render_batches,
        .resources = &resources,
        .resource_cache_entries = &resource_cache_entries,
        .resource_cache_actions = &resource_cache_actions,
        .glyph_atlas_entries = &glyphs,
        .changes = &changes,
    });

    try std.testing.expect(!frame.full_repaint);
    try std.testing.expect(frame.requiresRender());
    try std.testing.expectEqualDeep(geometry.SizeF.init(320, 240), frame.surface_size);
    try std.testing.expectEqual(@as(usize, 1), frame.batch_plan.batchCount());
    try std.testing.expectEqual(@as(usize, 1), frame.changes.len);
    try std.testing.expectEqual(canvas.DiffKind.changed, frame.changes[0].kind);
    try std.testing.expectEqual(@as(?canvas.ObjectId, 1), frame.changes[0].id);
    try std.testing.expectEqualDeep(geometry.RectF.init(0, 0, 60, 40), frame.dirty_bounds.?);
}

test "runtime next canvas frame tracks presented state and resource cache" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-canvas-next-frame", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
        }
    };

    var harness: TestHarness() = undefined;
    harness.init(.{});
    harness.null_platform.gpu_surfaces = true;
    var app_state: TestApp = .{};
    try harness.start(app_state.app());

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(0, 0, 320, 240),
    });

    const stops = [_]canvas.GradientStop{
        .{ .offset = 0, .color = canvas.Color.rgb8(255, 255, 255) },
        .{ .offset = 1, .color = canvas.Color.rgb8(24, 24, 27) },
    };
    const first_commands = [_]canvas.CanvasCommand{.{ .fill_rect = .{
        .id = 1,
        .rect = geometry.RectF.init(0, 0, 40, 40),
        .fill = .{ .linear_gradient = .{
            .start = geometry.PointF.init(0, 0),
            .end = geometry.PointF.init(40, 40),
            .stops = &stops,
        } },
    } }};
    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", .{ .commands = &first_commands });

    var render_commands: [4]canvas.RenderCommand = undefined;
    var render_batches: [4]canvas.RenderBatch = undefined;
    var resources: [4]canvas.RenderResource = undefined;
    var resource_cache_entries: [4]canvas.RenderResourceCacheEntry = undefined;
    var resource_cache_actions: [8]canvas.RenderResourceCacheAction = undefined;
    var glyphs: [4]canvas.GlyphAtlasEntry = undefined;
    var changes: [4]canvas.DiffChange = undefined;
    const frame_storage = canvas.CanvasFrameStorage{
        .render_commands = &render_commands,
        .render_batches = &render_batches,
        .resources = &resources,
        .resource_cache_entries = &resource_cache_entries,
        .resource_cache_actions = &resource_cache_actions,
        .glyph_atlas_entries = &glyphs,
        .changes = &changes,
    };

    const first_frame = try harness.runtime.nextCanvasFrame(1, "canvas", .{ .frame_index = 1 }, frame_storage);
    try std.testing.expect(first_frame.full_repaint);
    try std.testing.expect(first_frame.requiresRender());
    try std.testing.expectEqual(@as(usize, 1), first_frame.resource_cache_plan.uploadCount());
    try std.testing.expectEqual(@as(u64, 1), harness.runtime.views[0].presented_canvas_revision);
    try std.testing.expectEqual(@as(usize, 1), harness.runtime.views[0].canvas_frame_resource_cache_count);

    const clean_frame = try harness.runtime.nextCanvasFrame(1, "canvas", .{ .frame_index = 2 }, frame_storage);
    try std.testing.expect(!clean_frame.full_repaint);
    try std.testing.expect(!clean_frame.requiresRender());
    try std.testing.expectEqual(@as(usize, 0), clean_frame.render_plan.commandCount());
    try std.testing.expectEqual(@as(usize, 0), clean_frame.batch_plan.batchCount());
    try std.testing.expectEqual(@as(usize, 0), clean_frame.changes.len);
    try std.testing.expectEqual(@as(usize, 0), clean_frame.resource_cache_plan.retainCount());
    try std.testing.expectEqual(@as(usize, 1), harness.runtime.views[0].canvas_frame_resource_cache_count);
    try std.testing.expectEqual(@as(usize, 0), harness.runtime.views[0].canvas_frame_profile_work_units);

    const moved_commands = [_]canvas.CanvasCommand{.{ .fill_rect = .{
        .id = 1,
        .rect = geometry.RectF.init(20, 0, 40, 40),
        .fill = .{ .linear_gradient = .{
            .start = geometry.PointF.init(0, 0),
            .end = geometry.PointF.init(40, 40),
            .stops = &stops,
        } },
    } }};
    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", .{ .commands = &moved_commands });

    const moved_frame = try harness.runtime.nextCanvasFrame(1, "canvas", .{ .frame_index = 3 }, frame_storage);
    try std.testing.expect(!moved_frame.full_repaint);
    try std.testing.expect(moved_frame.requiresRender());
    try std.testing.expectEqual(@as(usize, 1), moved_frame.changes.len);
    try std.testing.expectEqual(canvas.DiffKind.changed, moved_frame.changes[0].kind);
    try std.testing.expectEqualDeep(geometry.RectF.init(0, 0, 60, 40), moved_frame.dirty_bounds.?);
    try std.testing.expectEqual(@as(usize, 1), moved_frame.resource_cache_plan.retainCount());
    try std.testing.expectEqual(@as(u64, 2), harness.runtime.views[0].presented_canvas_revision);
}

test "runtime next canvas frame repaints when retained surface size changes" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-canvas-next-frame-resize", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
        }
    };

    var harness: TestHarness() = undefined;
    harness.init(.{});
    harness.null_platform.gpu_surfaces = true;
    var app_state: TestApp = .{};
    try harness.start(app_state.app());

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(0, 0, 320, 240),
    });

    const commands = [_]canvas.CanvasCommand{.{ .fill_rect = .{
        .id = 1,
        .rect = geometry.RectF.init(0, 0, 40, 40),
        .fill = .{ .color = canvas.Color.rgb8(255, 255, 255) },
    } }};
    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", .{ .commands = &commands });

    var render_commands: [2]canvas.RenderCommand = undefined;
    var render_batches: [2]canvas.RenderBatch = undefined;
    var resources: [1]canvas.RenderResource = undefined;
    var resource_cache_entries: [1]canvas.RenderResourceCacheEntry = undefined;
    var resource_cache_actions: [2]canvas.RenderResourceCacheAction = undefined;
    var glyphs: [1]canvas.GlyphAtlasEntry = undefined;
    var changes: [2]canvas.DiffChange = undefined;
    const frame_storage = canvas.CanvasFrameStorage{
        .render_commands = &render_commands,
        .render_batches = &render_batches,
        .resources = &resources,
        .resource_cache_entries = &resource_cache_entries,
        .resource_cache_actions = &resource_cache_actions,
        .glyph_atlas_entries = &glyphs,
        .changes = &changes,
    };

    const first_frame = try harness.runtime.nextCanvasFrame(1, "canvas", .{
        .frame_index = 1,
        .surface_size = geometry.SizeF.init(320, 240),
    }, frame_storage);
    try std.testing.expect(first_frame.full_repaint);

    const resized_frame = try harness.runtime.nextCanvasFrame(1, "canvas", .{
        .frame_index = 2,
        .surface_size = geometry.SizeF.init(640, 360),
    }, frame_storage);
    try std.testing.expect(resized_frame.full_repaint);
    try std.testing.expect(resized_frame.requiresRender());
    try std.testing.expectEqual(@as(usize, 1), resized_frame.render_plan.commandCount());
    try std.testing.expectEqualDeep(geometry.RectF.init(0, 0, 640, 360), resized_frame.dirty_bounds.?);
}

test "runtime next canvas frame retains renderer cache families" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-canvas-render-caches", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
        }
    };

    var harness: TestHarness() = undefined;
    harness.init(.{});
    harness.null_platform.gpu_surfaces = true;
    var app_state: TestApp = .{};
    try harness.start(app_state.app());

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(0, 0, 96, 48),
    });

    const path_elements = [_]canvas.PathElement{
        .{ .verb = .move_to, .points = .{ geometry.PointF.init(4, 4), geometry.PointF.zero(), geometry.PointF.zero() } },
        .{ .verb = .line_to, .points = .{ geometry.PointF.init(24, 4), geometry.PointF.zero(), geometry.PointF.zero() } },
        .{ .verb = .line_to, .points = .{ geometry.PointF.init(14, 20), geometry.PointF.zero(), geometry.PointF.zero() } },
        .{ .verb = .close },
    };
    const commands = [_]canvas.CanvasCommand{
        .{ .fill_path = .{
            .id = 1,
            .elements = &path_elements,
            .fill = .{ .color = canvas.Color.rgb8(14, 165, 233) },
        } },
        .{ .draw_image = .{
            .id = 2,
            .image_id = 42,
            .dst = geometry.RectF.init(32, 4, 18, 18),
        } },
        .{ .shadow = .{
            .id = 3,
            .rect = geometry.RectF.init(58, 8, 20, 14),
            .radius = canvas.Radius.all(5),
            .blur = 8,
            .color = canvas.Color.rgba8(15, 23, 42, 80),
        } },
    };
    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", .{ .commands = &commands });

    const overrides = [_]canvas.CanvasRenderOverride{.{
        .id = 1,
        .opacity = 0.5,
    }};
    const first_frame = try harness.runtime.nextCanvasFrame(1, "canvas", .{
        .frame_index = 1,
        .surface_size = geometry.SizeF.init(96, 48),
        .render_overrides = &overrides,
    }, canvasFrameScratchStorage(&harness.runtime));
    const first_gpu_packet_summary = first_frame.gpuPacketSummary();
    try std.testing.expect(first_frame.full_repaint);
    try std.testing.expectEqual(@as(usize, 1), first_frame.path_geometry_plan.geometryCount());
    try std.testing.expect(first_frame.path_geometry_plan.vertexCount() > 0);
    try std.testing.expect(first_frame.path_geometry_plan.indexCount() > 0);
    try std.testing.expectEqual(@as(usize, 1), first_frame.path_geometry_cache_plan.uploadCount());
    try std.testing.expectEqual(@as(usize, 1), first_frame.image_plan.imageCount());
    try std.testing.expectEqual(@as(usize, 1), first_frame.image_cache_plan.uploadCount());
    try std.testing.expectEqual(@as(usize, 1), first_frame.layer_plan.layerCount());
    try std.testing.expectEqual(@as(usize, 1), first_frame.layer_plan.opacityLayerCount());
    try std.testing.expectEqual(@as(usize, 1), first_frame.layer_cache_plan.uploadCount());
    try std.testing.expectEqual(@as(usize, 1), first_frame.visual_effect_plan.effectCount());
    try std.testing.expectEqual(@as(usize, 1), first_frame.visual_effect_plan.shadowCount());
    try std.testing.expectEqual(@as(usize, 1), first_frame.visual_effect_cache_plan.uploadCount());

    const first_info = runtimeViewInfo(harness.runtime.views[0]);
    try std.testing.expectEqual(@as(usize, 1), first_info.canvas_frame_path_geometry_count);
    try std.testing.expect(first_info.canvas_frame_path_geometry_vertex_count > 0);
    try std.testing.expect(first_info.canvas_frame_path_geometry_index_count > 0);
    try std.testing.expectEqual(@as(usize, 1), first_info.canvas_frame_path_geometry_upload_count);
    try std.testing.expectEqual(@as(usize, 1), first_info.canvas_frame_image_count);
    try std.testing.expectEqual(@as(usize, 1), first_info.canvas_frame_image_upload_count);
    try std.testing.expectEqual(@as(usize, 1), first_info.canvas_frame_layer_count);
    try std.testing.expectEqual(@as(usize, 1), first_info.canvas_frame_layer_upload_count);
    try std.testing.expectEqual(@as(usize, 1), first_info.canvas_frame_visual_effect_count);
    try std.testing.expectEqual(@as(usize, 1), first_info.canvas_frame_visual_effect_upload_count);
    try std.testing.expectEqual(first_gpu_packet_summary.command_count, first_info.canvas_frame_gpu_packet_command_count);
    try std.testing.expectEqual(first_gpu_packet_summary.cache_action_count, first_info.canvas_frame_gpu_packet_cache_action_count);
    try std.testing.expectEqual(first_gpu_packet_summary.cached_resource_command_count, first_info.canvas_frame_gpu_packet_cached_resource_command_count);
    try std.testing.expectEqual(@as(usize, 0), first_info.canvas_frame_gpu_packet_unsupported_command_count);
    try std.testing.expect(first_info.canvas_frame_gpu_packet_representable);
    try std.testing.expect(first_info.canvas_frame_profile_work_units > 0);
    try std.testing.expectEqual(platform.CanvasFrameProfileRisk.high, first_info.canvas_frame_profile_risk);
    try std.testing.expectEqual(@as(f32, 4608), first_info.canvas_frame_profile_surface_area);
    try std.testing.expectEqual(@as(f32, 4608), first_info.canvas_frame_profile_dirty_area);
    try std.testing.expectEqual(@as(f32, 1), first_info.canvas_frame_profile_dirty_ratio);

    const first_gpu_frame = try harness.runtime.gpuSurfaceFrame(1, "canvas");
    try std.testing.expectEqual(@as(usize, 1), first_gpu_frame.canvas_frame_path_geometry_count);
    try std.testing.expectEqual(@as(usize, 1), first_gpu_frame.canvas_frame_image_count);
    try std.testing.expectEqual(@as(usize, 1), first_gpu_frame.canvas_frame_layer_count);
    try std.testing.expectEqual(@as(usize, 1), first_gpu_frame.canvas_frame_visual_effect_count);
    try std.testing.expectEqual(first_gpu_packet_summary.command_count, first_gpu_frame.canvas_frame_gpu_packet_command_count);
    try std.testing.expectEqual(first_gpu_packet_summary.cache_action_count, first_gpu_frame.canvas_frame_gpu_packet_cache_action_count);
    try std.testing.expectEqual(first_gpu_packet_summary.cached_resource_command_count, first_gpu_frame.canvas_frame_gpu_packet_cached_resource_command_count);
    try std.testing.expectEqual(@as(usize, 0), first_gpu_frame.canvas_frame_gpu_packet_unsupported_command_count);
    try std.testing.expect(first_gpu_frame.canvas_frame_gpu_packet_representable);
    try std.testing.expect(first_gpu_frame.canvas_frame_profile_work_units > 0);
    try std.testing.expectEqual(platform.CanvasFrameProfileRisk.high, first_gpu_frame.canvas_frame_profile_risk);
    try std.testing.expectEqual(@as(f32, 4608), first_gpu_frame.canvas_frame_profile_surface_area);
    try std.testing.expectEqual(@as(f32, 4608), first_gpu_frame.canvas_frame_profile_dirty_area);
    try std.testing.expectEqual(@as(f32, 1), first_gpu_frame.canvas_frame_profile_dirty_ratio);

    var view_json_buffer: [8192]u8 = undefined;
    const view_json = try writeViewJson(first_info, &view_json_buffer);
    try std.testing.expect(std.mem.indexOf(u8, view_json, "\"canvasFramePathGeometryCount\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, view_json, "\"canvasFrameImageCount\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, view_json, "\"canvasFrameLayerCount\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, view_json, "\"canvasFrameVisualEffectCount\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, view_json, "\"canvasFrameGpuPacketCommandCount\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, view_json, "\"canvasFrameGpuPacketCacheActionCount\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, view_json, "\"canvasFrameGpuPacketCachedResourceCommandCount\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, view_json, "\"canvasFrameGpuPacketUnsupportedCommandCount\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, view_json, "\"canvasFrameGpuPacketRepresentable\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, view_json, "\"canvasFrameProfileWorkUnits\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, view_json, "\"canvasFrameProfileRisk\":\"high\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, view_json, "\"canvasFrameProfileSurfaceArea\":4608") != null);
    try std.testing.expect(std.mem.indexOf(u8, view_json, "\"canvasFrameProfileDirtyArea\":4608") != null);
    try std.testing.expect(std.mem.indexOf(u8, view_json, "\"canvasFrameProfileDirtyRatio\":1") != null);

    const retained_frame = try harness.runtime.nextCanvasFrame(1, "canvas", .{
        .frame_index = 2,
        .surface_size = geometry.SizeF.init(96, 48),
        .render_overrides = &overrides,
    }, canvasFrameScratchStorage(&harness.runtime));
    try std.testing.expect(!retained_frame.requiresRender());
    try std.testing.expectEqual(@as(usize, 0), retained_frame.path_geometry_cache_plan.uploadCount());
    try std.testing.expectEqual(@as(usize, 1), retained_frame.path_geometry_cache_plan.retainCount());
    try std.testing.expectEqual(@as(usize, 0), retained_frame.image_cache_plan.uploadCount());
    try std.testing.expectEqual(@as(usize, 1), retained_frame.image_cache_plan.retainCount());
    try std.testing.expectEqual(@as(usize, 0), retained_frame.layer_cache_plan.uploadCount());
    try std.testing.expectEqual(@as(usize, 1), retained_frame.layer_cache_plan.retainCount());
    try std.testing.expectEqual(@as(usize, 0), retained_frame.visual_effect_cache_plan.uploadCount());
    try std.testing.expectEqual(@as(usize, 1), retained_frame.visual_effect_cache_plan.retainCount());

    const retained_info = runtimeViewInfo(harness.runtime.views[0]);
    try std.testing.expectEqual(@as(usize, 1), retained_info.canvas_frame_path_geometry_retain_count);
    try std.testing.expectEqual(@as(usize, 1), retained_info.canvas_frame_image_retain_count);
    try std.testing.expectEqual(@as(usize, 1), retained_info.canvas_frame_layer_retain_count);
    try std.testing.expectEqual(@as(usize, 1), retained_info.canvas_frame_visual_effect_retain_count);
    try std.testing.expectEqual(@as(usize, 0), retained_info.canvas_frame_gpu_packet_command_count);
    try std.testing.expectEqual(@as(usize, 0), retained_info.canvas_frame_gpu_packet_cache_action_count);
    try std.testing.expectEqual(@as(usize, 0), retained_info.canvas_frame_gpu_packet_cached_resource_command_count);
    try std.testing.expectEqual(@as(usize, 0), retained_info.canvas_frame_gpu_packet_unsupported_command_count);
    try std.testing.expect(retained_info.canvas_frame_gpu_packet_representable);
    try std.testing.expectEqual(@as(usize, 0), retained_info.canvas_frame_profile_work_units);
    try std.testing.expectEqual(platform.CanvasFrameProfileRisk.idle, retained_info.canvas_frame_profile_risk);
}

test "runtime GPU surface frame event exposes renderer cache family counters" {
    const TestApp = struct {
        frame_count: u32 = 0,
        last_path_geometry_count: usize = 0,
        last_path_geometry_upload_count: usize = 0,
        last_image_count: usize = 0,
        last_image_upload_count: usize = 0,
        last_layer_count: usize = 0,
        last_layer_upload_count: usize = 0,
        last_visual_effect_count: usize = 0,
        last_visual_effect_upload_count: usize = 0,
        last_gpu_packet_command_count: usize = 0,
        last_gpu_packet_cache_action_count: usize = 0,
        last_gpu_packet_cached_resource_command_count: usize = 0,
        last_gpu_packet_unsupported_command_count: usize = 0,
        last_gpu_packet_representable: bool = false,

        fn event(context: *anyopaque, runtime: *Runtime, event_value: Event) anyerror!void {
            _ = runtime;
            const self: *@This() = @ptrCast(@alignCast(context));
            switch (event_value) {
                .gpu_surface_frame => |frame_event| {
                    self.frame_count += 1;
                    self.last_path_geometry_count = frame_event.canvas_frame_path_geometry_count;
                    self.last_path_geometry_upload_count = frame_event.canvas_frame_path_geometry_upload_count;
                    self.last_image_count = frame_event.canvas_frame_image_count;
                    self.last_image_upload_count = frame_event.canvas_frame_image_upload_count;
                    self.last_layer_count = frame_event.canvas_frame_layer_count;
                    self.last_layer_upload_count = frame_event.canvas_frame_layer_upload_count;
                    self.last_visual_effect_count = frame_event.canvas_frame_visual_effect_count;
                    self.last_visual_effect_upload_count = frame_event.canvas_frame_visual_effect_upload_count;
                    self.last_gpu_packet_command_count = frame_event.canvas_frame_gpu_packet_command_count;
                    self.last_gpu_packet_cache_action_count = frame_event.canvas_frame_gpu_packet_cache_action_count;
                    self.last_gpu_packet_cached_resource_command_count = frame_event.canvas_frame_gpu_packet_cached_resource_command_count;
                    self.last_gpu_packet_unsupported_command_count = frame_event.canvas_frame_gpu_packet_unsupported_command_count;
                    self.last_gpu_packet_representable = frame_event.canvas_frame_gpu_packet_representable;
                },
                else => {},
            }
        }

        fn app(self: *@This()) App {
            return .{
                .context = self,
                .name = "gpu-canvas-frame-event-render-caches",
                .source = platform.WebViewSource.html("<h1>Hello</h1>"),
                .event_fn = event,
            };
        }
    };

    var harness: TestHarness() = undefined;
    harness.init(.{});
    harness.null_platform.gpu_surfaces = true;
    var app_state: TestApp = .{};
    const app = app_state.app();
    try harness.start(app);

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(0, 0, 96, 48),
    });

    const path_elements = [_]canvas.PathElement{
        .{ .verb = .move_to, .points = .{ geometry.PointF.init(4, 4), geometry.PointF.zero(), geometry.PointF.zero() } },
        .{ .verb = .line_to, .points = .{ geometry.PointF.init(24, 4), geometry.PointF.zero(), geometry.PointF.zero() } },
        .{ .verb = .line_to, .points = .{ geometry.PointF.init(14, 20), geometry.PointF.zero(), geometry.PointF.zero() } },
        .{ .verb = .close },
    };
    const commands = [_]canvas.CanvasCommand{
        .{ .fill_path = .{
            .id = 1,
            .elements = &path_elements,
            .fill = .{ .color = canvas.Color.rgb8(14, 165, 233) },
        } },
        .{ .draw_image = .{
            .id = 2,
            .image_id = 42,
            .dst = geometry.RectF.init(32, 4, 18, 18),
        } },
        .{ .shadow = .{
            .id = 3,
            .rect = geometry.RectF.init(58, 8, 20, 14),
            .radius = canvas.Radius.all(5),
            .blur = 8,
            .color = canvas.Color.rgba8(15, 23, 42, 80),
        } },
    };
    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", .{ .commands = &commands });
    const animations = [_]canvas.CanvasRenderAnimation{.{
        .id = 1,
        .start_ns = 0,
        .duration_ms = 1000,
        .from_opacity = 0.5,
        .to_opacity = 1,
    }};
    _ = try harness.runtime.setCanvasRenderAnimations(1, "canvas", &animations);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_frame = .{
        .window_id = 1,
        .label = "canvas",
        .size = geometry.SizeF.init(96, 48),
        .scale_factor = 1,
        .frame_index = 7,
        .timestamp_ns = 500_000_000,
    } });

    try std.testing.expectEqual(@as(u32, 1), app_state.frame_count);
    try std.testing.expectEqual(@as(usize, 1), app_state.last_path_geometry_count);
    try std.testing.expectEqual(@as(usize, 1), app_state.last_path_geometry_upload_count);
    try std.testing.expectEqual(@as(usize, 1), app_state.last_image_count);
    try std.testing.expectEqual(@as(usize, 1), app_state.last_image_upload_count);
    try std.testing.expectEqual(@as(usize, 1), app_state.last_layer_count);
    try std.testing.expectEqual(@as(usize, 1), app_state.last_layer_upload_count);
    try std.testing.expectEqual(@as(usize, 1), app_state.last_visual_effect_count);
    try std.testing.expectEqual(@as(usize, 1), app_state.last_visual_effect_upload_count);
    try std.testing.expect(app_state.last_gpu_packet_command_count > 0);
    try std.testing.expect(app_state.last_gpu_packet_cache_action_count > 0);
    try std.testing.expect(app_state.last_gpu_packet_cached_resource_command_count > 0);
    try std.testing.expectEqual(@as(usize, 0), app_state.last_gpu_packet_unsupported_command_count);
    try std.testing.expect(app_state.last_gpu_packet_representable);

    const frame = try harness.runtime.gpuSurfaceFrame(1, "canvas");
    try std.testing.expectEqual(@as(usize, 1), frame.canvas_frame_path_geometry_count);
    try std.testing.expectEqual(@as(usize, 1), frame.canvas_frame_image_count);
    try std.testing.expectEqual(@as(usize, 1), frame.canvas_frame_layer_count);
    try std.testing.expectEqual(@as(usize, 1), frame.canvas_frame_visual_effect_count);
    try std.testing.expectEqual(app_state.last_gpu_packet_command_count, frame.canvas_frame_gpu_packet_command_count);
    try std.testing.expectEqual(app_state.last_gpu_packet_cache_action_count, frame.canvas_frame_gpu_packet_cache_action_count);
    try std.testing.expectEqual(app_state.last_gpu_packet_cached_resource_command_count, frame.canvas_frame_gpu_packet_cached_resource_command_count);
    try std.testing.expectEqual(@as(usize, 0), frame.canvas_frame_gpu_packet_unsupported_command_count);
    try std.testing.expect(frame.canvas_frame_gpu_packet_representable);
}

test "runtime next canvas GPU packet returns backend handoff commands" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-canvas-packet", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
        }
    };

    var harness: TestHarness() = undefined;
    harness.init(.{});
    harness.null_platform.gpu_surfaces = true;
    var app_state: TestApp = .{};
    try harness.start(app_state.app());

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(0, 0, 128, 64),
    });

    const stops = [_]canvas.GradientStop{
        .{ .offset = 0, .color = canvas.Color.rgb8(255, 255, 255) },
        .{ .offset = 1, .color = canvas.Color.rgb8(37, 99, 235) },
    };
    const commands = [_]canvas.CanvasCommand{
        .{ .fill_rect = .{
            .id = 10,
            .rect = geometry.RectF.init(0, 0, 64, 64),
            .fill = .{ .color = canvas.Color.rgb8(255, 255, 255) },
        } },
        .{ .fill_rounded_rect = .{
            .id = 11,
            .rect = geometry.RectF.init(72, 8, 40, 24),
            .radius = canvas.Radius.all(8),
            .fill = .{ .linear_gradient = .{
                .start = geometry.PointF.init(72, 8),
                .end = geometry.PointF.init(112, 32),
                .stops = &stops,
            } },
        } },
    };
    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", .{ .commands = &commands });

    var gpu_commands: [max_canvas_commands_per_view]canvas.CanvasGpuCommand = undefined;
    const packet = try harness.runtime.nextCanvasGpuPacket(1, "canvas", .{
        .frame_index = 3,
        .timestamp_ns = 9_000,
        .surface_size = geometry.SizeF.init(128, 64),
        .scale = 2,
    }, canvasFrameScratchStorage(&harness.runtime), &gpu_commands);

    try std.testing.expect(packet.requiresRender());
    try std.testing.expect(packet.fullyRepresentable());
    try std.testing.expectEqual(@as(u64, 3), packet.frame_index);
    try std.testing.expectEqual(@as(u64, 9_000), packet.timestamp_ns);
    try std.testing.expectEqual(canvas.CanvasRenderPassLoadAction.clear, packet.load_action);
    try std.testing.expectEqualDeep(geometry.SizeF.init(128, 64), packet.surface_size);
    try std.testing.expectEqual(@as(f32, 2), packet.scale);
    try std.testing.expectEqualDeep(geometry.RectF.init(0, 0, 128, 64), packet.scissor.?);
    try std.testing.expectEqual(@as(usize, 2), packet.commandCount());
    try std.testing.expectEqual(@as(usize, 1), packet.cachedResourceCommandCount());
    try std.testing.expectEqual(canvas.CanvasGpuCommandKind.fill_rect_solid, packet.commands[0].kind);
    try std.testing.expectEqual(@as(?canvas.RenderPipelineKind, .solid), packet.commands[0].pipeline);
    try std.testing.expectEqual(@as(?canvas.ObjectId, 10), packet.commands[0].id);
    try std.testing.expectEqual(canvas.CanvasGpuCommandKind.fill_rounded_rect_gradient, packet.commands[1].kind);
    try std.testing.expectEqual(@as(?canvas.RenderPipelineKind, .linear_gradient), packet.commands[1].pipeline);
    try std.testing.expect(packet.commands[1].uses_resource);

    const frame = try harness.runtime.gpuSurfaceFrame(1, "canvas");
    try std.testing.expectEqual(packet.commandCount(), frame.canvas_frame_gpu_packet_command_count);
    try std.testing.expectEqual(packet.cacheActionCount(), frame.canvas_frame_gpu_packet_cache_action_count);
    try std.testing.expectEqual(packet.cachedResourceCommandCount(), frame.canvas_frame_gpu_packet_cached_resource_command_count);
    try std.testing.expectEqual(@as(usize, 0), frame.canvas_frame_gpu_packet_unsupported_command_count);
    try std.testing.expect(frame.canvas_frame_gpu_packet_representable);

    var clean_gpu_commands: [max_canvas_commands_per_view]canvas.CanvasGpuCommand = undefined;
    const clean_packet = try harness.runtime.nextCanvasGpuPacket(1, "canvas", .{
        .frame_index = 4,
        .timestamp_ns = 10_000,
        .surface_size = geometry.SizeF.init(128, 64),
        .scale = 2,
    }, canvasFrameScratchStorage(&harness.runtime), &clean_gpu_commands);
    try std.testing.expect(!clean_packet.requiresRender());
    try std.testing.expect(clean_packet.fullyRepresentable());
    try std.testing.expectEqual(@as(u64, 4), clean_packet.frame_index);
    try std.testing.expectEqual(canvas.CanvasRenderPassLoadAction.skip, clean_packet.load_action);
    try std.testing.expectEqual(@as(usize, 0), clean_packet.commandCount());
}

test "runtime presents next canvas GPU packet" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-canvas-packet-present", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
        }
    };

    var harness: TestHarness() = undefined;
    harness.init(.{});
    harness.null_platform.gpu_surfaces = true;
    var app_state: TestApp = .{};
    try harness.start(app_state.app());

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(0, 0, 96, 48),
    });

    const commands = [_]canvas.CanvasCommand{.{ .fill_rect = .{
        .id = 41,
        .rect = geometry.RectF.init(8, 6, 32, 20),
        .fill = .{ .color = canvas.Color.rgb8(37, 99, 235) },
    } }};
    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", .{ .commands = &commands });

    var gpu_commands: [max_canvas_commands_per_view]canvas.CanvasGpuCommand = undefined;
    var packet_json_buffer: [16 * 1024]u8 = undefined;
    const packet = try harness.runtime.presentNextCanvasGpuPacket(1, "canvas", .{
        .frame_index = 12,
        .timestamp_ns = 44_000,
        .surface_size = geometry.SizeF.init(96, 48),
        .scale = 2,
    }, canvasFrameScratchStorage(&harness.runtime), canvas.Color.rgb8(247, 249, 252), &gpu_commands, &packet_json_buffer);

    try std.testing.expect(packet.requiresRender());
    try std.testing.expectEqual(@as(usize, 1), packet.commandCount());
    try std.testing.expectEqual(@as(usize, 1), harness.null_platform.gpu_surface_packet_present_count);
    try std.testing.expectEqualStrings("canvas", harness.null_platform.gpu_surface_packet_present_label_storage[0..harness.null_platform.gpu_surface_packet_present_label_len]);
    try std.testing.expectEqual(@as(u64, 12), harness.null_platform.gpu_surface_packet_present_frame_index);
    try std.testing.expectEqual(@as(u64, 44_000), harness.null_platform.gpu_surface_packet_present_timestamp_ns);
    try std.testing.expectEqualDeep(geometry.SizeF.init(96, 48), harness.null_platform.gpu_surface_packet_present_surface_size);
    try std.testing.expectEqual(@as(f32, 2), harness.null_platform.gpu_surface_packet_present_scale_factor);
    try std.testing.expectEqualDeep([4]u8{ 247, 249, 252, 255 }, harness.null_platform.gpu_surface_packet_present_clear_color_rgba8);
    try std.testing.expect(harness.null_platform.gpu_surface_packet_present_requires_render);
    try std.testing.expectEqual(packet.commandCount(), harness.null_platform.gpu_surface_packet_present_command_count);
    try std.testing.expectEqual(packet.cacheActionCount(), harness.null_platform.gpu_surface_packet_present_cache_action_count);
    try std.testing.expectEqual(packet.cachedResourceCommandCount(), harness.null_platform.gpu_surface_packet_present_cached_resource_command_count);
    try std.testing.expectEqual(packet.unsupported_command_count, harness.null_platform.gpu_surface_packet_present_unsupported_command_count);
    try std.testing.expect(harness.null_platform.gpu_surface_packet_present_representable);
    try std.testing.expect(harness.null_platform.gpu_surface_packet_present_json_len > 0);
    try std.testing.expect(std.mem.indexOf(u8, packet_json_buffer[0..harness.null_platform.gpu_surface_packet_present_json_len], "\"commands\":[") != null);

    const presented_frame = try harness.runtime.gpuSurfaceFrame(1, "canvas");
    try std.testing.expect(!presented_frame.canvas_frame_requires_render);
    try std.testing.expect(!presented_frame.canvas_frame_full_repaint);
    try std.testing.expect(presented_frame.canvas_frame_dirty_bounds == null);
}

test "runtime presents canvas GPU packet with separate presentation scale" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-canvas-packet-presentation-scale", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
        }
    };

    var harness: TestHarness() = undefined;
    harness.init(.{});
    harness.null_platform.gpu_surfaces = true;
    var app_state: TestApp = .{};
    try harness.start(app_state.app());

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(0, 0, 96, 48),
    });

    const commands = [_]canvas.CanvasCommand{.{ .fill_rect = .{
        .id = 41,
        .rect = geometry.RectF.init(8, 6, 32, 20),
        .fill = .{ .color = canvas.Color.rgb8(37, 99, 235) },
    } }};
    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", .{ .commands = &commands });

    var gpu_commands: [max_canvas_commands_per_view]canvas.CanvasGpuCommand = undefined;
    var packet_json_buffer: [16 * 1024]u8 = undefined;
    const packet = try harness.runtime.presentNextCanvasGpuPacketWithScale(1, "canvas", .{
        .frame_index = 12,
        .timestamp_ns = 44_000,
        .surface_size = geometry.SizeF.init(96, 48),
        .scale = 2,
    }, canvasFrameScratchStorage(&harness.runtime), canvas.Color.rgb8(247, 249, 252), &gpu_commands, &packet_json_buffer, @as(f32, 1));

    try std.testing.expect(packet.requiresRender());
    try std.testing.expectEqual(@as(f32, 1), packet.scale);
    try std.testing.expectEqual(@as(f32, 1), harness.null_platform.gpu_surface_packet_present_scale_factor);
    try std.testing.expectEqual(@as(f32, 2), harness.runtime.views[0].presented_canvas_scale);
    const presented_frame = try harness.runtime.gpuSurfaceFrame(1, "canvas");
    try std.testing.expect(!presented_frame.canvas_frame_requires_render);
}

test "runtime direct canvas GPU packet reports unsupported when JSON buffer is too small" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-canvas-packet-direct-buffer", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
        }
    };

    var harness: TestHarness() = undefined;
    harness.init(.{});
    harness.null_platform.gpu_surfaces = true;
    var app_state: TestApp = .{};
    try harness.start(app_state.app());

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(0, 0, 96, 48),
    });

    const commands = [_]canvas.CanvasCommand{.{ .fill_rect = .{
        .id = 41,
        .rect = geometry.RectF.init(8, 6, 32, 20),
        .fill = .{ .color = canvas.Color.rgb8(37, 99, 235) },
    } }};
    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", .{ .commands = &commands });

    var gpu_commands: [max_canvas_commands_per_view]canvas.CanvasGpuCommand = undefined;
    var packet_json_buffer: [32]u8 = undefined;
    try std.testing.expectError(error.UnsupportedService, harness.runtime.presentNextCanvasGpuPacket(1, "canvas", .{
        .frame_index = 13,
        .timestamp_ns = 45_000,
        .surface_size = geometry.SizeF.init(96, 48),
        .scale = 2,
    }, canvasFrameScratchStorage(&harness.runtime), canvas.Color.rgb8(247, 249, 252), &gpu_commands, &packet_json_buffer));
    try std.testing.expectEqual(@as(usize, 0), harness.null_platform.gpu_surface_packet_present_count);
}

test "runtime presents next canvas frame through packet presenter when available" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-canvas-auto-packet", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
        }
    };

    var harness: TestHarness() = undefined;
    harness.init(.{});
    harness.null_platform.gpu_surfaces = true;
    var app_state: TestApp = .{};
    try harness.start(app_state.app());

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(0, 0, 96, 48),
    });

    const commands = [_]canvas.CanvasCommand{.{ .fill_rect = .{
        .id = 1,
        .rect = geometry.RectF.init(4, 4, 24, 18),
        .fill = .{ .color = canvas.Color.rgb8(37, 99, 235) },
    } }};
    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", .{ .commands = &commands });

    var gpu_commands: [max_canvas_commands_per_view]canvas.CanvasGpuCommand = undefined;
    var packet_json_buffer: [16 * 1024]u8 = undefined;
    var pixels: [96 * 48 * 4]u8 = undefined;
    var scratch: [96 * 48 * 4]u8 = undefined;
    const result = try harness.runtime.presentNextCanvasFrame(1, "canvas", .{
        .frame_index = 21,
        .timestamp_ns = 88_000,
        .surface_size = geometry.SizeF.init(96, 48),
        .scale = 1,
    }, canvasFrameScratchStorage(&harness.runtime), &gpu_commands, &packet_json_buffer, &pixels, &scratch, canvas.Color.rgb8(20, 24, 32), null);

    try std.testing.expectEqual(CanvasPresentationMode.gpu_packet, result.mode);
    try std.testing.expect(result.frame.requiresRender());
    try std.testing.expect(result.packet_representable);
    try std.testing.expectEqual(@as(usize, 1), result.packet_command_count);
    try std.testing.expectEqual(@as(usize, 1), harness.null_platform.gpu_surface_packet_present_count);
    try std.testing.expectEqual(@as(usize, 0), harness.null_platform.gpu_surface_present_count);
    try std.testing.expectEqualDeep([4]u8{ 20, 24, 32, 255 }, harness.null_platform.gpu_surface_packet_present_clear_color_rgba8);
    const presented_frame = try harness.runtime.gpuSurfaceFrame(1, "canvas");
    try std.testing.expect(!presented_frame.canvas_frame_requires_render);
}

test "runtime auto-present packet honors presentation scale without invalidating retained frame" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-canvas-auto-packet-presentation-scale", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
        }
    };

    var harness: TestHarness() = undefined;
    harness.init(.{});
    harness.null_platform.gpu_surfaces = true;
    var app_state: TestApp = .{};
    try harness.start(app_state.app());

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(0, 0, 96, 48),
    });

    const commands = [_]canvas.CanvasCommand{.{ .fill_rect = .{
        .id = 1,
        .rect = geometry.RectF.init(4, 4, 24, 18),
        .fill = .{ .color = canvas.Color.rgb8(37, 99, 235) },
    } }};
    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", .{ .commands = &commands });

    var gpu_commands: [max_canvas_commands_per_view]canvas.CanvasGpuCommand = undefined;
    var packet_json_buffer: [16 * 1024]u8 = undefined;
    var pixels: [96 * 48 * 4]u8 = undefined;
    var scratch: [96 * 48 * 4]u8 = undefined;
    const result = try harness.runtime.presentNextCanvasFrame(1, "canvas", .{
        .frame_index = 21,
        .timestamp_ns = 88_000,
        .surface_size = geometry.SizeF.init(96, 48),
        .scale = 2,
    }, canvasFrameScratchStorage(&harness.runtime), &gpu_commands, &packet_json_buffer, &pixels, &scratch, canvas.Color.rgb8(20, 24, 32), @as(f32, 1));

    try std.testing.expectEqual(CanvasPresentationMode.gpu_packet, result.mode);
    try std.testing.expectEqual(@as(f32, 2), result.frame.scale);
    try std.testing.expectEqual(@as(f32, 1), harness.null_platform.gpu_surface_packet_present_scale_factor);
    try std.testing.expectEqual(@as(f32, 2), harness.runtime.views[0].presented_canvas_scale);
    const presented_frame = try harness.runtime.gpuSurfaceFrame(1, "canvas");
    try std.testing.expect(!presented_frame.canvas_frame_requires_render);
}

test "runtime falls back to pixels when packet JSON buffer is too small" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-canvas-packet-buffer-fallback", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
        }
    };

    var harness: TestHarness() = undefined;
    harness.init(.{});
    harness.null_platform.gpu_surfaces = true;
    var app_state: TestApp = .{};
    try harness.start(app_state.app());

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(0, 0, 4, 4),
    });

    const commands = [_]canvas.CanvasCommand{.{ .fill_rect = .{
        .id = 1,
        .rect = geometry.RectF.init(1, 1, 2, 2),
        .fill = .{ .color = canvas.Color.rgb8(37, 99, 235) },
    } }};
    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", .{ .commands = &commands });

    var gpu_commands: [max_canvas_commands_per_view]canvas.CanvasGpuCommand = undefined;
    var packet_json_buffer: [32]u8 = undefined;
    var pixels: [4 * 4 * 4]u8 = undefined;
    var scratch: [4 * 4 * 4]u8 = undefined;
    const result = try harness.runtime.presentNextCanvasFrame(1, "canvas", .{
        .frame_index = 22,
        .timestamp_ns = 89_000,
        .surface_size = geometry.SizeF.init(4, 4),
        .scale = 1,
    }, canvasFrameScratchStorage(&harness.runtime), &gpu_commands, &packet_json_buffer, &pixels, &scratch, canvas.Color.rgb8(0, 0, 0), null);

    try std.testing.expectEqual(CanvasPresentationMode.pixels, result.mode);
    try std.testing.expectEqual(@as(usize, 0), harness.null_platform.gpu_surface_packet_present_count);
    try std.testing.expectEqual(@as(usize, 1), harness.null_platform.gpu_surface_present_count);
}

test "runtime falls back to pixel presentation when packet presenter is unavailable" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-canvas-auto-pixels", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
        }
    };

    var harness: TestHarness() = undefined;
    harness.init(.{});
    harness.null_platform.gpu_surfaces = true;
    harness.null_platform.gpu_surface_packets = false;
    var app_state: TestApp = .{};
    try harness.start(app_state.app());

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(0, 0, 4, 4),
    });

    const commands = [_]canvas.CanvasCommand{.{ .fill_rect = .{
        .id = 1,
        .rect = geometry.RectF.init(1, 1, 2, 2),
        .fill = .{ .color = canvas.Color.rgb8(255, 0, 0) },
    } }};
    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", .{ .commands = &commands });

    var gpu_commands: [max_canvas_commands_per_view]canvas.CanvasGpuCommand = undefined;
    var packet_json_buffer: [16 * 1024]u8 = undefined;
    var pixels: [4 * 4 * 4]u8 = undefined;
    var scratch: [4 * 4 * 4]u8 = undefined;
    const result = try harness.runtime.presentNextCanvasFrame(1, "canvas", .{
        .frame_index = 22,
        .timestamp_ns = 89_000,
        .surface_size = geometry.SizeF.init(4, 4),
        .scale = 1,
    }, canvasFrameScratchStorage(&harness.runtime), &gpu_commands, &packet_json_buffer, &pixels, &scratch, canvas.Color.rgb8(0, 0, 0), null);

    try std.testing.expectEqual(CanvasPresentationMode.pixels, result.mode);
    try std.testing.expect(result.frame.requiresRender());
    try std.testing.expectEqual(@as(usize, 0), harness.null_platform.gpu_surface_packet_present_count);
    try std.testing.expectEqual(@as(usize, 1), harness.null_platform.gpu_surface_present_count);
    const presented_frame = try harness.runtime.gpuSurfaceFrame(1, "canvas");
    try std.testing.expect(!presented_frame.canvas_frame_requires_render);
}

test "runtime pixel fallback honors presentation scale without invalidating retained frame" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-canvas-auto-pixels-presentation-scale", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
        }
    };

    var harness: TestHarness() = undefined;
    harness.init(.{});
    harness.null_platform.gpu_surfaces = true;
    harness.null_platform.gpu_surface_packets = false;
    var app_state: TestApp = .{};
    try harness.start(app_state.app());

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(0, 0, 4, 4),
    });

    const commands = [_]canvas.CanvasCommand{.{ .fill_rect = .{
        .id = 1,
        .rect = geometry.RectF.init(1, 1, 2, 2),
        .fill = .{ .color = canvas.Color.rgb8(255, 0, 0) },
    } }};
    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", .{ .commands = &commands });

    var gpu_commands: [max_canvas_commands_per_view]canvas.CanvasGpuCommand = undefined;
    var packet_json_buffer: [16 * 1024]u8 = undefined;
    var pixels: [4 * 4 * 4]u8 = undefined;
    var scratch: [4 * 4 * 4]u8 = undefined;
    const result = try harness.runtime.presentNextCanvasFrame(1, "canvas", .{
        .frame_index = 22,
        .timestamp_ns = 89_000,
        .surface_size = geometry.SizeF.init(4, 4),
        .scale = 2,
    }, canvasFrameScratchStorage(&harness.runtime), &gpu_commands, &packet_json_buffer, &pixels, &scratch, canvas.Color.rgb8(0, 0, 0), @as(f32, 1));

    try std.testing.expectEqual(CanvasPresentationMode.pixels, result.mode);
    try std.testing.expectEqual(@as(f32, 2), result.frame.scale);
    try std.testing.expectEqual(@as(f32, 1), harness.null_platform.gpu_surface_present_scale_factor);
    try std.testing.expectEqual(@as(f32, 2), harness.runtime.views[0].presented_canvas_scale);
    const presented_frame = try harness.runtime.gpuSurfaceFrame(1, "canvas");
    try std.testing.expect(!presented_frame.canvas_frame_requires_render);
}

test "runtime pixel fallback renders provided canvas image resources" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-canvas-image-pixels", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
        }
    };

    var harness: TestHarness() = undefined;
    harness.init(.{});
    harness.null_platform.gpu_surfaces = true;
    harness.null_platform.gpu_surface_packets = false;
    var app_state: TestApp = .{};
    try harness.start(app_state.app());

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(0, 0, 2, 2),
    });

    const commands = [_]canvas.CanvasCommand{.{ .draw_image = .{
        .id = 1,
        .image_id = 42,
        .dst = geometry.RectF.init(0, 0, 1, 1),
        .sampling = .nearest,
    } }};
    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", .{ .commands = &commands });

    const image_pixels = [_]u8{ 11, 22, 33, 255 };
    const image_resources = [_]canvas.ReferenceImage{.{
        .id = 42,
        .width = 1,
        .height = 1,
        .pixels = &image_pixels,
    }};
    var gpu_commands: [max_canvas_commands_per_view]canvas.CanvasGpuCommand = undefined;
    var packet_json_buffer: [16 * 1024]u8 = undefined;
    var pixels: [2 * 2 * 4]u8 = undefined;
    var scratch: [2 * 2 * 4]u8 = undefined;
    const result = try harness.runtime.presentNextCanvasFrame(1, "canvas", .{
        .frame_index = 23,
        .timestamp_ns = 90_000,
        .surface_size = geometry.SizeF.init(2, 2),
        .scale = 1,
        .image_resources = &image_resources,
    }, canvasFrameScratchStorage(&harness.runtime), &gpu_commands, &packet_json_buffer, &pixels, &scratch, canvas.Color.rgb8(0, 0, 0), null);

    try std.testing.expectEqual(CanvasPresentationMode.pixels, result.mode);
    try std.testing.expectEqual(@as(usize, 0), harness.null_platform.gpu_surface_packet_present_count);
    try std.testing.expectEqual(@as(usize, 1), harness.null_platform.gpu_surface_present_count);
    try std.testing.expectEqualDeep([4]u8{ 11, 22, 33, 255 }, harness.null_platform.gpu_surface_present_sample_rgba);
    try std.testing.expectEqual(@as(usize, 1), result.frame.image_cache_plan.uploadCount());
    try std.testing.expectEqual(@as(usize, 1), result.frame.image_plan.images[0].width);
    try std.testing.expectEqual(@as(usize, 1), result.frame.image_plan.images[0].height);
    try std.testing.expectEqualSlices(u8, &image_pixels, result.frame.image_plan.images[0].pixels);
}

test "runtime next canvas frame retains and evicts glyph atlas cache" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-canvas-glyph-cache", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
        }
    };

    var harness: TestHarness() = undefined;
    harness.init(.{});
    harness.null_platform.gpu_surfaces = true;
    var app_state: TestApp = .{};
    try harness.start(app_state.app());

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(0, 0, 160, 80),
    });

    const first_commands = [_]canvas.CanvasCommand{.{ .draw_text = .{
        .id = 1,
        .font_id = 5,
        .size = 14,
        .origin = geometry.PointF.init(12, 32),
        .color = canvas.Color.rgb8(15, 23, 42),
        .text = "A",
    } }};
    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", .{ .commands = &first_commands });

    var render_commands: [1]canvas.RenderCommand = undefined;
    var render_batches: [1]canvas.RenderBatch = undefined;
    var resources: [1]canvas.RenderResource = undefined;
    var resource_cache_entries: [1]canvas.RenderResourceCacheEntry = undefined;
    var resource_cache_actions: [2]canvas.RenderResourceCacheAction = undefined;
    var glyphs: [1]canvas.GlyphAtlasEntry = undefined;
    var glyph_cache_entries: [1]canvas.GlyphAtlasCacheEntry = undefined;
    var glyph_cache_actions: [2]canvas.GlyphAtlasCacheAction = undefined;
    var text_layout_plans: [1]canvas.TextLayoutPlan = undefined;
    var text_layout_lines: [1]canvas.TextLine = undefined;
    var text_layout_cache_entries: [1]canvas.TextLayoutCacheEntry = undefined;
    var text_layout_cache_actions: [2]canvas.TextLayoutCacheAction = undefined;
    var changes: [1]canvas.DiffChange = undefined;
    const frame_storage = canvas.CanvasFrameStorage{
        .render_commands = &render_commands,
        .render_batches = &render_batches,
        .resources = &resources,
        .resource_cache_entries = &resource_cache_entries,
        .resource_cache_actions = &resource_cache_actions,
        .glyph_atlas_entries = &glyphs,
        .glyph_atlas_cache_entries = &glyph_cache_entries,
        .glyph_atlas_cache_actions = &glyph_cache_actions,
        .text_layout_plans = &text_layout_plans,
        .text_layout_lines = &text_layout_lines,
        .text_layout_cache_entries = &text_layout_cache_entries,
        .text_layout_cache_actions = &text_layout_cache_actions,
        .changes = &changes,
    };

    const first_frame = try harness.runtime.nextCanvasFrame(1, "canvas", .{ .frame_index = 1 }, frame_storage);
    try std.testing.expectEqual(@as(usize, 1), first_frame.glyph_atlas_cache_plan.uploadCount());
    try std.testing.expectEqual(@as(usize, 0), first_frame.glyph_atlas_cache_plan.retainCount());
    try std.testing.expectEqual(@as(usize, 0), first_frame.glyph_atlas_cache_plan.evictCount());
    try std.testing.expectEqual(@as(usize, 1), harness.runtime.views[0].canvas_frame_glyph_atlas_cache_count);
    try std.testing.expectEqual(@as(usize, 1), harness.runtime.views[0].canvas_frame_glyph_atlas_upload_count);
    try std.testing.expectEqual(@as(usize, 1), first_frame.text_layout_cache_plan.uploadCount());
    try std.testing.expectEqual(@as(usize, 1), harness.runtime.views[0].canvas_frame_text_layout_cache_count);
    try std.testing.expectEqual(@as(usize, 1), harness.runtime.views[0].canvas_frame_text_layout_upload_count);

    const clean_frame = try harness.runtime.nextCanvasFrame(1, "canvas", .{ .frame_index = 2 }, frame_storage);
    try std.testing.expectEqual(@as(usize, 0), clean_frame.glyph_atlas_cache_plan.uploadCount());
    try std.testing.expectEqual(@as(usize, 0), clean_frame.glyph_atlas_cache_plan.retainCount());
    try std.testing.expectEqual(@as(usize, 0), clean_frame.glyph_atlas_cache_plan.evictCount());
    try std.testing.expectEqual(@as(usize, 1), harness.runtime.views[0].canvas_frame_glyph_atlas_cache_count);
    try std.testing.expectEqual(@as(usize, 0), harness.runtime.views[0].canvas_frame_glyph_atlas_retain_count);
    try std.testing.expectEqual(@as(usize, 0), clean_frame.text_layout_cache_plan.uploadCount());
    try std.testing.expectEqual(@as(usize, 0), clean_frame.text_layout_cache_plan.retainCount());
    try std.testing.expectEqual(@as(usize, 0), clean_frame.text_layout_cache_plan.evictCount());
    try std.testing.expectEqual(@as(usize, 1), harness.runtime.views[0].canvas_frame_text_layout_cache_count);
    try std.testing.expectEqual(@as(usize, 0), harness.runtime.views[0].canvas_frame_text_layout_retain_count);

    const next_commands = [_]canvas.CanvasCommand{.{ .draw_text = .{
        .id = 1,
        .font_id = 5,
        .size = 14,
        .origin = geometry.PointF.init(12, 32),
        .color = canvas.Color.rgb8(15, 23, 42),
        .text = "B",
    } }};
    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", .{ .commands = &next_commands });

    const changed_frame = try harness.runtime.nextCanvasFrame(1, "canvas", .{ .frame_index = 3 }, frame_storage);
    try std.testing.expectEqual(@as(usize, 1), changed_frame.glyph_atlas_cache_plan.uploadCount());
    try std.testing.expectEqual(@as(usize, 0), changed_frame.glyph_atlas_cache_plan.retainCount());
    try std.testing.expectEqual(@as(usize, 1), changed_frame.glyph_atlas_cache_plan.evictCount());
    try std.testing.expectEqual(@as(usize, 1), harness.runtime.views[0].canvas_frame_glyph_atlas_cache_count);
    try std.testing.expectEqual(@as(u32, 'B'), harness.runtime.views[0].canvas_frame_glyph_atlas_cache[0].key.glyph_id);
    try std.testing.expectEqual(@as(usize, 1), harness.runtime.views[0].canvas_frame_glyph_atlas_upload_count);
    try std.testing.expectEqual(@as(usize, 1), harness.runtime.views[0].canvas_frame_glyph_atlas_evict_count);
    try std.testing.expectEqual(@as(usize, 1), changed_frame.text_layout_cache_plan.uploadCount());
    try std.testing.expectEqual(@as(usize, 0), changed_frame.text_layout_cache_plan.retainCount());
    try std.testing.expectEqual(@as(usize, 1), changed_frame.text_layout_cache_plan.evictCount());
    try std.testing.expectEqual(@as(usize, 1), harness.runtime.views[0].canvas_frame_text_layout_cache_count);
    try std.testing.expectEqual(@as(usize, 1), harness.runtime.views[0].canvas_frame_text_layout_upload_count);
    try std.testing.expectEqual(@as(usize, 1), harness.runtime.views[0].canvas_frame_text_layout_evict_count);
}

test "runtime next canvas frame keeps recent unused text caches warm" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-canvas-text-cache-retention", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
        }
    };

    var harness: TestHarness() = undefined;
    harness.init(.{});
    harness.null_platform.gpu_surfaces = true;
    var app_state: TestApp = .{};
    try harness.start(app_state.app());

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(0, 0, 160, 80),
    });

    const first_commands = [_]canvas.CanvasCommand{
        .{ .draw_text = .{
            .id = 1,
            .font_id = 5,
            .size = 14,
            .origin = geometry.PointF.init(12, 32),
            .color = canvas.Color.rgb8(15, 23, 42),
            .text = "A",
        } },
        .{ .draw_text = .{
            .id = 2,
            .font_id = 5,
            .size = 14,
            .origin = geometry.PointF.init(32, 32),
            .color = canvas.Color.rgb8(15, 23, 42),
            .text = "B",
        } },
    };
    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", .{ .commands = &first_commands });

    var render_commands: [2]canvas.RenderCommand = undefined;
    var render_batches: [2]canvas.RenderBatch = undefined;
    var resources: [2]canvas.RenderResource = undefined;
    var resource_cache_entries: [2]canvas.RenderResourceCacheEntry = undefined;
    var resource_cache_actions: [4]canvas.RenderResourceCacheAction = undefined;
    var glyphs: [2]canvas.GlyphAtlasEntry = undefined;
    var glyph_cache_entries: [2]canvas.GlyphAtlasCacheEntry = undefined;
    var glyph_cache_actions: [4]canvas.GlyphAtlasCacheAction = undefined;
    var text_layout_plans: [2]canvas.TextLayoutPlan = undefined;
    var text_layout_lines: [2]canvas.TextLine = undefined;
    var text_layout_cache_entries: [2]canvas.TextLayoutCacheEntry = undefined;
    var text_layout_cache_actions: [4]canvas.TextLayoutCacheAction = undefined;
    var changes: [2]canvas.DiffChange = undefined;
    const frame_storage = canvas.CanvasFrameStorage{
        .render_commands = &render_commands,
        .render_batches = &render_batches,
        .resources = &resources,
        .resource_cache_entries = &resource_cache_entries,
        .resource_cache_actions = &resource_cache_actions,
        .glyph_atlas_entries = &glyphs,
        .glyph_atlas_cache_entries = &glyph_cache_entries,
        .glyph_atlas_cache_actions = &glyph_cache_actions,
        .text_layout_plans = &text_layout_plans,
        .text_layout_lines = &text_layout_lines,
        .text_layout_cache_entries = &text_layout_cache_entries,
        .text_layout_cache_actions = &text_layout_cache_actions,
        .changes = &changes,
    };

    _ = try harness.runtime.setCanvasFrameBudget(1, "canvas", .{
        .max_glyph_atlas_uploads = 1,
        .max_text_layout_uploads = 1,
    });
    const first_frame = try harness.runtime.nextCanvasFrame(1, "canvas", .{ .frame_index = 1 }, frame_storage);
    try std.testing.expectEqual(@as(usize, 2), first_frame.glyph_atlas_cache_plan.uploadCount());
    try std.testing.expectEqual(@as(usize, 2), first_frame.text_layout_cache_plan.uploadCount());
    const first_budget_status = first_frame.budgetStatus();
    try std.testing.expect(first_budget_status.glyph_atlas_uploads_over);
    try std.testing.expect(first_budget_status.text_layout_uploads_over);
    try std.testing.expectEqual(@as(usize, 2), first_budget_status.exceededCount());
    try std.testing.expectEqual(@as(usize, 2), harness.runtime.views[0].canvas_frame_budget_status.exceededCount());

    const second_commands = [_]canvas.CanvasCommand{first_commands[0]};
    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", .{ .commands = &second_commands });
    const second_frame = try harness.runtime.nextCanvasFrame(1, "canvas", .{ .frame_index = 2 }, frame_storage);
    try std.testing.expect(second_frame.requiresRender());
    try std.testing.expect(second_frame.budgetStatus().ok());
    try std.testing.expectEqual(@as(usize, 2), second_frame.glyph_atlas_cache_plan.entryCount());
    try std.testing.expectEqual(@as(usize, 0), second_frame.glyph_atlas_cache_plan.uploadCount());
    try std.testing.expectEqual(@as(usize, 2), second_frame.glyph_atlas_cache_plan.retainCount());
    try std.testing.expectEqual(@as(usize, 0), second_frame.glyph_atlas_cache_plan.evictCount());
    try std.testing.expectEqual(@as(u64, 2), second_frame.glyph_atlas_cache_plan.entries[0].last_used_frame);
    try std.testing.expectEqual(@as(u64, 1), second_frame.glyph_atlas_cache_plan.entries[1].last_used_frame);
    try std.testing.expectEqual(@as(usize, 2), second_frame.text_layout_cache_plan.entryCount());
    try std.testing.expectEqual(@as(usize, 0), second_frame.text_layout_cache_plan.uploadCount());
    try std.testing.expectEqual(@as(usize, 2), second_frame.text_layout_cache_plan.retainCount());
    try std.testing.expectEqual(@as(usize, 0), second_frame.text_layout_cache_plan.evictCount());
    try std.testing.expectEqual(@as(u64, 2), second_frame.text_layout_cache_plan.entries[0].last_used_frame);
    try std.testing.expectEqual(@as(u64, 1), second_frame.text_layout_cache_plan.entries[1].last_used_frame);
}

test "runtime canvas frame scratch storage includes text layout caches" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-canvas-scratch-text-cache", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
        }
    };

    var harness: TestHarness() = undefined;
    harness.init(.{});
    harness.null_platform.gpu_surfaces = true;
    var app_state: TestApp = .{};
    try harness.start(app_state.app());

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(0, 0, 160, 80),
    });

    const first_commands = [_]canvas.CanvasCommand{.{ .draw_text = .{
        .id = 1,
        .font_id = 5,
        .size = 14,
        .origin = geometry.PointF.init(12, 32),
        .color = canvas.Color.rgb8(15, 23, 42),
        .text = "First",
    } }};
    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", .{ .commands = &first_commands });

    const first_frame = try harness.runtime.nextCanvasFrame(1, "canvas", .{ .frame_index = 1 }, canvasFrameScratchStorage(&harness.runtime));
    try std.testing.expectEqual(@as(usize, 1), first_frame.text_layout_plan.planCount());
    try std.testing.expectEqual(@as(usize, 1), first_frame.text_layout_plan.lineCount());
    try std.testing.expectEqual(@as(usize, 1), first_frame.text_layout_cache_plan.uploadCount());
    try std.testing.expectEqual(@as(usize, 1), harness.runtime.views[0].canvas_frame_text_layout_cache_count);
    try std.testing.expectEqual(@as(usize, 1), harness.runtime.views[0].canvas_frame_text_layout_upload_count);

    const next_commands = [_]canvas.CanvasCommand{.{ .draw_text = .{
        .id = 1,
        .font_id = 5,
        .size = 14,
        .origin = geometry.PointF.init(12, 32),
        .color = canvas.Color.rgb8(15, 23, 42),
        .text = "Second",
    } }};
    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", .{ .commands = &next_commands });

    const changed_frame = try harness.runtime.nextCanvasFrame(1, "canvas", .{ .frame_index = 2 }, canvasFrameScratchStorage(&harness.runtime));
    try std.testing.expect(changed_frame.requiresRender());
    try std.testing.expectEqual(@as(usize, 1), changed_frame.text_layout_plan.planCount());
    try std.testing.expectEqual(@as(usize, 1), changed_frame.text_layout_cache_plan.uploadCount());
    try std.testing.expectEqual(@as(usize, 1), changed_frame.text_layout_cache_plan.retainCount());
    try std.testing.expectEqual(@as(usize, 0), changed_frame.text_layout_cache_plan.evictCount());
    try std.testing.expectEqual(@as(usize, 2), harness.runtime.views[0].canvas_frame_text_layout_cache_count);
    try std.testing.expectEqual(@as(usize, 1), harness.runtime.views[0].canvas_frame_text_layout_upload_count);
    try std.testing.expectEqual(@as(usize, 1), harness.runtime.views[0].canvas_frame_text_layout_retain_count);
    try std.testing.expectEqual(@as(usize, 0), harness.runtime.views[0].canvas_frame_text_layout_evict_count);
}

test "runtime next canvas frame applies render override dirty regions" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-canvas-next-frame-overrides", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
        }
    };

    var harness: TestHarness() = undefined;
    harness.init(.{});
    harness.null_platform.gpu_surfaces = true;
    var app_state: TestApp = .{};
    try harness.start(app_state.app());

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(0, 0, 40, 20),
    });

    const commands = [_]canvas.CanvasCommand{.{ .fill_rect = .{
        .id = 1,
        .rect = geometry.RectF.init(0, 0, 10, 10),
        .fill = .{ .color = canvas.Color.rgb8(255, 0, 0) },
    } }};
    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", .{ .commands = &commands });

    var render_commands: [1]canvas.RenderCommand = undefined;
    var render_batches: [1]canvas.RenderBatch = undefined;
    var resources: [1]canvas.RenderResource = undefined;
    var resource_cache_entries: [1]canvas.RenderResourceCacheEntry = undefined;
    var resource_cache_actions: [2]canvas.RenderResourceCacheAction = undefined;
    var glyphs: [1]canvas.GlyphAtlasEntry = undefined;
    var changes: [1]canvas.DiffChange = undefined;
    const frame_storage = canvas.CanvasFrameStorage{
        .render_commands = &render_commands,
        .render_batches = &render_batches,
        .resources = &resources,
        .resource_cache_entries = &resource_cache_entries,
        .resource_cache_actions = &resource_cache_actions,
        .glyph_atlas_entries = &glyphs,
        .changes = &changes,
    };

    const first_frame = try harness.runtime.nextCanvasFrame(1, "canvas", .{ .frame_index = 1 }, frame_storage);
    try std.testing.expect(first_frame.full_repaint);
    try std.testing.expectEqualDeep(geometry.RectF.init(0, 0, 40, 20), first_frame.dirty_bounds.?);

    const overrides = [_]canvas.CanvasRenderOverride{.{
        .id = 1,
        .opacity = 0.5,
        .transform = canvas.Affine.translate(10, 0),
    }};
    const moved_frame = try harness.runtime.nextCanvasFrame(1, "canvas", .{
        .frame_index = 2,
        .render_overrides = &overrides,
    }, frame_storage);
    try std.testing.expect(!moved_frame.full_repaint);
    try std.testing.expect(moved_frame.requiresRender());
    try std.testing.expectEqual(@as(usize, 0), moved_frame.changes.len);
    try std.testing.expectEqual(@as(f32, 0.5), moved_frame.render_plan.commands[0].opacity);
    try std.testing.expectEqualDeep(canvas.Affine.translate(10, 0), moved_frame.render_plan.commands[0].transform);
    try std.testing.expectEqualDeep(geometry.RectF.init(0, 0, 20, 10), moved_frame.dirty_bounds.?);
    try std.testing.expectEqualDeep(geometry.RectF.init(0, 0, 20, 10), harness.runtime.views[0].canvas_frame_dirty_bounds.?);

    const clean_frame = try harness.runtime.nextCanvasFrame(1, "canvas", .{
        .frame_index = 3,
        .previous_render_overrides = &overrides,
        .render_overrides = &overrides,
    }, frame_storage);
    try std.testing.expect(!clean_frame.requiresRender());
    try std.testing.expect(clean_frame.dirty_bounds == null);
    try std.testing.expect(harness.runtime.views[0].canvas_frame_dirty_bounds == null);
}

test "runtime schedules canvas render animations without display list rebuild" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-canvas-runtime-animation", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
        }
    };

    var harness: TestHarness() = undefined;
    harness.init(.{});
    harness.null_platform.gpu_surfaces = true;
    var app_state: TestApp = .{};
    try harness.start(app_state.app());

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(0, 0, 40, 20),
    });
    try std.testing.expectEqual(@as(u64, 0), try harness.runtime.canvasRenderAnimationStartNs(1, "canvas"));

    const commands = [_]canvas.CanvasCommand{.{ .fill_rect = .{
        .id = 1,
        .rect = geometry.RectF.init(0, 0, 10, 10),
        .fill = .{ .color = canvas.Color.rgb8(255, 0, 0) },
    } }};
    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", .{ .commands = &commands });

    var render_commands: [1]canvas.RenderCommand = undefined;
    var render_batches: [1]canvas.RenderBatch = undefined;
    var resources: [1]canvas.RenderResource = undefined;
    var resource_cache_entries: [1]canvas.RenderResourceCacheEntry = undefined;
    var resource_cache_actions: [2]canvas.RenderResourceCacheAction = undefined;
    var glyphs: [1]canvas.GlyphAtlasEntry = undefined;
    var changes: [1]canvas.DiffChange = undefined;
    const frame_storage = canvas.CanvasFrameStorage{
        .render_commands = &render_commands,
        .render_batches = &render_batches,
        .resources = &resources,
        .resource_cache_entries = &resource_cache_entries,
        .resource_cache_actions = &resource_cache_actions,
        .glyph_atlas_entries = &glyphs,
        .changes = &changes,
    };

    const start_ns: u64 = 1_000_000_000;
    try harness.runtime.dispatchPlatformEvent(app_state.app(), .{ .gpu_surface_frame = .{
        .window_id = 1,
        .label = "canvas",
        .size = geometry.SizeF.init(40, 20),
        .timestamp_ns = start_ns,
        .nonblank = true,
    } });
    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    _ = try harness.runtime.nextCanvasFrame(1, "canvas", .{ .frame_index = 1, .timestamp_ns = start_ns }, frame_storage);
    try std.testing.expectEqual(start_ns, try harness.runtime.canvasRenderAnimationStartNs(1, "canvas"));
    try harness.runtime.dispatchPlatformEvent(app_state.app(), .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_move,
        .timestamp_ns = start_ns + 60_000_000,
        .x = 12,
        .y = 8,
    } });
    try std.testing.expectEqual(start_ns + 60_000_000, try harness.runtime.canvasRenderAnimationStartNs(1, "canvas"));
    const initial_revision = harness.runtime.views[0].canvas_revision;

    const animations = [_]canvas.CanvasRenderAnimation{.{
        .id = 1,
        .start_ns = start_ns,
        .duration_ms = 1_000,
        .easing = .linear,
        .from_opacity = 0,
        .to_opacity = 1,
        .from_transform = canvas.Affine.translate(10, 0),
        .to_transform = canvas.Affine.identity(),
    }};
    _ = try harness.runtime.setCanvasRenderAnimations(1, "canvas", &animations);
    try std.testing.expectEqual(@as(usize, 1), (try harness.runtime.canvasRenderAnimations(1, "canvas")).len);
    try std.testing.expect(harness.runtime.invalidated);

    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    const mid_frame = try harness.runtime.nextCanvasFrame(1, "canvas", .{
        .frame_index = 2,
        .timestamp_ns = start_ns + 500_000_000,
    }, frame_storage);
    try std.testing.expectEqual(initial_revision, harness.runtime.views[0].canvas_revision);
    try std.testing.expect(!mid_frame.full_repaint);
    try std.testing.expect(mid_frame.requiresRender());
    try std.testing.expectEqual(@as(usize, 0), mid_frame.changes.len);
    try std.testing.expectEqual(@as(f32, 0.5), mid_frame.render_plan.commands[0].opacity);
    try std.testing.expectEqualDeep(canvas.Affine.translate(5, 0), mid_frame.render_plan.commands[0].transform);
    try std.testing.expectEqualDeep(geometry.RectF.init(0, 0, 15, 10), mid_frame.dirty_bounds.?);
    try std.testing.expect(harness.runtime.invalidated);

    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    const final_frame = try harness.runtime.nextCanvasFrame(1, "canvas", .{
        .frame_index = 3,
        .timestamp_ns = start_ns + 1_000_000_000,
    }, frame_storage);
    try std.testing.expect(final_frame.requiresRender());
    try std.testing.expectEqual(@as(f32, 1), final_frame.render_plan.commands[0].opacity);
    try std.testing.expectEqualDeep(canvas.Affine.identity(), final_frame.render_plan.commands[0].transform);
    try std.testing.expectEqualDeep(geometry.RectF.init(0, 0, 15, 10), final_frame.dirty_bounds.?);
    try std.testing.expect(!harness.runtime.invalidated);
    try std.testing.expectEqual(@as(usize, 0), (try harness.runtime.canvasRenderAnimations(1, "canvas")).len);
    try std.testing.expectEqual(@as(usize, 0), runtimeViewCanvasFrameRenderOverrides(&harness.runtime.views[0]).len);

    const clean_frame = try harness.runtime.nextCanvasFrame(1, "canvas", .{
        .frame_index = 4,
        .timestamp_ns = start_ns + 1_016_000_000,
    }, frame_storage);
    try std.testing.expect(!clean_frame.requiresRender());
    try std.testing.expect(clean_frame.dirty_bounds == null);
}

test "runtime classifies render animation final overrides for cleanup" {
    try std.testing.expect(canvasRenderAnimationFinalOverrideNoop(.{
        .id = 1,
        .to_opacity = 1,
        .to_transform = canvas.Affine.identity(),
    }));
    try std.testing.expect(!canvasRenderAnimationFinalOverrideNoop(.{
        .id = 2,
        .to_opacity = 0,
    }));
    try std.testing.expect(!canvasRenderAnimationFinalOverrideNoop(.{
        .id = 3,
        .to_transform = canvas.Affine.translate(8, 0),
    }));
}

test "runtime presents next canvas frame pixels" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-canvas-present-next-frame", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
        }
    };

    var harness: TestHarness() = undefined;
    harness.init(.{});
    harness.null_platform.gpu_surfaces = true;
    var app_state: TestApp = .{};
    try harness.start(app_state.app());

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(0, 0, 4, 4),
    });

    const commands = [_]canvas.CanvasCommand{.{ .fill_rect = .{
        .id = 1,
        .rect = geometry.RectF.init(1, 1, 2, 2),
        .fill = .{ .color = canvas.Color.rgb8(255, 0, 0) },
    } }};
    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", .{ .commands = &commands });

    var render_commands: [1]canvas.RenderCommand = undefined;
    var render_batches: [1]canvas.RenderBatch = undefined;
    var resources: [1]canvas.RenderResource = undefined;
    var resource_cache_entries: [1]canvas.RenderResourceCacheEntry = undefined;
    var resource_cache_actions: [2]canvas.RenderResourceCacheAction = undefined;
    var glyphs: [1]canvas.GlyphAtlasEntry = undefined;
    var changes: [1]canvas.DiffChange = undefined;
    const frame_storage = canvas.CanvasFrameStorage{
        .render_commands = &render_commands,
        .render_batches = &render_batches,
        .resources = &resources,
        .resource_cache_entries = &resource_cache_entries,
        .resource_cache_actions = &resource_cache_actions,
        .glyph_atlas_entries = &glyphs,
        .changes = &changes,
    };
    var pixels: [8 * 8 * 4]u8 = undefined;
    var scratch: [8 * 8 * 4]u8 = undefined;

    const frame = try harness.runtime.presentNextCanvasFramePixels(1, "canvas", .{
        .frame_index = 1,
        .surface_size = geometry.SizeF.init(4, 4),
        .scale = 2,
    }, frame_storage, &pixels, &scratch, canvas.Color.rgb8(0, 0, 0));

    try std.testing.expect(frame.requiresRender());
    try std.testing.expectEqual(@as(usize, 1), harness.null_platform.gpu_surface_present_count);
    try std.testing.expectEqual(@as(usize, 8), harness.null_platform.gpu_surface_present_width);
    try std.testing.expectEqual(@as(usize, 8), harness.null_platform.gpu_surface_present_height);
    try std.testing.expectEqualDeep(geometry.RectF.init(0, 0, 4, 4), harness.null_platform.gpu_surface_present_dirty_bounds.?);
    try std.testing.expectEqual(@as(usize, 8 * 8 * 4), harness.null_platform.gpu_surface_present_byte_len);
    const presented_frame = try harness.runtime.gpuSurfaceFrame(1, "canvas");
    try std.testing.expect(!presented_frame.canvas_frame_requires_render);
    try std.testing.expect(!presented_frame.canvas_frame_full_repaint);
    try std.testing.expect(presented_frame.canvas_frame_dirty_bounds == null);
    try std.testing.expectEqual(@as(usize, 0), presented_frame.canvas_frame_profile_work_units);
    try std.testing.expectEqual(platform.CanvasFrameProfileRisk.idle, presented_frame.canvas_frame_profile_risk);

    const changed_commands = [_]canvas.CanvasCommand{.{ .fill_rect = .{
        .id = 1,
        .rect = geometry.RectF.init(2, 1, 1, 2),
        .fill = .{ .color = canvas.Color.rgb8(0, 128, 255) },
    } }};
    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", .{ .commands = &changed_commands });
    const changed_frame = try harness.runtime.presentNextCanvasFramePixels(1, "canvas", .{
        .frame_index = 2,
        .surface_size = geometry.SizeF.init(4, 4),
        .scale = 2,
    }, frame_storage, &pixels, &scratch, canvas.Color.rgb8(0, 0, 0));

    try std.testing.expect(changed_frame.requiresRender());
    try std.testing.expect(!changed_frame.full_repaint);
    try std.testing.expect(changed_frame.dirty_bounds != null);
    try std.testing.expectEqual(@as(usize, 2), harness.null_platform.gpu_surface_present_count);
    try std.testing.expectEqualDeep(changed_frame.dirty_bounds.?, harness.null_platform.gpu_surface_present_dirty_bounds.?);
}

test "runtime next canvas frame presents empty canvas once" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-canvas-empty-next-frame", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
        }
    };

    var harness: TestHarness() = undefined;
    harness.init(.{});
    harness.null_platform.gpu_surfaces = true;
    var app_state: TestApp = .{};
    try harness.start(app_state.app());

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(0, 0, 320, 240),
    });

    var render_commands: [1]canvas.RenderCommand = undefined;
    var render_batches: [1]canvas.RenderBatch = undefined;
    var resources: [1]canvas.RenderResource = undefined;
    var resource_cache_entries: [1]canvas.RenderResourceCacheEntry = undefined;
    var resource_cache_actions: [2]canvas.RenderResourceCacheAction = undefined;
    var glyphs: [1]canvas.GlyphAtlasEntry = undefined;
    var changes: [1]canvas.DiffChange = undefined;
    const frame_storage = canvas.CanvasFrameStorage{
        .render_commands = &render_commands,
        .render_batches = &render_batches,
        .resources = &resources,
        .resource_cache_entries = &resource_cache_entries,
        .resource_cache_actions = &resource_cache_actions,
        .glyph_atlas_entries = &glyphs,
        .changes = &changes,
    };

    const first_frame = try harness.runtime.nextCanvasFrame(1, "canvas", .{
        .frame_index = 1,
        .surface_size = geometry.SizeF.init(320, 240),
    }, frame_storage);
    try std.testing.expect(first_frame.full_repaint);
    try std.testing.expect(first_frame.requiresRender());
    try std.testing.expectEqualDeep(geometry.RectF.init(0, 0, 320, 240), first_frame.dirty_bounds.?);
    try std.testing.expect(harness.runtime.views[0].presented_canvas_valid);
    try std.testing.expectEqual(@as(u64, 0), harness.runtime.views[0].presented_canvas_revision);
    try std.testing.expect(harness.runtime.views[0].canvas_frame_requires_render);
    try std.testing.expect(harness.runtime.views[0].canvas_frame_full_repaint);

    const clean_frame = try harness.runtime.nextCanvasFrame(1, "canvas", .{
        .frame_index = 2,
        .surface_size = geometry.SizeF.init(320, 240),
    }, frame_storage);
    try std.testing.expect(!clean_frame.full_repaint);
    try std.testing.expect(!clean_frame.requiresRender());
    try std.testing.expect(clean_frame.dirty_bounds == null);
    try std.testing.expect(!harness.runtime.views[0].canvas_frame_requires_render);
    try std.testing.expect(!harness.runtime.views[0].canvas_frame_full_repaint);
    try std.testing.expectEqual(@as(usize, 0), harness.runtime.views[0].canvas_frame_change_count);
    try std.testing.expect(harness.runtime.views[0].canvas_frame_dirty_bounds == null);
}

test "runtime duplicate GPU surface resize keeps retained canvas frame clean" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-canvas-duplicate-resize", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
        }
    };

    var harness: TestHarness() = undefined;
    harness.init(.{});
    harness.null_platform.gpu_surfaces = true;
    var app_state: TestApp = .{};
    const app = app_state.app();
    try harness.start(app);

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(0, 0, 320, 240),
    });
    const initial_frame = harness.runtime.views[0].frame;

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_resized = .{
        .window_id = 1,
        .label = "canvas",
        .frame = initial_frame,
        .scale_factor = 2,
    } });

    const commands = [_]canvas.CanvasCommand{.{ .fill_rect = .{
        .id = 1,
        .rect = geometry.RectF.init(0, 0, 320, 240),
        .fill = .{ .color = canvas.Color.rgb8(245, 248, 255) },
    } }};
    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", .{ .commands = &commands });

    var render_commands: [1]canvas.RenderCommand = undefined;
    var render_batches: [1]canvas.RenderBatch = undefined;
    var resources: [1]canvas.RenderResource = undefined;
    var resource_cache_entries: [1]canvas.RenderResourceCacheEntry = undefined;
    var resource_cache_actions: [2]canvas.RenderResourceCacheAction = undefined;
    var glyphs: [1]canvas.GlyphAtlasEntry = undefined;
    var changes: [2]canvas.DiffChange = undefined;
    const frame_storage = canvas.CanvasFrameStorage{
        .render_commands = &render_commands,
        .render_batches = &render_batches,
        .resources = &resources,
        .resource_cache_entries = &resource_cache_entries,
        .resource_cache_actions = &resource_cache_actions,
        .glyph_atlas_entries = &glyphs,
        .changes = &changes,
    };

    const first_frame = try harness.runtime.nextCanvasFrame(1, "canvas", .{
        .frame_index = 1,
        .surface_size = geometry.SizeF.init(320, 240),
        .scale = 2,
    }, frame_storage);
    try std.testing.expect(first_frame.full_repaint);
    try std.testing.expect(harness.runtime.views[0].presented_canvas_valid);

    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_resized = .{
        .window_id = 1,
        .label = "canvas",
        .frame = initial_frame,
        .scale_factor = 2,
    } });
    try std.testing.expect(!harness.runtime.invalidated);
    try std.testing.expectEqual(@as(usize, 0), harness.runtime.dirty_region_count);
    try std.testing.expect(harness.runtime.views[0].presented_canvas_valid);

    const clean_frame = try harness.runtime.nextCanvasFrame(1, "canvas", .{
        .frame_index = 2,
        .surface_size = geometry.SizeF.init(320, 240),
        .scale = 2,
    }, frame_storage);
    try std.testing.expect(!clean_frame.full_repaint);
    try std.testing.expect(!clean_frame.requiresRender());

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_resized = .{
        .window_id = 1,
        .label = "canvas",
        .frame = geometry.RectF.init(0, 0, 360, 240),
        .scale_factor = 2,
    } });
    try std.testing.expect(harness.runtime.invalidated);
    try std.testing.expect(!harness.runtime.views[0].presented_canvas_valid);
}

test "runtime next canvas frame keeps unchanged clipped display lists incremental" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-canvas-clipped-next-frame", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
        }
    };

    var harness: TestHarness() = undefined;
    harness.init(.{});
    harness.null_platform.gpu_surfaces = true;
    var app_state: TestApp = .{};
    try harness.start(app_state.app());

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(0, 0, 120, 80),
    });

    const commands = [_]canvas.CanvasCommand{
        .{ .push_clip = .{ .id = 90, .rect = geometry.RectF.init(0, 0, 80, 48) } },
        .{ .fill_rect = .{ .id = 1, .rect = geometry.RectF.init(8, 8, 96, 32), .fill = .{ .color = canvas.Color.rgb8(255, 255, 255) } } },
        .pop_clip,
    };
    const changed_commands = [_]canvas.CanvasCommand{
        .{ .push_clip = .{ .id = 90, .rect = geometry.RectF.init(0, 0, 80, 48) } },
        .{ .fill_rect = .{ .id = 1, .rect = geometry.RectF.init(12, 8, 96, 32), .fill = .{ .color = canvas.Color.rgb8(255, 255, 255) } } },
        .pop_clip,
    };

    var render_commands: [2]canvas.RenderCommand = undefined;
    var render_batches: [1]canvas.RenderBatch = undefined;
    var resources: [2]canvas.RenderResource = undefined;
    var resource_cache_entries: [2]canvas.RenderResourceCacheEntry = undefined;
    var resource_cache_actions: [4]canvas.RenderResourceCacheAction = undefined;
    var layers: [2]canvas.RenderLayer = undefined;
    var layer_cache_entries: [2]canvas.RenderLayerCacheEntry = undefined;
    var layer_cache_actions: [4]canvas.RenderLayerCacheAction = undefined;
    var glyphs: [0]canvas.GlyphAtlasEntry = .{};
    var changes: [4]canvas.DiffChange = undefined;
    const frame_storage = canvas.CanvasFrameStorage{
        .render_commands = &render_commands,
        .render_batches = &render_batches,
        .resources = &resources,
        .resource_cache_entries = &resource_cache_entries,
        .resource_cache_actions = &resource_cache_actions,
        .layers = &layers,
        .layer_cache_entries = &layer_cache_entries,
        .layer_cache_actions = &layer_cache_actions,
        .glyph_atlas_entries = &glyphs,
        .changes = &changes,
    };

    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", .{ .commands = &commands });
    const first_frame = try harness.runtime.nextCanvasFrame(1, "canvas", .{ .frame_index = 1 }, frame_storage);
    try std.testing.expect(first_frame.full_repaint);
    try std.testing.expect(first_frame.requiresRender());

    const clean_frame = try harness.runtime.nextCanvasFrame(1, "canvas", .{ .frame_index = 2 }, frame_storage);
    try std.testing.expect(!clean_frame.full_repaint);
    try std.testing.expect(!clean_frame.requiresRender());
    try std.testing.expect(clean_frame.dirty_bounds == null);

    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", .{ .commands = &changed_commands });
    const changed_frame = try harness.runtime.nextCanvasFrame(1, "canvas", .{ .frame_index = 3 }, frame_storage);
    try std.testing.expect(!changed_frame.full_repaint);
    try std.testing.expect(changed_frame.requiresRender());
    try std.testing.expect(changed_frame.dirty_bounds != null);
}

test "runtime invalidates canvas display list dirty regions" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-canvas-dirty", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
        }
    };

    var harness: TestHarness() = undefined;
    harness.init(.{});
    harness.null_platform.gpu_surfaces = true;
    var app_state: TestApp = .{};
    try harness.start(app_state.app());

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(50, 70, 320, 240),
    });

    var initial_commands: [1]canvas.CanvasCommand = undefined;
    var initial_builder = canvas.Builder.init(&initial_commands);
    try initial_builder.fillRect(.{
        .id = 1,
        .rect = geometry.RectF.init(-10, -10, 40, 40),
        .fill = .{ .color = canvas.Color.rgb8(255, 255, 255) },
    });

    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", initial_builder.displayList());
    try std.testing.expect(harness.runtime.invalidated);
    try std.testing.expectEqual(@as(usize, 1), harness.runtime.pendingDirtyRegions().len);
    try std.testing.expectEqualDeep(geometry.RectF.init(50, 70, 30, 30), harness.runtime.pendingDirtyRegions()[0]);

    var moved_commands: [1]canvas.CanvasCommand = undefined;
    var moved_builder = canvas.Builder.init(&moved_commands);
    try moved_builder.fillRect(.{
        .id = 1,
        .rect = geometry.RectF.init(10, 0, 40, 40),
        .fill = .{ .color = canvas.Color.rgb8(255, 255, 255) },
    });

    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", moved_builder.displayList());
    try std.testing.expect(harness.runtime.invalidated);
    try std.testing.expectEqual(@as(usize, 1), harness.runtime.pendingDirtyRegions().len);
    try std.testing.expectEqualDeep(geometry.RectF.init(50, 70, 50, 40), harness.runtime.pendingDirtyRegions()[0]);

    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", moved_builder.displayList());
    try std.testing.expect(!harness.runtime.invalidated);
    try std.testing.expectEqual(@as(usize, 0), harness.runtime.pendingDirtyRegions().len);
}

test "runtime requests gpu surface frames for retained canvas changes" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-canvas-frame-request", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
        }
    };

    var harness: TestHarness() = undefined;
    harness.init(.{});
    harness.null_platform.gpu_surfaces = true;
    var app_state: TestApp = .{};
    try harness.start(app_state.app());

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(50, 70, 320, 240),
    });

    var initial_commands: [1]canvas.CanvasCommand = undefined;
    var initial_builder = canvas.Builder.init(&initial_commands);
    try initial_builder.fillRect(.{
        .id = 1,
        .rect = geometry.RectF.init(0, 0, 40, 40),
        .fill = .{ .color = canvas.Color.rgb8(255, 255, 255) },
    });

    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", initial_builder.displayList());
    try std.testing.expectEqual(@as(usize, 1), harness.null_platform.gpu_surface_frame_request_count);
    try std.testing.expectEqual(@as(platform.WindowId, 1), harness.null_platform.gpu_surface_frame_request_window_id);
    try std.testing.expectEqualStrings("canvas", harness.null_platform.gpu_surface_frame_request_label_storage[0..harness.null_platform.gpu_surface_frame_request_label_len]);

    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", initial_builder.displayList());
    try std.testing.expectEqual(@as(usize, 1), harness.null_platform.gpu_surface_frame_request_count);

    var moved_commands: [1]canvas.CanvasCommand = undefined;
    var moved_builder = canvas.Builder.init(&moved_commands);
    try moved_builder.fillRect(.{
        .id = 1,
        .rect = geometry.RectF.init(8, 0, 40, 40),
        .fill = .{ .color = canvas.Color.rgb8(255, 255, 255) },
    });

    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", moved_builder.displayList());
    try std.testing.expectEqual(@as(usize, 2), harness.null_platform.gpu_surface_frame_request_count);
}

test "runtime rejects duplicate canvas ids before replacing retained scene" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-canvas-duplicate", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
        }
    };

    var harness: TestHarness() = undefined;
    harness.init(.{});
    harness.null_platform.gpu_surfaces = true;
    var app_state: TestApp = .{};
    try harness.start(app_state.app());

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(0, 0, 320, 240),
    });

    var valid_commands: [1]canvas.CanvasCommand = undefined;
    var valid_builder = canvas.Builder.init(&valid_commands);
    try valid_builder.fillRect(.{
        .id = 1,
        .rect = geometry.RectF.init(0, 0, 40, 40),
        .fill = .{ .color = canvas.Color.rgb8(255, 255, 255) },
    });
    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", valid_builder.displayList());

    const duplicate_commands = [_]canvas.CanvasCommand{
        .{ .fill_rect = .{ .id = 2, .rect = geometry.RectF.init(0, 0, 40, 40), .fill = .{ .color = canvas.Color.rgb8(255, 255, 255) } } },
        .{ .blur = .{ .id = 2, .rect = geometry.RectF.init(0, 0, 40, 40), .radius = 4 } },
    };
    try std.testing.expectError(error.DuplicateObjectId, harness.runtime.setCanvasDisplayList(1, "canvas", .{ .commands = &duplicate_commands }));

    const retained = try harness.runtime.canvasDisplayList(1, "canvas");
    try std.testing.expectEqual(@as(usize, 1), retained.commandCount());
    try std.testing.expectEqual(@as(?canvas.ObjectId, 1), retained.commands[0].objectId());
}

test "runtime validates canvas display list command limits" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-canvas-limits", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
        }
    };

    var harness: TestHarness() = undefined;
    harness.init(.{});
    harness.null_platform.gpu_surfaces = true;
    var app_state: TestApp = .{};
    try harness.start(app_state.app());

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(0, 0, 320, 240),
    });

    var commands: [max_canvas_commands_per_view + 1]canvas.CanvasCommand = undefined;
    for (&commands) |*command| command.* = .pop_opacity;
    try std.testing.expectError(error.CanvasCommandLimitReached, harness.runtime.setCanvasDisplayList(1, "canvas", .{ .commands = &commands }));
}
