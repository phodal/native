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

test "runtime retains canvas widget layout for automation semantics" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-semantics", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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

    const children = [_]canvas.Widget{.{
        .id = 2,
        .kind = .button,
        .frame = geometry.RectF.init(10, 12, 96, 32),
        .text = "Run",
        .semantics = .{ .label = "Run query" },
    }};
    var nodes: [4]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &children }, geometry.RectF.init(0, 0, 320, 240), &nodes);

    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    const info = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);
    try std.testing.expectEqual(@as(u64, 1), info.widget_revision);
    try std.testing.expectEqual(@as(usize, 2), info.widget_node_count);
    try std.testing.expectEqual(@as(usize, 1), info.widget_semantics_count);
    try std.testing.expect(harness.runtime.invalidated);
    try std.testing.expectEqual(@as(usize, 1), harness.runtime.pendingDirtyRegions().len);
    try std.testing.expectEqualDeep(geometry.RectF.init(59.5, 81.5, 97, 33), harness.runtime.pendingDirtyRegions()[0]);

    const retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqual(@as(usize, 2), retained.nodeCount());
    try std.testing.expectEqualStrings("Run", retained.nodes[1].widget.text);
    try std.testing.expectEqualStrings("Run query", retained.nodes[1].widget.semantics.label);
    try std.testing.expectEqual(@as(usize, 0), retained.nodes[1].widget.children.len);

    const snapshot = harness.runtime.automationSnapshot("Widgets");
    const canvas_view = testViewByLabel(snapshot.views, "canvas").?;
    try std.testing.expectEqual(@as(u64, 1), canvas_view.widget_revision);
    try std.testing.expectEqual(@as(usize, 1), snapshot.widgets.len);
    try std.testing.expectEqual(@as(u64, 2), snapshot.widgets[0].id);
    try std.testing.expectEqualStrings("button", snapshot.widgets[0].role);
    try std.testing.expectEqualStrings("Run query", snapshot.widgets[0].name);
    try std.testing.expectEqualDeep(geometry.RectF.init(60, 82, 96, 32), snapshot.widgets[0].bounds);
    try std.testing.expect(!snapshot.widgets[0].hovered);
    try std.testing.expect(!snapshot.widgets[0].pressed);
    try std.testing.expect(!snapshot.widgets[0].selected);
    try std.testing.expect(snapshot.widgets[0].actions.focus);
    try std.testing.expect(snapshot.widgets[0].actions.press);
    try std.testing.expect(!snapshot.widgets[0].actions.toggle);

    var a11y_buffer: [1024]u8 = undefined;
    var a11y_writer = std.Io.Writer.fixed(&a11y_buffer);
    try automation.snapshot.writeA11yText(snapshot, &a11y_writer);
    try std.testing.expect(std.mem.indexOf(u8, a11y_writer.buffered(), "@w1/canvas#2 role=button name=\"Run query\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, a11y_writer.buffered(), "actions=[focus,press]") != null);
}

test "runtime automation snapshot exposes canvas widget text ranges" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-text-range-semantics", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(20, 30, 240, 120),
    });

    const text_field = canvas.Widget{
        .id = 2,
        .kind = .text_field,
        .frame = geometry.RectF.init(12, 16, 180, 36),
        .text = "Deploy",
        .text_selection = .{ .anchor = 1, .focus = 4 },
        .text_composition = canvas.TextRange.init(2, 5),
        .semantics = .{ .label = "Release name" },
    };
    var nodes: [2]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &.{text_field} }, geometry.RectF.init(0, 0, 240, 120), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    const snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expectEqual(@as(usize, 1), snapshot.widgets.len);
    try std.testing.expectEqualStrings("textbox", snapshot.widgets[0].role);
    try std.testing.expectEqualStrings("Release name", snapshot.widgets[0].name);
    try std.testing.expectEqualStrings("Deploy", snapshot.widgets[0].text_value);
    try std.testing.expectEqualDeep(automation.snapshot.TextRange{ .start = 1, .end = 4 }, snapshot.widgets[0].text_selection.?);
    try std.testing.expectEqualDeep(automation.snapshot.TextRange{ .start = 2, .end = 5 }, snapshot.widgets[0].text_composition.?);

    var a11y_buffer: [1024]u8 = undefined;
    var a11y_writer = std.Io.Writer.fixed(&a11y_buffer);
    try automation.snapshot.writeA11yText(snapshot, &a11y_writer);
    try std.testing.expect(std.mem.indexOf(u8, a11y_writer.buffered(), "@w1/canvas#2 role=textbox name=\"Release name\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, a11y_writer.buffered(), "text=\"Deploy\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, a11y_writer.buffered(), "selection=1..4") != null);
    try std.testing.expect(std.mem.indexOf(u8, a11y_writer.buffered(), "composition=2..5") != null);
}

test "runtime emits canvas display list from focused widget layout" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-display-list", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(20, 30, 320, 240),
    });

    const children = [_]canvas.Widget{
        .{
            .id = 2,
            .kind = .button,
            .frame = geometry.RectF.init(10, 12, 96, 32),
            .text = "Run",
        },
        .{
            .id = 3,
            .kind = .button,
            .frame = geometry.RectF.init(10, 56, 96, 32),
            .text = "Stop",
            .state = .{ .hovered = true, .pressed = true, .focused = true },
        },
    };
    var nodes: [4]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &children }, geometry.RectF.init(0, 0, 320, 240), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_down,
        .x = 24,
        .y = 20,
    } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 2), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 2), harness.runtime.views[0].canvas_widget_hovered_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 2), harness.runtime.views[0].canvas_widget_pressed_id);

    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    const info = try harness.runtime.emitCanvasWidgetDisplayList(1, "canvas", .{
        .colors = .{
            .accent = canvas.Color.rgb8(10, 20, 30),
            .focus_ring = canvas.Color.rgb8(1, 2, 3),
        },
        .stroke = .{ .focus = 3 },
    });
    try std.testing.expectEqual(@as(u64, 1), info.canvas_revision);
    try std.testing.expectEqual(@as(usize, 6), info.canvas_command_count);
    try std.testing.expect(harness.runtime.invalidated);
    try std.testing.expect(harness.runtime.pendingDirtyRegions().len > 0);

    const retained = try harness.runtime.canvasDisplayList(1, "canvas");
    var saw_runtime_focus = false;
    var saw_stale_focus = false;
    var saw_run_text = false;
    for (retained.commands) |command| {
        if (command.objectId()) |id| {
            if (id == testCanvasWidgetPartId(2, 3)) saw_runtime_focus = true;
            if (id == testCanvasWidgetPartId(3, 3)) saw_stale_focus = true;
        }
        switch (command) {
            .fill_rounded_rect => |fill| {
                if (fill.id == testCanvasWidgetPartId(2, 1)) {
                    switch (fill.fill) {
                        .color => |color| try std.testing.expectEqualDeep(canvas.Color.rgb8(10, 20, 30), color),
                        else => return error.TestUnexpectedResult,
                    }
                }
            },
            .draw_text => |text| {
                if (text.id == testCanvasWidgetPartId(2, 4)) {
                    try std.testing.expectEqualStrings("Run", text.text);
                    saw_run_text = true;
                }
            },
            else => {},
        }
    }
    try std.testing.expect(!saw_runtime_focus);
    try std.testing.expect(!saw_stale_focus);
    try std.testing.expect(saw_run_text);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_up,
        .x = 24,
        .y = 20,
    } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 2), harness.runtime.views[0].canvas_widget_hovered_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 0), harness.runtime.views[0].canvas_widget_pressed_id);

    const changed_children = [_]canvas.Widget{.{
        .id = 2,
        .kind = .button,
        .frame = geometry.RectF.init(10, 12, 96, 32),
        .text = "Changed",
    }};
    var changed_nodes: [2]canvas.WidgetLayoutNode = undefined;
    const changed_layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &changed_children }, geometry.RectF.init(0, 0, 320, 240), &changed_nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", changed_layout);

    const retained_after_widget_update = try harness.runtime.canvasDisplayList(1, "canvas");
    var saw_changed_text = false;
    for (retained_after_widget_update.commands) |command| {
        switch (command) {
            .draw_text => |text| {
                if (text.id == testCanvasWidgetPartId(2, 4)) {
                    try std.testing.expectEqualStrings("Changed", text.text);
                    saw_changed_text = true;
                }
            },
            else => {},
        }
    }
    try std.testing.expect(saw_changed_text);

    var manual_commands: [1]canvas.CanvasCommand = undefined;
    var manual_builder = canvas.Builder.init(&manual_commands);
    try manual_builder.drawText(.{ .id = 900, .font_id = 1, .size = 12, .origin = geometry.PointF.init(4, 16), .color = canvas.Color.rgb8(1, 2, 3), .text = "Manual" });
    _ = try harness.runtime.setCanvasDisplayList(1, "canvas", manual_builder.displayList());

    const manual_changed_children = [_]canvas.Widget{.{
        .id = 2,
        .kind = .button,
        .frame = geometry.RectF.init(10, 12, 96, 32),
        .text = "Ignored",
    }};
    var manual_changed_nodes: [2]canvas.WidgetLayoutNode = undefined;
    const manual_changed_layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &manual_changed_children }, geometry.RectF.init(0, 0, 320, 240), &manual_changed_nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", manual_changed_layout);

    const manual_retained = try harness.runtime.canvasDisplayList(1, "canvas");
    try std.testing.expectEqual(@as(usize, 1), manual_retained.commandCount());
    switch (manual_retained.commands[0]) {
        .draw_text => |text| try std.testing.expectEqualStrings("Manual", text.text),
        else => return error.TestUnexpectedResult,
    }
}

test "runtime shows canvas widget focus rings only for keyboard-visible focus" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-view-focus-render-state", .source = platform.WebViewSource.html("<h1>GPU</h1>") };
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
        .frame = geometry.RectF.init(0, 0, 240, 120),
    });
    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "other",
        .kind = .button,
        .frame = geometry.RectF.init(260, 0, 80, 32),
        .text = "Other",
    });

    const children = [_]canvas.Widget{
        .{
            .id = 2,
            .kind = .button,
            .frame = geometry.RectF.init(10, 12, 96, 32),
            .text = "Run",
        },
        .{
            .id = 3,
            .kind = .button,
            .frame = geometry.RectF.init(10, 56, 96, 32),
            .text = "Stop",
        },
    };
    var nodes: [3]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &children }, geometry.RectF.init(0, 0, 240, 120), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);
    _ = try harness.runtime.emitCanvasWidgetDisplayList(1, "canvas", .{});

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_down,
        .x = 20,
        .y = 24,
    } });
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_up,
        .x = 20,
        .y = 24,
    } });
    try std.testing.expect(harness.runtime.views[0].focused);
    try std.testing.expectEqual(@as(canvas.ObjectId, 2), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 0), harness.runtime.views[0].canvas_widget_focus_visible_id);

    var display_list = try harness.runtime.canvasDisplayList(1, "canvas");
    var saw_focus_ring = false;
    for (display_list.commands) |command| {
        if (command.objectId()) |id| {
            if (id == testCanvasWidgetPartId(2, 3)) saw_focus_ring = true;
        }
    }
    try std.testing.expect(!saw_focus_ring);

    var snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expectEqual(@as(usize, 2), snapshot.widgets.len);
    try std.testing.expect(snapshot.widgets[0].focused);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "tab",
    } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 3), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 3), harness.runtime.views[0].canvas_widget_focus_visible_id);

    display_list = try harness.runtime.canvasDisplayList(1, "canvas");
    saw_focus_ring = false;
    for (display_list.commands) |command| {
        if (command.objectId()) |id| {
            if (id == testCanvasWidgetPartId(3, 3)) saw_focus_ring = true;
        }
    }
    try std.testing.expect(saw_focus_ring);

    snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expectEqual(@as(usize, 2), snapshot.widgets.len);
    try std.testing.expect(!snapshot.widgets[0].focused);
    try std.testing.expect(snapshot.widgets[1].focused);

    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    try harness.runtime.focusView(1, "other");
    try std.testing.expect(!harness.runtime.views[0].focused);
    try std.testing.expectEqual(@as(canvas.ObjectId, 3), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 3), harness.runtime.views[0].canvas_widget_focus_visible_id);
    try std.testing.expect(harness.runtime.invalidated);
    try std.testing.expect(harness.runtime.pendingDirtyRegions().len >= 1);

    display_list = try harness.runtime.canvasDisplayList(1, "canvas");
    saw_focus_ring = false;
    for (display_list.commands) |command| {
        if (command.objectId()) |id| {
            if (id == testCanvasWidgetPartId(3, 3)) saw_focus_ring = true;
        }
    }
    try std.testing.expect(!saw_focus_ring);

    snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expectEqual(@as(usize, 2), snapshot.widgets.len);
    try std.testing.expect(!snapshot.widgets[1].focused);

    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    try harness.runtime.focusView(1, "canvas");
    try std.testing.expect(harness.runtime.views[0].focused);
    try std.testing.expect(harness.runtime.invalidated);
    try std.testing.expect(harness.runtime.pendingDirtyRegions().len >= 1);

    display_list = try harness.runtime.canvasDisplayList(1, "canvas");
    saw_focus_ring = false;
    for (display_list.commands) |command| {
        if (command.objectId()) |id| {
            if (id == testCanvasWidgetPartId(3, 3)) saw_focus_ring = true;
        }
    }
    try std.testing.expect(saw_focus_ring);

    snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expectEqual(@as(usize, 2), snapshot.widgets.len);
    try std.testing.expect(snapshot.widgets[1].focused);
}

test "runtime ignores stale canvas widget keyboard focus when canvas view loses focus" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-view-focus-keyboard-route", .source = platform.WebViewSource.html("<h1>GPU</h1>") };
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
        .frame = geometry.RectF.init(0, 0, 240, 120),
    });
    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "other",
        .kind = .button,
        .frame = geometry.RectF.init(260, 0, 80, 32),
        .text = "Other",
    });

    const children = [_]canvas.Widget{.{
        .id = 2,
        .kind = .text_field,
        .frame = geometry.RectF.init(10, 12, 140, 32),
        .text = "Query",
    }};
    var nodes: [2]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &children }, geometry.RectF.init(0, 0, 240, 120), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_down,
        .x = 20,
        .y = 24,
    } });
    try std.testing.expect(harness.runtime.views[0].focused);
    try std.testing.expectEqual(@as(canvas.ObjectId, 2), harness.runtime.views[0].canvas_widget_focused_id);

    var route_buffer: [4]canvas.WidgetEventRouteEntry = undefined;
    const key_route = try harness.runtime.routeCanvasWidgetKeyboardInput(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "a",
        .text = "a",
    }, &route_buffer);
    try std.testing.expect(key_route != null);
    try std.testing.expectEqual(@as(canvas.ObjectId, 2), key_route.?.target.?.id);

    const text_route = try harness.runtime.routeCanvasWidgetTextInput(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "a",
        .text = "a",
    }, &route_buffer);
    try std.testing.expect(text_route != null);
    try std.testing.expectEqual(@as(canvas.ObjectId, 2), text_route.?.target.?.id);

    try harness.runtime.focusView(1, "other");
    try std.testing.expect(!harness.runtime.views[0].focused);
    try std.testing.expectEqual(@as(canvas.ObjectId, 2), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expect(try harness.runtime.routeCanvasWidgetKeyboardInput(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "a",
        .text = "a",
    }, &route_buffer) == null);
    try std.testing.expect(try harness.runtime.routeCanvasWidgetTextInput(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "a",
        .text = "a",
    }, &route_buffer) == null);
}

test "runtime clears focused canvas widget when layout replacement hides it" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-hidden-focus", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(50, 70, 320, 160),
    });

    const children = [_]canvas.Widget{.{
        .id = 2,
        .kind = .button,
        .frame = geometry.RectF.init(10, 10, 80, 32),
        .text = "Run",
    }};
    var nodes: [2]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &children }, geometry.RectF.init(0, 0, 320, 160), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    try harness.runtime.focusView(1, "canvas");
    harness.runtime.views[0].canvas_widget_focused_id = 2;
    harness.runtime.views[0].canvas_widget_focus_visible_id = 2;
    _ = try harness.runtime.emitCanvasWidgetDisplayList(1, "canvas", .{});

    const retained = try harness.runtime.canvasDisplayList(1, "canvas");
    var saw_focused_ring = false;
    for (retained.commands) |command| {
        if (command.objectId()) |id| {
            if (id == testCanvasWidgetPartId(2, 3)) saw_focused_ring = true;
        }
    }
    try std.testing.expect(saw_focused_ring);

    const hidden_children = [_]canvas.Widget{.{
        .id = 2,
        .kind = .button,
        .frame = geometry.RectF.init(10, 10, 80, 32),
        .text = "Run",
        .semantics = .{ .hidden = true },
    }};
    var hidden_nodes: [2]canvas.WidgetLayoutNode = undefined;
    const hidden_layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &hidden_children }, geometry.RectF.init(0, 0, 320, 160), &hidden_nodes);

    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", hidden_layout);

    try std.testing.expectEqual(@as(canvas.ObjectId, 0), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expect(harness.runtime.invalidated);
    try std.testing.expect(harness.runtime.pendingDirtyRegions().len >= 2);
    try std.testing.expectEqualDeep(geometry.RectF.init(59.5, 79.5, 81, 33), harness.runtime.pendingDirtyRegions()[0]);
    try std.testing.expectEqualDeep(geometry.RectF.init(59, 79, 82, 34), harness.runtime.pendingDirtyRegions()[1]);

    const retained_after_hide = try harness.runtime.canvasDisplayList(1, "canvas");
    var saw_stale_focused_ring = false;
    var saw_hidden_button_part = false;
    for (retained_after_hide.commands) |command| {
        if (command.objectId()) |id| {
            if (id == testCanvasWidgetPartId(2, 3)) saw_stale_focused_ring = true;
            if (id == testCanvasWidgetPartId(2, 1) or
                id == testCanvasWidgetPartId(2, 2) or
                id == testCanvasWidgetPartId(2, 4))
            {
                saw_hidden_button_part = true;
            }
        }
    }
    try std.testing.expect(!saw_stale_focused_ring);
    try std.testing.expect(!saw_hidden_button_part);
}

test "runtime dismisses nearest canvas floating surface with escape" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-surface-dismiss", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(20, 30, 360, 220),
    });

    const popover_children = [_]canvas.Widget{.{
        .id = 3,
        .kind = .button,
        .frame = geometry.RectF.init(16, 16, 100, 32),
        .text = "Copy",
    }};
    const dialog_children = [_]canvas.Widget{
        .{
            .id = 2,
            .kind = .popover,
            .frame = geometry.RectF.init(18, 52, 160, 96),
            .semantics = .{ .label = "Actions" },
            .children = &popover_children,
        },
        .{
            .id = 4,
            .kind = .button,
            .frame = geometry.RectF.init(196, 52, 100, 32),
            .text = "Keep",
        },
    };
    const dialog = canvas.Widget{
        .id = 1,
        .kind = .dialog,
        .frame = geometry.RectF.init(12, 12, 320, 180),
        .text = "Command palette",
        .semantics = .{ .label = "Command palette" },
        .children = &dialog_children,
    };
    var nodes: [4]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(dialog, dialog.frame, &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);
    try harness.runtime.focusView(1, "canvas");
    harness.runtime.views[0].canvas_widget_focused_id = 3;
    harness.runtime.views[0].canvas_widget_hovered_id = 3;
    harness.runtime.views[0].canvas_widget_pressed_id = 3;
    harness.runtime.views[0].canvas_widget_cursor = .pointing_hand;
    _ = try harness.runtime.emitCanvasWidgetDisplayList(1, "canvas", .{});
    try std.testing.expect((try harness.runtime.canvasDisplayList(1, "canvas")).findCommandById(testCanvasWidgetPartId(2, 2)) != null);

    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "escape",
    } });

    const retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expect(!retained.findById(1).?.widget.semantics.hidden);
    try std.testing.expect(retained.findById(2).?.widget.semantics.hidden);
    try std.testing.expectEqual(@as(canvas.ObjectId, 0), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 0), harness.runtime.views[0].canvas_widget_hovered_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 0), harness.runtime.views[0].canvas_widget_pressed_id);
    try std.testing.expectEqual(platform.Cursor.arrow, harness.runtime.views[0].canvas_widget_cursor);
    try std.testing.expect(harness.runtime.invalidated);

    for (runtimeViewWidgetSemantics(&harness.runtime.views[0])) |node| {
        try std.testing.expect(node.id != 2);
        try std.testing.expect(node.id != 3);
    }
    const retained_after_dismiss = try harness.runtime.canvasDisplayList(1, "canvas");
    try std.testing.expect(retained_after_dismiss.findCommandById(testCanvasWidgetPartId(2, 2)) == null);
    try std.testing.expect(retained_after_dismiss.findCommandById(testCanvasWidgetPartId(3, 1)) == null);
    try std.testing.expect(retained_after_dismiss.findCommandById(testCanvasWidgetPartId(1, 2)) != null);
    try std.testing.expect(retained_after_dismiss.findCommandById(testCanvasWidgetPartId(4, 1)) != null);
}

test "runtime dismisses canvas floating surfaces from automation and accessibility actions" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-surface-action-dismiss", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
        }
    };
    const Fixture = struct {
        fn install(runtime: *Runtime) !void {
            const popover_children = [_]canvas.Widget{.{
                .id = 3,
                .kind = .button,
                .frame = geometry.RectF.init(12, 12, 92, 30),
                .text = "Copy",
            }};
            const children = [_]canvas.Widget{
                .{
                    .id = 1,
                    .kind = .button,
                    .frame = geometry.RectF.init(12, 12, 104, 32),
                    .text = "Open",
                },
                .{
                    .id = 2,
                    .kind = .popover,
                    .frame = geometry.RectF.init(36, 52, 140, 76),
                    .semantics = .{ .label = "Actions" },
                    .children = &popover_children,
                },
            };
            var nodes: [4]canvas.WidgetLayoutNode = undefined;
            const layout = try canvas.layoutWidgetTree(.{ .id = 10, .kind = .stack, .children = &children }, geometry.RectF.init(0, 0, 220, 160), &nodes);
            _ = try runtime.setCanvasWidgetLayout(1, "canvas", layout);
        }

        fn snapshotWidget(snapshot: automation.snapshot.Input, id: u64) ?automation.snapshot.Widget {
            for (snapshot.widgets) |widget| {
                if (widget.id == id) return widget;
            }
            return null;
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
        .frame = geometry.RectF.init(20, 30, 260, 180),
    });

    try Fixture.install(&harness.runtime);
    var snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expect(Fixture.snapshotWidget(snapshot, 2).?.actions.dismiss);
    try std.testing.expect(!Fixture.snapshotWidget(snapshot, 1).?.actions.dismiss);
    try std.testing.expectError(error.InvalidCommand, dispatchAutomationWidgetAction(&harness.runtime, app, .{ .view_label = "canvas", .id = 1, .action = .dismiss }));

    try dispatchAutomationWidgetAction(&harness.runtime, app, .{ .view_label = "canvas", .id = 2, .action = .dismiss });
    var retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expect(retained.findById(2).?.widget.semantics.hidden);
    try std.testing.expect(canvasWidgetSemanticsById(runtimeViewWidgetSemantics(&harness.runtime.views[0]), 2) == null);
    try std.testing.expect(canvasWidgetSemanticsById(runtimeViewWidgetSemantics(&harness.runtime.views[0]), 3) == null);
    snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expect(Fixture.snapshotWidget(snapshot, 2) == null);
    try std.testing.expect(Fixture.snapshotWidget(snapshot, 3) == null);

    try Fixture.install(&harness.runtime);
    try harness.runtime.dispatchPlatformEvent(app, .{ .widget_accessibility_action = .{
        .window_id = 1,
        .label = "canvas",
        .id = 2,
        .action = .dismiss,
    } });
    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expect(retained.findById(2).?.widget.semantics.hidden);
    try std.testing.expect(canvasWidgetSemanticsById(runtimeViewWidgetSemantics(&harness.runtime.views[0]), 2) == null);
    try std.testing.expect(canvasWidgetSemanticsById(runtimeViewWidgetSemantics(&harness.runtime.views[0]), 3) == null);
}

test "runtime dismisses focused canvas floating surface from outside pointer down" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-surface-outside-dismiss", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(0, 0, 320, 180),
    });

    const popover_children = [_]canvas.Widget{.{
        .id = 3,
        .kind = .button,
        .frame = geometry.RectF.init(8, 8, 92, 32),
        .text = "Copy",
    }};
    const widgets = [_]canvas.Widget{
        .{
            .id = 2,
            .kind = .popover,
            .frame = geometry.RectF.init(20, 20, 128, 72),
            .children = &popover_children,
        },
        .{
            .id = 4,
            .kind = .button,
            .frame = geometry.RectF.init(176, 40, 92, 32),
            .text = "Outside",
        },
    };
    var nodes: [4]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &widgets }, geometry.RectF.init(0, 0, 320, 180), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);
    try harness.runtime.focusView(1, "canvas");
    harness.runtime.views[0].canvas_widget_focused_id = 3;
    harness.runtime.views[0].canvas_widget_hovered_id = 3;
    harness.runtime.views[0].canvas_widget_cursor = .pointing_hand;
    _ = try harness.runtime.emitCanvasWidgetDisplayList(1, "canvas", .{});

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_down,
        .x = 36,
        .y = 36,
    } });
    var retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expect(!retained.findById(2).?.widget.semantics.hidden);
    try std.testing.expectEqual(@as(canvas.ObjectId, 3), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 3), harness.runtime.views[0].canvas_widget_pressed_id);

    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_down,
        .x = 190,
        .y = 52,
    } });

    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expect(retained.findById(2).?.widget.semantics.hidden);
    try std.testing.expectEqual(@as(canvas.ObjectId, 4), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 4), harness.runtime.views[0].canvas_widget_hovered_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 4), harness.runtime.views[0].canvas_widget_pressed_id);
    try std.testing.expectEqual(platform.Cursor.pointing_hand, harness.runtime.views[0].canvas_widget_cursor);
    try std.testing.expect(harness.runtime.invalidated);

    for (runtimeViewWidgetSemantics(&harness.runtime.views[0])) |node| {
        try std.testing.expect(node.id != 2);
        try std.testing.expect(node.id != 3);
    }
    const retained_after_dismiss = try harness.runtime.canvasDisplayList(1, "canvas");
    try std.testing.expect(retained_after_dismiss.findCommandById(testCanvasWidgetPartId(2, 2)) == null);
    try std.testing.expect(retained_after_dismiss.findCommandById(testCanvasWidgetPartId(3, 1)) == null);
    try std.testing.expect(retained_after_dismiss.findCommandById(testCanvasWidgetPartId(4, 1)) != null);
}

test "runtime traps tab focus inside canvas floating surfaces" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-surface-focus-scope", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(0, 0, 360, 200),
    });

    const popover_children = [_]canvas.Widget{
        .{
            .id = 3,
            .kind = .button,
            .frame = geometry.RectF.init(12, 12, 96, 32),
            .text = "First",
        },
        .{
            .id = 4,
            .kind = .button,
            .frame = geometry.RectF.init(12, 52, 96, 32),
            .text = "Second",
        },
    };
    const widgets = [_]canvas.Widget{
        .{
            .id = 2,
            .kind = .button,
            .frame = geometry.RectF.init(10, 20, 90, 32),
            .text = "Before",
        },
        .{
            .id = 10,
            .kind = .popover,
            .frame = geometry.RectF.init(120, 20, 140, 104),
            .children = &popover_children,
        },
        .{
            .id = 5,
            .kind = .button,
            .frame = geometry.RectF.init(280, 20, 70, 32),
            .text = "After",
        },
    };
    var nodes: [6]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &widgets }, geometry.RectF.init(0, 0, 360, 200), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);
    try harness.runtime.focusView(1, "canvas");
    harness.runtime.views[0].canvas_widget_focused_id = 3;

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "tab",
    } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 4), harness.runtime.views[0].canvas_widget_focused_id);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "tab",
    } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 3), harness.runtime.views[0].canvas_widget_focused_id);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "tab",
        .modifiers = .{ .shift = true },
    } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 4), harness.runtime.views[0].canvas_widget_focused_id);
}

