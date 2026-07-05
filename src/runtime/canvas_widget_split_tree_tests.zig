//! Split-pane divider and disclosure-tree keyboard tests, driven through
//! the REAL input dispatch path (`dispatchPlatformEvent` with gpu-surface
//! pointer/key events): drag → fraction → `canvas_widget_resize` → Msg,
//! the source-wins fraction reconcile across rebuilds, and the full ARIA
//! tree keymap walk over a nested tree.

const support = @import("test_support.zig");
const std = support.std;
const geometry = support.geometry;
const canvas = support.canvas;
const platform = support.platform;
const App = support.App;
const Runtime = support.Runtime;
const Event = support.Event;
const TestHarness = support.TestHarness;

const TestMsg = union(enum) {
    resized: f32,
    pane_pressed,
};

const TestUi = canvas.Ui(TestMsg);

/// A resize-observing app: records every `canvas_widget_resize` event the
/// runtime dispatches plus the routed keyboard traffic the tree walk
/// asserts on.
const ObservingApp = struct {
    resize_count: u32 = 0,
    last_resize_id: canvas.ObjectId = 0,
    last_resize_fraction: f32 = -1,
    keyboard_count: u32 = 0,
    last_keyboard_target_id: canvas.ObjectId = 0,
    last_keyboard_focus_moved: bool = false,
    last_keyboard_key: []const u8 = "",

    fn app(self: *@This()) App {
        return .{ .context = self, .name = "gpu-split-tree", .source = platform.WebViewSource.html("<h1>GPU</h1>"), .event_fn = event };
    }

    fn event(context: *anyopaque, runtime: *Runtime, event_value: Event) anyerror!void {
        _ = runtime;
        const self: *@This() = @ptrCast(@alignCast(context));
        switch (event_value) {
            .canvas_widget_resize => |resize_event| {
                self.resize_count += 1;
                self.last_resize_id = resize_event.id;
                self.last_resize_fraction = resize_event.fraction;
            },
            .canvas_widget_keyboard => |keyboard_event| {
                self.keyboard_count += 1;
                self.last_keyboard_focus_moved = keyboard_event.keyboard.focus_moved;
                self.last_keyboard_key = keyboard_event.keyboard.key;
                self.last_keyboard_target_id = if (keyboard_event.target) |target| target.id else 0;
            },
            else => {},
        }
    }
};

fn buildSplitTree(ui: *TestUi) TestUi.Node {
    return ui.split(.{ .value = 0.5, .on_resize = TestUi.valueMsg(.resized) }, .{
        ui.column(.{ .min_width = 60 }, .{}),
        ui.column(.{ .min_width = 60 }, .{}),
    });
}

fn findNodeByKind(layout: canvas.WidgetLayoutTree, kind: canvas.WidgetKind) ?canvas.WidgetLayoutNode {
    for (layout.nodes) |node| {
        if (node.widget.kind == kind) return node;
    }
    return null;
}

test "split finalize synthesizes the divider and binds on_resize to the split" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var ui = TestUi.init(arena.allocator());
    const tree = try ui.finalize(buildSplitTree(&ui));

    try std.testing.expectEqual(canvas.WidgetKind.split, tree.root.kind);
    try std.testing.expectEqual(@as(usize, 3), tree.root.children.len);
    try std.testing.expectEqual(canvas.WidgetKind.split_divider, tree.root.children[1].kind);
    try std.testing.expect(tree.root.children[1].id != 0);
    // Panes clip so drag echoes (and narrow panes) never paint into the
    // neighbor.
    try std.testing.expect(tree.root.children[0].layout.clip_content);
    try std.testing.expect(tree.root.children[2].layout.clip_content);
    // The resize handler binds to the SPLIT id and builds the fraction Msg.
    const msg = tree.msgForResize(tree.root.id, 0.25) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(f32, 0.25), msg.resized);
    try std.testing.expectEqual(@as(?TestMsg, null), tree.msgForResize(tree.root.children[1].id, 0.25));
}

