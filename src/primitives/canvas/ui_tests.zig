const std = @import("std");
const geometry = @import("geometry");
const canvas = @import("root.zig");
const ui_model = @import("ui.zig");

const testing = std.testing;

const Filter = enum { all, active, done };

const Task = struct {
    id: u32,
    title: []const u8,
    done: bool = false,

    fn key(task: *const Task) ui_model.UiKey {
        return ui_model.uiKey(task.id);
    }
};

const Msg = union(enum) {
    add,
    toggle: u32,
    set_filter: Filter,
};

const InboxUi = ui_model.Ui(Msg);

const Model = struct {
    tasks: []const Task,
    filter: Filter = .all,
    open_count: usize = 0,
};

fn taskRow(ui: *InboxUi, task: *const Task) InboxUi.Node {
    return ui.row(.{ .gap = 8, .padding = 4, .cross = .center }, .{
        ui.checkbox(.{ .checked = task.done, .on_toggle = Msg{ .toggle = task.id } }),
        ui.text(.{ .grow = 1 }, task.title),
    });
}

fn inboxView(ui: *InboxUi, model: *const Model) InboxUi.Node {
    return ui.column(.{ .gap = 8 }, .{
        ui.row(.{ .gap = 8, .padding = 8 }, .{
            ui.textField(.{ .placeholder = "New task…", .grow = 1, .on_submit = .add }),
            ui.button(.{ .variant = .primary, .on_press = .add }, "Add"),
        }),
        ui.scroll(.{ .grow = 1 }, ui.each(model.tasks, Task.key, taskRow)),
        ui.statusBar(.{}, .{
            ui.text(.{}, ui.fmt("{d} open", .{model.open_count})),
        }),
    });
}

fn collectIds(widget: canvas.Widget, ids: *std.ArrayListUnmanaged(canvas.ObjectId), allocator: std.mem.Allocator) !void {
    try ids.append(allocator, widget.id);
    for (widget.children) |child| try collectIds(child, ids, allocator);
}

fn findByKind(widget: canvas.Widget, kind: canvas.WidgetKind) ?canvas.Widget {
    if (widget.kind == kind) return widget;
    for (widget.children) |child| {
        if (findByKind(child, kind)) |found| return found;
    }
    return null;
}

fn findRowByCheckboxToggle(tree: InboxUi.Tree, widget: canvas.Widget, task_id: u32) ?canvas.Widget {
    if (widget.kind == .checkbox) {
        if (tree.msgFor(widget.id, .toggle)) |msg| {
            if (msg == .toggle and msg.toggle == task_id) return widget;
        }
    }
    for (widget.children) |child| {
        if (findRowByCheckboxToggle(tree, child, task_id)) |found| return found;
    }
    return null;
}

test "ui builder emits an engine-compatible widget tree" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();

    const tasks = [_]Task{
        .{ .id = 1, .title = "Ship IR" },
        .{ .id = 2, .title = "Write RFC", .done = true },
    };
    const model = Model{ .tasks = &tasks, .open_count = 1 };

    var ui = InboxUi.init(arena_state.allocator());
    const tree = try ui.finalize(inboxView(&ui, &model));

    try testing.expectEqual(canvas.WidgetKind.column, tree.root.kind);
    try testing.expectEqual(@as(usize, 3), tree.root.children.len);
    try testing.expect(findByKind(tree.root, .text_field) != null);
    try testing.expectEqual(@as(usize, 2), findByKind(tree.root, .scroll_view).?.children.len);
    try testing.expectEqualStrings("1 open", findByKind(tree.root, .status_bar).?.children[0].text);

    var ids: std.ArrayListUnmanaged(canvas.ObjectId) = .empty;
    defer ids.deinit(testing.allocator);
    try collectIds(tree.root, &ids, testing.allocator);
    for (ids.items, 0..) |id, index| {
        try testing.expect(id != 0);
        for (ids.items[index + 1 ..]) |other| try testing.expect(id != other);
    }

    var layout_nodes: [64]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(tree.root, geometry.RectF.init(0, 0, 720, 480), &layout_nodes);
    const button_id = findByKind(tree.root, .button).?.id;
    var saw_button = false;
    for (layout.nodes) |node| {
        if (node.widget.id == button_id) saw_button = true;
    }
    try testing.expect(saw_button);
}