test "runtime keeps single focus target scoped inside canvas floating surface" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-surface-single-focus-scope", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(0, 0, 260, 140),
    });

    const popover_children = [_]canvas.Widget{.{
        .id = 3,
        .kind = .button,
        .frame = geometry.RectF.init(12, 12, 96, 32),
        .text = "Only",
    }};
    const widgets = [_]canvas.Widget{
        .{
            .id = 10,
            .kind = .popover,
            .frame = geometry.RectF.init(20, 20, 140, 64),
            .children = &popover_children,
        },
        .{
            .id = 4,
            .kind = .button,
            .frame = geometry.RectF.init(180, 20, 64, 32),
            .text = "After",
        },
    };
    var nodes: [4]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &widgets }, geometry.RectF.init(0, 0, 260, 140), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);
    try harness.runtime.focusView(1, "canvas");
    harness.runtime.views[0].canvas_widget_focused_id = 3;

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "tab",
    } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 3), harness.runtime.views[0].canvas_widget_focused_id);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "tab",
        .modifiers = .{ .shift = true },
    } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 3), harness.runtime.views[0].canvas_widget_focused_id);
}

test "runtime keeps floating surface open when escape cancels text composition" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-surface-dismiss-ime", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(0, 0, 260, 160),
    });

    const popover_children = [_]canvas.Widget{.{
        .id = 3,
        .kind = .text_field,
        .frame = geometry.RectF.init(12, 12, 140, 34),
        .text = "Cafe",
        .text_selection = canvas.TextSelection.collapsed(4),
        .text_composition = canvas.TextRange.init(2, 4),
    }};
    const popover = canvas.Widget{
        .id = 2,
        .kind = .popover,
        .frame = geometry.RectF.init(18, 18, 180, 72),
        .children = &popover_children,
    };
    var nodes: [2]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(popover, popover.frame, &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);
    try harness.runtime.focusView(1, "canvas");
    harness.runtime.views[0].canvas_widget_focused_id = 3;
    _ = try harness.runtime.emitCanvasWidgetDisplayList(1, "canvas", .{});

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "escape",
    } });

    const retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expect(!retained.findById(2).?.widget.semantics.hidden);
    try std.testing.expect(retained.findById(3).?.widget.text_composition == null);
    try std.testing.expectEqual(@as(canvas.ObjectId, 3), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expect((try harness.runtime.canvasDisplayList(1, "canvas")).findCommandById(testCanvasWidgetPartId(2, 2)) != null);
}

test "runtime clears canvas widget interaction state when layout replacement disables it" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-disabled-interaction", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(40, 50, 220, 120),
    });

    const children = [_]canvas.Widget{.{
        .id = 2,
        .kind = .button,
        .frame = geometry.RectF.init(10, 12, 96, 32),
        .text = "Run",
    }};
    var nodes: [2]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &children }, geometry.RectF.init(0, 0, 220, 120), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);
    _ = try harness.runtime.emitCanvasWidgetDisplayList(1, "canvas", .{});

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_down,
        .x = 20,
        .y = 24,
    } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 2), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 2), harness.runtime.views[0].canvas_widget_hovered_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 2), harness.runtime.views[0].canvas_widget_pressed_id);
    try std.testing.expectEqual(platform.Cursor.pointing_hand, harness.runtime.views[0].canvas_widget_cursor);

    const disabled_children = [_]canvas.Widget{.{
        .id = 2,
        .kind = .button,
        .frame = geometry.RectF.init(10, 12, 96, 32),
        .text = "Run",
        .state = .{ .disabled = true },
    }};
    var disabled_nodes: [2]canvas.WidgetLayoutNode = undefined;
    const disabled_layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &disabled_children }, geometry.RectF.init(0, 0, 220, 120), &disabled_nodes);

    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", disabled_layout);

    try std.testing.expectEqual(@as(canvas.ObjectId, 0), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 0), harness.runtime.views[0].canvas_widget_hovered_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 0), harness.runtime.views[0].canvas_widget_pressed_id);
    try std.testing.expectEqual(platform.Cursor.arrow, harness.runtime.views[0].canvas_widget_cursor);
    try std.testing.expect(harness.runtime.invalidated);
    try std.testing.expect(harness.runtime.pendingDirtyRegions().len >= 1);

    const snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expectEqual(@as(usize, 1), snapshot.widgets.len);
    try std.testing.expect(!snapshot.widgets[0].enabled);
    try std.testing.expect(!snapshot.widgets[0].focused);
    try std.testing.expect(!snapshot.widgets[0].hovered);
    try std.testing.expect(!snapshot.widgets[0].pressed);
}

test "runtime retains canvas widget design tokens" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-design-tokens", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(0, 0, 240, 120),
    });

    const button = canvas.Widget{
        .id = 2,
        .kind = .button,
        .frame = geometry.RectF.init(10, 12, 96, 32),
        .text = "Run",
        .state = .{ .selected = true },
    };
    var nodes: [2]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &.{button} }, geometry.RectF.init(0, 0, 240, 120), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    const tokens = canvas.DesignTokens{
        .colors = .{
            .accent = canvas.Color.rgb8(100, 20, 200),
            .accent_text = canvas.Color.rgb8(255, 250, 240),
        },
        .radius = .{ .md = 7 },
    };
    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    const themed = try harness.runtime.setCanvasWidgetDesignTokens(1, "canvas", tokens);
    try std.testing.expectEqual(@as(u64, 2), themed.widget_revision);
    try std.testing.expectEqualDeep(tokens, try harness.runtime.canvasWidgetDesignTokens(1, "canvas"));
    try std.testing.expect(!harness.runtime.invalidated);
    try std.testing.expectEqual(@as(usize, 0), harness.runtime.pendingDirtyRegions().len);

    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    const unchanged = try harness.runtime.setCanvasWidgetDesignTokens(1, "canvas", tokens);
    try std.testing.expectEqual(@as(u64, 2), unchanged.widget_revision);
    try std.testing.expect(!harness.runtime.invalidated);
    try std.testing.expectEqual(@as(usize, 0), harness.runtime.pendingDirtyRegions().len);

    _ = try harness.runtime.emitCanvasWidgetDisplayListWithStoredTokens(1, "canvas");
    const display_list = try harness.runtime.canvasDisplayList(1, "canvas");
    var saw_accent_fill = false;
    var saw_accent_text = false;
    for (display_list.commands) |command| {
        switch (command) {
            .fill_rounded_rect => |fill| {
                if (fill.id == testCanvasWidgetPartId(2, 1)) {
                    switch (fill.fill) {
                        .color => |color| try std.testing.expectEqualDeep(tokens.colors.accent, color),
                        else => return error.TestUnexpectedResult,
                    }
                    saw_accent_fill = true;
                }
            },
            .draw_text => |text| {
                if (text.id == testCanvasWidgetPartId(2, 4)) {
                    try std.testing.expectEqualDeep(tokens.colors.accent_text, text.color);
                    saw_accent_text = true;
                }
            },
            else => {},
        }
    }
    try std.testing.expect(saw_accent_fill);
    try std.testing.expect(saw_accent_text);

    const next_tokens = canvas.DesignTokens{
        .colors = .{
            .accent = canvas.Color.rgb8(20, 120, 80),
            .accent_text = canvas.Color.rgb8(240, 255, 250),
        },
    };
    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    const changed = try harness.runtime.setCanvasWidgetDesignTokens(1, "canvas", next_tokens);
    try std.testing.expectEqual(@as(u64, 3), changed.widget_revision);
    try std.testing.expect(harness.runtime.invalidated);
    try std.testing.expect(harness.runtime.pendingDirtyRegions().len >= 1);
    _ = try harness.runtime.emitCanvasWidgetDisplayListWithStoredTokens(1, "canvas");
    const changed_display_list = try harness.runtime.canvasDisplayList(1, "canvas");
    for (changed_display_list.commands) |command| {
        switch (command) {
            .fill_rounded_rect => |fill| {
                if (fill.id == testCanvasWidgetPartId(2, 1)) {
                    switch (fill.fill) {
                        .color => |color| try std.testing.expectEqualDeep(next_tokens.colors.accent, color),
                        else => return error.TestUnexpectedResult,
                    }
                    return;
                }
            },
            else => {},
        }
    }
    return error.TestUnexpectedResult;
}

test "runtime wheel input scrolls retained canvas scroll views" {
    const TestApp = struct {
        widget_pointer_count: u32 = 0,
        raw_input_count: u32 = 0,
        last_phase: canvas.WidgetPointerPhase = .hover,
        last_target_id: canvas.ObjectId = 0,

        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-scroll", .source = platform.WebViewSource.html("<h1>Hello</h1>"), .event_fn = event };
        }

        fn event(context: *anyopaque, runtime: *Runtime, event_value: Event) anyerror!void {
            _ = runtime;
            const self: *@This() = @ptrCast(@alignCast(context));
            switch (event_value) {
                .canvas_widget_pointer => |pointer_event| {
                    self.widget_pointer_count += 1;
                    self.last_phase = pointer_event.pointer.phase;
                    self.last_target_id = if (pointer_event.target) |target| target.id else 0;
                },
                .gpu_surface_input => self.raw_input_count += 1,
                else => {},
            }
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
        .frame = geometry.RectF.init(10, 20, 180, 72),
    });

    const children = [_]canvas.Widget{
        .{ .id = 2, .kind = .button, .frame = geometry.RectF.init(0, 0, 0, 32), .text = "One" },
        .{ .id = 3, .kind = .button, .frame = geometry.RectF.init(0, 44, 0, 32), .text = "Two" },
        .{ .id = 4, .kind = .button, .frame = geometry.RectF.init(0, 88, 0, 32), .text = "Three" },
    };
    const scroll = canvas.Widget{
        .id = 1,
        .kind = .scroll_view,
        .children = &children,
    };
    var nodes: [5]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(scroll, geometry.RectF.init(0, 0, 180, 72), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .timestamp_ns = 1_000_000_000,
        .kind = .scroll,
        .x = 20,
        .y = 20,
        .delta_y = 24,
    } });

    try std.testing.expectEqual(@as(u32, 1), app_state.widget_pointer_count);
    try std.testing.expectEqual(@as(u32, 1), app_state.raw_input_count);
    try std.testing.expectEqual(canvas.WidgetPointerPhase.wheel, app_state.last_phase);
    try std.testing.expectEqual(@as(canvas.ObjectId, 2), app_state.last_target_id);
    try std.testing.expect(harness.runtime.invalidated);
    try std.testing.expectEqual(@as(usize, 1), harness.runtime.pendingDirtyRegions().len);
    try std.testing.expectEqualDeep(geometry.RectF.init(10, 20, 180, 72), harness.runtime.pendingDirtyRegions()[0]);

    const retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqual(@as(f32, 24), retained.nodes[0].widget.value);
    try std.testing.expectEqualDeep(geometry.RectF.init(0, -24, 180, 32), retained.nodes[1].frame);
    try std.testing.expectEqualDeep(geometry.RectF.init(0, 20, 180, 32), retained.nodes[2].frame);
    try std.testing.expectEqualDeep(geometry.RectF.init(0, 64, 180, 32), retained.nodes[3].frame);
    try std.testing.expectEqual(@as(u64, 2), harness.runtime.views[0].widget_revision);

    const snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expectEqual(@as(usize, 4), snapshot.widgets.len);
    try std.testing.expectEqual(@as(?f32, 0.5), snapshot.widgets[0].value);
    try std.testing.expect(snapshot.widgets[0].scroll.present);
    try std.testing.expectEqual(@as(f32, 24.0), snapshot.widgets[0].scroll.offset);
    try std.testing.expectEqual(@as(f32, 72.0), snapshot.widgets[0].scroll.viewport_extent);
    try std.testing.expectEqual(@as(f32, 120.0), snapshot.widgets[0].scroll.content_extent);
    try std.testing.expect(snapshot.widgets[0].actions.focus);
    try std.testing.expect(snapshot.widgets[0].actions.increment);
    try std.testing.expect(snapshot.widgets[0].actions.decrement);
    try std.testing.expectEqualDeep(geometry.RectF.init(10, -4, 180, 32), snapshot.widgets[1].bounds);
    try std.testing.expectEqualDeep(geometry.RectF.init(10, 40, 180, 32), snapshot.widgets[2].bounds);

    var a11y_buffer: [2048]u8 = undefined;
    var a11y_writer = std.Io.Writer.fixed(&a11y_buffer);
    try automation.snapshot.writeA11yText(snapshot, &a11y_writer);
    try std.testing.expect(std.mem.indexOf(u8, a11y_writer.buffered(), "@w1/canvas#1 role=group") != null);
    try std.testing.expect(std.mem.indexOf(u8, a11y_writer.buffered(), "value=0.5") != null);
    try std.testing.expect(std.mem.indexOf(u8, a11y_writer.buffered(), "scroll=[offset=24,viewport=72,content=120]") != null);
    try std.testing.expect(std.mem.indexOf(u8, a11y_writer.buffered(), "actions=[focus,increment,decrement]") != null);

    _ = try harness.runtime.emitCanvasWidgetDisplayList(1, "canvas", .{});
    const display_list = try harness.runtime.canvasDisplayList(1, "canvas");
    var saw_scrolled_button = false;
    for (display_list.commands) |command| {
        switch (command) {
            .fill_rounded_rect => |fill| {
                if (fill.id == testCanvasWidgetPartId(3, 1)) {
                    try std.testing.expectEqualDeep(geometry.RectF.init(0, 20, 180, 32), fill.rect);
                    saw_scrolled_button = true;
                }
            },
            else => {},
        }
    }
    try std.testing.expect(saw_scrolled_button);

    try std.testing.expect(harness.runtime.views[0].widget_scroll_states[0].velocity > 0);
    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    harness.null_platform.gpu_surface_frame_request_count = 0;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_frame = .{
        .label = "canvas",
        .size = geometry.SizeF.init(180, 72),
        .scale_factor = 2,
        .frame_index = 1,
        .timestamp_ns = 1_016_000_000,
        .frame_interval_ns = 16_000_000,
        .nonblank = true,
    } });
    var kinetic_layout = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqual(@as(f32, 24), kinetic_layout.nodes[0].widget.value);
    try std.testing.expectEqual(@as(usize, 1), harness.null_platform.gpu_surface_frame_request_count);

    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    harness.null_platform.gpu_surface_frame_request_count = 0;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_frame = .{
        .label = "canvas",
        .size = geometry.SizeF.init(180, 72),
        .scale_factor = 2,
        .frame_index = 2,
        .timestamp_ns = 1_032_000_000,
        .frame_interval_ns = 16_000_000,
        .nonblank = true,
    } });
    const kinetic = try harness.runtime.gpuSurfaceFrame(1, "canvas");
    try std.testing.expectEqual(@as(u64, 3), kinetic.widget_revision);
    try std.testing.expect(harness.runtime.invalidated);
    try std.testing.expect(harness.runtime.pendingDirtyRegions().len >= 1);
    try std.testing.expectEqualDeep(geometry.RectF.init(10, 20, 180, 72), harness.runtime.pendingDirtyRegions()[0]);
    try std.testing.expectEqual(@as(usize, 1), harness.null_platform.gpu_surface_frame_request_count);

    kinetic_layout = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectApproxEqAbs(@as(f32, 47.04), kinetic_layout.nodes[0].widget.value, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, -47.04), kinetic_layout.nodes[1].frame.y, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, -3.04), kinetic_layout.nodes[2].frame.y, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 40.96), kinetic_layout.nodes[3].frame.y, 0.01);
    try std.testing.expect(harness.runtime.views[0].widget_scroll_states[0].velocity > 0);

    const kinetic_display_list = try harness.runtime.canvasDisplayList(1, "canvas");
    var saw_kinetic_scrolled_button = false;
    for (kinetic_display_list.commands) |command| {
        switch (command) {
            .fill_rounded_rect => |fill| {
                if (fill.id == testCanvasWidgetPartId(3, 1)) {
                    try std.testing.expectApproxEqAbs(@as(f32, -3.04), fill.rect.y, 0.01);
                    saw_kinetic_scrolled_button = true;
                }
            },
            else => {},
        }
    }
    try std.testing.expect(saw_kinetic_scrolled_button);

    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    const clamped = try harness.runtime.stepCanvasWidgetKineticScroll(1, "canvas", 16);
    try std.testing.expectEqual(@as(u64, 4), clamped.widget_revision);
    try std.testing.expect(harness.runtime.invalidated);
    try std.testing.expect(harness.runtime.pendingDirtyRegions().len >= 1);
    try std.testing.expectEqualDeep(geometry.RectF.init(10, 20, 180, 72), harness.runtime.pendingDirtyRegions()[0]);

    kinetic_layout = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectApproxEqAbs(@as(f32, 48), kinetic_layout.nodes[0].widget.value, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, -48), kinetic_layout.nodes[1].frame.y, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, -4), kinetic_layout.nodes[2].frame.y, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 40), kinetic_layout.nodes[3].frame.y, 0.01);
    try std.testing.expectEqual(@as(f32, 0), harness.runtime.views[0].widget_scroll_states[0].velocity);

    var settle_frame: usize = 0;
    while (settle_frame < 48) : (settle_frame += 1) {
        harness.runtime.invalidated = false;
        harness.runtime.dirty_region_count = 0;
        _ = try harness.runtime.stepCanvasWidgetKineticScroll(1, "canvas", 16);
        kinetic_layout = try harness.runtime.canvasWidgetLayout(1, "canvas");
        if (@abs(kinetic_layout.nodes[0].widget.value - 48) <= 0.01 and harness.runtime.views[0].widget_scroll_states[0].velocity == 0) break;
    }

    try std.testing.expect(settle_frame < 48);
    try std.testing.expectApproxEqAbs(@as(f32, 48), kinetic_layout.nodes[0].widget.value, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, -48), kinetic_layout.nodes[1].frame.y, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, -4), kinetic_layout.nodes[2].frame.y, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 40), kinetic_layout.nodes[3].frame.y, 0.01);
    try std.testing.expectEqual(@as(f32, 0), harness.runtime.views[0].widget_scroll_states[0].velocity);

    const settled_revision = harness.runtime.views[0].widget_revision;
    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    const idle = try harness.runtime.stepCanvasWidgetKineticScroll(1, "canvas", 16);
    try std.testing.expectEqual(settled_revision, idle.widget_revision);
    try std.testing.expect(!harness.runtime.invalidated);
    try std.testing.expectEqual(@as(usize, 0), harness.runtime.pendingDirtyRegions().len);
}

test "runtime wheel over virtualized scroll does not bubble to parent scroll view" {
    const TestApp = struct {
        widget_pointer_count: u32 = 0,

        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-virtual-scroll-bubble", .source = platform.WebViewSource.html("<h1>Hello</h1>"), .event_fn = event };
        }

        fn event(context: *anyopaque, runtime: *Runtime, event_value: Event) anyerror!void {
            _ = runtime;
            const self: *@This() = @ptrCast(@alignCast(context));
            switch (event_value) {
                .canvas_widget_pointer => |pointer_event| if (pointer_event.pointer.phase == .wheel) {
                    self.widget_pointer_count += 1;
                },
                else => {},
            }
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
        .frame = geometry.RectF.init(0, 0, 180, 72),
    });

    const virtual_children = [_]canvas.Widget{
        .{ .id = 3, .kind = .list_item, .text = "One" },
        .{ .id = 4, .kind = .list_item, .text = "Two" },
        .{ .id = 5, .kind = .list_item, .text = "Three" },
        .{ .id = 6, .kind = .list_item, .text = "Four" },
    };
    const parent_children = [_]canvas.Widget{
        .{
            .id = 2,
            .kind = .scroll_view,
            .frame = geometry.RectF.init(0, 0, 180, 40),
            .layout = .{ .virtualized = true, .virtual_item_extent = 20 },
            .children = &virtual_children,
        },
        .{ .id = 20, .kind = .button, .frame = geometry.RectF.init(0, 120, 0, 32), .text = "Below" },
    };
    const parent_scroll = canvas.Widget{
        .id = 1,
        .kind = .scroll_view,
        .children = &parent_children,
    };
    var nodes: [8]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(parent_scroll, geometry.RectF.init(0, 0, 180, 72), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    const initial_revision = harness.runtime.views[0].widget_revision;
    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .timestamp_ns = 1_000_000_000,
        .kind = .scroll,
        .x = 20,
        .y = 20,
        .delta_y = 24,
    } });

    try std.testing.expectEqual(@as(u32, 1), app_state.widget_pointer_count);
    const retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqual(@as(f32, 0), retained.findById(1).?.widget.value);
    try std.testing.expectEqual(@as(f32, 0), retained.findById(2).?.widget.value);
    try std.testing.expectEqual(initial_revision, harness.runtime.views[0].widget_revision);
    try std.testing.expect(!harness.runtime.invalidated);
    try std.testing.expectEqual(@as(usize, 0), harness.runtime.pendingDirtyRegions().len);
}

test "runtime automation widget wheel timestamps retained canvas scroll input" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-wheel-automation", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(0, 0, 180, 64),
    });

    const children = [_]canvas.Widget{
        .{ .id = 2, .kind = .button, .frame = geometry.RectF.init(0, 0, 0, 32), .text = "One" },
        .{ .id = 3, .kind = .button, .frame = geometry.RectF.init(0, 40, 0, 32), .text = "Two" },
        .{ .id = 4, .kind = .button, .frame = geometry.RectF.init(0, 80, 0, 32), .text = "Three" },
    };
    var nodes: [4]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .id = 1, .kind = .scroll_view, .children = &children }, geometry.RectF.init(0, 0, 180, 64), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    try harness.runtime.dispatchAutomationCommand(app, "widget-wheel canvas 1 18");
    try std.testing.expect(harness.runtime.views[0].gpu_input_timestamp_ns > 0);
    try std.testing.expectEqual(harness.runtime.views[0].gpu_input_timestamp_ns, harness.runtime.views[0].gpu_pending_input_timestamp_ns);
    try std.testing.expect(harness.runtime.invalidated);

    const retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqual(@as(f32, 18), retained.findById(1).?.widget.value);
    try std.testing.expectEqual(@as(u64, 2), harness.runtime.views[0].widget_revision);
}

test "runtime automation widget key inputs route to focused canvas widgets" {
    const TestApp = struct {
        command_count: u32 = 0,
        last_command: []const u8 = "",
        last_source: CommandSource = .runtime,
        last_view_label: []const u8 = "",

        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-key-automation", .source = platform.WebViewSource.html("<h1>Hello</h1>"), .event_fn = event };
        }

        fn event(context: *anyopaque, runtime: *Runtime, event_value: Event) anyerror!void {
            _ = runtime;
            const self: *@This() = @ptrCast(@alignCast(context));
            switch (event_value) {
                .command => |command| {
                    self.command_count += 1;
                    self.last_command = command.name;
                    self.last_source = command.source;
                    self.last_view_label = command.view_label;
                },
                else => {},
            }
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
        .frame = geometry.RectF.init(0, 0, 240, 120),
    });

    const children = [_]canvas.Widget{
        .{ .id = 2, .kind = .text_field, .frame = geometry.RectF.init(12, 16, 160, 36), .text = "Draft" },
        .{ .id = 3, .kind = .button, .frame = geometry.RectF.init(12, 64, 96, 32), .text = "Run", .command = "app.run" },
    };
    var nodes: [3]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &children }, geometry.RectF.init(0, 0, 240, 120), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    try harness.runtime.dispatchAutomationCommand(app, "widget-action canvas 2 focus");
    try harness.runtime.dispatchAutomationCommand(app, "widget-key canvas a a");

    const retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqual(@as(canvas.ObjectId, 2), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expectEqualStrings("Drafta", retained.findById(2).?.widget.text);
    try std.testing.expectEqualDeep(canvas.TextSelection.collapsed(6), retained.findById(2).?.widget.text_selection.?);

    try harness.runtime.dispatchAutomationCommand(app, "widget-key canvas tab");
    try std.testing.expectEqual(@as(canvas.ObjectId, 3), harness.runtime.views[0].canvas_widget_focused_id);
    const snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expect(!snapshot.widgets[0].focused);
    try std.testing.expect(snapshot.widgets[1].focused);

    try harness.runtime.dispatchAutomationCommand(app, "widget-key canvas enter");
    try std.testing.expectEqual(@as(u32, 1), app_state.command_count);
    try std.testing.expectEqualStrings("app.run", app_state.last_command);
    try std.testing.expectEqual(CommandSource.native_view, app_state.last_source);
    try std.testing.expectEqualStrings("canvas", app_state.last_view_label);
}

test "runtime applies stored design token scroll physics" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-token-scroll", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(10, 20, 180, 72),
    });

    const children = [_]canvas.Widget{
        .{ .id = 2, .kind = .button, .frame = geometry.RectF.init(0, 0, 0, 32), .text = "One" },
        .{ .id = 3, .kind = .button, .frame = geometry.RectF.init(0, 44, 0, 32), .text = "Two" },
        .{ .id = 4, .kind = .button, .frame = geometry.RectF.init(0, 88, 0, 32), .text = "Three" },
    };
    const scroll = canvas.Widget{
        .id = 1,
        .kind = .scroll_view,
        .children = &children,
    };
    var nodes: [5]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(scroll, geometry.RectF.init(0, 0, 180, 72), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    const tokens = canvas.DesignTokens{
        .scroll = .{
            .wheel_multiplier = 0.5,
            .wheel_velocity_scale = 4,
            .deceleration_per_second = 1,
            .stop_velocity = 0,
        },
    };
    _ = try harness.runtime.setCanvasWidgetDesignTokens(1, "canvas", tokens);
    try std.testing.expectEqualDeep(tokens, try harness.runtime.canvasWidgetDesignTokens(1, "canvas"));

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .scroll,
        .x = 20,
        .y = 20,
        .delta_y = 40,
    } });

    var retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqual(@as(f32, 20), retained.nodes[0].widget.value);
    try std.testing.expectEqual(@as(f32, -20), retained.nodes[1].frame.y);
    try std.testing.expectEqual(@as(f32, 80), harness.runtime.views[0].widget_scroll_states[0].velocity);

    _ = try harness.runtime.stepCanvasWidgetKineticScroll(1, "canvas", 16);
    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectApproxEqAbs(@as(f32, 21.28), retained.nodes[0].widget.value, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -21.28), retained.nodes[1].frame.y, 0.001);
    try std.testing.expectEqual(@as(f32, 80), harness.runtime.views[0].widget_scroll_states[0].velocity);
}