test "divider drag applies the clamped fraction and dispatches canvas_widget_resize" {
    const harness = try TestHarness().create(std.testing.allocator, .{});
    defer harness.destroy(std.testing.allocator);
    harness.null_platform.gpu_surfaces = true;
    var app_state: ObservingApp = .{};
    const app = app_state.app();
    try harness.start(app);

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(0, 0, 309, 100),
    });

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var ui = TestUi.init(arena.allocator());
    const tree = try ui.finalize(buildSplitTree(&ui));
    var nodes: [8]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(tree.root, geometry.RectF.init(0, 0, 309, 100), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    // Divider band: 9pt default, centered at x = 154.5 for fraction 0.5
    // of the 300pt pane space.
    const installed = try harness.runtime.canvasWidgetLayout(1, "canvas");
    const divider = findNodeByKind(installed, .split_divider) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(f32, 150), divider.frame.x);
    try std.testing.expectEqual(@as(f32, 9), divider.frame.width);

    // Press the divider band and drag right: fraction follows the
    // pointer, clamped only by the panes' min widths.
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{ .window_id = 1, .label = "canvas", .kind = .pointer_down, .x = 154, .y = 50, .button = 0 } });
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{ .window_id = 1, .label = "canvas", .kind = .pointer_drag, .x = 214, .y = 50 } });

    const dragged = try harness.runtime.canvasWidgetLayout(1, "canvas");
    const split_node = findNodeByKind(dragged, .split) orelse return error.TestUnexpectedResult;
    const expected_fraction: f32 = (214.0 - 4.5) / 300.0;
    try std.testing.expectApproxEqAbs(expected_fraction, split_node.widget.value, 0.0001);
    // Frames follow: pane 1 widened, divider moved, pane 2 shifted.
    const dragged_divider = findNodeByKind(dragged, .split_divider) orelse return error.TestUnexpectedResult;
    try std.testing.expectApproxEqAbs(expected_fraction * 300.0, dragged_divider.frame.x, 0.001);
    // The app observed exactly one coalesced resize with the applied
    // fraction, addressed to the SPLIT.
    try std.testing.expectEqual(@as(u32, 1), app_state.resize_count);
    try std.testing.expectEqual(split_node.widget.id, app_state.last_resize_id);
    try std.testing.expectApproxEqAbs(expected_fraction, app_state.last_resize_fraction, 0.0001);

    // Dragging past the second pane's min width clamps: pane 2 keeps its
    // 60pt floor, so the fraction tops out at 240/300.
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{ .window_id = 1, .label = "canvas", .kind = .pointer_drag, .x = 305, .y = 50 } });
    const clamped = try harness.runtime.canvasWidgetLayout(1, "canvas");
    const clamped_split = findNodeByKind(clamped, .split) orelse return error.TestUnexpectedResult;
    try std.testing.expectApproxEqAbs(@as(f32, 240.0 / 300.0), clamped_split.widget.value, 0.0001);
    try std.testing.expectEqual(@as(u32, 2), app_state.resize_count);
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{ .window_id = 1, .label = "canvas", .kind = .pointer_up, .x = 305, .y = 50, .button = 0 } });
}