test "structural ids are stable across rebuilds" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();

    const tasks = [_]Task{
        .{ .id = 1, .title = "Ship IR" },
        .{ .id = 2, .title = "Write RFC" },
    };
    const model = Model{ .tasks = &tasks, .open_count = 2 };

    var first_ui = InboxUi.init(arena_state.allocator());
    const first = try first_ui.finalize(inboxView(&first_ui, &model));
    var second_ui = InboxUi.init(arena_state.allocator());
    const second = try second_ui.finalize(inboxView(&second_ui, &model));

    var first_ids: std.ArrayListUnmanaged(canvas.ObjectId) = .empty;
    defer first_ids.deinit(testing.allocator);
    var second_ids: std.ArrayListUnmanaged(canvas.ObjectId) = .empty;
    defer second_ids.deinit(testing.allocator);
    try collectIds(first.root, &first_ids, testing.allocator);
    try collectIds(second.root, &second_ids, testing.allocator);
    try testing.expectEqualSlices(canvas.ObjectId, first_ids.items, second_ids.items);
}

test "keyed items keep their ids across reorders and insertions" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();

    const before_tasks = [_]Task{
        .{ .id = 1, .title = "Ship IR" },
        .{ .id = 2, .title = "Write RFC" },
    };
    const after_tasks = [_]Task{
        .{ .id = 3, .title = "New first task" },
        .{ .id = 2, .title = "Write RFC" },
        .{ .id = 1, .title = "Ship IR" },
    };

    var before_ui = InboxUi.init(arena_state.allocator());
    const before = try before_ui.finalize(inboxView(&before_ui, &Model{ .tasks = &before_tasks }));
    var after_ui = InboxUi.init(arena_state.allocator());
    const after = try after_ui.finalize(inboxView(&after_ui, &Model{ .tasks = &after_tasks }));

    const before_task_one = findRowByCheckboxToggle(before, before.root, 1).?;
    const after_task_one = findRowByCheckboxToggle(after, after.root, 1).?;
    try testing.expectEqual(before_task_one.id, after_task_one.id);

    const before_task_two = findRowByCheckboxToggle(before, before.root, 2).?;
    const after_task_two = findRowByCheckboxToggle(after, after.root, 2).?;
    try testing.expectEqual(before_task_two.id, after_task_two.id);
}

test "typed handlers dispatch through the elm-style loop" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();

    var tasks = [_]Task{
        .{ .id = 1, .title = "Ship IR" },
        .{ .id = 2, .title = "Write RFC" },
    };
    var model = Model{ .tasks = &tasks, .open_count = 2 };

    var ui = InboxUi.init(arena_state.allocator());
    const tree = try ui.finalize(inboxView(&ui, &model));

    const add_button = findByKind(tree.root, .button).?;
    try testing.expectEqual(Msg.add, tree.msgFor(add_button.id, .press).?);
    try testing.expectEqual(@as(?Msg, null), tree.msgFor(add_button.id, .toggle));

    const checkbox = findRowByCheckboxToggle(tree, tree.root, 2).?;
    try testing.expect(!checkbox.state.selected);

    // Dispatch the checkbox toggle message and rebuild, elm-style.
    switch (tree.msgFor(checkbox.id, .toggle).?) {
        .toggle => |task_id| {
            for (&tasks) |*task| {
                if (task.id == task_id) task.done = !task.done;
            }
        },
        else => return error.TestUnexpectedResult,
    }
    model.open_count = 1;

    var next_ui = InboxUi.init(arena_state.allocator());
    const next = try next_ui.finalize(inboxView(&next_ui, &model));
    const next_checkbox = findRowByCheckboxToggle(next, next.root, 2).?;
    try testing.expectEqual(checkbox.id, next_checkbox.id);
    try testing.expect(next_checkbox.state.selected);
    try testing.expectEqualStrings("1 open", findByKind(next.root, .status_bar).?.children[0].text);
}

test "allocation failure latches and surfaces from finalize" {
    var failing = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 0 });
    var ui = InboxUi.init(failing.allocator());
    const node = ui.column(.{}, .{
        ui.text(.{}, ui.fmt("{d}", .{@as(usize, 1)})),
    });
    try testing.expectError(error.OutOfMemory, ui.finalize(node));
}