test "runtime refreshes hovered canvas widget after scroll clipping" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-scroll-hover", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(10, 20, 160, 40),
    });

    const children = [_]canvas.Widget{
        .{ .id = 2, .kind = .button, .frame = geometry.RectF.init(0, 0, 0, 32), .text = "One" },
        .{ .id = 3, .kind = .button, .frame = geometry.RectF.init(0, 48, 0, 32), .text = "Two" },
    };
    var nodes: [3]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(
        .{ .id = 1, .kind = .scroll_view, .children = &children },
        geometry.RectF.init(0, 0, 160, 40),
        &nodes,
    );
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_move,
        .x = 12,
        .y = 12,
    } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 2), harness.runtime.views[0].canvas_widget_hovered_id);
    try std.testing.expectEqual(platform.Cursor.pointing_hand, harness.runtime.views[0].canvas_widget_cursor);

    var snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expect(snapshot.widgets[1].hovered);
    try std.testing.expect(!snapshot.widgets[2].hovered);

    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .scroll,
        .x = 12,
        .y = 12,
        .delta_y = 40,
    } });

    const retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualDeep(geometry.RectF.init(0, -40, 160, 32), retained.findById(2).?.frame);
    try std.testing.expectEqualDeep(geometry.RectF.init(0, 8, 160, 32), retained.findById(3).?.frame);
    try std.testing.expectEqual(@as(canvas.ObjectId, 3), harness.runtime.views[0].canvas_widget_hovered_id);
    try std.testing.expectEqual(platform.Cursor.pointing_hand, harness.runtime.views[0].canvas_widget_cursor);
    try std.testing.expect(harness.runtime.invalidated);
    try std.testing.expectEqual(@as(usize, 1), harness.runtime.pendingDirtyRegions().len);
    try std.testing.expectEqualDeep(geometry.RectF.init(10, 20, 160, 40), harness.runtime.pendingDirtyRegions()[0]);

    snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expect(!snapshot.widgets[1].hovered);
    try std.testing.expect(snapshot.widgets[2].hovered);
}

test "runtime clears focused canvas widget after scroll clipping" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-scroll-focus", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(10, 20, 160, 40),
    });

    const children = [_]canvas.Widget{
        .{ .id = 2, .kind = .button, .frame = geometry.RectF.init(0, 0, 0, 32), .text = "One" },
        .{ .id = 3, .kind = .button, .frame = geometry.RectF.init(0, 48, 0, 32), .text = "Two" },
    };
    var nodes: [3]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(
        .{ .id = 1, .kind = .scroll_view, .children = &children },
        geometry.RectF.init(0, 0, 160, 40),
        &nodes,
    );
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);
    try harness.runtime.focusView(1, "canvas");
    harness.runtime.views[0].canvas_widget_focused_id = 2;
    harness.runtime.views[0].canvas_widget_focus_visible_id = 2;
    _ = try harness.runtime.emitCanvasWidgetDisplayList(1, "canvas", .{});

    var route_buffer: [4]canvas.WidgetEventRouteEntry = undefined;
    const initial_route = try harness.runtime.routeCanvasWidgetKeyboardInput(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "enter",
    }, &route_buffer);
    try std.testing.expect(initial_route != null);
    try std.testing.expectEqual(@as(canvas.ObjectId, 2), initial_route.?.target.?.id);

    var display_list = try harness.runtime.canvasDisplayList(1, "canvas");
    var saw_focus_ring = false;
    for (display_list.commands) |command| {
        if (command.objectId()) |id| {
            if (id == testCanvasWidgetPartId(2, 3)) saw_focus_ring = true;
        }
    }
    try std.testing.expect(saw_focus_ring);

    var snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expect(snapshot.widgets[1].focused);

    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .scroll,
        .x = 12,
        .y = 12,
        .delta_y = 40,
    } });

    const retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualDeep(geometry.RectF.init(0, -40, 160, 32), retained.findById(2).?.frame);
    try std.testing.expectEqualDeep(geometry.RectF.init(0, 8, 160, 32), retained.findById(3).?.frame);
    try std.testing.expectEqual(@as(canvas.ObjectId, 0), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expect(try harness.runtime.routeCanvasWidgetKeyboardInput(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "enter",
    }, &route_buffer) == null);

    display_list = try harness.runtime.canvasDisplayList(1, "canvas");
    saw_focus_ring = false;
    for (display_list.commands) |command| {
        if (command.objectId()) |id| {
            if (id == testCanvasWidgetPartId(2, 3)) saw_focus_ring = true;
        }
    }
    try std.testing.expect(!saw_focus_ring);

    snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expect(!snapshot.widgets[1].focused);
    try std.testing.expect(!snapshot.widgets[2].focused);
    try std.testing.expect(harness.runtime.invalidated);
    try std.testing.expect(harness.runtime.pendingDirtyRegions().len >= 1);
    try std.testing.expectEqualDeep(geometry.RectF.init(10, 20, 160, 40), harness.runtime.pendingDirtyRegions()[0]);
}

test "runtime clears focused canvas widget after kinetic scroll clipping" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-kinetic-focus", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(10, 20, 160, 40),
    });

    const children = [_]canvas.Widget{
        .{ .id = 2, .kind = .button, .frame = geometry.RectF.init(0, 0, 0, 32), .text = "One" },
        .{ .id = 3, .kind = .button, .frame = geometry.RectF.init(0, 48, 0, 32), .text = "Two" },
    };
    var nodes: [3]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(
        .{ .id = 1, .kind = .scroll_view, .children = &children },
        geometry.RectF.init(0, 0, 160, 40),
        &nodes,
    );
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);
    try harness.runtime.focusView(1, "canvas");
    harness.runtime.views[0].canvas_widget_focused_id = 2;
    harness.runtime.views[0].widget_scroll_states[0].velocity = 2500;
    _ = try harness.runtime.emitCanvasWidgetDisplayList(1, "canvas", .{});

    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    const frame = try harness.runtime.stepCanvasWidgetKineticScroll(1, "canvas", 16);
    try std.testing.expectEqual(@as(canvas.ObjectId, 0), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expectEqual(@as(u64, 2), frame.widget_revision);
    try std.testing.expect(harness.runtime.invalidated);
    try std.testing.expect(harness.runtime.pendingDirtyRegions().len >= 1);
    try std.testing.expectEqualDeep(geometry.RectF.init(10, 20, 160, 40), harness.runtime.pendingDirtyRegions()[0]);

    const retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqual(@as(f32, 40), retained.findById(1).?.widget.value);
    try std.testing.expectEqualDeep(geometry.RectF.init(0, -40, 160, 32), retained.findById(2).?.frame);
    try std.testing.expectEqualDeep(geometry.RectF.init(0, 8, 160, 32), retained.findById(3).?.frame);

    const snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expect(!snapshot.widgets[1].focused);
    try std.testing.expect(!snapshot.widgets[2].focused);

    const display_list = try harness.runtime.canvasDisplayList(1, "canvas");
    for (display_list.commands) |command| {
        if (command.objectId()) |id| {
            try std.testing.expect(id != testCanvasWidgetPartId(2, 3));
        }
    }
}

test "runtime reconciles canvas widget render state after keyboard scroll clipping" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-keyboard-scroll-state", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(10, 20, 160, 40),
    });

    const children = [_]canvas.Widget{
        .{ .id = 2, .kind = .button, .frame = geometry.RectF.init(0, 0, 0, 32), .text = "One" },
        .{ .id = 3, .kind = .button, .frame = geometry.RectF.init(0, 48, 0, 32), .text = "Two" },
    };
    var nodes: [3]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(
        .{ .id = 1, .kind = .scroll_view, .children = &children },
        geometry.RectF.init(0, 0, 160, 40),
        &nodes,
    );
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);
    try harness.runtime.focusView(1, "canvas");
    harness.runtime.views[0].canvas_widget_focused_id = 1;
    harness.runtime.views[0].canvas_widget_hovered_id = 2;
    harness.runtime.views[0].canvas_widget_cursor = .pointing_hand;
    _ = try harness.runtime.emitCanvasWidgetDisplayList(1, "canvas", .{});

    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "pagedown",
    } });

    try std.testing.expectEqual(@as(canvas.ObjectId, 1), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 0), harness.runtime.views[0].canvas_widget_hovered_id);
    try std.testing.expectEqual(platform.Cursor.arrow, harness.runtime.views[0].canvas_widget_cursor);
    try std.testing.expect(harness.runtime.invalidated);
    try std.testing.expect(harness.runtime.pendingDirtyRegions().len >= 1);
    try std.testing.expectEqualDeep(geometry.RectF.init(10, 20, 160, 40), harness.runtime.pendingDirtyRegions()[0]);

    const retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqual(@as(f32, 34), retained.findById(1).?.widget.value);
    try std.testing.expectEqualDeep(geometry.RectF.init(0, -34, 160, 32), retained.findById(2).?.frame);
    try std.testing.expectEqualDeep(geometry.RectF.init(0, 14, 160, 32), retained.findById(3).?.frame);

    const snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expect(snapshot.widgets[0].focused);
    try std.testing.expect(!snapshot.widgets[1].hovered);
    try std.testing.expect(!snapshot.widgets[2].hovered);

    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "end",
    } });
    var keyboard_scrolled = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqual(@as(f32, 40), keyboard_scrolled.findById(1).?.widget.value);
    try std.testing.expectEqualDeep(geometry.RectF.init(0, -40, 160, 32), keyboard_scrolled.findById(2).?.frame);
    try std.testing.expectEqualDeep(geometry.RectF.init(0, 8, 160, 32), keyboard_scrolled.findById(3).?.frame);
    try std.testing.expect(harness.runtime.invalidated);
    try std.testing.expect(harness.runtime.pendingDirtyRegions().len >= 1);

    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "home",
    } });
    keyboard_scrolled = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqual(@as(f32, 0), keyboard_scrolled.findById(1).?.widget.value);
    try std.testing.expectEqualDeep(geometry.RectF.init(0, 0, 160, 32), keyboard_scrolled.findById(2).?.frame);
    try std.testing.expectEqualDeep(geometry.RectF.init(0, 48, 160, 32), keyboard_scrolled.findById(3).?.frame);
    try std.testing.expect(harness.runtime.invalidated);
    try std.testing.expect(harness.runtime.pendingDirtyRegions().len >= 1);
}

test "runtime reconciles canvas widget scroll momentum across layout replacement" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-scroll-reconcile", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(10, 20, 220, 96),
    });

    const children = [_]canvas.Widget{
        .{ .id = 2, .kind = .button, .frame = geometry.RectF.init(0, 0, 0, 32), .text = "One" },
        .{ .id = 3, .kind = .button, .frame = geometry.RectF.init(0, 44, 0, 32), .text = "Two" },
        .{ .id = 4, .kind = .button, .frame = geometry.RectF.init(0, 88, 0, 32), .text = "Three" },
    };
    const scroll = canvas.Widget{
        .id = 1,
        .kind = .scroll_view,
        .frame = geometry.RectF.init(0, 0, 180, 72),
        .children = &children,
    };
    var nodes: [4]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(scroll, geometry.RectF.init(0, 0, 180, 72), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .scroll,
        .x = 20,
        .y = 20,
        .delta_y = 24,
    } });
    try std.testing.expect(harness.runtime.views[0].widget_scroll_states[0].velocity > 0);

    const scrolled = try harness.runtime.canvasWidgetLayout(1, "canvas");
    const current_offset = scrolled.findById(1).?.widget.value;
    try std.testing.expectEqual(@as(f32, 24), current_offset);

    const refreshed_scroll = canvas.Widget{
        .id = 1,
        .kind = .scroll_view,
        .frame = geometry.RectF.init(24, 12, 180, 72),
        .value = current_offset,
        .children = &children,
    };
    const refreshed_widgets = [_]canvas.Widget{
        .{ .id = 10, .kind = .text, .frame = geometry.RectF.init(8, 0, 120, 12), .text = "Activity" },
        refreshed_scroll,
    };
    var refreshed_nodes: [6]canvas.WidgetLayoutNode = undefined;
    const refreshed_layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &refreshed_widgets }, geometry.RectF.init(0, 0, 220, 96), &refreshed_nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", refreshed_layout);

    const refreshed = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqual(@as(f32, 24), refreshed.findById(1).?.widget.value);
    try std.testing.expect(harness.runtime.views[0].widget_scroll_states[2].velocity > 0);

    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    const kinetic = try harness.runtime.stepCanvasWidgetKineticScroll(1, "canvas", 16);
    try std.testing.expectEqual(@as(u64, 4), kinetic.widget_revision);
    try std.testing.expect(harness.runtime.invalidated);
    try std.testing.expect(harness.runtime.pendingDirtyRegions().len >= 1);
    try std.testing.expectEqualDeep(geometry.RectF.init(34, 32, 180, 72), harness.runtime.pendingDirtyRegions()[0]);

    const kinetic_layout = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectApproxEqAbs(@as(f32, 47.04), kinetic_layout.findById(1).?.widget.value, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, -35.04), kinetic_layout.findById(2).?.frame.y, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 8.96), kinetic_layout.findById(3).?.frame.y, 0.01);
}

test "runtime clamps canvas scroll offset after layout replacement shrinks content" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-scroll-clamp-replacement", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(10, 20, 220, 96),
    });

    const full_children = [_]canvas.Widget{
        .{ .id = 2, .kind = .button, .frame = geometry.RectF.init(0, 0, 0, 32), .text = "One" },
        .{ .id = 3, .kind = .button, .frame = geometry.RectF.init(0, 44, 0, 32), .text = "Two" },
        .{ .id = 4, .kind = .button, .frame = geometry.RectF.init(0, 88, 0, 32), .text = "Three" },
    };
    const full_scroll = canvas.Widget{
        .id = 1,
        .kind = .scroll_view,
        .frame = geometry.RectF.init(0, 0, 180, 72),
        .value = 48,
        .children = &full_children,
    };
    var full_nodes: [4]canvas.WidgetLayoutNode = undefined;
    const full_layout = try canvas.layoutWidgetTree(full_scroll, geometry.RectF.init(0, 0, 180, 72), &full_nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", full_layout);

    var retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqual(@as(f32, 48), retained.findById(1).?.widget.value);
    try std.testing.expectEqual(@as(f32, -48), retained.findById(2).?.frame.y);

    const short_children = [_]canvas.Widget{
        .{ .id = 2, .kind = .button, .frame = geometry.RectF.init(0, 0, 0, 32), .text = "One" },
    };
    const short_scroll = canvas.Widget{
        .id = 1,
        .kind = .scroll_view,
        .frame = geometry.RectF.init(0, 0, 180, 72),
        .value = 48,
        .children = &short_children,
    };
    var short_nodes: [2]canvas.WidgetLayoutNode = undefined;
    const short_layout = try canvas.layoutWidgetTree(short_scroll, geometry.RectF.init(0, 0, 180, 72), &short_nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", short_layout);

    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqual(@as(f32, 0), retained.findById(1).?.widget.value);
    try std.testing.expectEqual(@as(f32, 0), retained.findById(2).?.frame.y);
    try std.testing.expectEqual(@as(f32, 0), harness.runtime.views[0].widget_scroll_states[0].offset);
    try std.testing.expectEqual(@as(f32, 0), harness.runtime.views[0].widget_scroll_states[0].velocity);

    const snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expectEqual(@as(usize, 2), snapshot.widgets.len);
    try std.testing.expect(snapshot.widgets[0].scroll.present);
    try std.testing.expectEqual(@as(f32, 0), snapshot.widgets[0].scroll.offset);
    try std.testing.expectEqual(@as(f32, 72), snapshot.widgets[0].scroll.viewport_extent);
    try std.testing.expectEqual(@as(f32, 72), snapshot.widgets[0].scroll.content_extent);
    try std.testing.expectEqualDeep(geometry.RectF.init(10, 20, 180, 32), snapshot.widgets[1].bounds);
}

test "runtime chains wheel input from saturated nested canvas scroll views" {
    const TestApp = struct {
        widget_pointer_count: u32 = 0,
        last_phase: canvas.WidgetPointerPhase = .hover,
        last_target_id: canvas.ObjectId = 0,

        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-scroll-chain", .source = platform.WebViewSource.html("<h1>Hello</h1>"), .event_fn = event };
        }

        fn event(context: *anyopaque, runtime: *Runtime, event_value: Event) anyerror!void {
            _ = runtime;
            const self: *@This() = @ptrCast(@alignCast(context));
            switch (event_value) {
                .canvas_widget_pointer => |pointer_event| {
                    self.widget_pointer_count += 1;
                    self.last_phase = pointer_event.pointer.phase;
                    self.last_target_id = if (pointer_event.target) |target| target.id else 0;
                },
                else => {},
            }
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
        .frame = geometry.RectF.init(10, 20, 180, 80),
    });

    const inner_children = [_]canvas.Widget{
        .{ .id = 3, .kind = .button, .frame = geometry.RectF.init(0, 0, 0, 32), .text = "Inner one" },
        .{ .id = 4, .kind = .button, .frame = geometry.RectF.init(0, 44, 0, 32), .text = "Inner two" },
    };
    const outer_children = [_]canvas.Widget{
        .{
            .id = 2,
            .kind = .scroll_view,
            .frame = geometry.RectF.init(0, 0, 0, 40),
            .value = 36,
            .children = &inner_children,
        },
        .{ .id = 5, .kind = .button, .frame = geometry.RectF.init(0, 120, 0, 32), .text = "Outer footer" },
    };
    const outer = canvas.Widget{
        .id = 1,
        .kind = .scroll_view,
        .children = &outer_children,
    };

    var nodes: [6]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(outer, geometry.RectF.init(0, 0, 180, 80), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .scroll,
        .x = 20,
        .y = 20,
        .delta_y = 24,
    } });

    try std.testing.expectEqual(@as(u32, 1), app_state.widget_pointer_count);
    try std.testing.expectEqual(canvas.WidgetPointerPhase.wheel, app_state.last_phase);
    try std.testing.expectEqual(@as(canvas.ObjectId, 4), app_state.last_target_id);
    try std.testing.expect(harness.runtime.invalidated);
    try std.testing.expectEqual(@as(usize, 1), harness.runtime.pendingDirtyRegions().len);
    try std.testing.expectEqualDeep(geometry.RectF.init(10, 20, 180, 80), harness.runtime.pendingDirtyRegions()[0]);

    const retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqual(@as(f32, 24), retained.nodes[0].widget.value);
    try std.testing.expectEqual(@as(f32, 36), retained.nodes[1].widget.value);
    try std.testing.expectEqualDeep(geometry.RectF.init(0, -24, 180, 40), retained.nodes[1].frame);
    try std.testing.expectEqualDeep(geometry.RectF.init(0, -60, 180, 32), retained.nodes[2].frame);
    try std.testing.expectEqualDeep(geometry.RectF.init(0, -16, 180, 32), retained.nodes[3].frame);
    try std.testing.expectEqualDeep(geometry.RectF.init(0, 96, 180, 32), retained.nodes[4].frame);
    try std.testing.expect(harness.runtime.views[0].widget_scroll_states[0].velocity > 0);
    try std.testing.expectEqual(@as(f32, 0), harness.runtime.views[0].widget_scroll_states[1].velocity);
}

test "runtime leaves virtualized canvas scroll views app driven" {
    const TestApp = struct {
        widget_pointer_count: u32 = 0,

        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-virtual-scroll", .source = platform.WebViewSource.html("<h1>Hello</h1>"), .event_fn = event };
        }

        fn event(context: *anyopaque, runtime: *Runtime, event_value: Event) anyerror!void {
            _ = runtime;
            const self: *@This() = @ptrCast(@alignCast(context));
            switch (event_value) {
                .canvas_widget_pointer => self.widget_pointer_count += 1,
                else => {},
            }
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
        .frame = geometry.RectF.init(0, 0, 160, 48),
    });

    const children = [_]canvas.Widget{
        .{ .id = 2, .kind = .button, .frame = geometry.RectF.init(0, 0, 0, 20), .text = "Zero" },
        .{ .id = 3, .kind = .button, .frame = geometry.RectF.init(0, 0, 0, 20), .text = "One" },
        .{ .id = 4, .kind = .button, .frame = geometry.RectF.init(0, 0, 0, 20), .text = "Two" },
        .{ .id = 5, .kind = .button, .frame = geometry.RectF.init(0, 0, 0, 20), .text = "Three" },
    };
    const scroll = canvas.Widget{
        .id = 1,
        .kind = .scroll_view,
        .layout = .{
            .virtualized = true,
            .virtual_item_extent = 20,
            .virtual_overscan = 1,
        },
        .children = &children,
    };
    var nodes: [5]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(scroll, geometry.RectF.init(0, 0, 160, 48), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);
    const retained_layout = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqual(@as(usize, 0), retained_layout.nodes[0].widget.children.len);
    try std.testing.expectEqual(@as(?u32, 4), retained_layout.nodes[0].widget.semantics.list_item_count);
    try std.testing.expectEqual(@as(f32, 20), retained_layout.nodes[0].widget.layout.virtual_item_extent);

    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .scroll,
        .x = 12,
        .y = 12,
        .delta_y = 20,
    } });

    try std.testing.expectEqual(@as(u32, 1), app_state.widget_pointer_count);
    try std.testing.expect(!harness.runtime.invalidated);
    try std.testing.expectEqual(@as(usize, 0), harness.runtime.pendingDirtyRegions().len);

    const retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqual(@as(f32, 0), retained.nodes[0].widget.value);
    try std.testing.expectEqualDeep(layout.nodes[1].frame, retained.nodes[1].frame);
    try std.testing.expectEqual(@as(u64, 1), harness.runtime.views[0].widget_revision);

    const snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expectEqual(@as(usize, 5), snapshot.widgets.len);
    try std.testing.expect(snapshot.widgets[0].scroll.present);
    try std.testing.expectEqual(@as(f32, 0), snapshot.widgets[0].scroll.offset);
    try std.testing.expectEqual(@as(f32, 48), snapshot.widgets[0].scroll.viewport_extent);
    try std.testing.expectEqual(@as(f32, 80), snapshot.widgets[0].scroll.content_extent);
    try std.testing.expect(snapshot.widgets[0].actions.focus);
    try std.testing.expect(snapshot.widgets[0].actions.increment);
    try std.testing.expect(snapshot.widgets[0].actions.decrement);

    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    const kinetic = try harness.runtime.stepCanvasWidgetKineticScroll(1, "canvas", 16);
    try std.testing.expectEqual(@as(u64, 1), kinetic.widget_revision);
    try std.testing.expect(!harness.runtime.invalidated);
    try std.testing.expectEqual(@as(usize, 0), harness.runtime.pendingDirtyRegions().len);
}

test "runtime exposes retained canvas widget text geometry" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-text-geometry", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(0, 0, 240, 160),
    });

    const children = [_]canvas.Widget{
        .{
            .id = 2,
            .kind = .text_field,
            .frame = geometry.RectF.init(12, 16, 160, 36),
            .text = "Search",
            .text_selection = canvas.TextSelection.collapsed(3),
        },
        .{
            .id = 3,
            .kind = .search_field,
            .frame = geometry.RectF.init(12, 60, 160, 36),
            .text = "Cafe",
            .text_selection = .{ .anchor = 1, .focus = 4 },
            .text_composition = canvas.TextRange.init(2, 4),
        },
        .{
            .id = 4,
            .kind = .button,
            .frame = geometry.RectF.init(12, 108, 120, 32),
            .text = "Run",
        },
    };
    var nodes: [4]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &children }, geometry.RectF.init(0, 0, 240, 160), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    const caret = try harness.runtime.canvasWidgetTextGeometry(1, "canvas", 2);
    try std.testing.expect(caret.caret_bounds != null);
    try std.testing.expect(caret.selection_bounds == null);
    try std.testing.expectEqual(@as(usize, 0), caret.selection_rect_count);
    try std.testing.expect(caret.composition_bounds == null);

    const range = try harness.runtime.canvasWidgetTextGeometry(1, "canvas", 3);
    try std.testing.expect(range.caret_bounds == null);
    try std.testing.expect(range.selection_bounds != null);
    try std.testing.expectEqual(@as(usize, 1), range.selection_rect_count);
    try std.testing.expect(range.composition_bounds != null);
    try std.testing.expectEqual(@as(usize, 1), range.composition_rect_count);

    try std.testing.expectError(error.InvalidCommand, harness.runtime.canvasWidgetTextGeometry(1, "canvas", 0));
    try std.testing.expectError(error.InvalidCommand, harness.runtime.canvasWidgetTextGeometry(1, "canvas", 4));
    try std.testing.expectError(error.InvalidCommand, harness.runtime.canvasWidgetTextGeometry(1, "canvas", 99));
}

test "runtime applies text input to focused canvas text fields" {
    const TestApp = struct {
        widget_keyboard_count: u32 = 0,
        widget_text_input_count: u32 = 0,

        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-text-edit", .source = platform.WebViewSource.html("<h1>Hello</h1>"), .event_fn = event };
        }

        fn event(context: *anyopaque, runtime: *Runtime, event_value: Event) anyerror!void {
            _ = runtime;
            const self: *@This() = @ptrCast(@alignCast(context));
            switch (event_value) {
                .canvas_widget_keyboard => |keyboard_event| {
                    self.widget_keyboard_count += 1;
                    if (keyboard_event.keyboard.phase == .text_input) self.widget_text_input_count += 1;
                },
                else => {},
            }
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
        .frame = geometry.RectF.init(0, 0, 240, 120),
    });

    const text_field = canvas.Widget{
        .id = 2,
        .kind = .text_field,
        .frame = geometry.RectF.init(12, 16, 160, 36),
        .text = "Query",
        .semantics = .{ .label = "Search" },
    };
    var nodes: [2]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &.{text_field} }, geometry.RectF.init(0, 0, 240, 120), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_down,
        .x = 168,
        .y = 24,
    } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 2), harness.runtime.views[0].canvas_widget_focused_id);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "a",
        .text = "a",
    } });
    try std.testing.expectEqual(@as(u32, 2), app_state.widget_keyboard_count);
    try std.testing.expectEqual(@as(u32, 1), app_state.widget_text_input_count);
    try std.testing.expectEqual(@as(u64, 2), harness.runtime.views[0].widget_revision);

    var retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualStrings("Querya", retained.nodes[1].widget.text);
    try std.testing.expectEqualDeep(canvas.TextSelection.collapsed(6), retained.nodes[1].widget.text_selection.?);
    try std.testing.expect(retained.nodes[1].widget.text_composition == null);

    var snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expectEqual(@as(usize, 1), snapshot.widgets.len);
    try std.testing.expectEqualStrings("Search", snapshot.widgets[0].name);
    try std.testing.expectEqualStrings("Querya", snapshot.widgets[0].text_value);
    try std.testing.expectEqualDeep(automation.snapshot.TextRange{ .start = 6, .end = 6 }, snapshot.widgets[0].text_selection.?);
    try std.testing.expect(snapshot.widgets[0].text_composition == null);

    _ = try harness.runtime.emitCanvasWidgetDisplayList(1, "canvas", .{});
    var display_list = try harness.runtime.canvasDisplayList(1, "canvas");
    var saw_inserted_text = false;
    for (display_list.commands) |command| {
        switch (command) {
            .draw_text => |text| {
                if (text.id == testCanvasWidgetPartId(2, 4)) {
                    try std.testing.expectEqualStrings("Querya", text.text);
                    saw_inserted_text = true;
                }
            },
            else => {},
        }
    }
    try std.testing.expect(saw_inserted_text);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "b",
        .text = "b",
        .modifiers = .{ .primary = true, .command = true },
    } });
    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualStrings("Querya", retained.nodes[1].widget.text);
    try std.testing.expectEqual(@as(u64, 2), harness.runtime.views[0].widget_revision);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "backspace",
    } });
    try std.testing.expectEqual(@as(u64, 3), harness.runtime.views[0].widget_revision);
    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualStrings("Query", retained.nodes[1].widget.text);
    try std.testing.expectEqualDeep(canvas.TextSelection.collapsed(5), retained.nodes[1].widget.text_selection.?);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "a",
        .text = "a",
        .modifiers = .{ .primary = true, .command = true },
    } });
    try std.testing.expectEqual(@as(u64, 4), harness.runtime.views[0].widget_revision);
    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualStrings("Query", retained.nodes[1].widget.text);
    try std.testing.expectEqualDeep(canvas.TextSelection{ .anchor = 0, .focus = 5 }, retained.nodes[1].widget.text_selection.?);

    snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expectEqualStrings("Query", snapshot.widgets[0].text_value);
    try std.testing.expectEqualDeep(automation.snapshot.TextRange{ .start = 0, .end = 5 }, snapshot.widgets[0].text_selection.?);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "x",
        .text = "x",
    } });
    try std.testing.expectEqual(@as(u64, 5), harness.runtime.views[0].widget_revision);
    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualStrings("x", retained.nodes[1].widget.text);
    try std.testing.expectEqualDeep(canvas.TextSelection.collapsed(1), retained.nodes[1].widget.text_selection.?);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "arrowleft",
        .modifiers = .{ .command = true },
    } });
    try std.testing.expectEqual(@as(u64, 6), harness.runtime.views[0].widget_revision);
    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualDeep(canvas.TextSelection.collapsed(0), retained.nodes[1].widget.text_selection.?);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "arrowright",
        .modifiers = .{ .command = true },
    } });
    try std.testing.expectEqual(@as(u64, 7), harness.runtime.views[0].widget_revision);
    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualDeep(canvas.TextSelection.collapsed(1), retained.nodes[1].widget.text_selection.?);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "arrowup",
    } });
    try std.testing.expectEqual(@as(u64, 8), harness.runtime.views[0].widget_revision);
    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualDeep(canvas.TextSelection.collapsed(0), retained.nodes[1].widget.text_selection.?);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "arrowdown",
    } });
    try std.testing.expectEqual(@as(u64, 9), harness.runtime.views[0].widget_revision);
    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualDeep(canvas.TextSelection.collapsed(1), retained.nodes[1].widget.text_selection.?);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "escape",
    } });
    try std.testing.expectEqual(@as(u64, 9), harness.runtime.views[0].widget_revision);
    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualStrings("x", retained.nodes[1].widget.text);
    try std.testing.expectEqualDeep(canvas.TextSelection.collapsed(1), retained.nodes[1].widget.text_selection.?);

    _ = try harness.runtime.emitCanvasWidgetDisplayList(1, "canvas", .{});
    display_list = try harness.runtime.canvasDisplayList(1, "canvas");
    var saw_deleted_text = false;
    for (display_list.commands) |command| {
        switch (command) {
            .draw_text => |text| {
                if (text.id == testCanvasWidgetPartId(2, 4)) {
                    try std.testing.expectEqualStrings("x", text.text);
                    saw_deleted_text = true;
                }
            },
            else => {},
        }
    }
    try std.testing.expect(saw_deleted_text);

    snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expectEqualStrings("Search", snapshot.widgets[0].name);
    try std.testing.expectEqualStrings("x", snapshot.widgets[0].text_value);
    try std.testing.expectEqualDeep(canvas.TextRange.init(1, 1), runtimeViewWidgetSemantics(&harness.runtime.views[0])[0].text_selection.?);
    try std.testing.expectEqualDeep(automation.snapshot.TextRange{ .start = 1, .end = 1 }, snapshot.widgets[0].text_selection.?);
    try std.testing.expect(snapshot.widgets[0].text_composition == null);
}