test "split fractions survive rebuilds until the source changes and panes re-lay out" {
    const harness = try TestHarness().create(std.testing.allocator, .{});
    defer harness.destroy(std.testing.allocator);
    harness.null_platform.gpu_surfaces = true;
    var app_state: ObservingApp = .{};
    const app = app_state.app();
    try harness.start(app);

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(0, 0, 309, 100),
    });

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var ui = TestUi.init(arena.allocator());
    const tree = try ui.finalize(buildSplitTree(&ui));
    var nodes: [8]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(tree.root, geometry.RectF.init(0, 0, 309, 100), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    // The user drags: runtime owns the fraction.
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{ .window_id = 1, .label = "canvas", .kind = .pointer_down, .x = 154, .y = 50, .button = 0 } });
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{ .window_id = 1, .label = "canvas", .kind = .pointer_drag, .x = 214, .y = 50 } });
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{ .window_id = 1, .label = "canvas", .kind = .pointer_up, .x = 214, .y = 50, .button = 0 } });
    const dragged_fraction = (try harness.runtime.canvasWidgetLayout(1, "canvas")).findById(tree.root.id).?.widget.value;
    try std.testing.expect(dragged_fraction > 0.6);

    // An elm-style rebuild with the unchanged source fraction must not
    // reset the divider, and the restored fraction RE-LAYS the panes
    // (the reconcile re-runs the split's child layout in place).
    var rebuild_ui = TestUi.init(arena.allocator());
    const rebuild_tree = try rebuild_ui.finalize(buildSplitTree(&rebuild_ui));
    var rebuild_nodes: [8]canvas.WidgetLayoutNode = undefined;
    const rebuild_layout = try canvas.layoutWidgetTree(rebuild_tree.root, geometry.RectF.init(0, 0, 309, 100), &rebuild_nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", rebuild_layout);
    const rebuilt = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expectApproxEqAbs(dragged_fraction, rebuilt.findById(tree.root.id).?.widget.value, 0.0001);
    const rebuilt_divider = findNodeByKind(rebuilt, .split_divider) orelse return error.TestUnexpectedResult;
    try std.testing.expectApproxEqAbs(dragged_fraction * 300.0, rebuilt_divider.frame.x, 0.001);

    // A source-side fraction change (the model driving the split) wins.
    var driven_ui = TestUi.init(arena.allocator());
    const driven_tree = try driven_ui.finalize(driven_ui.split(.{ .value = 0.3, .on_resize = TestUi.valueMsg(.resized) }, .{
        driven_ui.column(.{ .min_width = 60 }, .{}),
        driven_ui.column(.{ .min_width = 60 }, .{}),
    }));
    var driven_nodes: [8]canvas.WidgetLayoutNode = undefined;
    const driven_layout = try canvas.layoutWidgetTree(driven_tree.root, geometry.RectF.init(0, 0, 309, 100), &driven_nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", driven_layout);
    try std.testing.expectApproxEqAbs(@as(f32, 0.3), (try harness.runtime.canvasWidgetLayout(1, "canvas")).findById(tree.root.id).?.widget.value, 0.0001);
}

test "keyboard adjusts the focused split divider through the resize event" {
    const harness = try TestHarness().create(std.testing.allocator, .{});
    defer harness.destroy(std.testing.allocator);
    harness.null_platform.gpu_surfaces = true;
    var app_state: ObservingApp = .{};
    const app = app_state.app();
    try harness.start(app);

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(0, 0, 309, 100),
    });

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var ui = TestUi.init(arena.allocator());
    const tree = try ui.finalize(buildSplitTree(&ui));
    var nodes: [8]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(tree.root, geometry.RectF.init(0, 0, 309, 100), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    // Focus the divider by pressing it (press-claiming, focusable).
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{ .window_id = 1, .label = "canvas", .kind = .pointer_down, .x = 154, .y = 50, .button = 0 } });
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{ .window_id = 1, .label = "canvas", .kind = .pointer_up, .x = 154, .y = 50, .button = 0 } });
    const divider_id = findNodeByKind(layout, .split_divider).?.widget.id;
    try std.testing.expectEqual(divider_id, harness.runtime.views[0].canvas_widget_focused_id);

    // ArrowRight steps the fraction up by 0.05 (the slider step) and the
    // resize event carries the applied value; Home/End jump to the min
    // width clamp edges.
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{ .window_id = 1, .label = "canvas", .kind = .key_down, .key = "arrowright" } });
    try std.testing.expectEqual(@as(u32, 1), app_state.resize_count);
    try std.testing.expectApproxEqAbs(@as(f32, 0.55), app_state.last_resize_fraction, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.55), (try harness.runtime.canvasWidgetLayout(1, "canvas")).findById(tree.root.id).?.widget.value, 0.0001);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{ .window_id = 1, .label = "canvas", .kind = .key_down, .key = "arrowleft", .modifiers = .{ .shift = true } } });
    try std.testing.expectApproxEqAbs(@as(f32, 0.45), app_state.last_resize_fraction, 0.0001);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{ .window_id = 1, .label = "canvas", .kind = .key_down, .key = "home" } });
    try std.testing.expectApproxEqAbs(@as(f32, 60.0 / 300.0), app_state.last_resize_fraction, 0.0001);
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{ .window_id = 1, .label = "canvas", .kind = .key_down, .key = "end" } });
    try std.testing.expectApproxEqAbs(@as(f32, 240.0 / 300.0), app_state.last_resize_fraction, 0.0001);
    try std.testing.expectEqual(@as(u32, 4), app_state.resize_count);
}

fn treeRowPanel(id: canvas.ObjectId, y: f32, height: f32, expanded: ?bool, children: []const canvas.Widget) canvas.Widget {
    return .{
        .id = id,
        .kind = .panel,
        .frame = geometry.RectF.init(0, y, 0, height),
        .state = .{ .expanded = expanded },
        // Pressable rows (markup rows bind on-press): the press action
        // makes the row a press claimer, the treeitem role makes it a
        // roving-focus tree row.
        .semantics = .{ .role = .treeitem, .actions = .{ .press = true } },
        .children = children,
    };
}

