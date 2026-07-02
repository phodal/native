const std = @import("std");
const zero_native = @import("zero-native");
const main = @import("main.zig");

const canvas = zero_native.canvas;
const testing = std.testing;

const HabitsUi = main.HabitsUi;
const Model = main.Model;
const Msg = main.Msg;

const HabitsMarkup = canvas.MarkupView(Model, main.Msg);

fn buildTree(arena: std.mem.Allocator, model: *const Model) !HabitsUi.Tree {
    var view = try HabitsMarkup.init(arena, main.habits_markup);
    var ui = HabitsUi.init(arena);
    return ui.finalize(try view.build(&ui, model));
}

fn findByText(widget: canvas.Widget, kind: canvas.WidgetKind, text: []const u8) ?canvas.Widget {
    if (widget.kind == kind and std.mem.eql(u8, widget.text, text)) return widget;
    for (widget.children) |child| {
        if (findByText(child, kind, text)) |found| return found;
    }
    return null;
}

fn subtreeHasText(widget: canvas.Widget, text: []const u8) bool {
    if (std.mem.eql(u8, widget.text, text)) return true;
    for (widget.children) |child| {
        if (subtreeHasText(child, text)) return true;
    }
    return false;
}

/// The keyed habit row for a given name: the list-item row whose subtree
/// contains the name text.
fn findRow(widget: canvas.Widget, habit_name: []const u8) ?canvas.Widget {
    if (widget.semantics.role == .listitem and subtreeHasText(widget, habit_name)) return widget;
    for (widget.children) |child| {
        if (findRow(child, habit_name)) |found| return found;
    }
    return null;
}

fn findButtonIn(widget: canvas.Widget, text: []const u8) ?canvas.Widget {
    if (widget.kind == .button and std.mem.eql(u8, widget.text, text)) return widget;
    for (widget.children) |child| {
        if (findButtonIn(child, text)) |found| return found;
    }
    return null;
}

fn countRows(widget: canvas.Widget) usize {
    var total: usize = 0;
    if (widget.semantics.role == .listitem) total += 1;
    for (widget.children) |child| total += countRows(child);
    return total;
}

test "a full session: add, done, and filter drive the model through typed dispatch" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var model = main.initialModel();

    var tree = try buildTree(arena, &model);
    try testing.expect(findByText(tree.root, .status_bar, "3 habits · 21 total days") != null);
    try testing.expectEqual(@as(usize, 3), countRows(tree.root));

    // Click "New habit": a new habit with streak 0 appears.
    const add_button = findByText(tree.root, .button, "New habit").?;
    main.update(&model, tree.msgForPointer(add_button.id, .up).?);
    try testing.expectEqual(@as(usize, 4), model.habit_count);

    tree = try buildTree(arena, &model);
    try testing.expect(findByText(tree.root, .status_bar, "4 habits · 21 total days") != null);
    try testing.expectEqual(@as(usize, 4), countRows(tree.root));
    try testing.expect(findRow(tree.root, "Habit 4") != null);
    try testing.expect(subtreeHasText(findRow(tree.root, "Habit 4").?, "0 days"));

    // Click "Done today" on the Meditate row: its streak increments.
    const meditate_row = findRow(tree.root, "Meditate").?;
    try testing.expect(subtreeHasText(meditate_row, "12 days"));
    const done_button = findButtonIn(meditate_row, "Done today").?;
    main.update(&model, tree.msgForPointer(done_button.id, .up).?);
    try testing.expectEqual(@as(u32, 13), model.habitById(1).?.streak);

    // The row keeps its widget id across the rebuild and the streak text
    // updates in place.
    tree = try buildTree(arena, &model);
    const meditate_after = findRow(tree.root, "Meditate").?;
    try testing.expectEqual(meditate_row.id, meditate_after.id);
    try testing.expect(subtreeHasText(meditate_after, "13 days"));
    try testing.expect(!subtreeHasText(meditate_after, "12 days"));
    try testing.expect(findByText(tree.root, .status_bar, "4 habits · 22 total days") != null);

    // Switch to the active filter: zero-streak habits disappear, and the
    // Meditate row keeps its widget id across the filtering.
    const active_button = findByText(tree.root, .button, "active").?;
    main.update(&model, tree.msgForPointer(active_button.id, .up).?);
    try testing.expectEqual(main.Filter.active, model.filter);

    tree = try buildTree(arena, &model);
    try testing.expectEqual(@as(usize, 2), countRows(tree.root));
    try testing.expect(findRow(tree.root, "Exercise") == null);
    try testing.expect(findRow(tree.root, "Habit 4") == null);
    const meditate_filtered = findRow(tree.root, "Meditate").?;
    try testing.expectEqual(meditate_row.id, meditate_filtered.id);
    const done_filtered = findButtonIn(meditate_filtered, "Done today").?;
    try testing.expectEqual(done_button.id, done_filtered.id);

    // The button still dispatches after filtering.
    main.update(&model, tree.msgForPointer(done_filtered.id, .up).?);
    try testing.expectEqual(@as(u32, 14), model.habitById(1).?.streak);

    // Back to "all": every row returns, identities intact.
    const all_button = findByText(tree.root, .button, "all").?;
    main.update(&model, tree.msgForPointer(all_button.id, .up).?);
    tree = try buildTree(arena, &model);
    try testing.expectEqual(@as(usize, 4), countRows(tree.root));
    try testing.expectEqual(meditate_row.id, findRow(tree.root, "Meditate").?.id);
}

test "the habits view lays out through the canvas engine" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();

    var model = main.initialModel();
    const tree = try buildTree(arena_state.allocator(), &model);

    var nodes: [256]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(tree.root, zero_native.geometry.RectF.init(0, 0, 720, 520), &nodes);
    try testing.expect(layout.nodes.len > 0);

    const add_button = findByText(tree.root, .button, "New habit").?;
    var saw_button = false;
    for (layout.nodes) |node| {
        if (node.widget.id == add_button.id) saw_button = true;
    }
    try testing.expect(saw_button);
}