test "runtime applies text input to canvas textareas" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-textarea-edit", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(0, 0, 260, 160),
    });

    const textarea = canvas.Widget{
        .id = 2,
        .kind = .textarea,
        .frame = geometry.RectF.init(12, 16, 180, 84),
        .text = "First",
        .semantics = .{ .label = "Message" },
    };
    var nodes: [2]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &.{textarea} }, geometry.RectF.init(0, 0, 260, 160), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_down,
        .x = 188,
        .y = 28,
    } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 2), harness.runtime.views[0].canvas_widget_focused_id);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "!",
        .text = "!",
    } });
    var retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualStrings("First!", retained.nodes[1].widget.text);
    try std.testing.expectEqualDeep(canvas.TextSelection.collapsed(6), retained.nodes[1].widget.text_selection.?);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "enter",
        .modifiers = .{ .shift = true },
    } });
    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualStrings("First!\n", retained.nodes[1].widget.text);
    try std.testing.expectEqualDeep(canvas.TextSelection.collapsed(7), retained.nodes[1].widget.text_selection.?);
    const newline_geometry = try harness.runtime.canvasWidgetTextGeometry(1, "canvas", 2);
    try std.testing.expect(newline_geometry.caret_bounds.?.y > textarea.frame.y + 24);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "arrowleft",
        .modifiers = .{ .command = true },
    } });
    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualDeep(canvas.TextSelection.collapsed(0), retained.nodes[1].widget.text_selection.?);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "arrowright",
        .modifiers = .{ .command = true },
    } });
    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualDeep(canvas.TextSelection.collapsed(7), retained.nodes[1].widget.text_selection.?);

    const textarea_revision = harness.runtime.views[0].widget_revision;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "arrowup",
    } });
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "arrowdown",
    } });
    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqual(@as(u64, textarea_revision), harness.runtime.views[0].widget_revision);
    try std.testing.expectEqualStrings("First!\n", retained.nodes[1].widget.text);
    try std.testing.expectEqualDeep(canvas.TextSelection.collapsed(7), retained.nodes[1].widget.text_selection.?);

    _ = try harness.runtime.editCanvasWidgetText(1, "canvas", 2, .{ .insert_text = "Second" });
    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualStrings("First!\nSecond", retained.nodes[1].widget.text);
    try std.testing.expectEqualDeep(canvas.TextSelection.collapsed(13), retained.nodes[1].widget.text_selection.?);
    try std.testing.expectEqualDeep(canvas.TextRange.init(13, 13), runtimeViewWidgetSemantics(&harness.runtime.views[0])[0].text_selection.?);

    const text_geometry = try harness.runtime.canvasWidgetTextGeometry(1, "canvas", 2);
    try std.testing.expect(text_geometry.caret_bounds != null);
    const snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expectEqualStrings("Message", snapshot.widgets[0].name);
    try std.testing.expectEqualStrings("First!\nSecond", snapshot.widgets[0].text_value);
    try std.testing.expect(snapshot.widgets[0].actions.set_text);
    try std.testing.expect(snapshot.widgets[0].actions.set_selection);

    _ = try harness.runtime.emitCanvasWidgetDisplayList(1, "canvas", .{});
    const display_list = try harness.runtime.canvasDisplayList(1, "canvas");
    var saw_textarea_text = false;
    for (display_list.commands) |command| {
        switch (command) {
            .draw_text => |text| {
                if (text.id == testCanvasWidgetPartId(2, 4)) {
                    try std.testing.expectEqualStrings("First!\nSecond", text.text);
                    try std.testing.expect(text.text_layout != null);
                    try std.testing.expectEqual(canvas.TextWrap.word, text.text_layout.?.wrap);
                    saw_textarea_text = true;
                }
            },
            else => {},
        }
    }
    try std.testing.expect(saw_textarea_text);

    _ = try harness.runtime.editCanvasWidgetText(1, "canvas", 2, .{ .insert_text = "\nThird\nFourth\nFifth\nSixth\nSeventh\nEighth" });
    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expect(retained.nodes[1].widget.value > 0);
    try std.testing.expect(canvas.textInputMaxScrollOffsetForWidget(retained.nodes[1].widget, .{}) > 0);
    const scrolled_viewport = canvas.textInputViewportForWidget(retained.nodes[1].widget, .{}).?;
    const scrolled_geometry = try harness.runtime.canvasWidgetTextGeometry(1, "canvas", 2);
    const scrolled_caret = scrolled_geometry.caret_bounds.?;
    try std.testing.expect(scrolled_caret.y >= scrolled_viewport.y - 0.001);
    try std.testing.expect(scrolled_caret.maxY() <= scrolled_viewport.maxY() + 0.001);

    _ = try harness.runtime.emitCanvasWidgetDisplayList(1, "canvas", .{});
    const scrolled_display_list = try harness.runtime.canvasDisplayList(1, "canvas");
    var saw_textarea_clip = false;
    for (scrolled_display_list.commands) |command| {
        switch (command) {
            .push_clip => |clip| {
                if (clip.id == testCanvasWidgetPartId(2, 16)) {
                    try std.testing.expectEqualDeep(scrolled_viewport, clip.rect);
                    saw_textarea_clip = true;
                }
            },
            else => {},
        }
    }
    try std.testing.expect(saw_textarea_clip);
}

test "runtime applies ime composition edits to canvas text fields" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-text-ime", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(20, 30, 240, 120),
    });

    const text_field = canvas.Widget{
        .id = 2,
        .kind = .text_field,
        .frame = geometry.RectF.init(12, 16, 160, 36),
        .text = "Cafe",
        .semantics = .{ .label = "Name" },
    };
    var nodes: [2]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &.{text_field} }, geometry.RectF.init(0, 0, 240, 120), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);
    _ = try harness.runtime.emitCanvasWidgetDisplayList(1, "canvas", .{});

    _ = try harness.runtime.editCanvasWidgetText(1, "canvas", 2, .{ .set_selection = .{ .anchor = 3, .focus = 4 } });
    try std.testing.expectEqual(@as(u64, 2), harness.runtime.views[0].widget_revision);
    var display_list = try harness.runtime.canvasDisplayList(1, "canvas");
    var saw_selected_text = false;
    var saw_selection_fill = false;
    for (display_list.commands) |command| {
        switch (command) {
            .fill_rounded_rect => |fill| {
                if (fill.id == testCanvasWidgetPartId(2, 3)) saw_selection_fill = true;
            },
            .draw_text => |text| {
                if (text.id == testCanvasWidgetPartId(2, 4)) {
                    try std.testing.expectEqualStrings("Cafe", text.text);
                    saw_selected_text = true;
                }
            },
            else => {},
        }
    }
    try std.testing.expect(saw_selected_text);
    try std.testing.expect(saw_selection_fill);

    _ = try harness.runtime.editCanvasWidgetText(1, "canvas", 2, .{ .set_composition = .{ .text = "\xc3\xa9", .cursor = 2 } });
    try std.testing.expectEqual(@as(u64, 3), harness.runtime.views[0].widget_revision);

    var retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualStrings("Caf\xc3\xa9", retained.nodes[1].widget.text);
    try std.testing.expectEqualDeep(canvas.TextSelection.collapsed(5), retained.nodes[1].widget.text_selection.?);
    try std.testing.expectEqualDeep(canvas.TextRange.init(3, 5), retained.nodes[1].widget.text_composition.?);
    display_list = try harness.runtime.canvasDisplayList(1, "canvas");
    var saw_composed_text = false;
    var saw_composition_underline = false;
    for (display_list.commands) |command| {
        switch (command) {
            .draw_text => |text| {
                if (text.id == testCanvasWidgetPartId(2, 4)) {
                    try std.testing.expectEqualStrings("Caf\xc3\xa9", text.text);
                    saw_composed_text = true;
                }
            },
            .draw_line => |line| {
                if (line.id == testCanvasWidgetPartId(2, 5)) saw_composition_underline = true;
            },
            else => {},
        }
    }
    try std.testing.expect(saw_composed_text);
    try std.testing.expect(saw_composition_underline);

    var snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expectEqualStrings("Name", snapshot.widgets[0].name);
    try std.testing.expectEqualStrings("Caf\xc3\xa9", snapshot.widgets[0].text_value);
    try std.testing.expectEqualDeep(automation.snapshot.TextRange{ .start = 5, .end = 5 }, snapshot.widgets[0].text_selection.?);
    try std.testing.expectEqualDeep(automation.snapshot.TextRange{ .start = 3, .end = 5 }, snapshot.widgets[0].text_composition.?);

    var a11y_buffer: [1024]u8 = undefined;
    var a11y_writer = std.Io.Writer.fixed(&a11y_buffer);
    try automation.snapshot.writeA11yText(snapshot, &a11y_writer);
    try std.testing.expect(std.mem.indexOf(u8, a11y_writer.buffered(), "text=\"Caf\xc3\xa9\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, a11y_writer.buffered(), "composition=3..5") != null);

    _ = try harness.runtime.editCanvasWidgetText(1, "canvas", 2, .commit_composition);
    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualStrings("Caf\xc3\xa9", retained.nodes[1].widget.text);
    try std.testing.expect(retained.nodes[1].widget.text_composition == null);
    try std.testing.expectEqual(@as(u64, 4), harness.runtime.views[0].widget_revision);

    _ = try harness.runtime.editCanvasWidgetText(1, "canvas", 2, .{ .set_composition = .{ .text = " noir", .cursor = 5 } });
    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualStrings("Caf\xc3\xa9 noir", retained.nodes[1].widget.text);
    try std.testing.expectEqualDeep(canvas.TextRange.init(5, 10), retained.nodes[1].widget.text_composition.?);
    try std.testing.expectEqual(@as(u64, 5), harness.runtime.views[0].widget_revision);

    try harness.runtime.focusView(1, "canvas");
    harness.runtime.views[0].canvas_widget_focused_id = 2;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "escape",
    } });
    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualStrings("Caf\xc3\xa9", retained.nodes[1].widget.text);
    try std.testing.expectEqualDeep(canvas.TextSelection.collapsed(5), retained.nodes[1].widget.text_selection.?);
    try std.testing.expect(retained.nodes[1].widget.text_composition == null);
    try std.testing.expectEqual(@as(u64, 6), harness.runtime.views[0].widget_revision);

    snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expectEqualStrings("Caf\xc3\xa9", snapshot.widgets[0].text_value);
    try std.testing.expect(snapshot.widgets[0].text_composition == null);

    try std.testing.expectError(error.InvalidCommand, harness.runtime.editCanvasWidgetText(1, "canvas", 99, .commit_composition));
}

test "runtime clips canvas widget text edit dirty bounds to scroll ancestors" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-clipped-text-dirty", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(10, 20, 160, 48),
    });

    const partially_visible_children = [_]canvas.Widget{.{
        .id = 2,
        .kind = .text_field,
        .frame = geometry.RectF.init(0, 40, 0, 32),
        .text = "Draft",
    }};
    var partially_visible_nodes: [2]canvas.WidgetLayoutNode = undefined;
    const partially_visible_layout = try canvas.layoutWidgetTree(
        .{ .id = 1, .kind = .scroll_view, .children = &partially_visible_children },
        geometry.RectF.init(0, 0, 160, 48),
        &partially_visible_nodes,
    );
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", partially_visible_layout);

    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    _ = try harness.runtime.editCanvasWidgetText(1, "canvas", 2, .{ .insert_text = "!" });
    try std.testing.expect(harness.runtime.invalidated);
    try std.testing.expectEqual(@as(usize, 1), harness.runtime.pendingDirtyRegions().len);
    try std.testing.expectEqualDeep(geometry.RectF.init(10, 60, 160, 8), harness.runtime.pendingDirtyRegions()[0]);

    const fully_clipped_children = [_]canvas.Widget{.{
        .id = 2,
        .kind = .text_field,
        .frame = geometry.RectF.init(0, 64, 0, 32),
        .text = "Draft",
    }};
    var fully_clipped_nodes: [2]canvas.WidgetLayoutNode = undefined;
    const fully_clipped_layout = try canvas.layoutWidgetTree(
        .{ .id = 1, .kind = .scroll_view, .children = &fully_clipped_children },
        geometry.RectF.init(0, 0, 160, 48),
        &fully_clipped_nodes,
    );
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", fully_clipped_layout);

    try std.testing.expectError(error.InvalidCommand, harness.runtime.editCanvasWidgetText(1, "canvas", 2, .{ .insert_text = "!" }));
}

test "runtime clips canvas widget control dirty bounds to scroll ancestors" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-clipped-control-dirty", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(10, 20, 160, 48),
    });

    const children = [_]canvas.Widget{.{
        .id = 2,
        .kind = .list_item,
        .frame = geometry.RectF.init(0, 40, 0, 32),
        .text = "Partially visible",
    }};
    var nodes: [2]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(
        .{ .id = 1, .kind = .scroll_view, .children = &children },
        geometry.RectF.init(0, 0, 160, 48),
        &nodes,
    );
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    const dirty = try runtimeViewSetCanvasWidgetSelected(&harness.runtime.views[0], 2, true);
    try std.testing.expectEqualDeep(geometry.RectF.init(0, 40, 160, 8), dirty.?);
}

test "runtime reconciles canvas text edit state across layout replacement" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-text-reconcile", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(20, 30, 260, 140),
    });

    const text_field = canvas.Widget{
        .id = 2,
        .kind = .text_field,
        .frame = geometry.RectF.init(12, 16, 160, 36),
        .text = "Cafe",
        .semantics = .{ .label = "Name" },
    };
    var nodes: [2]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &.{text_field} }, geometry.RectF.init(0, 0, 260, 140), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    _ = try harness.runtime.editCanvasWidgetText(1, "canvas", 2, .{ .set_selection = .{ .anchor = 1, .focus = 4 } });

    const moved_text_field = canvas.Widget{
        .id = 2,
        .kind = .text_field,
        .frame = geometry.RectF.init(20, 24, 180, 36),
        .text = "Cafe",
        .semantics = .{ .label = "Name" },
    };
    var moved_nodes: [2]canvas.WidgetLayoutNode = undefined;
    const moved_layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &.{moved_text_field} }, geometry.RectF.init(0, 0, 260, 140), &moved_nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", moved_layout);

    var retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualStrings("Cafe", retained.nodes[1].widget.text);
    try std.testing.expectEqualDeep(canvas.TextSelection{ .anchor = 1, .focus = 4 }, retained.nodes[1].widget.text_selection.?);
    try std.testing.expect(retained.nodes[1].widget.text_composition == null);

    _ = try harness.runtime.editCanvasWidgetText(1, "canvas", 2, .{ .set_composition = .{ .text = "af\xc3\xa9", .cursor = 4 } });
    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualStrings("Caf\xc3\xa9", retained.nodes[1].widget.text);
    try std.testing.expectEqualDeep(canvas.TextSelection.collapsed(5), retained.nodes[1].widget.text_selection.?);
    try std.testing.expectEqualDeep(canvas.TextRange.init(1, 5), retained.nodes[1].widget.text_composition.?);

    const composed_text_field = canvas.Widget{
        .id = 2,
        .kind = .text_field,
        .frame = geometry.RectF.init(24, 28, 184, 36),
        .text = "Caf\xc3\xa9",
        .semantics = .{ .label = "Name" },
    };
    var composed_nodes: [2]canvas.WidgetLayoutNode = undefined;
    const composed_layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &.{composed_text_field} }, geometry.RectF.init(0, 0, 260, 140), &composed_nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", composed_layout);

    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualStrings("Caf\xc3\xa9", retained.nodes[1].widget.text);
    try std.testing.expectEqualDeep(canvas.TextSelection.collapsed(5), retained.nodes[1].widget.text_selection.?);
    try std.testing.expectEqualDeep(canvas.TextRange.init(1, 5), retained.nodes[1].widget.text_composition.?);

    const snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expectEqualStrings("Caf\xc3\xa9", snapshot.widgets[0].text_value);
    try std.testing.expectEqualDeep(automation.snapshot.TextRange{ .start = 5, .end = 5 }, snapshot.widgets[0].text_selection.?);
    try std.testing.expectEqualDeep(automation.snapshot.TextRange{ .start = 1, .end = 5 }, snapshot.widgets[0].text_composition.?);

    const replaced_text_field = canvas.Widget{
        .id = 2,
        .kind = .text_field,
        .frame = geometry.RectF.init(24, 28, 184, 36),
        .text = "Reset",
        .semantics = .{ .label = "Name" },
    };
    var replaced_nodes: [2]canvas.WidgetLayoutNode = undefined;
    const replaced_layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &.{replaced_text_field} }, geometry.RectF.init(0, 0, 260, 140), &replaced_nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", replaced_layout);

    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualStrings("Reset", retained.nodes[1].widget.text);
    try std.testing.expect(retained.nodes[1].widget.text_selection == null);
    try std.testing.expect(retained.nodes[1].widget.text_composition == null);
}

test "runtime preserves canvas text edits across unchanged source layout replacement" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-text-source-reconcile", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(20, 30, 260, 140),
    });

    const text_field = canvas.Widget{
        .id = 2,
        .kind = .text_field,
        .frame = geometry.RectF.init(12, 16, 160, 36),
        .text = "Draft",
        .semantics = .{ .label = "Name" },
    };
    var nodes: [2]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &.{text_field} }, geometry.RectF.init(0, 0, 260, 140), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    _ = try harness.runtime.editCanvasWidgetText(1, "canvas", 2, .{ .set_selection = canvas.TextSelection.collapsed(5) });
    _ = try harness.runtime.editCanvasWidgetText(1, "canvas", 2, .{ .insert_text = " updated" });

    var retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualStrings("Draft updated", retained.nodes[1].widget.text);
    try std.testing.expectEqualDeep(canvas.TextSelection.collapsed(13), retained.nodes[1].widget.text_selection.?);

    const moved_text_field = canvas.Widget{
        .id = 2,
        .kind = .text_field,
        .frame = geometry.RectF.init(24, 28, 184, 36),
        .text = "Draft",
        .semantics = .{ .label = "Name" },
    };
    var moved_nodes: [2]canvas.WidgetLayoutNode = undefined;
    const moved_layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &.{moved_text_field} }, geometry.RectF.init(0, 0, 260, 140), &moved_nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", moved_layout);

    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualStrings("Draft updated", retained.nodes[1].widget.text);
    try std.testing.expectEqualDeep(canvas.TextSelection.collapsed(13), retained.nodes[1].widget.text_selection.?);

    const replaced_text_field = canvas.Widget{
        .id = 2,
        .kind = .text_field,
        .frame = geometry.RectF.init(24, 28, 184, 36),
        .text = "Reset",
        .semantics = .{ .label = "Name" },
    };
    var replaced_nodes: [2]canvas.WidgetLayoutNode = undefined;
    const replaced_layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &.{replaced_text_field} }, geometry.RectF.init(0, 0, 260, 140), &replaced_nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", replaced_layout);

    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualStrings("Reset", retained.nodes[1].widget.text);
    try std.testing.expect(retained.nodes[1].widget.text_selection == null);
}

test "runtime avoids dirty regions for reconciled canvas text edit layout replacement" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-text-reconcile-dirty", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(20, 30, 260, 140),
    });

    const text_field = canvas.Widget{
        .id = 2,
        .kind = .text_field,
        .frame = geometry.RectF.init(12, 16, 160, 36),
        .text = "Cafe",
        .semantics = .{ .label = "Name" },
    };
    var nodes: [2]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &.{text_field} }, geometry.RectF.init(0, 0, 260, 140), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    _ = try harness.runtime.editCanvasWidgetText(1, "canvas", 2, .{ .set_selection = .{ .anchor = 1, .focus = 4 } });
    _ = try harness.runtime.editCanvasWidgetText(1, "canvas", 2, .{ .set_composition = .{ .text = "af\xc3\xa9", .cursor = 4 } });

    var retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualStrings("Caf\xc3\xa9", retained.nodes[1].widget.text);
    try std.testing.expectEqualDeep(canvas.TextSelection.collapsed(5), retained.nodes[1].widget.text_selection.?);
    try std.testing.expectEqualDeep(canvas.TextRange.init(1, 5), retained.nodes[1].widget.text_composition.?);

    const refreshed_text_field = canvas.Widget{
        .id = 2,
        .kind = .text_field,
        .frame = geometry.RectF.init(12, 16, 160, 36),
        .text = "Caf\xc3\xa9",
        .semantics = .{ .label = "Name" },
    };
    var refreshed_nodes: [2]canvas.WidgetLayoutNode = undefined;
    const refreshed_layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &.{refreshed_text_field} }, geometry.RectF.init(0, 0, 260, 140), &refreshed_nodes);

    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", refreshed_layout);

    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualStrings("Caf\xc3\xa9", retained.nodes[1].widget.text);
    try std.testing.expectEqualDeep(canvas.TextSelection.collapsed(5), retained.nodes[1].widget.text_selection.?);
    try std.testing.expectEqualDeep(canvas.TextRange.init(1, 5), retained.nodes[1].widget.text_composition.?);
    try std.testing.expect(!harness.runtime.invalidated);
    try std.testing.expectEqual(@as(usize, 0), harness.runtime.pendingDirtyRegions().len);
}

test "runtime drops canvas text edit state when layout replacement disables text field" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-disabled-text-reconcile", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(20, 30, 260, 140),
    });

    const text_field = canvas.Widget{
        .id = 2,
        .kind = .text_field,
        .frame = geometry.RectF.init(12, 16, 160, 36),
        .text = "Cafe",
        .semantics = .{ .label = "Name" },
    };
    var nodes: [2]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &.{text_field} }, geometry.RectF.init(0, 0, 260, 140), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    harness.runtime.views[0].canvas_widget_focused_id = 2;
    _ = try harness.runtime.editCanvasWidgetText(1, "canvas", 2, .{ .set_selection = .{ .anchor = 1, .focus = 4 } });
    _ = try harness.runtime.editCanvasWidgetText(1, "canvas", 2, .{ .set_composition = .{ .text = "af\xc3\xa9", .cursor = 4 } });

    var retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualStrings("Caf\xc3\xa9", retained.nodes[1].widget.text);
    try std.testing.expectEqualDeep(canvas.TextSelection.collapsed(5), retained.nodes[1].widget.text_selection.?);
    try std.testing.expectEqualDeep(canvas.TextRange.init(1, 5), retained.nodes[1].widget.text_composition.?);
    try std.testing.expectEqual(@as(canvas.ObjectId, 2), harness.runtime.views[0].canvas_widget_focused_id);

    const disabled_text_field = canvas.Widget{
        .id = 2,
        .kind = .text_field,
        .frame = geometry.RectF.init(24, 28, 184, 36),
        .text = "Caf\xc3\xa9",
        .state = .{ .disabled = true },
        .semantics = .{ .label = "Name" },
    };
    var disabled_nodes: [2]canvas.WidgetLayoutNode = undefined;
    const disabled_layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &.{disabled_text_field} }, geometry.RectF.init(0, 0, 260, 140), &disabled_nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", disabled_layout);

    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualStrings("Caf\xc3\xa9", retained.nodes[1].widget.text);
    try std.testing.expect(retained.nodes[1].widget.text_selection == null);
    try std.testing.expect(retained.nodes[1].widget.text_composition == null);
    try std.testing.expectEqual(@as(canvas.ObjectId, 0), harness.runtime.views[0].canvas_widget_focused_id);

    const snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expectEqual(@as(usize, 1), snapshot.widgets.len);
    try std.testing.expectEqualStrings("Caf\xc3\xa9", snapshot.widgets[0].text_value);
    try std.testing.expect(!snapshot.widgets[0].enabled);
    try std.testing.expect(!snapshot.widgets[0].focused);
    try std.testing.expect(snapshot.widgets[0].text_selection == null);
    try std.testing.expect(snapshot.widgets[0].text_composition == null);
}