test "tree keymap walks visible rows, collapses, expands, and selects through real key dispatch" {
    const harness = try TestHarness().create(std.testing.allocator, .{});
    defer harness.destroy(std.testing.allocator);
    harness.null_platform.gpu_surfaces = true;
    var app_state: ObservingApp = .{};
    const app = app_state.app();
    try harness.start(app);

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(0, 0, 240, 400),
    });

    // A nested disclosure tree:
    //   A (expanded)
    //   ├─ A1 (leaf)
    //   └─ A2 (collapsed)
    //   B (leaf)
    const a_children = [_]canvas.Widget{
        treeRowPanel(111, 30, 24, null, &.{}),
        treeRowPanel(112, 60, 24, false, &.{}),
    };
    const rows = [_]canvas.Widget{
        treeRowPanel(11, 0, 90, true, &a_children),
        treeRowPanel(12, 100, 24, null, &.{}),
    };
    const root = canvas.Widget{ .id = 10, .kind = .tree, .children = &rows };
    var nodes: [8]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(root, geometry.RectF.init(0, 0, 240, 400), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);

    const view = &harness.runtime.views[0];

    // Focus row A by pressing its header area (above its child rows).
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{ .window_id = 1, .label = "canvas", .kind = .pointer_down, .x = 10, .y = 10, .button = 0 } });
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{ .window_id = 1, .label = "canvas", .kind = .pointer_up, .x = 10, .y = 10, .button = 0 } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 11), view.canvas_widget_focused_id);

    const key = struct {
        fn down(h: anytype, a: App, name: []const u8) !void {
            try h.runtime.dispatchPlatformEvent(a, .{ .gpu_surface_input = .{ .window_id = 1, .label = "canvas", .kind = .key_down, .key = name } });
        }
    };

    // Down walks visible rows in tree order, at every depth; the routed
    // keyboard events target the NEW row with focus_moved set, so
    // selection follows focus (runtime echo asserts below, the app Msg
    // rides the same intent).
    try key.down(harness, app, "arrowdown");
    try std.testing.expectEqual(@as(canvas.ObjectId, 111), view.canvas_widget_focused_id);
    try std.testing.expectEqual(@as(canvas.ObjectId, 111), app_state.last_keyboard_target_id);
    try std.testing.expect(app_state.last_keyboard_focus_moved);
    try key.down(harness, app, "arrowdown");
    try std.testing.expectEqual(@as(canvas.ObjectId, 112), view.canvas_widget_focused_id);
    try key.down(harness, app, "arrowdown");
    try std.testing.expectEqual(@as(canvas.ObjectId, 12), view.canvas_widget_focused_id);
    // Selection followed focus onto B (runtime echo through the select
    // intent) and single-select cleared the earlier rows.
    const after_walk = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expect(after_walk.findById(12).?.widget.state.selected);
    try std.testing.expect(!after_walk.findById(112).?.widget.state.selected);
    // Down at the last row stays put.
    try key.down(harness, app, "arrowdown");
    try std.testing.expectEqual(@as(canvas.ObjectId, 12), view.canvas_widget_focused_id);

    // Home/End jump across the whole scope regardless of depth.
    try key.down(harness, app, "home");
    try std.testing.expectEqual(@as(canvas.ObjectId, 11), view.canvas_widget_focused_id);
    try key.down(harness, app, "end");
    try std.testing.expectEqual(@as(canvas.ObjectId, 12), view.canvas_widget_focused_id);

    // Up from B lands on A2 (the deepest previous visible row).
    try key.down(harness, app, "arrowup");
    try std.testing.expectEqual(@as(canvas.ObjectId, 112), view.canvas_widget_focused_id);

    // Left on a collapsed child moves to its PARENT row.
    try key.down(harness, app, "arrowleft");
    try std.testing.expectEqual(@as(canvas.ObjectId, 11), view.canvas_widget_focused_id);
    try std.testing.expect(app_state.last_keyboard_focus_moved);

    // Left on the expanded parent is a COLLAPSE, not a move: focus stays,
    // the routed event lands in place (focus_moved false → the app's
    // on_toggle intent), and the runtime echoes the expanded flip.
    try key.down(harness, app, "arrowleft");
    try std.testing.expectEqual(@as(canvas.ObjectId, 11), view.canvas_widget_focused_id);
    try std.testing.expect(!app_state.last_keyboard_focus_moved);
    try std.testing.expectEqual(@as(?bool, false), (try harness.runtime.canvasWidgetLayout(1, "canvas")).findById(11).?.widget.state.expanded);

    // Right on the collapsed row EXPANDS (echo back to true), and a
    // second Right moves into the first child row.
    try key.down(harness, app, "arrowright");
    try std.testing.expectEqual(@as(canvas.ObjectId, 11), view.canvas_widget_focused_id);
    try std.testing.expectEqual(@as(?bool, true), (try harness.runtime.canvasWidgetLayout(1, "canvas")).findById(11).?.widget.state.expanded);
    try key.down(harness, app, "arrowright");
    try std.testing.expectEqual(@as(canvas.ObjectId, 111), view.canvas_widget_focused_id);

    // Enter selects the focused row (the select intent both echoes and
    // reaches the app's on_press through the handler table).
    try key.down(harness, app, "enter");
    const after_enter = try harness.runtime.canvasWidgetLayout(1, "canvas");
    try std.testing.expect(after_enter.findById(111).?.widget.state.selected);
    try std.testing.expect(!after_enter.findById(12).?.widget.state.selected);
}