test "runtime applies pointer selection to canvas text fields" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-text-pointer-selection", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(0, 0, 240, 120),
    });

    const text_field = canvas.Widget{
        .id = 2,
        .kind = .text_field,
        .frame = geometry.RectF.init(12, 16, 160, 36),
        .text = "Query",
        .semantics = .{ .label = "Search" },
    };
    var nodes: [2]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &.{text_field} }, geometry.RectF.init(0, 0, 240, 120), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_down,
        .x = 20,
        .y = 24,
    } });
    var retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualDeep(canvas.TextSelection.collapsed(0), retained.nodes[1].widget.text_selection.?);
    try std.testing.expectEqualDeep(canvas.TextRange.init(0, 0), runtimeViewWidgetSemantics(&harness.runtime.views[0])[0].text_selection.?);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_drag,
        .x = 47,
        .y = 24,
    } });
    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualDeep(canvas.TextSelection{ .anchor = 0, .focus = 3 }, retained.nodes[1].widget.text_selection.?);
    var snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expectEqualStrings("Query", snapshot.widgets[0].text_value);
    try std.testing.expectEqualDeep(automation.snapshot.TextRange{ .start = 0, .end = 3 }, snapshot.widgets[0].text_selection.?);

    _ = try harness.runtime.emitCanvasWidgetDisplayList(1, "canvas", .{});
    const selected_display_list = try harness.runtime.canvasDisplayList(1, "canvas");
    var saw_selection_fill = false;
    for (selected_display_list.commands) |command| {
        switch (command) {
            .fill_rounded_rect => |fill| {
                if (fill.id == testCanvasWidgetPartId(2, 3)) saw_selection_fill = true;
            },
            else => {},
        }
    }
    try std.testing.expect(saw_selection_fill);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "X",
        .text = "X",
    } });
    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualStrings("Xry", retained.nodes[1].widget.text);
    try std.testing.expectEqualDeep(canvas.TextSelection.collapsed(1), retained.nodes[1].widget.text_selection.?);
    snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expectEqualStrings("Xry", snapshot.widgets[0].text_value);
    try std.testing.expectEqualDeep(automation.snapshot.TextRange{ .start = 1, .end = 1 }, snapshot.widgets[0].text_selection.?);
}

test "runtime maps canvas text pointer selection with stored design tokens" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-text-pointer-token-selection", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(0, 0, 240, 120),
    });

    const text_field = canvas.Widget{
        .id = 2,
        .kind = .text_field,
        .frame = geometry.RectF.init(12, 16, 160, 36),
        .text = "Query",
        .semantics = .{ .label = "Search" },
    };
    var nodes: [2]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &.{text_field} }, geometry.RectF.init(0, 0, 240, 120), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    const tokens = canvas.DesignTokens{
        .typography = .{ .body_size = 20 },
    };
    _ = try harness.runtime.setCanvasWidgetDesignTokens(1, "canvas", tokens);

    const point = geometry.PointF.init(47, 24);
    const expected = canvas.textSelectionForWidgetPoint(text_field, point, null, tokens).?;
    const default_selection = canvas.textSelectionForWidgetPoint(text_field, point, null, .{}).?;
    try std.testing.expect(expected.focus != default_selection.focus);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_down,
        .x = point.x,
        .y = point.y,
    } });

    const retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualDeep(expected, retained.nodes[1].widget.text_selection.?);
}

test "runtime applies text input to focused canvas search fields" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-search-edit", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(0, 0, 240, 120),
    });

    const search_field = canvas.Widget{
        .id = 2,
        .kind = .search_field,
        .frame = geometry.RectF.init(12, 16, 180, 36),
        .text = "Query",
        .semantics = .{ .label = "Search" },
    };
    var nodes: [2]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &.{search_field} }, geometry.RectF.init(0, 0, 240, 120), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_down,
        .x = 188,
        .y = 24,
    } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 2), harness.runtime.views[0].canvas_widget_focused_id);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "x",
        .text = "x",
    } });
    try std.testing.expectEqual(@as(u64, 2), harness.runtime.views[0].widget_revision);

    const retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualStrings("Queryx", retained.nodes[1].widget.text);
    try std.testing.expectEqualDeep(canvas.TextSelection.collapsed(6), retained.nodes[1].widget.text_selection.?);
    try std.testing.expectEqualDeep(canvas.TextRange.init(6, 6), runtimeViewWidgetSemantics(&harness.runtime.views[0])[0].text_selection.?);
    const snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expectEqualStrings("Queryx", snapshot.widgets[0].text_value);

    _ = try harness.runtime.emitCanvasWidgetDisplayList(1, "canvas", .{});
    const display_list = try harness.runtime.canvasDisplayList(1, "canvas");
    var saw_search_icon = false;
    var saw_inserted_text = false;
    for (display_list.commands) |command| {
        switch (command) {
            .draw_line => |line| {
                if (line.id == testCanvasWidgetPartId(2, 3)) {
                    saw_search_icon = true;
                }
            },
            .draw_text => |text| {
                if (text.id == testCanvasWidgetPartId(2, 9)) {
                    try std.testing.expectEqualStrings("Queryx", text.text);
                    saw_inserted_text = true;
                }
            },
            else => {},
        }
    }
    try std.testing.expect(saw_search_icon);
    try std.testing.expect(saw_inserted_text);

    _ = try harness.runtime.editCanvasWidgetText(1, "canvas", 2, .{ .set_composition = .{ .text = "ing", .cursor = 3 } });
    try std.testing.expectEqual(@as(u64, 3), harness.runtime.views[0].widget_revision);

    const composing = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualStrings("Queryxing", composing.nodes[1].widget.text);
    try std.testing.expectEqualDeep(canvas.TextSelection.collapsed(9), composing.nodes[1].widget.text_selection.?);
    try std.testing.expectEqualDeep(canvas.TextRange.init(6, 9), composing.nodes[1].widget.text_composition.?);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "escape",
    } });
    try std.testing.expectEqual(@as(u64, 4), harness.runtime.views[0].widget_revision);

    const restored = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualStrings("Queryx", restored.nodes[1].widget.text);
    try std.testing.expectEqualDeep(canvas.TextSelection.collapsed(6), restored.nodes[1].widget.text_selection.?);
    try std.testing.expect(restored.nodes[1].widget.text_composition == null);
    const restored_snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expectEqualStrings("Queryx", restored_snapshot.widgets[0].text_value);
    try std.testing.expect(restored_snapshot.widgets[0].text_composition == null);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "escape",
    } });
    try std.testing.expectEqual(@as(u64, 5), harness.runtime.views[0].widget_revision);

    const cleared = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqualStrings("", cleared.nodes[1].widget.text);
    try std.testing.expectEqualDeep(canvas.TextSelection.collapsed(0), cleared.nodes[1].widget.text_selection.?);
    try std.testing.expectEqualDeep(canvas.TextRange.init(0, 0), runtimeViewWidgetSemantics(&harness.runtime.views[0])[0].text_selection.?);
    const cleared_snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expectEqualStrings("", cleared_snapshot.widgets[0].text_value);
    try std.testing.expectEqualDeep(automation.snapshot.TextRange{ .start = 0, .end = 0 }, cleared_snapshot.widgets[0].text_selection.?);

    _ = try harness.runtime.emitCanvasWidgetDisplayList(1, "canvas", .{});
    const cleared_display_list = try harness.runtime.canvasDisplayList(1, "canvas");
    var saw_search_placeholder = false;
    for (cleared_display_list.commands) |command| {
        switch (command) {
            .draw_text => |text| {
                if (text.id == testCanvasWidgetPartId(2, 9)) {
                    try std.testing.expectEqualStrings("Search", text.text);
                    saw_search_placeholder = true;
                }
            },
            else => {},
        }
    }
    try std.testing.expect(saw_search_placeholder);
}

test "runtime applies pointer values to canvas controls" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-control-values", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
            .kind = .slider,
            .frame = geometry.RectF.init(10, 88, 100, 32),
            .value = 0.25,
        },
    };
    var nodes: [4]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &controls }, geometry.RectF.init(0, 0, 240, 140), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

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
    try std.testing.expectEqual(@as(u64, 2), harness.runtime.views[0].widget_revision);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_down,
        .x = 84,
        .y = 60,
    } });
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_up,
        .x = 84,
        .y = 60,
    } });
    try std.testing.expectEqual(@as(u64, 3), harness.runtime.views[0].widget_revision);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_down,
        .x = 75,
        .y = 104,
    } });
    try std.testing.expectEqual(@as(u64, 4), harness.runtime.views[0].widget_revision);
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_drag,
        .x = 110,
        .y = 104,
    } });
    try std.testing.expectEqual(@as(u64, 5), harness.runtime.views[0].widget_revision);
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_up,
        .x = 10,
        .y = 104,
    } });
    try std.testing.expectEqual(@as(u64, 6), harness.runtime.views[0].widget_revision);

    const retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expect(retained.nodes[1].widget.state.selected);
    try std.testing.expectEqual(@as(f32, 1), retained.nodes[1].widget.value);
    try std.testing.expect(!retained.nodes[2].widget.state.selected);
    try std.testing.expectEqual(@as(f32, 0), retained.nodes[2].widget.value);
    try std.testing.expectEqual(@as(f32, 0), retained.nodes[3].widget.value);

    const semantics = runtimeViewWidgetSemantics(&harness.runtime.views[0]);
    try std.testing.expectEqual(@as(?f32, 1), semantics[0].value);
    try std.testing.expectEqual(@as(?f32, 0), semantics[1].value);
    try std.testing.expectEqual(@as(?f32, 0), semantics[2].value);

    const snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expect(snapshot.widgets[0].selected);
    try std.testing.expect(!snapshot.widgets[1].selected);
    try std.testing.expect(!snapshot.widgets[2].selected);

    _ = try harness.runtime.emitCanvasWidgetDisplayList(1, "canvas", .{});
    const display_list = try harness.runtime.canvasDisplayList(1, "canvas");
    var saw_checkbox_check = false;
    var saw_empty_slider_active = false;
    for (display_list.commands) |command| {
        switch (command) {
            .draw_line => |line| {
                if (line.id == testCanvasWidgetPartId(2, 4)) saw_checkbox_check = true;
            },
            .fill_rounded_rect => |fill| {
                if (fill.id == testCanvasWidgetPartId(4, 2)) {
                    try std.testing.expectEqual(@as(f32, 0), fill.rect.width);
                    saw_empty_slider_active = true;
                }
            },
            else => {},
        }
    }
    try std.testing.expect(saw_checkbox_check);
    try std.testing.expect(saw_empty_slider_active);
}

test "runtime automation widget click dispatches pointer input" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-click-automation", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(0, 0, 220, 100),
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
    };
    var nodes: [3]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &controls }, geometry.RectF.init(0, 0, 220, 100), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);
    _ = try harness.runtime.emitCanvasWidgetDisplayList(1, "canvas", .{});
    harness.null_platform.gpu_surface_frame_request_count = 0;

    try harness.runtime.dispatchAutomationCommand(app, "widget-click canvas 2");
    try harness.runtime.dispatchAutomationCommand(app, "widget-click canvas 3");
    try std.testing.expect(harness.runtime.views[0].gpu_input_timestamp_ns > 0);
    try std.testing.expect(harness.runtime.views[0].gpu_pending_input_timestamp_ns > 0);
    try std.testing.expect(harness.null_platform.gpu_surface_frame_request_count > 0);
    try std.testing.expectEqual(@as(platform.WindowId, 1), harness.null_platform.gpu_surface_frame_request_window_id);
    try std.testing.expectEqualStrings("canvas", harness.null_platform.gpu_surface_frame_request_label_storage[0..harness.null_platform.gpu_surface_frame_request_label_len]);

    const retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expect(retained.nodes[1].widget.state.selected);
    try std.testing.expectEqual(@as(f32, 1), retained.nodes[1].widget.value);
    try std.testing.expect(!retained.nodes[2].widget.state.selected);
    try std.testing.expectEqual(@as(f32, 0), retained.nodes[2].widget.value);

    const snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expect(snapshot.widgets[0].selected);
    try std.testing.expect(!snapshot.widgets[1].selected);
    try std.testing.expectError(error.InvalidCommand, harness.runtime.dispatchAutomationCommand(app, "widget-click canvas 0"));
    try std.testing.expectError(error.InvalidCommand, harness.runtime.dispatchAutomationCommand(app, "widget-click canvas 9"));
}

test "runtime batches pointer widget display list refreshes" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-pointer-refresh-batch", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(0, 0, 220, 100),
    });

    const controls = [_]canvas.Widget{.{
        .id = 4,
        .kind = .toggle,
        .frame = geometry.RectF.init(10, 20, 112, 32),
        .text = "Live",
    }};
    var nodes: [2]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &controls }, geometry.RectF.init(0, 0, 220, 100), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);
    _ = try harness.runtime.emitCanvasWidgetDisplayList(1, "canvas", .{});
    harness.null_platform.gpu_surface_frame_request_count = 0;

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_down,
        .timestamp_ns = 100,
        .x = 66,
        .y = 36,
    } });
    try std.testing.expectEqual(@as(usize, 0), harness.null_platform.gpu_surface_frame_request_count);
    try std.testing.expectEqual(@as(canvas.ObjectId, 4), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 4), harness.runtime.views[0].canvas_widget_pressed_id);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_up,
        .timestamp_ns = 110,
        .x = 66,
        .y = 36,
    } });
    try std.testing.expectEqual(@as(usize, 1), harness.null_platform.gpu_surface_frame_request_count);
    try std.testing.expectEqual(@as(canvas.ObjectId, 0), harness.runtime.views[0].canvas_widget_pressed_id);

    const retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expect(retained.nodes[1].widget.state.selected);
    try std.testing.expectEqual(@as(f32, 1), retained.nodes[1].widget.value);

    const travel = canvas.toggleWidgetKnobTravel(retained.nodes[1].widget, harness.runtime.views[0].widget_tokens);
    const animations = try harness.runtime.canvasRenderAnimations(1, "canvas");
    try std.testing.expectEqual(@as(usize, 1), animations.len);
    try std.testing.expectEqual(canvas.toggleWidgetKnobCommandId(4), animations[0].id);
    try std.testing.expectEqual(@as(u64, 110), animations[0].start_ns);
    try std.testing.expectEqual(harness.runtime.views[0].widget_tokens.motion.durationMs(.fast), animations[0].duration_ms);
    try std.testing.expectApproxEqAbs(-travel, animations[0].from_transform.?.tx, 0.001);
    try std.testing.expectEqual(canvas.Affine.identity(), animations[0].to_transform.?);
    const expected_toggle_dirty = runtimeViewCanvasWidgetDirtyBounds(&harness.runtime.views[0], 1, retained.nodes[1].widget.frame).?;
    try std.testing.expectEqual(@as(usize, 1), harness.runtime.views[0].canvas_render_animation_dirty_bounds_count);
    try std.testing.expectEqual(canvas.toggleWidgetKnobCommandId(4), harness.runtime.views[0].canvas_render_animation_dirty_bounds[0].id);
    try std.testing.expectEqualDeep(expected_toggle_dirty, harness.runtime.views[0].canvas_render_animation_dirty_bounds[0].bounds.?);

    var overrides: [1]canvas.CanvasRenderOverride = undefined;
    const sampled = try canvas.sampleCanvasRenderAnimations(animations, 110 + 60_000_000, &overrides);
    try std.testing.expectEqual(@as(usize, 1), sampled.len);
    try std.testing.expect(sampled[0].transform.?.tx > -travel);
    try std.testing.expect(sampled[0].transform.?.tx < 0);
    try std.testing.expectEqualDeep(expected_toggle_dirty, runtimeViewCanvasRenderAnimationDirtyBoundsForOverrides(&harness.runtime.views[0], &.{}, sampled).?);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_down,
        .timestamp_ns = 200,
        .x = 66,
        .y = 36,
    } });
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_up,
        .timestamp_ns = 210,
        .x = 66,
        .y = 36,
    } });
    const reverse_animations = try harness.runtime.canvasRenderAnimations(1, "canvas");
    try std.testing.expectEqual(@as(usize, 1), reverse_animations.len);
    try std.testing.expectEqual(canvas.toggleWidgetKnobCommandId(4), reverse_animations[0].id);
    try std.testing.expectEqual(@as(u64, 210), reverse_animations[0].start_ns);
    try std.testing.expectApproxEqAbs(travel, reverse_animations[0].from_transform.?.tx, 0.001);
}

test "runtime batches keyboard widget display list refreshes" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-keyboard-refresh-batch", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(0, 0, 240, 100),
    });

    const controls = [_]canvas.Widget{
        .{
            .id = 2,
            .kind = .button,
            .frame = geometry.RectF.init(10, 20, 96, 32),
            .text = "One",
        },
        .{
            .id = 3,
            .kind = .button,
            .frame = geometry.RectF.init(118, 20, 96, 32),
            .text = "Two",
        },
    };
    var nodes: [3]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &controls }, geometry.RectF.init(0, 0, 240, 100), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);
    _ = try harness.runtime.emitCanvasWidgetDisplayList(1, "canvas", .{});
    harness.runtime.views[0].focused = false;
    harness.runtime.views[0].canvas_widget_focused_id = 2;
    harness.null_platform.gpu_surface_frame_request_count = 0;

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .timestamp_ns = 100,
        .key = "tab",
    } });
    try std.testing.expectEqual(@as(usize, 1), harness.null_platform.gpu_surface_frame_request_count);
    try std.testing.expect(harness.runtime.views[0].focused);
    try std.testing.expectEqual(@as(canvas.ObjectId, 3), harness.runtime.views[0].canvas_widget_focused_id);
}

test "runtime automation widget drag dispatches pointer input" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-drag-automation", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(0, 0, 220, 100),
    });

    const controls = [_]canvas.Widget{.{
        .id = 4,
        .kind = .slider,
        .frame = geometry.RectF.init(10, 20, 100, 32),
        .value = 0.25,
    }};
    var nodes: [2]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &controls }, geometry.RectF.init(0, 0, 220, 100), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);
    _ = try harness.runtime.emitCanvasWidgetDisplayList(1, "canvas", .{});
    harness.null_platform.gpu_surface_frame_request_count = 0;

    try harness.runtime.dispatchAutomationCommand(app, "widget-drag canvas 4 0.25 0.82");
    try std.testing.expect(harness.runtime.views[0].gpu_input_timestamp_ns > 0);
    try std.testing.expect(harness.runtime.views[0].gpu_pending_input_timestamp_ns > 0);
    try std.testing.expect(harness.null_platform.gpu_surface_frame_request_count > 0);
    try std.testing.expectEqual(@as(platform.WindowId, 1), harness.null_platform.gpu_surface_frame_request_window_id);
    try std.testing.expectEqualStrings("canvas", harness.null_platform.gpu_surface_frame_request_label_storage[0..harness.null_platform.gpu_surface_frame_request_label_len]);
    try std.testing.expectEqual(@as(canvas.ObjectId, 4), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 4), harness.runtime.views[0].canvas_widget_hovered_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 0), harness.runtime.views[0].canvas_widget_pressed_id);

    const retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectApproxEqAbs(@as(f32, 0.82), retained.nodes[1].widget.value, 0.001);

    const snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expectEqual(@as(usize, 1), snapshot.widgets.len);
    try std.testing.expect(snapshot.widgets[0].focused);
    try std.testing.expect(snapshot.widgets[0].hovered);
    try std.testing.expect(!snapshot.widgets[0].pressed);
    try std.testing.expectApproxEqAbs(@as(f32, 0.82), snapshot.widgets[0].value.?, 0.001);

    try std.testing.expectError(error.InvalidCommand, harness.runtime.dispatchAutomationCommand(app, "widget-drag canvas 0 0.25 0.82"));
    try std.testing.expectError(error.InvalidCommand, harness.runtime.dispatchAutomationCommand(app, "widget-drag canvas 9 0.25 0.82"));
}

test "runtime reconciles canvas control state across layout replacement" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-control-reconcile", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(0, 0, 280, 220),
    });

    const list_items = [_]canvas.Widget{
        .{
            .id = 5,
            .kind = .list_item,
            .frame = geometry.RectF.init(0, 0, 0, 30),
            .text = "Overview",
            .state = .{ .selected = true },
        },
        .{
            .id = 6,
            .kind = .list_item,
            .frame = geometry.RectF.init(0, 36, 0, 30),
            .text = "Customers",
        },
    };
    const mode_items = [_]canvas.Widget{
        .{
            .id = 7,
            .kind = .segmented_control,
            .frame = geometry.RectF.init(0, 0, 72, 30),
            .text = "List",
            .state = .{ .selected = true },
        },
        .{
            .id = 8,
            .kind = .segmented_control,
            .frame = geometry.RectF.init(80, 0, 72, 30),
            .text = "Grid",
        },
    };
    const data_cells = [_]canvas.Widget{
        .{
            .id = 11,
            .kind = .data_cell,
            .frame = geometry.RectF.init(0, 0, 72, 30),
            .text = "Edge",
            .state = .{ .selected = true },
        },
        .{
            .id = 12,
            .kind = .data_cell,
            .frame = geometry.RectF.init(80, 0, 72, 30),
            .text = "Billing",
        },
    };
    const menu_items = [_]canvas.Widget{
        .{
            .id = 13,
            .kind = .menu_item,
            .frame = geometry.RectF.init(0, 0, 0, 30),
            .text = "Copy",
            .state = .{ .selected = true },
        },
        .{
            .id = 14,
            .kind = .menu_item,
            .frame = geometry.RectF.init(0, 36, 0, 30),
            .text = "Archive",
        },
    };
    const radio_items = [_]canvas.Widget{
        .{
            .id = 16,
            .kind = .radio,
            .frame = geometry.RectF.init(0, 0, 80, 30),
            .text = "Monthly",
            .state = .{ .selected = true },
        },
        .{
            .id = 17,
            .kind = .radio,
            .frame = geometry.RectF.init(88, 0, 72, 30),
            .text = "Annual",
        },
    };
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
            .kind = .slider,
            .frame = geometry.RectF.init(10, 88, 120, 32),
            .value = 0.5,
        },
        .{
            .id = 10,
            .kind = .list,
            .frame = geometry.RectF.init(150, 10, 110, 72),
            .children = &list_items,
        },
        .{
            .kind = .row,
            .frame = geometry.RectF.init(10, 140, 160, 30),
            .children = &mode_items,
        },
        .{
            .kind = .row,
            .frame = geometry.RectF.init(10, 178, 160, 30),
            .children = &data_cells,
        },
        .{
            .id = 15,
            .kind = .menu_surface,
            .frame = geometry.RectF.init(150, 96, 110, 72),
            .children = &menu_items,
        },
        .{
            .kind = .row,
            .frame = geometry.RectF.init(150, 178, 160, 30),
            .children = &radio_items,
        },
    };
    var nodes: [20]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &controls }, geometry.RectF.init(0, 0, 280, 220), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    try dispatchAutomationWidgetAction(&harness.runtime, app, .{ .view_label = "canvas", .id = 2, .action = .toggle });
    try dispatchAutomationWidgetAction(&harness.runtime, app, .{ .view_label = "canvas", .id = 3, .action = .toggle });
    try dispatchAutomationWidgetAction(&harness.runtime, app, .{ .view_label = "canvas", .id = 4, .action = .increment });
    try dispatchAutomationWidgetAction(&harness.runtime, app, .{ .view_label = "canvas", .id = 6, .action = .select });
    try dispatchAutomationWidgetAction(&harness.runtime, app, .{ .view_label = "canvas", .id = 8, .action = .select });
    try dispatchAutomationWidgetAction(&harness.runtime, app, .{ .view_label = "canvas", .id = 12, .action = .select });
    try dispatchAutomationWidgetAction(&harness.runtime, app, .{ .view_label = "canvas", .id = 14, .action = .select });
    try dispatchAutomationWidgetAction(&harness.runtime, app, .{ .view_label = "canvas", .id = 17, .action = .select });

    var retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expect(retained.findById(2).?.widget.state.selected);
    try std.testing.expectEqual(@as(f32, 1), retained.findById(2).?.widget.value);
    try std.testing.expect(!retained.findById(3).?.widget.state.selected);
    try std.testing.expectEqual(@as(f32, 0), retained.findById(3).?.widget.value);
    try std.testing.expectApproxEqAbs(@as(f32, 0.55), retained.findById(4).?.widget.value, 0.001);
    try std.testing.expect(!retained.findById(5).?.widget.state.selected);
    try std.testing.expect(retained.findById(6).?.widget.state.selected);
    try std.testing.expect(!retained.findById(7).?.widget.state.selected);
    try std.testing.expect(retained.findById(8).?.widget.state.selected);
    try std.testing.expect(!retained.findById(11).?.widget.state.selected);
    try std.testing.expect(retained.findById(12).?.widget.state.selected);
    try std.testing.expect(!retained.findById(13).?.widget.state.selected);
    try std.testing.expect(retained.findById(14).?.widget.state.selected);
    try std.testing.expect(!retained.findById(16).?.widget.state.selected);
    try std.testing.expect(retained.findById(17).?.widget.state.selected);

    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expect(retained.findById(2).?.widget.state.selected);
    try std.testing.expectEqual(@as(f32, 1), retained.findById(2).?.widget.value);
    try std.testing.expect(!retained.findById(3).?.widget.state.selected);
    try std.testing.expectEqual(@as(f32, 0), retained.findById(3).?.widget.value);
    try std.testing.expectApproxEqAbs(@as(f32, 0.55), retained.findById(4).?.widget.value, 0.001);
    try std.testing.expect(!retained.findById(5).?.widget.state.selected);
    try std.testing.expectEqual(@as(f32, 0), retained.findById(5).?.widget.value);
    try std.testing.expect(retained.findById(6).?.widget.state.selected);
    try std.testing.expectEqual(@as(f32, 1), retained.findById(6).?.widget.value);
    try std.testing.expect(!retained.findById(7).?.widget.state.selected);
    try std.testing.expectEqual(@as(f32, 0), retained.findById(7).?.widget.value);
    try std.testing.expect(retained.findById(8).?.widget.state.selected);
    try std.testing.expectEqual(@as(f32, 1), retained.findById(8).?.widget.value);
    try std.testing.expect(!retained.findById(11).?.widget.state.selected);
    try std.testing.expectEqual(@as(f32, 0), retained.findById(11).?.widget.value);
    try std.testing.expect(retained.findById(12).?.widget.state.selected);
    try std.testing.expectEqual(@as(f32, 1), retained.findById(12).?.widget.value);
    try std.testing.expect(!retained.findById(13).?.widget.state.selected);
    try std.testing.expectEqual(@as(f32, 0), retained.findById(13).?.widget.value);
    try std.testing.expect(retained.findById(14).?.widget.state.selected);
    try std.testing.expectEqual(@as(f32, 1), retained.findById(14).?.widget.value);
    try std.testing.expect(!retained.findById(16).?.widget.state.selected);
    try std.testing.expectEqual(@as(f32, 0), retained.findById(16).?.widget.value);
    try std.testing.expect(retained.findById(17).?.widget.state.selected);
    try std.testing.expectEqual(@as(f32, 1), retained.findById(17).?.widget.value);
    try std.testing.expect(!harness.runtime.invalidated);
    try std.testing.expectEqual(@as(usize, 0), harness.runtime.pendingDirtyRegions().len);

    const semantics = runtimeViewWidgetSemantics(&harness.runtime.views[0]);
    try std.testing.expectEqual(@as(?f32, 1), canvasWidgetSemanticsById(semantics, 2).?.value);
    try std.testing.expectEqual(@as(?f32, 0), canvasWidgetSemanticsById(semantics, 3).?.value);
    try std.testing.expectApproxEqAbs(@as(f32, 0.55), canvasWidgetSemanticsById(semantics, 4).?.value.?, 0.001);
    try std.testing.expectEqual(@as(?f32, 0), canvasWidgetSemanticsById(semantics, 5).?.value);
    try std.testing.expectEqual(@as(?f32, 1), canvasWidgetSemanticsById(semantics, 6).?.value);
    try std.testing.expectEqual(@as(?f32, 0), canvasWidgetSemanticsById(semantics, 7).?.value);
    try std.testing.expectEqual(@as(?f32, 1), canvasWidgetSemanticsById(semantics, 8).?.value);
    try std.testing.expectEqual(@as(?f32, 0), canvasWidgetSemanticsById(semantics, 11).?.value);
    try std.testing.expectEqual(@as(?f32, 1), canvasWidgetSemanticsById(semantics, 12).?.value);
    try std.testing.expectEqual(@as(?f32, 0), canvasWidgetSemanticsById(semantics, 13).?.value);
    try std.testing.expectEqual(@as(?f32, 1), canvasWidgetSemanticsById(semantics, 14).?.value);
    try std.testing.expectEqual(@as(?f32, 0), canvasWidgetSemanticsById(semantics, 16).?.value);
    try std.testing.expectEqual(@as(?f32, 1), canvasWidgetSemanticsById(semantics, 17).?.value);
}

test "runtime drives retained settings and data grid workflow" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-settings-grid-workflow", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(12, 18, 380, 300),
    });

    const mode_items = [_]canvas.Widget{
        .{ .id = 22, .kind = .segmented_control, .frame = geometry.RectF.init(150, 18, 82, 30), .text = "List", .state = .{ .selected = true } },
        .{ .id = 23, .kind = .segmented_control, .frame = geometry.RectF.init(238, 18, 82, 30), .text = "Grid" },
    };
    const header_cells = [_]canvas.Widget{
        .{ .id = 32, .kind = .data_cell, .text = "Project", .layout = .{ .grow = 1 } },
        .{ .id = 33, .kind = .data_cell, .text = "Status", .layout = .{ .grow = 1 } },
    };
    const edge_cells = [_]canvas.Widget{
        .{ .id = 35, .kind = .data_cell, .text = "Edge API", .layout = .{ .grow = 1 } },
        .{ .id = 36, .kind = .data_cell, .text = "Live", .layout = .{ .grow = 1 } },
    };
    const billing_cells = [_]canvas.Widget{
        .{ .id = 38, .kind = .data_cell, .text = "Billing", .layout = .{ .grow = 1 } },
        .{ .id = 39, .kind = .data_cell, .text = "Queued", .layout = .{ .grow = 1 } },
    };
    const rows = [_]canvas.Widget{
        .{ .id = 31, .kind = .data_row, .frame = geometry.RectF.init(0, 0, 0, 28), .children = &header_cells },
        .{ .id = 34, .kind = .data_row, .frame = geometry.RectF.init(0, 0, 0, 28), .children = &edge_cells },
        .{ .id = 37, .kind = .data_row, .frame = geometry.RectF.init(0, 0, 0, 28), .children = &billing_cells },
    };
    const controls = [_]canvas.Widget{
        .{ .id = 20, .kind = .checkbox, .frame = geometry.RectF.init(18, 18, 116, 28), .text = "Live data" },
        .{ .id = 21, .kind = .toggle, .frame = geometry.RectF.init(18, 58, 116, 28), .text = "Compact", .state = .{ .selected = true } },
        .{ .kind = .row, .frame = geometry.RectF.init(150, 18, 170, 30), .layout = .{ .gap = 6 }, .children = &mode_items },
        .{ .id = 24, .kind = .search_field, .frame = geometry.RectF.init(150, 58, 170, 34), .text = "edge", .semantics = .{ .label = "Deployment search" } },
        .{ .id = 30, .kind = .data_grid, .frame = geometry.RectF.init(18, 112, 330, 94), .text = "Deployments", .layout = .{ .gap = 3 }, .children = &rows },
    };
    const root = canvas.Widget{
        .id = 10,
        .kind = .panel,
        .frame = geometry.RectF.init(0, 0, 360, 236),
        .text = "Deployment settings",
        .children = &controls,
    };
    var nodes: [20]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(root, geometry.RectF.init(0, 0, 360, 236), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);
    _ = try harness.runtime.emitCanvasWidgetDisplayList(1, "canvas", .{});

    try dispatchAutomationWidgetAction(&harness.runtime, app, .{ .view_label = "canvas", .id = 20, .action = .toggle });
    try dispatchAutomationWidgetAction(&harness.runtime, app, .{ .view_label = "canvas", .id = 21, .action = .toggle });
    try dispatchAutomationWidgetAction(&harness.runtime, app, .{ .view_label = "canvas", .id = 23, .action = .select });
    try dispatchAutomationWidgetAction(&harness.runtime, app, .{ .view_label = "canvas", .id = 24, .action = .set_text, .value = "edge customers" });
    try dispatchAutomationWidgetAction(&harness.runtime, app, .{ .view_label = "canvas", .id = 36, .action = .select });

    var retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expect(retained.findById(20).?.widget.state.selected);
    try std.testing.expectEqual(@as(f32, 1), retained.findById(20).?.widget.value);
    try std.testing.expect(!retained.findById(21).?.widget.state.selected);
    try std.testing.expectEqual(@as(f32, 0), retained.findById(21).?.widget.value);
    try std.testing.expect(!retained.findById(22).?.widget.state.selected);
    try std.testing.expect(retained.findById(23).?.widget.state.selected);
    try std.testing.expectEqualStrings("edge customers", retained.findById(24).?.widget.text);
    try std.testing.expect(!retained.findById(35).?.widget.state.selected);
    try std.testing.expect(retained.findById(36).?.widget.state.selected);

    var semantics = runtimeViewWidgetSemantics(&harness.runtime.views[0]);
    try std.testing.expectEqual(canvas.WidgetRole.grid, canvasWidgetSemanticsById(semantics, 30).?.role);
    try std.testing.expectEqual(@as(?usize, 3), canvasWidgetSemanticsById(semantics, 30).?.grid_row_count);
    try std.testing.expectEqual(@as(?usize, 2), canvasWidgetSemanticsById(semantics, 30).?.grid_column_count);
    try std.testing.expectEqualStrings("edge customers", canvasWidgetSemanticsById(semantics, 24).?.text_value);
    try std.testing.expectEqual(@as(?f32, 1), canvasWidgetSemanticsById(semantics, 20).?.value);
    try std.testing.expectEqual(@as(?f32, 0), canvasWidgetSemanticsById(semantics, 21).?.value);
    try std.testing.expectEqual(@as(?f32, 1), canvasWidgetSemanticsById(semantics, 23).?.value);
    try std.testing.expectEqual(@as(?usize, 1), canvasWidgetSemanticsById(semantics, 36).?.grid_row_index);
    try std.testing.expectEqual(@as(?usize, 1), canvasWidgetSemanticsById(semantics, 36).?.grid_column_index);
    try std.testing.expectEqual(@as(?f32, 1), canvasWidgetSemanticsById(semantics, 36).?.value);

    const snapshot = harness.runtime.automationSnapshot("Settings");
    var a11y_buffer: [4096]u8 = undefined;
    var a11y_writer = std.Io.Writer.fixed(&a11y_buffer);
    try automation.snapshot.writeA11yText(snapshot, &a11y_writer);
    try std.testing.expect(std.mem.indexOf(u8, a11y_writer.buffered(), "@w1/canvas#20 role=checkbox name=\"Live data\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, a11y_writer.buffered(), "@w1/canvas#24 role=textbox name=\"Deployment search\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, a11y_writer.buffered(), "text=\"edge customers\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, a11y_writer.buffered(), "@w1/canvas#30 role=grid name=\"Deployments\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, a11y_writer.buffered(), "@w1/canvas#36 role=gridcell name=\"Live\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, a11y_writer.buffered(), "grid=[row_index=1,column_index=1,row_count=3,column_count=2]") != null);

    const next_edge_cells = [_]canvas.Widget{
        .{ .id = 35, .kind = .data_cell, .text = "Edge API", .layout = .{ .grow = 1 } },
        .{ .id = 36, .kind = .data_cell, .text = "Ready", .layout = .{ .grow = 1 } },
    };
    const next_billing_cells = [_]canvas.Widget{
        .{ .id = 38, .kind = .data_cell, .text = "Billing", .layout = .{ .grow = 1 } },
        .{ .id = 39, .kind = .data_cell, .text = "Filtered", .layout = .{ .grow = 1 } },
    };
    const next_rows = [_]canvas.Widget{
        .{ .id = 31, .kind = .data_row, .frame = geometry.RectF.init(0, 0, 0, 28), .children = &header_cells },
        .{ .id = 34, .kind = .data_row, .frame = geometry.RectF.init(0, 0, 0, 28), .children = &next_edge_cells },
        .{ .id = 37, .kind = .data_row, .frame = geometry.RectF.init(0, 0, 0, 28), .children = &next_billing_cells },
    };
    const next_controls = [_]canvas.Widget{
        .{ .id = 20, .kind = .checkbox, .frame = geometry.RectF.init(18, 18, 116, 28), .text = "Live data" },
        .{ .id = 21, .kind = .toggle, .frame = geometry.RectF.init(18, 58, 116, 28), .text = "Compact", .state = .{ .selected = true } },
        .{ .kind = .row, .frame = geometry.RectF.init(150, 18, 170, 30), .layout = .{ .gap = 6 }, .children = &mode_items },
        .{ .id = 24, .kind = .search_field, .frame = geometry.RectF.init(150, 58, 170, 34), .text = "edge customers", .semantics = .{ .label = "Deployment search" } },
        .{ .id = 30, .kind = .data_grid, .frame = geometry.RectF.init(18, 112, 330, 94), .text = "Deployments", .layout = .{ .gap = 3 }, .children = &next_rows },
    };
    const next_root = canvas.Widget{
        .id = 10,
        .kind = .panel,
        .frame = geometry.RectF.init(0, 0, 360, 236),
        .text = "Deployment settings",
        .children = &next_controls,
    };
    var next_nodes: [20]canvas.WidgetLayoutNode = undefined;
    const next_layout = try canvas.layoutWidgetTree(next_root, geometry.RectF.init(0, 0, 360, 236), &next_nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", next_layout);

    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expect(retained.findById(20).?.widget.state.selected);
    try std.testing.expect(!retained.findById(21).?.widget.state.selected);
    try std.testing.expect(!retained.findById(22).?.widget.state.selected);
    try std.testing.expect(retained.findById(23).?.widget.state.selected);
    try std.testing.expect(retained.findById(36).?.widget.state.selected);
    try std.testing.expectEqualStrings("Ready", retained.findById(36).?.widget.text);

    semantics = runtimeViewWidgetSemantics(&harness.runtime.views[0]);
    try std.testing.expectEqualStrings("Ready", canvasWidgetSemanticsById(semantics, 36).?.label);
    try std.testing.expectEqual(@as(?f32, 1), canvasWidgetSemanticsById(semantics, 36).?.value);
    try std.testing.expectEqual(@as(?f32, 1), canvasWidgetSemanticsById(semantics, 23).?.value);
}

test "runtime refreshes widget owned display list from canvas input" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-display-list-input", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(0, 0, 180, 80),
    });

    const controls = [_]canvas.Widget{.{
        .id = 2,
        .kind = .checkbox,
        .frame = geometry.RectF.init(10, 10, 120, 28),
        .text = "Live",
    }};
    var nodes: [2]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &controls }, geometry.RectF.init(0, 0, 180, 80), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);
    _ = try harness.runtime.emitCanvasWidgetDisplayList(1, "canvas", .{});

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_down,
        .x = 18,
        .y = 20,
    } });
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_up,
        .x = 18,
        .y = 20,
    } });

    const display_list = try harness.runtime.canvasDisplayList(1, "canvas");
    var saw_checkbox_check = false;
    for (display_list.commands) |command| {
        switch (command) {
            .draw_line => |line| {
                if (line.id == testCanvasWidgetPartId(2, 4)) saw_checkbox_check = true;
            },
            else => {},
        }
    }
    try std.testing.expect(saw_checkbox_check);
}

test "runtime routes canvas widget pointers using design token layers" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-layered-input", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(0, 0, 160, 100),
    });

    const widgets = [_]canvas.Widget{
        .{
            .id = 2,
            .kind = .popover,
            .frame = geometry.RectF.init(8, 8, 96, 64),
        },
        .{
            .id = 3,
            .kind = .button,
            .frame = geometry.RectF.init(12, 12, 80, 32),
            .text = "Base",
        },
    };
    var nodes: [3]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &widgets }, geometry.RectF.init(0, 0, 160, 100), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    var route_entries: [4]canvas.WidgetEventRouteEntry = undefined;
    const default_route = (try harness.runtime.routeCanvasWidgetPointerInput(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_down,
        .x = 20,
        .y = 20,
    }, &route_entries)).?;
    try std.testing.expectEqual(@as(canvas.ObjectId, 2), default_route.target.?.id);

    _ = try harness.runtime.setCanvasWidgetDesignTokens(1, "canvas", .{
        .layer = .{
            .base = 10,
            .floating = 20,
            .overlay = 0,
            .modal = 30,
        },
    });
    const lowered_overlay_route = (try harness.runtime.routeCanvasWidgetPointerInput(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_down,
        .x = 20,
        .y = 20,
    }, &route_entries)).?;
    try std.testing.expectEqual(@as(canvas.ObjectId, 3), lowered_overlay_route.target.?.id);
}

test "runtime selects canvas widgets from pointer and keyboard activation" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-select-controls", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(0, 0, 240, 150),
    });

    const controls = [_]canvas.Widget{
        .{
            .id = 2,
            .kind = .list_item,
            .frame = geometry.RectF.init(10, 10, 120, 32),
            .text = "Inbox",
        },
        .{
            .id = 3,
            .kind = .segmented_control,
            .frame = geometry.RectF.init(10, 52, 120, 32),
            .text = "Grid",
        },
        .{
            .id = 4,
            .kind = .data_cell,
            .frame = geometry.RectF.init(10, 94, 120, 32),
            .text = "Edge API",
        },
    };
    var nodes: [4]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &controls }, geometry.RectF.init(0, 0, 240, 150), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_down,
        .x = 20,
        .y = 20,
    } });
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_up,
        .x = 20,
        .y = 20,
    } });
    try std.testing.expectEqual(@as(u64, 2), harness.runtime.views[0].widget_revision);

    var retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expect(retained.findById(2).?.widget.state.selected);
    try std.testing.expectEqual(@as(f32, 1), retained.findById(2).?.widget.value);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_down,
        .x = 20,
        .y = 62,
    } });
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_up,
        .x = 220,
        .y = 62,
    } });
    try std.testing.expectEqual(@as(u64, 2), harness.runtime.views[0].widget_revision);
    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expect(!retained.findById(3).?.widget.state.selected);

    harness.runtime.views[0].canvas_widget_focused_id = 4;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "space",
    } });
    try std.testing.expectEqual(@as(u64, 3), harness.runtime.views[0].widget_revision);

    harness.runtime.views[0].canvas_widget_focused_id = 3;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "enter",
        .modifiers = .{ .option = true },
    } });
    try std.testing.expectEqual(@as(u64, 3), harness.runtime.views[0].widget_revision);

    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expect(!retained.findById(3).?.widget.state.selected);
    try std.testing.expect(retained.findById(4).?.widget.state.selected);
    try std.testing.expectEqual(@as(f32, 1), retained.findById(4).?.widget.value);

    const semantics = runtimeViewWidgetSemantics(&harness.runtime.views[0]);
    try std.testing.expectEqual(@as(usize, 3), semantics.len);
    try std.testing.expectEqual(@as(?f32, 1), semantics[0].value);
    try std.testing.expectEqual(@as(?f32, 0), semantics[1].value);
    try std.testing.expectEqual(@as(?f32, 1), semantics[2].value);

    const snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expect(snapshot.widgets[0].selected);
    try std.testing.expect(!snapshot.widgets[1].selected);
    try std.testing.expect(snapshot.widgets[2].selected);
}

test "runtime clears sibling canvas selections in retained groups" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-select-groups", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(30, 40, 260, 180),
    });

    const nav_items = [_]canvas.Widget{
        .{
            .id = 2,
            .kind = .list_item,
            .frame = geometry.RectF.init(0, 0, 0, 32),
            .text = "Overview",
            .state = .{ .selected = true },
        },
        .{
            .id = 3,
            .kind = .list_item,
            .frame = geometry.RectF.init(0, 0, 0, 32),
            .text = "Customers",
        },
    };
    const mode_items = [_]canvas.Widget{
        .{
            .id = 4,
            .kind = .segmented_control,
            .frame = geometry.RectF.init(0, 0, 64, 32),
            .text = "List",
            .state = .{ .selected = true },
        },
        .{
            .id = 5,
            .kind = .segmented_control,
            .frame = geometry.RectF.init(0, 0, 64, 32),
            .text = "Grid",
        },
    };
    const menu_items = [_]canvas.Widget{
        .{
            .id = 6,
            .kind = .menu_item,
            .frame = geometry.RectF.init(0, 0, 0, 28),
            .text = "Rename",
            .state = .{ .selected = true },
        },
        .{
            .id = 7,
            .kind = .menu_item,
            .frame = geometry.RectF.init(0, 0, 0, 28),
            .text = "Archive",
        },
    };
    const groups = [_]canvas.Widget{
        .{
            .id = 10,
            .kind = .list,
            .frame = geometry.RectF.init(10, 10, 120, 68),
            .layout = .{ .gap = 4 },
            .children = &nav_items,
        },
        .{
            .id = 0,
            .kind = .row,
            .frame = geometry.RectF.init(10, 96, 140, 32),
            .layout = .{ .gap = 8 },
            .children = &mode_items,
        },
        .{
            .id = 11,
            .kind = .menu_surface,
            .frame = geometry.RectF.init(160, 10, 90, 68),
            .layout = .{ .gap = 4 },
            .children = &menu_items,
        },
    };
    var nodes: [10]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &groups }, geometry.RectF.init(0, 0, 260, 180), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_down,
        .x = 20,
        .y = 50,
    } });
    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_up,
        .x = 20,
        .y = 50,
    } });

    var retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expect(!retained.findById(2).?.widget.state.selected);
    try std.testing.expectEqual(@as(f32, 0), retained.findById(2).?.widget.value);
    try std.testing.expect(retained.findById(3).?.widget.state.selected);
    try std.testing.expectEqual(@as(f32, 1), retained.findById(3).?.widget.value);
    try std.testing.expect(harness.runtime.pendingDirtyRegions().len >= 1);
    try std.testing.expectEqualDeep(geometry.RectF.init(40, 50, 120, 68), harness.runtime.pendingDirtyRegions()[0]);

    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    harness.runtime.views[0].canvas_widget_focused_id = 5;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "enter",
    } });

    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expect(!retained.findById(4).?.widget.state.selected);
    try std.testing.expectEqual(@as(f32, 0), retained.findById(4).?.widget.value);
    try std.testing.expect(retained.findById(5).?.widget.state.selected);
    try std.testing.expectEqual(@as(f32, 1), retained.findById(5).?.widget.value);

    const semantics = runtimeViewWidgetSemantics(&harness.runtime.views[0]);
    try std.testing.expectEqual(@as(?f32, 0), semantics[1].value);
    try std.testing.expectEqual(@as(?f32, 1), semantics[2].value);
    try std.testing.expectEqual(@as(?f32, 0), semantics[3].value);
    try std.testing.expectEqual(@as(?f32, 1), semantics[4].value);
    try std.testing.expect(semantics[6].actions.press);
    try std.testing.expect(semantics[6].actions.select);
    try std.testing.expect(semantics[7].actions.press);
    try std.testing.expect(semantics[7].actions.select);

    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    harness.runtime.views[0].canvas_widget_focused_id = 7;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "space",
    } });

    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expect(!retained.findById(6).?.widget.state.selected);
    try std.testing.expectEqual(@as(f32, 0), retained.findById(6).?.widget.value);
    try std.testing.expect(retained.findById(7).?.widget.state.selected);
    try std.testing.expectEqual(@as(f32, 1), retained.findById(7).?.widget.value);

    const menu_semantics = runtimeViewWidgetSemantics(&harness.runtime.views[0]);
    try std.testing.expectEqual(@as(?f32, 0), menu_semantics[6].value);
    try std.testing.expectEqual(@as(?f32, 1), menu_semantics[7].value);

    const snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expect(!snapshot.widgets[1].selected);
    try std.testing.expect(snapshot.widgets[2].selected);
    try std.testing.expect(!snapshot.widgets[3].selected);
    try std.testing.expect(snapshot.widgets[4].selected);
    try std.testing.expect(!snapshot.widgets[6].selected);
    try std.testing.expect(snapshot.widgets[7].selected);
}

test "runtime applies keyboard values to focused canvas controls" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-control-keyboard", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(0, 0, 240, 180),
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
            .kind = .slider,
            .frame = geometry.RectF.init(10, 88, 100, 32),
            .value = 0.5,
        },
        .{
            .id = 5,
            .kind = .accordion,
            .frame = geometry.RectF.init(10, 126, 140, 36),
            .text = "Advanced",
        },
    };
    var nodes: [5]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &controls }, geometry.RectF.init(0, 0, 240, 180), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    harness.runtime.views[0].canvas_widget_focused_id = 2;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "space",
    } });
    try std.testing.expectEqual(@as(u64, 2), harness.runtime.views[0].widget_revision);

    harness.runtime.views[0].canvas_widget_focused_id = 3;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "enter",
    } });
    try std.testing.expectEqual(@as(u64, 3), harness.runtime.views[0].widget_revision);

    harness.runtime.views[0].canvas_widget_focused_id = 4;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "arrowright",
    } });
    try std.testing.expectEqual(@as(u64, 4), harness.runtime.views[0].widget_revision);
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "arrowleft",
        .modifiers = .{ .shift = true },
    } });
    try std.testing.expectEqual(@as(u64, 5), harness.runtime.views[0].widget_revision);
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "end",
    } });
    try std.testing.expectEqual(@as(u64, 6), harness.runtime.views[0].widget_revision);
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "arrowleft",
        .modifiers = .{ .option = true },
    } });
    try std.testing.expectEqual(@as(u64, 6), harness.runtime.views[0].widget_revision);

    harness.runtime.views[0].canvas_widget_focused_id = 5;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "enter",
    } });
    try std.testing.expectEqual(@as(u64, 7), harness.runtime.views[0].widget_revision);

    const retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expect(retained.nodes[1].widget.state.selected);
    try std.testing.expectEqual(@as(f32, 1), retained.nodes[1].widget.value);
    try std.testing.expect(!retained.nodes[2].widget.state.selected);
    try std.testing.expectEqual(@as(f32, 0), retained.nodes[2].widget.value);
    try std.testing.expectEqual(@as(f32, 1), retained.nodes[3].widget.value);
    try std.testing.expect(retained.findById(5).?.widget.state.selected);
    try std.testing.expectEqual(@as(f32, 1), retained.findById(5).?.widget.value);

    const semantics = runtimeViewWidgetSemantics(&harness.runtime.views[0]);
    try std.testing.expectEqual(@as(?f32, 1), semantics[0].value);
    try std.testing.expectEqual(@as(?f32, 0), semantics[1].value);
    try std.testing.expectEqual(@as(?f32, 1), semantics[2].value);
    try std.testing.expectEqual(@as(?f32, 1), semantics[3].value);

    _ = try harness.runtime.emitCanvasWidgetDisplayList(1, "canvas", .{});
    const display_list = try harness.runtime.canvasDisplayList(1, "canvas");
    var saw_full_slider_active = false;
    for (display_list.commands) |command| {
        switch (command) {
            .fill_rounded_rect => |fill| {
                if (fill.id == testCanvasWidgetPartId(4, 2)) {
                    try std.testing.expectEqual(@as(f32, 100), fill.rect.width);
                    saw_full_slider_active = true;
                }
            },
            else => {},
        }
    }
    try std.testing.expect(saw_full_slider_active);
}

test "runtime dispatches canvas widget commands from pointer and keyboard activation" {
    const TestApp = struct {
        command_count: u32 = 0,
        widget_pointer_count: u32 = 0,
        widget_keyboard_count: u32 = 0,
        last_name: []const u8 = "",
        last_source: CommandSource = .runtime,
        last_window_id: platform.WindowId = 0,
        last_view_label: []const u8 = "",

        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-command", .source = platform.WebViewSource.html("<h1>Hello</h1>"), .event_fn = event };
        }

        fn event(context: *anyopaque, runtime: *Runtime, event_value: Event) anyerror!void {
            _ = runtime;
            const self: *@This() = @ptrCast(@alignCast(context));
            switch (event_value) {
                .command => |command| {
                    self.command_count += 1;
                    self.last_name = command.name;
                    self.last_source = command.source;
                    self.last_window_id = command.window_id;
                    self.last_view_label = command.view_label;
                },
                .canvas_widget_pointer => self.widget_pointer_count += 1,
                .canvas_widget_keyboard => self.widget_keyboard_count += 1,
                else => {},
            }
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
        .frame = geometry.RectF.init(0, 0, 240, 200),
    });

    const widgets = [_]canvas.Widget{
        .{
            .id = 2,
            .kind = .button,
            .frame = geometry.RectF.init(12, 12, 96, 32),
            .text = "Run",
            .command = "widget.run",
        },
        .{
            .id = 3,
            .kind = .text_field,
            .frame = geometry.RectF.init(12, 56, 140, 32),
            .text = "Q",
        },
        .{
            .id = 4,
            .kind = .menu_item,
            .frame = geometry.RectF.init(128, 12, 96, 32),
            .text = "Archive",
            .command = "widget.archive",
        },
        .{
            .id = 5,
            .kind = .select,
            .frame = geometry.RectF.init(12, 96, 120, 32),
            .text = "Environment",
            .command = "widget.select",
        },
        .{
            .id = 6,
            .kind = .combobox,
            .frame = geometry.RectF.init(12, 136, 140, 32),
            .text = "Production",
            .command = "widget.combo",
        },
    };
    var nodes: [6]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &widgets }, geometry.RectF.init(0, 0, 240, 200), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    const combobox_semantics = canvasWidgetSemanticsById(runtimeViewWidgetSemantics(&harness.runtime.views[0]), 6).?;
    try std.testing.expectEqual(canvas.WidgetRole.textbox, combobox_semantics.role);
    try std.testing.expectEqualStrings("Production", combobox_semantics.text_value);
    try std.testing.expect(combobox_semantics.actions.press);
    try std.testing.expect(combobox_semantics.actions.set_text);
    try std.testing.expect(combobox_semantics.actions.set_selection);

    harness.runtime.views[0].canvas_widget_focused_id = 3;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "a",
        .text = "a",
    } });
    try std.testing.expectEqualStrings("Qa", (try harness.runtime.canvasWidgetLayout(1, "canvas")).nodes[2].widget.text);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_down,
        .x = 20,
        .y = 20,
    } });
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_up,
        .x = 20,
        .y = 20,
    } });
    try std.testing.expectEqual(@as(u32, 1), app_state.command_count);
    try std.testing.expectEqualStrings("widget.run", app_state.last_name);
    try std.testing.expectEqual(CommandSource.native_view, app_state.last_source);
    try std.testing.expectEqual(@as(platform.WindowId, 1), app_state.last_window_id);
    try std.testing.expectEqualStrings("canvas", app_state.last_view_label);

    harness.runtime.views[0].canvas_widget_focused_id = 2;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "enter",
    } });
    try std.testing.expectEqual(@as(u32, 2), app_state.command_count);
    try std.testing.expectEqual(@as(u32, 2), app_state.widget_pointer_count);
    try std.testing.expectEqual(@as(u32, 3), app_state.widget_keyboard_count);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "space",
        .modifiers = .{ .option = true },
    } });
    try std.testing.expectEqual(@as(u32, 2), app_state.command_count);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_down,
        .x = 140,
        .y = 20,
    } });
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_up,
        .x = 140,
        .y = 20,
    } });
    try std.testing.expectEqual(@as(u32, 3), app_state.command_count);
    try std.testing.expectEqualStrings("widget.archive", app_state.last_name);
    var retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expect(retained.findById(4).?.widget.state.selected);
    try std.testing.expectEqual(@as(f32, 1), retained.findById(4).?.widget.value);

    harness.runtime.views[0].canvas_widget_focused_id = 4;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "enter",
    } });
    try std.testing.expectEqual(@as(u32, 4), app_state.command_count);
    try std.testing.expectEqualStrings("widget.archive", app_state.last_name);
    retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expect(retained.findById(4).?.widget.state.selected);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_down,
        .x = 20,
        .y = 108,
    } });
    try std.testing.expectEqual(@as(u32, 5), app_state.command_count);
    try std.testing.expectEqualStrings("widget.select", app_state.last_name);
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_up,
        .x = 20,
        .y = 108,
    } });
    try std.testing.expectEqual(@as(u32, 5), app_state.command_count);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_down,
        .x = 20,
        .y = 144,
    } });
    try std.testing.expectEqual(@as(u32, 6), app_state.command_count);
    try std.testing.expectEqualStrings("widget.combo", app_state.last_name);
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_up,
        .x = 20,
        .y = 144,
    } });
    try std.testing.expectEqual(@as(u32, 6), app_state.command_count);

    harness.runtime.views[0].canvas_widget_focused_id = 6;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "enter",
    } });
    try std.testing.expectEqual(@as(u32, 7), app_state.command_count);
    try std.testing.expectEqualStrings("widget.combo", app_state.last_name);
}