test "a virtual list declaring the tree role scopes the tree keymap over its rows" {
    const harness = try TestHarness().create(std.testing.allocator, .{});
    defer harness.destroy(std.testing.allocator);
    harness.null_platform.gpu_surfaces = true;
    var app_state: ObservingApp = .{};
    const app = app_state.app();
    try harness.start(app);

    _ = try harness.runtime.createView(.{
        .window_id = 1,
        .label = "canvas",
        .kind = .gpu_surface,
        .frame = geometry.RectF.init(0, 0, 240, 100),
    });

    // A windowed virtual list of treeitem rows: the scroll container
    // itself carries `role = .tree` (rows are placed straight under the
    // virtualized region — there is no room for a `.tree` flow container
    // between them), and the keymap must scope to it.
    const rows = [_]canvas.Widget{
        treeRowPanel(21, 0, 24, null, &.{}),
        treeRowPanel(22, 0, 24, null, &.{}),
        treeRowPanel(23, 0, 24, null, &.{}),
    };
    const list = canvas.Widget{
        .id = 20,
        .kind = .scroll_view,
        .layout = .{
            .virtualized = true,
            .virtual_item_extent = 24,
            .virtual_overscan = 1,
            .virtual_item_count = 3,
            .virtual_first_index = 0,
        },
        .semantics = .{ .role = .tree },
        .children = &rows,
    };
    var nodes: [6]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(list, geometry.RectF.init(0, 0, 240, 100), &nodes);
    _ = try harness.runtime.setCanvasWidgetLayout(1, "canvas", layout);
    const view = &harness.runtime.views[0];

    // Focus the first row by pressing it.
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{ .window_id = 1, .label = "canvas", .kind = .pointer_down, .x = 10, .y = 10, .button = 0 } });
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{ .window_id = 1, .label = "canvas", .kind = .pointer_up, .x = 10, .y = 10, .button = 0 } });
    try std.testing.expectEqual(@as(canvas.ObjectId, 21), view.canvas_widget_focused_id);

    const key = struct {
        fn down(h: anytype, a: App, name: []const u8) !void {
            try h.runtime.dispatchPlatformEvent(a, .{ .gpu_surface_input = .{ .window_id = 1, .label = "canvas", .kind = .key_down, .key = name } });
        }
    };

    // Up/Down walk the mounted rows; Home/End jump the scope's edges.
    try key.down(harness, app, "arrowdown");
    try std.testing.expectEqual(@as(canvas.ObjectId, 22), view.canvas_widget_focused_id);
    try key.down(harness, app, "arrowdown");
    try std.testing.expectEqual(@as(canvas.ObjectId, 23), view.canvas_widget_focused_id);
    try key.down(harness, app, "arrowdown");
    try std.testing.expectEqual(@as(canvas.ObjectId, 23), view.canvas_widget_focused_id);
    try key.down(harness, app, "home");
    try std.testing.expectEqual(@as(canvas.ObjectId, 21), view.canvas_widget_focused_id);
    try key.down(harness, app, "end");
    try std.testing.expectEqual(@as(canvas.ObjectId, 23), view.canvas_widget_focused_id);
}