test "runtime automation snapshot exposes canvas list roles" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-list-semantics", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(20, 30, 240, 160),
    });

    const rows = [_]canvas.Widget{
        .{ .id = 2, .kind = .list_item, .frame = geometry.RectF.init(0, 0, 0, 32), .text = "Inbox" },
        .{ .id = 3, .kind = .list_item, .frame = geometry.RectF.init(0, 0, 0, 32), .text = "Archive" },
    };
    const list = canvas.Widget{
        .id = 1,
        .kind = .list,
        .text = "Mailboxes",
        .layout = .{ .gap = 4 },
        .children = &rows,
    };
    var nodes: [4]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(list, geometry.RectF.init(0, 0, 240, 160), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    const snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expectEqual(@as(usize, 3), snapshot.widgets.len);
    try std.testing.expectEqual(@as(u64, 1), snapshot.widgets[0].id);
    try std.testing.expectEqualStrings("list", snapshot.widgets[0].role);
    try std.testing.expectEqualStrings("Mailboxes", snapshot.widgets[0].name);
    try std.testing.expect(snapshot.widgets[0].parent_id == null);
    try std.testing.expectEqualDeep(geometry.RectF.init(20, 30, 240, 160), snapshot.widgets[0].bounds);
    try std.testing.expectEqualStrings("listitem", snapshot.widgets[1].role);
    try std.testing.expectEqualStrings("Inbox", snapshot.widgets[1].name);
    try std.testing.expectEqual(@as(?u64, 1), snapshot.widgets[1].parent_id);
    try std.testing.expectEqualDeep(geometry.RectF.init(20, 30, 240, 32), snapshot.widgets[1].bounds);
    try std.testing.expect(snapshot.widgets[1].list.present);
    try std.testing.expectEqual(@as(u32, 0), snapshot.widgets[1].list.item_index);
    try std.testing.expectEqual(@as(u32, 2), snapshot.widgets[1].list.item_count);
    try std.testing.expectEqualStrings("listitem", snapshot.widgets[2].role);
    try std.testing.expectEqualStrings("Archive", snapshot.widgets[2].name);
    try std.testing.expectEqual(@as(?u64, 1), snapshot.widgets[2].parent_id);
    try std.testing.expect(snapshot.widgets[2].list.present);
    try std.testing.expectEqual(@as(u32, 1), snapshot.widgets[2].list.item_index);
    try std.testing.expectEqual(@as(u32, 2), snapshot.widgets[2].list.item_count);

    var a11y_buffer: [1024]u8 = undefined;
    var a11y_writer = std.Io.Writer.fixed(&a11y_buffer);
    try automation.snapshot.writeA11yText(snapshot, &a11y_writer);
    try std.testing.expect(std.mem.indexOf(u8, a11y_writer.buffered(), "@w1/canvas#1 role=list name=\"Mailboxes\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, a11y_writer.buffered(), "@w1/canvas#2 role=listitem name=\"Inbox\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, a11y_writer.buffered(), "parent=#1") != null);
    try std.testing.expect(std.mem.indexOf(u8, a11y_writer.buffered(), "list=[index=0,count=2]") != null);
}

test "runtime preserves virtualized list item semantics" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-virtual-list-semantics", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(0, 0, 240, 160),
    });

    const rows = [_]canvas.Widget{
        .{ .id = 2, .kind = .list_item, .frame = geometry.RectF.init(0, 0, 0, 20), .text = "Zero" },
        .{ .id = 3, .kind = .list_item, .frame = geometry.RectF.init(0, 0, 0, 20), .text = "One" },
        .{ .id = 4, .kind = .list_item, .frame = geometry.RectF.init(0, 0, 0, 20), .text = "Two" },
        .{ .id = 5, .kind = .list_item, .frame = geometry.RectF.init(0, 0, 0, 20), .text = "Three" },
        .{ .id = 6, .kind = .list_item, .frame = geometry.RectF.init(0, 0, 0, 20), .text = "Four" },
        .{ .id = 7, .kind = .list_item, .frame = geometry.RectF.init(0, 0, 0, 20), .text = "Five" },
        .{ .id = 8, .kind = .list_item, .frame = geometry.RectF.init(0, 0, 0, 20), .text = "Six" },
        .{ .id = 9, .kind = .list_item, .frame = geometry.RectF.init(0, 0, 0, 20), .text = "Seven" },
        .{ .id = 10, .kind = .list_item, .frame = geometry.RectF.init(0, 0, 0, 20), .text = "Eight" },
        .{ .id = 11, .kind = .list_item, .frame = geometry.RectF.init(0, 0, 0, 20), .text = "Nine" },
    };
    const list = canvas.Widget{
        .id = 1,
        .kind = .list,
        .text = "Mailboxes",
        .value = 45,
        .layout = .{
            .gap = 5,
            .virtualized = true,
            .virtual_item_extent = 20,
            .virtual_overscan = 1,
        },
        .children = &rows,
    };
    var nodes: [6]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(list, geometry.RectF.init(0, 0, 240, 50), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    const retained = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectEqual(@as(usize, 6), retained.nodeCount());
    try std.testing.expectEqual(@as(usize, 0), retained.nodes[0].widget.children.len);
    try std.testing.expectEqual(@as(usize, 0), retained.nodes[3].widget.children.len);

    const snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expectEqual(@as(usize, 6), snapshot.widgets.len);
    try std.testing.expect(snapshot.widgets[0].virtual_range.present);
    try std.testing.expectEqual(@as(u32, 0), snapshot.widgets[0].virtual_range.start_index);
    try std.testing.expectEqual(@as(u32, 5), snapshot.widgets[0].virtual_range.end_index);
    try std.testing.expectEqual(@as(u32, 1), snapshot.widgets[0].virtual_range.first_visible_index);
    try std.testing.expectEqual(@as(u32, 3), snapshot.widgets[0].virtual_range.last_visible_index);
    try std.testing.expectEqual(@as(u32, 5), snapshot.widgets[0].virtual_range.rendered_count);
    try std.testing.expectEqual(@as(u64, 4), snapshot.widgets[3].id);
    try std.testing.expect(snapshot.widgets[3].list.present);
    try std.testing.expectEqual(@as(u32, 2), snapshot.widgets[3].list.item_index);
    try std.testing.expectEqual(@as(u32, 10), snapshot.widgets[3].list.item_count);
    try std.testing.expectEqual(@as(u64, 6), snapshot.widgets[5].id);
    try std.testing.expect(snapshot.widgets[5].list.present);
    try std.testing.expectEqual(@as(u32, 4), snapshot.widgets[5].list.item_index);
    try std.testing.expectEqual(@as(u32, 10), snapshot.widgets[5].list.item_count);

    var a11y_buffer: [2048]u8 = undefined;
    var a11y_writer = std.Io.Writer.fixed(&a11y_buffer);
    try automation.snapshot.writeA11yText(snapshot, &a11y_writer);
    try std.testing.expect(std.mem.indexOf(u8, a11y_writer.buffered(), "@w1/canvas#4 role=listitem name=\"Two\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, a11y_writer.buffered(), "virtual=[start=0,end=5,first=1,last=3,rendered=5]") != null);
    try std.testing.expect(std.mem.indexOf(u8, a11y_writer.buffered(), "list=[index=2,count=10]") != null);
}

test "runtime automation snapshot exposes canvas data grid roles" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-data-grid-semantics", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(20, 30, 320, 180),
    });

    const header_cells = [_]canvas.Widget{
        .{ .id = 3, .kind = .data_cell, .text = "Project", .layout = .{ .grow = 1 } },
        .{ .id = 4, .kind = .data_cell, .text = "Status", .layout = .{ .grow = 1 } },
    };
    const row_cells = [_]canvas.Widget{
        .{ .id = 6, .kind = .data_cell, .text = "Edge API", .layout = .{ .grow = 1 } },
        .{ .id = 7, .kind = .data_cell, .text = "Live", .layout = .{ .grow = 1 } },
    };
    const rows = [_]canvas.Widget{
        .{ .id = 2, .kind = .data_row, .frame = geometry.RectF.init(0, 0, 0, 28), .children = &header_cells },
        .{ .id = 5, .kind = .data_row, .frame = geometry.RectF.init(0, 0, 0, 28), .children = &row_cells },
    };
    const grid = canvas.Widget{
        .id = 1,
        .kind = .data_grid,
        .text = "Deployments",
        .layout = .{ .gap = 2 },
        .children = &rows,
    };
    var nodes: [8]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(grid, geometry.RectF.init(0, 0, 320, 180), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    const snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expectEqual(@as(usize, 7), snapshot.widgets.len);
    try std.testing.expectEqualStrings("grid", snapshot.widgets[0].role);
    try std.testing.expectEqualStrings("Deployments", snapshot.widgets[0].name);
    try std.testing.expect(snapshot.widgets[0].parent_id == null);
    try std.testing.expectEqualDeep(geometry.RectF.init(20, 30, 320, 180), snapshot.widgets[0].bounds);
    try std.testing.expect(snapshot.widgets[0].grid_row_index == null);
    try std.testing.expect(snapshot.widgets[0].grid_column_index == null);
    try std.testing.expectEqual(@as(?usize, 2), snapshot.widgets[0].grid_row_count);
    try std.testing.expectEqual(@as(?usize, 2), snapshot.widgets[0].grid_column_count);
    try std.testing.expectEqualStrings("row", snapshot.widgets[1].role);
    try std.testing.expectEqual(@as(?u64, 1), snapshot.widgets[1].parent_id);
    try std.testing.expectEqual(@as(?usize, 0), snapshot.widgets[1].grid_row_index);
    try std.testing.expect(snapshot.widgets[1].grid_column_index == null);
    try std.testing.expectEqual(@as(?usize, 2), snapshot.widgets[1].grid_row_count);
    try std.testing.expectEqual(@as(?usize, 2), snapshot.widgets[1].grid_column_count);
    try std.testing.expectEqualStrings("gridcell", snapshot.widgets[2].role);
    try std.testing.expectEqualStrings("Project", snapshot.widgets[2].name);
    try std.testing.expectEqual(@as(?u64, 2), snapshot.widgets[2].parent_id);
    try std.testing.expectEqualDeep(geometry.RectF.init(20, 30, 160, 28), snapshot.widgets[2].bounds);
    try std.testing.expectEqual(@as(?usize, 0), snapshot.widgets[2].grid_row_index);
    try std.testing.expectEqual(@as(?usize, 0), snapshot.widgets[2].grid_column_index);
    try std.testing.expectEqual(@as(?usize, 2), snapshot.widgets[2].grid_row_count);
    try std.testing.expectEqual(@as(?usize, 2), snapshot.widgets[2].grid_column_count);
    try std.testing.expect(snapshot.widgets[2].actions.focus);
    try std.testing.expect(snapshot.widgets[2].actions.select);
    try std.testing.expect(!snapshot.widgets[2].actions.press);
    try std.testing.expectEqualStrings("gridcell", snapshot.widgets[5].role);
    try std.testing.expectEqualStrings("Edge API", snapshot.widgets[5].name);
    try std.testing.expectEqual(@as(?u64, 5), snapshot.widgets[5].parent_id);
    try std.testing.expectEqualDeep(geometry.RectF.init(20, 60, 160, 28), snapshot.widgets[5].bounds);
    try std.testing.expectEqual(@as(?usize, 1), snapshot.widgets[5].grid_row_index);
    try std.testing.expectEqual(@as(?usize, 0), snapshot.widgets[5].grid_column_index);
    try std.testing.expectEqual(@as(?usize, 2), snapshot.widgets[5].grid_row_count);
    try std.testing.expectEqual(@as(?usize, 2), snapshot.widgets[5].grid_column_count);
    try std.testing.expect(snapshot.widgets[5].actions.select);

    var a11y_buffer: [2048]u8 = undefined;
    var a11y_writer = std.Io.Writer.fixed(&a11y_buffer);
    try automation.snapshot.writeA11yText(snapshot, &a11y_writer);
    try std.testing.expect(std.mem.indexOf(u8, a11y_writer.buffered(), "@w1/canvas#1 role=grid name=\"Deployments\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, a11y_writer.buffered(), "@w1/canvas#6 role=gridcell name=\"Edge API\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, a11y_writer.buffered(), "grid=[row_index=1,column_index=0,row_count=2,column_count=2]") != null);
    try std.testing.expect(std.mem.indexOf(u8, a11y_writer.buffered(), "actions=[focus,select]") != null);
}

test "runtime moves focused canvas data grid cells with arrow keys" {
    const TestApp = struct {
        widget_keyboard_count: u32 = 0,
        last_target_id: canvas.ObjectId = 0,
        last_target_kind: canvas.WidgetKind = .stack,
        last_key: []const u8 = "",

        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-data-grid-navigation", .source = platform.WebViewSource.html("<h1>Hello</h1>"), .event_fn = event };
        }

        fn event(context: *anyopaque, runtime: *Runtime, event_value: Event) anyerror!void {
            _ = runtime;
            const self: *@This() = @ptrCast(@alignCast(context));
            switch (event_value) {
                .canvas_widget_keyboard => |keyboard_event| {
                    self.widget_keyboard_count += 1;
                    self.last_key = keyboard_event.keyboard.key;
                    if (keyboard_event.target) |target| {
                        self.last_target_id = target.id;
                        self.last_target_kind = target.kind;
                    }
                },
                else => {},
            }
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
        .frame = geometry.RectF.init(20, 30, 320, 180),
    });

    const header_cells = [_]canvas.Widget{
        .{ .id = 3, .kind = .data_cell, .text = "Project", .layout = .{ .grow = 1 } },
        .{ .id = 4, .kind = .data_cell, .text = "Status", .layout = .{ .grow = 1 } },
    };
    const row_cells = [_]canvas.Widget{
        .{ .id = 6, .kind = .data_cell, .text = "Edge API", .layout = .{ .grow = 1 } },
        .{ .id = 7, .kind = .data_cell, .text = "Live", .layout = .{ .grow = 1 } },
    };
    const rows = [_]canvas.Widget{
        .{ .id = 2, .kind = .data_row, .frame = geometry.RectF.init(0, 0, 0, 28), .children = &header_cells },
        .{ .id = 5, .kind = .data_row, .frame = geometry.RectF.init(0, 0, 0, 28), .children = &row_cells },
    };
    const grid = canvas.Widget{
        .id = 1,
        .kind = .data_grid,
        .text = "Deployments",
        .layout = .{ .gap = 2 },
        .children = &rows,
    };
    var nodes: [8]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(grid, geometry.RectF.init(0, 0, 320, 180), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    harness.runtime.views[0].canvas_widget_focused_id = 3;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "arrowright",
    } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 4), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expectEqual(@as(u32, 1), app_state.widget_keyboard_count);
    try std.testing.expectEqual(@as(canvas.ObjectId, 4), app_state.last_target_id);
    try std.testing.expectEqual(canvas.WidgetKind.data_cell, app_state.last_target_kind);
    try std.testing.expectEqualStrings("arrowright", app_state.last_key);

    const right_snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expect(!right_snapshot.widgets[2].focused);
    try std.testing.expect(right_snapshot.widgets[3].focused);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "arrowdown",
    } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 7), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 7), app_state.last_target_id);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "arrowleft",
    } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 6), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 6), app_state.last_target_id);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "arrowup",
    } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 3), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 3), app_state.last_target_id);
    try std.testing.expectEqual(@as(u32, 4), app_state.widget_keyboard_count);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "end",
    } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 4), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 4), app_state.last_target_id);
    try std.testing.expectEqualStrings("end", app_state.last_key);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "home",
    } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 3), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 3), app_state.last_target_id);
    try std.testing.expectEqualStrings("home", app_state.last_key);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "arrowright",
        .modifiers = .{ .option = true },
    } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 3), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 3), app_state.last_target_id);
    try std.testing.expectEqual(@as(u32, 7), app_state.widget_keyboard_count);
}

test "runtime moves focused grouped canvas controls with arrow keys" {
    const TestApp = struct {
        widget_keyboard_count: u32 = 0,
        last_target_id: canvas.ObjectId = 0,
        last_target_kind: canvas.WidgetKind = .stack,
        last_key: []const u8 = "",

        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-grouped-navigation", .source = platform.WebViewSource.html("<h1>Hello</h1>"), .event_fn = event };
        }

        fn event(context: *anyopaque, runtime: *Runtime, event_value: Event) anyerror!void {
            _ = runtime;
            const self: *@This() = @ptrCast(@alignCast(context));
            switch (event_value) {
                .canvas_widget_keyboard => |keyboard_event| {
                    self.widget_keyboard_count += 1;
                    self.last_key = keyboard_event.keyboard.key;
                    if (keyboard_event.target) |target| {
                        self.last_target_id = target.id;
                        self.last_target_kind = target.kind;
                    }
                },
                else => {},
            }
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
        .frame = geometry.RectF.init(0, 0, 360, 180),
    });

    const list_items = [_]canvas.Widget{
        .{ .id = 11, .kind = .list_item, .frame = geometry.RectF.init(0, 0, 0, 30), .text = "Inbox" },
        .{ .id = 12, .kind = .list_item, .frame = geometry.RectF.init(0, 36, 0, 30), .text = "Archive" },
    };
    const menu_items = [_]canvas.Widget{
        .{ .id = 21, .kind = .menu_item, .frame = geometry.RectF.init(0, 0, 0, 28), .text = "Rename" },
        .{ .id = 22, .kind = .menu_item, .frame = geometry.RectF.init(0, 34, 0, 28), .text = "Archive" },
    };
    const segment_items = [_]canvas.Widget{
        .{ .id = 31, .kind = .segmented_control, .frame = geometry.RectF.init(0, 0, 72, 30), .text = "List" },
        .{ .id = 32, .kind = .segmented_control, .frame = geometry.RectF.init(78, 0, 72, 30), .text = "Grid" },
    };
    const children = [_]canvas.Widget{
        .{ .id = 10, .kind = .list, .frame = geometry.RectF.init(12, 12, 140, 72), .children = &list_items },
        .{ .id = 20, .kind = .menu_surface, .frame = geometry.RectF.init(180, 12, 140, 70), .children = &menu_items },
        .{ .id = 30, .kind = .row, .frame = geometry.RectF.init(12, 108, 150, 30), .children = &segment_items },
        .{ .id = 40, .kind = .button, .frame = geometry.RectF.init(220, 108, 96, 32), .text = "Run" },
    };
    var nodes: [12]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .id = 1, .kind = .panel, .children = &children }, geometry.RectF.init(0, 0, 360, 180), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    harness.runtime.views[0].canvas_widget_focused_id = 11;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "arrowdown",
    } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 12), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 12), app_state.last_target_id);
    try std.testing.expectEqual(canvas.WidgetKind.list_item, app_state.last_target_kind);
    try std.testing.expectEqualStrings("arrowdown", app_state.last_key);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "arrowright",
    } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 12), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 12), app_state.last_target_id);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "home",
    } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 11), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 11), app_state.last_target_id);
    try std.testing.expectEqualStrings("home", app_state.last_key);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "end",
        .modifiers = .{ .shift = true },
    } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 11), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 11), app_state.last_target_id);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "end",
    } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 12), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 12), app_state.last_target_id);
    try std.testing.expectEqualStrings("end", app_state.last_key);

    harness.runtime.views[0].canvas_widget_focused_id = 21;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "arrowdown",
    } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 22), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 22), app_state.last_target_id);
    try std.testing.expectEqual(canvas.WidgetKind.menu_item, app_state.last_target_kind);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "home",
    } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 21), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 21), app_state.last_target_id);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "end",
    } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 22), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 22), app_state.last_target_id);

    harness.runtime.views[0].canvas_widget_focused_id = 31;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "arrowright",
    } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 32), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 32), app_state.last_target_id);
    try std.testing.expectEqual(canvas.WidgetKind.segmented_control, app_state.last_target_kind);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "home",
    } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 31), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 31), app_state.last_target_id);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "end",
    } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 32), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 32), app_state.last_target_id);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "arrowdown",
    } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 32), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 32), app_state.last_target_id);

    harness.runtime.views[0].canvas_widget_focused_id = 40;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .key_down,
        .key = "arrowleft",
    } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 40), harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 40), app_state.last_target_id);
    try std.testing.expectEqual(canvas.WidgetKind.button, app_state.last_target_kind);
    try std.testing.expectEqual(@as(u32, 13), app_state.widget_keyboard_count);
}

test "runtime moves focus within shadcn grouped component controls" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-shadcn-group-navigation", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(0, 0, 360, 280),
    });

    const button_group_buttons = [_]canvas.Widget{
        .{ .id = 11, .kind = .button, .text = "One" },
        .{ .id = 12, .kind = .button, .text = "Two" },
    };
    const pagination_buttons = [_]canvas.Widget{
        .{ .id = 21, .kind = .button, .text = "1" },
        .{ .id = 22, .kind = .button, .text = "2" },
        .{ .id = 23, .kind = .button, .text = "Next" },
    };
    const toggle_buttons = [_]canvas.Widget{
        .{ .id = 31, .kind = .toggle_button, .text = "B" },
        .{ .id = 32, .kind = .toggle_button, .text = "I" },
    };
    const tab_buttons = [_]canvas.Widget{
        .{ .id = 41, .kind = .segmented_control, .text = "Open" },
        .{ .id = 42, .kind = .segmented_control, .text = "Closed" },
    };
    const radio_buttons = [_]canvas.Widget{
        .{ .id = 51, .kind = .radio, .text = "Card" },
        .{ .id = 52, .kind = .radio, .text = "List" },
    };
    const top_children = [_]canvas.Widget{
        .{ .id = 10, .kind = .button_group, .frame = geometry.RectF.init(12, 12, 180, 34), .layout = builtinShadcnGroupLayout(), .children = &button_group_buttons },
        .{ .id = 20, .kind = .pagination, .frame = geometry.RectF.init(12, 56, 220, 34), .layout = builtinShadcnGroupLayout(), .children = &pagination_buttons },
        .{ .id = 30, .kind = .toggle_group, .frame = geometry.RectF.init(12, 100, 160, 34), .layout = builtinShadcnGroupLayout(), .children = &toggle_buttons },
        .{ .id = 40, .kind = .tabs, .frame = geometry.RectF.init(12, 144, 180, 34), .layout = builtinShadcnGroupLayout(), .children = &tab_buttons },
        .{ .id = 50, .kind = .radio_group, .frame = geometry.RectF.init(12, 188, 180, 34), .layout = builtinShadcnGroupLayout(), .children = &radio_buttons },
        .{ .id = 90, .kind = .button, .frame = geometry.RectF.init(248, 12, 84, 34), .text = "Alone" },
    };
    var nodes: [24]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{ .id = 1, .kind = .panel, .children = &top_children }, geometry.RectF.init(0, 0, 360, 280), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    harness.runtime.views[0].canvas_widget_focused_id = 11;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{ .window_id = 1, .label = "canvas", .kind = .key_down, .key = "arrowright" } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 12), harness.runtime.views[0].canvas_widget_focused_id);
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{ .window_id = 1, .label = "canvas", .kind = .key_down, .key = "home" } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 11), harness.runtime.views[0].canvas_widget_focused_id);

    harness.runtime.views[0].canvas_widget_focused_id = 21;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{ .window_id = 1, .label = "canvas", .kind = .key_down, .key = "end" } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 23), harness.runtime.views[0].canvas_widget_focused_id);
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{ .window_id = 1, .label = "canvas", .kind = .key_down, .key = "home" } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 21), harness.runtime.views[0].canvas_widget_focused_id);

    harness.runtime.views[0].canvas_widget_focused_id = 31;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{ .window_id = 1, .label = "canvas", .kind = .key_down, .key = "arrowright" } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 32), harness.runtime.views[0].canvas_widget_focused_id);

    harness.runtime.views[0].canvas_widget_focused_id = 41;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{ .window_id = 1, .label = "canvas", .kind = .key_down, .key = "arrowright" } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 42), harness.runtime.views[0].canvas_widget_focused_id);

    harness.runtime.views[0].canvas_widget_focused_id = 51;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{ .window_id = 1, .label = "canvas", .kind = .key_down, .key = "arrowright" } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 52), harness.runtime.views[0].canvas_widget_focused_id);

    harness.runtime.views[0].canvas_widget_focused_id = 90;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{ .window_id = 1, .label = "canvas", .kind = .key_down, .key = "arrowleft" } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 90), harness.runtime.views[0].canvas_widget_focused_id);
}

fn builtinShadcnGroupLayout() canvas.WidgetLayoutStyle {
    return .{ .gap = 4, .cross_alignment = .center };
}

test "runtime publishes canvas widget accessibility snapshots to platform" {
    const WidgetAccessibilityPlatform = struct {
        update_count: usize = 0,
        window_id: platform.WindowId = 0,
        view_label: [platform.max_view_label_bytes]u8 = undefined,
        view_label_len: usize = 0,
        nodes: [16]platform.WidgetAccessibilityNode = undefined,
        node_count: usize = 0,

        fn platformValue(self: *@This()) platform.Platform {
            return .{
                .context = self,
                .name = "widget-a11y",
                .surface_value = .{ .id = 1, .size = geometry.SizeF.init(320, 240), .scale_factor = 1 },
                .run_fn = run,
                .services = .{
                    .context = self,
                    .load_webview_fn = loadWebView,
                    .create_view_fn = createView,
                    .focus_view_fn = focusView,
                    .update_widget_accessibility_fn = updateWidgetAccessibility,
                },
            };
        }

        fn run(context: *anyopaque, handler: platform.EventHandler, handler_context: *anyopaque) anyerror!void {
            _ = context;
            _ = handler;
            _ = handler_context;
        }

        fn createView(context: ?*anyopaque, options: platform.ViewOptions) anyerror!void {
            _ = context;
            _ = options;
        }

        fn focusView(context: ?*anyopaque, window_id: platform.WindowId, label: []const u8) anyerror!void {
            _ = context;
            _ = window_id;
            _ = label;
        }

        fn loadWebView(context: ?*anyopaque, source: platform.WebViewSource) anyerror!void {
            _ = context;
            _ = source;
        }

        fn updateWidgetAccessibility(context: ?*anyopaque, snapshot: platform.WidgetAccessibilitySnapshot) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.update_count += 1;
            self.window_id = snapshot.window_id;
            self.view_label_len = (try copyInto(&self.view_label, snapshot.view_label)).len;
            self.node_count = @min(snapshot.nodes.len, self.nodes.len);
            for (snapshot.nodes[0..self.node_count], 0..) |node, index| {
                self.nodes[index] = node;
            }
        }
    };

    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-platform-a11y", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
        }
    };

    var platform_state: WidgetAccessibilityPlatform = .{};
    var runtime = Runtime.init(.{ .platform = platform_state.platformValue() });
    var app_state: TestApp = .{};
    try runtime.dispatchPlatformEvent(app_state.app(), .app_start);
    _ = try runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(0, 0, 320, 160),
    });

    const header_cells = [_]canvas.Widget{
        .{ .id = 12, .kind = .data_cell, .text = "Project", .layout = .{ .grow = 1 } },
        .{ .id = 13, .kind = .data_cell, .text = "Status", .layout = .{ .grow = 1 } },
    };
    const row_cells = [_]canvas.Widget{
        .{ .id = 15, .kind = .data_cell, .text = "Edge API", .layout = .{ .grow = 1 } },
        .{ .id = 16, .kind = .data_cell, .text = "Live", .layout = .{ .grow = 1 } },
    };
    const rows = [_]canvas.Widget{
        .{ .id = 11, .kind = .data_row, .children = &header_cells },
        .{ .id = 14, .kind = .data_row, .children = &row_cells },
    };
    const children = [_]canvas.Widget{
        .{ .id = 2, .kind = .button, .frame = geometry.RectF.init(12, 14, 96, 32), .text = "Deploy", .command = "deploy.run" },
        .{ .id = 3, .kind = .checkbox, .frame = geometry.RectF.init(12, 58, 120, 28), .text = "Preview", .state = .{ .selected = true } },
        .{ .id = 4, .kind = .text_field, .frame = geometry.RectF.init(12, 96, 160, 28), .text = "Search", .placeholder = "Search deployments", .text_selection = canvas.TextSelection{ .anchor = 1, .focus = 4 }, .text_composition = canvas.TextRange.init(2, 5), .state = .{ .required = true, .read_only = true, .invalid = true } },
        .{ .id = 5, .kind = .select, .frame = geometry.RectF.init(184, 96, 120, 28), .text = "Production", .state = .{ .expanded = false }, .semantics = .{ .label = "Environment" } },
        .{ .id = 10, .kind = .data_grid, .frame = geometry.RectF.init(12, 132, 220, 64), .text = "Deployments", .layout = .{ .gap = 2 }, .children = &rows },
    };
    var layout_nodes: [16]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(.{
        .id = 1,
        .kind = .stack,
        .frame = geometry.RectF.init(0, 0, 320, 160),
        .semantics = .{ .label = "Actions" },
        .children = &children,
    }, geometry.RectF.init(0, 0, 320, 160), &layout_nodes);
    _ = try runtime.setCanvasWidgetLayout(1, "canvas", layout);

    try std.testing.expect(platform_state.update_count >= 1);
    try std.testing.expectEqual(@as(platform.WindowId, 1), platform_state.window_id);
    try std.testing.expectEqualStrings("canvas", platform_state.view_label[0..platform_state.view_label_len]);
    try std.testing.expectEqual(@as(usize, 12), platform_state.node_count);
    try std.testing.expectEqual(platform.WidgetAccessibilityRole.group, platform_state.nodes[0].role);
    try std.testing.expectEqual(platform.WidgetAccessibilityRole.button, platform_state.nodes[1].role);
    try std.testing.expectEqual(platform.WidgetAccessibilityRole.checkbox, platform_state.nodes[2].role);
    try std.testing.expectEqual(platform.WidgetAccessibilityRole.textbox, platform_state.nodes[3].role);
    const grid_node = platformWidgetAccessibilityNodeById(platform_state.nodes[0..platform_state.node_count], 10).?;
    const row_node = platformWidgetAccessibilityNodeById(platform_state.nodes[0..platform_state.node_count], 14).?;
    const cell_node = platformWidgetAccessibilityNodeById(platform_state.nodes[0..platform_state.node_count], 16).?;
    const text_node = platformWidgetAccessibilityNodeById(platform_state.nodes[0..platform_state.node_count], 4).?;
    const select_node = platformWidgetAccessibilityNodeById(platform_state.nodes[0..platform_state.node_count], 5).?;
    try std.testing.expectEqual(@as(?bool, false), select_node.expanded);
    try std.testing.expect(text_node.required);
    try std.testing.expect(text_node.read_only);
    try std.testing.expect(text_node.invalid);
    try std.testing.expect(!text_node.actions.set_text);
    try std.testing.expect(text_node.actions.set_selection);
    try std.testing.expectEqual(platform.WidgetAccessibilityRole.grid, grid_node.role);
    try std.testing.expectEqual(@as(?usize, 2), grid_node.grid_row_count);
    try std.testing.expectEqual(@as(?usize, 2), grid_node.grid_column_count);
    try std.testing.expectEqual(platform.WidgetAccessibilityRole.row, row_node.role);
    try std.testing.expectEqual(@as(?usize, 1), row_node.grid_row_index);
    try std.testing.expectEqual(@as(?usize, 2), row_node.grid_row_count);
    try std.testing.expectEqual(@as(?usize, 2), row_node.grid_column_count);
    try std.testing.expectEqual(platform.WidgetAccessibilityRole.gridcell, cell_node.role);
    try std.testing.expectEqual(@as(?usize, 1), cell_node.grid_row_index);
    try std.testing.expectEqual(@as(?usize, 1), cell_node.grid_column_index);
    try std.testing.expectEqual(@as(?usize, 2), cell_node.grid_row_count);
    try std.testing.expectEqual(@as(?usize, 2), cell_node.grid_column_count);
    try std.testing.expectEqualStrings("Deploy", platform_state.nodes[1].label);
    try std.testing.expect(platform_state.nodes[1].actions.press);
    try std.testing.expect(platform_state.nodes[2].selected);
    try std.testing.expectEqualStrings("Search", platform_state.nodes[3].text_value);
    try std.testing.expectEqualStrings("Search deployments", platform_state.nodes[3].placeholder);
    try std.testing.expectEqualDeep(platform.WidgetAccessibilityTextRange{ .start = 1, .end = 4 }, platform_state.nodes[3].text_selection.?);
    try std.testing.expectEqualDeep(platform.WidgetAccessibilityTextRange{ .start = 2, .end = 5 }, platform_state.nodes[3].text_composition.?);
    try std.testing.expect(!platform_state.nodes[3].actions.set_text);
    try std.testing.expect(platform_state.nodes[3].actions.set_selection);
    try std.testing.expectEqual(@as(f32, 12), platform_state.nodes[1].bounds.x);
    try std.testing.expectEqual(@as(f32, 14), platform_state.nodes[1].bounds.y);

    const published_after_layout = platform_state.update_count;
    try runtime.dispatchPlatformEvent(app_state.app(), .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .pointer_move,
        .x = 20,
        .y = 24,
    } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 2), runtime.views[0].canvas_widget_hovered_id);
    try std.testing.expectEqual(published_after_layout, platform_state.update_count);

    const published_before_focus = platform_state.update_count;
    _ = try runtime.dispatchCanvasWidgetAccessibilityAction(app_state.app(), 1, "canvas", .{ .id = 2, .action = .focus });
    try std.testing.expectEqual(@as(canvas.ObjectId, 2), runtime.views[0].canvas_widget_focused_id);
    try std.testing.expect(platform_state.update_count > published_before_focus);
    try std.testing.expect(platform_state.nodes[1].focused);

    try runtime.dispatchPlatformEvent(app_state.app(), .{ .widget_accessibility_action = .{
        .window_id = 1,
        .label = "canvas",
        .id = 3,
        .action = .toggle,
    } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 3), runtime.views[0].canvas_widget_focused_id);
    try std.testing.expect(!platform_state.nodes[2].selected);

    try std.testing.expectError(error.InvalidCommand, runtime.dispatchPlatformEvent(app_state.app(), .{ .widget_accessibility_action = .{
        .window_id = 1,
        .label = "canvas",
        .id = 4,
        .action = .set_text,
        .text = "Customer search",
    } }));
    try std.testing.expectEqualStrings("Search", platform_state.nodes[3].text_value);

    try runtime.dispatchPlatformEvent(app_state.app(), .{ .widget_accessibility_action = .{
        .window_id = 1,
        .label = "canvas",
        .id = 4,
        .action = .set_selection,
        .selection = .{ .start = 3, .end = 11 },
    } });
    try std.testing.expectEqualDeep(platform.WidgetAccessibilityTextRange{ .start = 3, .end = 6 }, platform_state.nodes[3].text_selection.?);

    const scroll_items = [_]canvas.Widget{
        .{ .id = 22, .kind = .list_item, .frame = geometry.RectF.init(0, 0, 0, 28), .text = "One" },
        .{ .id = 23, .kind = .list_item, .frame = geometry.RectF.init(0, 44, 0, 28), .text = "Two" },
        .{ .id = 24, .kind = .list_item, .frame = geometry.RectF.init(0, 88, 0, 28), .text = "Three" },
    };
    const scroll_children = [_]canvas.Widget{
        .{ .id = 21, .kind = .scroll_view, .frame = geometry.RectF.init(16, 16, 140, 56), .children = &scroll_items },
    };
    var scroll_nodes: [6]canvas.WidgetLayoutNode = undefined;
    const scroll_layout = try canvas.layoutWidgetTree(.{
        .id = 20,
        .kind = .panel,
        .children = &scroll_children,
    }, geometry.RectF.init(0, 0, 320, 160), &scroll_nodes);
    _ = try runtime.setCanvasWidgetLayout(1, "canvas", scroll_layout);
    _ = try runtime.emitCanvasWidgetDisplayList(1, "canvas", .{});
    const published_count = platform_state.update_count;

    try runtime.dispatchPlatformEvent(app_state.app(), .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = "canvas",
        .kind = .scroll,
        .x = 32,
        .y = 32,
        .delta_y = 20,
    } });
    const scrolled_layout = try runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expect(scrolled_layout.findById(21).?.widget.value > 0);
    try std.testing.expectEqual(published_count, platform_state.update_count);
}

test "runtime automation snapshot exposes canvas icon roles" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-icon-semantics", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(24, 32, 160, 80),
    });

    const children = [_]canvas.Widget{
        .{
            .id = 2,
            .kind = .icon,
            .frame = geometry.RectF.init(8, 8, 24, 24),
            .text = "?",
            .semantics = .{ .label = "Help" },
        },
        .{
            .id = 3,
            .kind = .icon_button,
            .frame = geometry.RectF.init(40, 4, 32, 32),
            .text = "+",
            .semantics = .{ .label = "Add item" },
        },
    };
    const root = canvas.Widget{ .kind = .stack, .children = &children };
    var nodes: [3]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(root, geometry.RectF.init(0, 0, 160, 80), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    const snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expectEqual(@as(usize, 2), snapshot.widgets.len);
    try std.testing.expectEqualStrings("image", snapshot.widgets[0].role);
    try std.testing.expectEqualStrings("Help", snapshot.widgets[0].name);
    try std.testing.expectEqualDeep(geometry.RectF.init(32, 40, 24, 24), snapshot.widgets[0].bounds);
    try std.testing.expectEqualStrings("button", snapshot.widgets[1].role);
    try std.testing.expectEqualStrings("Add item", snapshot.widgets[1].name);
    try std.testing.expectEqualDeep(geometry.RectF.init(64, 36, 32, 32), snapshot.widgets[1].bounds);

    var a11y_buffer: [512]u8 = undefined;
    var a11y_writer = std.Io.Writer.fixed(&a11y_buffer);
    try automation.snapshot.writeA11yText(snapshot, &a11y_writer);
    try std.testing.expect(std.mem.indexOf(u8, a11y_writer.buffered(), "@w1/canvas#2 role=image name=\"Help\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, a11y_writer.buffered(), "@w1/canvas#3 role=button name=\"Add item\"") != null);
}

test "runtime automation snapshot exposes canvas tooltip roles" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-tooltip-semantics", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(40, 50, 240, 160),
    });

    const tooltip = canvas.Widget{
        .id = 1,
        .kind = .tooltip,
        .frame = geometry.RectF.init(12, 16, 120, 28),
        .text = "Saved",
    };
    var nodes: [1]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(tooltip, tooltip.frame, &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    const snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expectEqual(@as(usize, 1), snapshot.widgets.len);
    try std.testing.expectEqualStrings("tooltip", snapshot.widgets[0].role);
    try std.testing.expectEqualStrings("Saved", snapshot.widgets[0].name);
    try std.testing.expectEqualDeep(geometry.RectF.init(52, 66, 120, 28), snapshot.widgets[0].bounds);

    var a11y_buffer: [512]u8 = undefined;
    var a11y_writer = std.Io.Writer.fixed(&a11y_buffer);
    try automation.snapshot.writeA11yText(snapshot, &a11y_writer);
    try std.testing.expect(std.mem.indexOf(u8, a11y_writer.buffered(), "@w1/canvas#1 role=tooltip name=\"Saved\"") != null);
}

test "runtime automation snapshot exposes canvas popover dialog roles" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-popover-semantics", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(40, 50, 260, 180),
    });

    const actions = [_]canvas.Widget{.{
        .id = 2,
        .kind = .button,
        .frame = geometry.RectF.init(0, 0, 96, 32),
        .text = "Open",
    }};
    const popover = canvas.Widget{
        .id = 1,
        .kind = .popover,
        .frame = geometry.RectF.init(12, 16, 180, 120),
        .layout = .{ .padding = geometry.InsetsF.all(10) },
        .semantics = .{ .label = "Command palette" },
        .children = &actions,
    };
    var nodes: [3]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(popover, popover.frame, &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    const snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expectEqual(@as(usize, 2), snapshot.widgets.len);
    try std.testing.expectEqualStrings("dialog", snapshot.widgets[0].role);
    try std.testing.expectEqualStrings("Command palette", snapshot.widgets[0].name);
    try std.testing.expectEqualDeep(geometry.RectF.init(52, 66, 180, 120), snapshot.widgets[0].bounds);
    try std.testing.expectEqualStrings("button", snapshot.widgets[1].role);
    try std.testing.expectEqualStrings("Open", snapshot.widgets[1].name);
    try std.testing.expectEqualDeep(geometry.RectF.init(62, 76, 96, 32), snapshot.widgets[1].bounds);

    var a11y_buffer: [512]u8 = undefined;
    var a11y_writer = std.Io.Writer.fixed(&a11y_buffer);
    try automation.snapshot.writeA11yText(snapshot, &a11y_writer);
    try std.testing.expect(std.mem.indexOf(u8, a11y_writer.buffered(), "@w1/canvas#1 role=dialog name=\"Command palette\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, a11y_writer.buffered(), "@w1/canvas#2 role=button name=\"Open\"") != null);
}

test "runtime automation snapshot exposes canvas menu roles" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-menu-semantics", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(40, 50, 260, 180),
    });

    const items = [_]canvas.Widget{
        .{ .id = 2, .kind = .menu_item, .frame = geometry.RectF.init(0, 0, 0, 28), .text = "Rename" },
        .{ .id = 3, .kind = .menu_item, .frame = geometry.RectF.init(0, 0, 0, 28), .text = "Archive" },
    };
    const menu = canvas.Widget{
        .id = 1,
        .kind = .menu_surface,
        .frame = geometry.RectF.init(12, 16, 180, 90),
        .layout = .{ .padding = geometry.InsetsF.all(6), .gap = 2 },
        .semantics = .{ .label = "More actions" },
        .children = &items,
    };
    var nodes: [4]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(menu, menu.frame, &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    const snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expectEqual(@as(usize, 3), snapshot.widgets.len);
    try std.testing.expectEqualStrings("menu", snapshot.widgets[0].role);
    try std.testing.expectEqualStrings("More actions", snapshot.widgets[0].name);
    try std.testing.expectEqualDeep(geometry.RectF.init(52, 66, 180, 90), snapshot.widgets[0].bounds);
    try std.testing.expectEqualStrings("menuitem", snapshot.widgets[1].role);
    try std.testing.expectEqualStrings("Rename", snapshot.widgets[1].name);
    try std.testing.expectEqualDeep(geometry.RectF.init(58, 72, 168, 28), snapshot.widgets[1].bounds);
    try std.testing.expectEqualStrings("menuitem", snapshot.widgets[2].role);
    try std.testing.expectEqualStrings("Archive", snapshot.widgets[2].name);

    var a11y_buffer: [4096]u8 = undefined;
    var a11y_writer = std.Io.Writer.fixed(&a11y_buffer);
    try automation.snapshot.writeA11yText(snapshot, &a11y_writer);
    try std.testing.expect(std.mem.indexOf(u8, a11y_writer.buffered(), "@w1/canvas#1 role=menu name=\"More actions\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, a11y_writer.buffered(), "@w1/canvas#2 role=menuitem name=\"Rename\"") != null);
}

test "runtime invalidates canvas widget layout and semantics changes" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-dirty", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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

    const initial_children = [_]canvas.Widget{.{
        .id = 2,
        .kind = .button,
        .frame = geometry.RectF.init(10, 10, 80, 32),
        .text = "Run",
    }};
    var initial_nodes: [3]canvas.WidgetLayoutNode = undefined;
    const initial = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &initial_children }, geometry.RectF.init(0, 0, 320, 240), &initial_nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", initial);

    const moved_children = [_]canvas.Widget{.{
        .id = 2,
        .kind = .button,
        .frame = geometry.RectF.init(30, 10, 80, 32),
        .text = "Run",
    }};
    var moved_nodes: [3]canvas.WidgetLayoutNode = undefined;
    const moved = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &moved_children }, geometry.RectF.init(0, 0, 320, 240), &moved_nodes);

    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", moved);
    try std.testing.expect(harness.runtime.invalidated);
    try std.testing.expectEqual(@as(usize, 1), harness.runtime.pendingDirtyRegions().len);
    try std.testing.expectEqualDeep(geometry.RectF.init(59.5, 79.5, 101, 33), harness.runtime.pendingDirtyRegions()[0]);

    const renamed_children = [_]canvas.Widget{.{
        .id = 2,
        .kind = .button,
        .frame = geometry.RectF.init(30, 10, 80, 32),
        .text = "Run",
        .semantics = .{ .label = "Run report" },
    }};
    var renamed_nodes: [3]canvas.WidgetLayoutNode = undefined;
    const renamed = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &renamed_children }, geometry.RectF.init(0, 0, 320, 240), &renamed_nodes);

    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", renamed);
    try std.testing.expect(harness.runtime.invalidated);
    try std.testing.expectEqual(@as(usize, 0), harness.runtime.pendingDirtyRegions().len);
}

test "runtime keeps unchanged canvas list semantics refresh clean" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-list-clean-refresh", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(20, 30, 260, 180),
    });

    const items = [_]canvas.Widget{
        .{ .id = 2, .kind = .list_item, .frame = geometry.RectF.init(0, 0, 0, 30), .text = "Inbox" },
        .{ .id = 3, .kind = .list_item, .frame = geometry.RectF.init(0, 0, 0, 30), .text = "Archive" },
        .{ .id = 4, .kind = .list_item, .frame = geometry.RectF.init(0, 0, 0, 30), .text = "Drafts" },
    };
    const list = canvas.Widget{
        .id = 1,
        .kind = .list,
        .frame = geometry.RectF.init(10, 12, 180, 120),
        .layout = .{ .gap = 4 },
        .children = &items,
    };
    var nodes: [4]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(list, geometry.RectF.init(0, 0, 260, 180), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    var snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expectEqual(@as(usize, 4), snapshot.widgets.len);
    try std.testing.expect(snapshot.widgets[1].list.present);
    try std.testing.expectEqual(@as(u32, 0), snapshot.widgets[1].list.item_index);
    try std.testing.expectEqual(@as(u32, 3), snapshot.widgets[1].list.item_count);
    try std.testing.expect(snapshot.widgets[3].list.present);
    try std.testing.expectEqual(@as(u32, 2), snapshot.widgets[3].list.item_index);
    try std.testing.expectEqual(@as(u32, 3), snapshot.widgets[3].list.item_count);

    harness.runtime.invalidated = false;
    harness.runtime.dirty_region_count = 0;
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    try std.testing.expect(!harness.runtime.invalidated);
    try std.testing.expectEqual(@as(usize, 0), harness.runtime.pendingDirtyRegions().len);
    snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expect(snapshot.widgets[1].list.present);
    try std.testing.expectEqual(@as(u32, 0), snapshot.widgets[1].list.item_index);
    try std.testing.expectEqual(@as(u32, 3), snapshot.widgets[1].list.item_count);
    try std.testing.expect(snapshot.widgets[3].list.present);
    try std.testing.expectEqual(@as(u32, 2), snapshot.widgets[3].list.item_index);
    try std.testing.expectEqual(@as(u32, 3), snapshot.widgets[3].list.item_count);
}

test "runtime accepts larger retained widget shells for automation" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-large-shell", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
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
        .frame = geometry.RectF.init(0, 0, 320, 480),
    });

    var items: [24]canvas.Widget = undefined;
    for (&items, 0..) |*item, index| {
        item.* = .{
            .id = @intCast(index + 2),
            .kind = .list_item,
            .frame = geometry.RectF.init(0, 0, 0, 18),
            .text = "Item",
        };
    }
    const list = canvas.Widget{
        .id = 1,
        .kind = .list,
        .text = "Workspace list",
        .layout = .{ .gap = 1 },
        .children = &items,
    };

    var nodes: [25]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(list, geometry.RectF.init(0, 0, 320, 480), &nodes);
    try std.testing.expectEqual(@as(usize, 25), layout.nodeCount());

    const info = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);
    try std.testing.expectEqual(@as(u64, 1), info.widget_revision);
    try std.testing.expectEqual(@as(usize, 25), info.widget_node_count);
    try std.testing.expectEqual(@as(usize, 25), info.widget_semantics_count);

    const snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expectEqual(@as(usize, 25), snapshot.widgets.len);
    try std.testing.expectEqualStrings("list", snapshot.widgets[0].role);
    try std.testing.expectEqualStrings("Workspace list", snapshot.widgets[0].name);
    try std.testing.expectEqualStrings("listitem", snapshot.widgets[24].role);
    try std.testing.expectEqual(@as(u64, 25), snapshot.widgets[24].id);
    try std.testing.expect(snapshot.widgets[24].list.present);
    try std.testing.expectEqual(@as(u32, 23), snapshot.widgets[24].list.item_index);
    try std.testing.expectEqual(@as(u32, 24), snapshot.widgets[24].list.item_count);
}

test "runtime automation snapshot retains widgets from multiple canvas surfaces" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-multi-surface-snapshot", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
        }
    };

    var harness: TestHarness() = undefined;
    harness.init(.{});
    harness.null_platform.gpu_surfaces = true;
    var app_state: TestApp = .{};
    try harness.start(app_state.app());

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "left-canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(0, 0, 240, 320),
    });
    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "right-canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(250, 0, 240, 320),
    });

    var left_items: [40]canvas.Widget = undefined;
    var right_items: [40]canvas.Widget = undefined;
    for (&left_items, &right_items, 0..) |*left, *right, index| {
        const y = @as(f32, @floatFromInt(index)) * 7;
        left.* = .{
            .id = 100 + @as(canvas.ObjectId, @intCast(index)),
            .kind = .button,
            .frame = geometry.RectF.init(8, y, 120, 6),
            .text = "Left",
        };
        right.* = .{
            .id = 200 + @as(canvas.ObjectId, @intCast(index)),
            .kind = .button,
            .frame = geometry.RectF.init(8, y, 120, 6),
            .text = "Right",
        };
    }

    var left_nodes: [41]canvas.WidgetLayoutNode = undefined;
    var right_nodes: [41]canvas.WidgetLayoutNode = undefined;
    const left_layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &left_items }, geometry.RectF.init(0, 0, 240, 320), &left_nodes);
    const right_layout = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &right_items }, geometry.RectF.init(0, 0, 240, 320), &right_nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "left-canvas", left_layout);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "right-canvas", right_layout);

    const snapshot = harness.runtime.automationSnapshot("Widgets");
    try std.testing.expectEqual(@as(usize, 80), snapshot.widgets.len);
    try std.testing.expectEqualStrings("left-canvas", snapshot.widgets[0].view_label);
    try std.testing.expectEqual(@as(u64, 100), snapshot.widgets[0].id);
    try std.testing.expectEqualStrings("left-canvas", snapshot.widgets[39].view_label);
    try std.testing.expectEqual(@as(u64, 139), snapshot.widgets[39].id);
    try std.testing.expectEqualStrings("right-canvas", snapshot.widgets[40].view_label);
    try std.testing.expectEqual(@as(u64, 200), snapshot.widgets[40].id);
    try std.testing.expectEqualStrings("right-canvas", snapshot.widgets[79].view_label);
    try std.testing.expectEqual(@as(u64, 239), snapshot.widgets[79].id);
}

test "runtime validates canvas widget layout targets and limits" {
    const TestApp = struct {
        fn app(self: *@This()) App {
            return .{ .context = self, .name = "gpu-widget-limits", .source = platform.WebViewSource.html("<h1>Hello</h1>") };
        }
    };

    var harness: TestHarness() = undefined;
    harness.init(.{});
    harness.null_platform.gpu_surfaces = true;
    var app_state: TestApp = .{};
    try harness.start(app_state.app());

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "status",
        .kind = .statusbar,
        .frame = geometry.RectF.init(0, 0, 320, 40),
    });
    try std.testing.expectError(error.InvalidViewOptions, harness.runtime.setCanvasWidgetLayout(1, "status", .{}));

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(0, 40, 320, 240),
    });

    const duplicate_children = [_]canvas.Widget{
        .{ .id = 2, .kind = .text, .text = "One" },
        .{ .id = 2, .kind = .text, .text = "Two" },
    };
    var duplicate_nodes: [3]canvas.WidgetLayoutNode = undefined;
    const duplicate = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &duplicate_children }, geometry.RectF.init(0, 0, 320, 240), &duplicate_nodes);
    try std.testing.expectError(error.DuplicateWidgetId, harness.runtime.setCanvasWidgetLayout(1, "canvas", duplicate));

    const invalid_command_children = [_]canvas.Widget{.{
        .id = 5,
        .kind = .button,
        .text = "Run",
        .command = "bad\ncommand",
    }};
    var invalid_command_nodes: [2]canvas.WidgetLayoutNode = undefined;
    const invalid_command = try canvas.layoutWidgetTree(.{ .kind = .stack, .children = &invalid_command_children }, geometry.RectF.init(0, 0, 320, 240), &invalid_command_nodes);
    try std.testing.expectError(error.InvalidCommand, harness.runtime.setCanvasWidgetLayout(1, "canvas", invalid_command));

    var many_nodes: [max_canvas_widget_nodes_per_view + 1]canvas.WidgetLayoutNode = undefined;
    for (&many_nodes, 0..) |*node, index| {
        node.* = .{
            .widget = .{ .id = @intCast(index + 1), .kind = .text, .text = "x" },
            .frame = geometry.RectF.init(0, @floatFromInt(index), 10, 10),
            .depth = 0,
        };
    }
    try std.testing.expectError(error.WidgetNodeLimitReached, harness.runtime.setCanvasWidgetLayout(1, "canvas", .{ .nodes = &many_nodes }));
}
