//! habits: a small habit tracker authored in markup + Zig.
//!
//! The view lives in `habits.zml` (embedded into the binary, and watched
//! for hot reload in dev); this file is the logic: `Model`, `Msg`, and
//! `update`. Rows carry a markup `global-key` pinned to the habit id, so a
//! row keeps its widget identity across rebuilds and filtering.

const std = @import("std");
const runner = @import("runner");
const zero_native = @import("zero-native");

pub const panic = std.debug.FullPanic(zero_native.debug.capturePanic);

const canvas = zero_native.canvas;
const geometry = zero_native.geometry;

const canvas_label = "habits-canvas";
const window_width: f32 = 720;
const window_height: f32 = 520;
const max_habits = 64;
const max_habit_name = 32;

const app_permissions = [_][]const u8{ zero_native.security.permission_command, zero_native.security.permission_view };
const shell_views = [_]zero_native.ShellView{
    .{ .label = canvas_label, .kind = .gpu_surface, .fill = true, .role = "Habit tracker canvas", .accessibility_label = "Habit tracker", .gpu_backend = .metal, .gpu_pixel_format = .bgra8_unorm, .gpu_present_mode = .timer, .gpu_alpha_mode = .@"opaque", .gpu_color_space = .srgb, .gpu_vsync = true },
};
const shell_windows = [_]zero_native.ShellWindow{.{
    .label = "main",
    .title = "zero-native Habits",
    .width = window_width,
    .height = window_height,
    .restore_state = false,
    .views = &shell_views,
}};
const shell_scene: zero_native.ShellConfig = .{ .windows = &shell_windows };

// ------------------------------------------------------------------ model

pub const Filter = enum { all, active };

pub const Habit = struct {
    id: u32,
    name_storage: [max_habit_name]u8 = [_]u8{0} ** max_habit_name,
    name_len: usize = 0,
    streak: u32 = 0,

    pub fn name(habit: *const Habit) []const u8 {
        return habit.name_storage[0..habit.name_len];
    }
};

pub const Msg = union(enum) {
    add,
    done: u32,
    set_filter: Filter,
};

pub const Model = struct {
    habits: [max_habits]Habit = undefined,
    habit_count: usize = 0,
    next_id: u32 = 1,
    filter: Filter = .all,

    pub const filters = [_]Filter{ .all, .active };

    pub fn addHabit(model: *Model, text: []const u8, streak: u32) void {
        if (model.habit_count >= max_habits) return;
        var habit = Habit{ .id = model.next_id, .streak = streak };
        const len = @min(text.len, max_habit_name);
        @memcpy(habit.name_storage[0..len], text[0..len]);
        habit.name_len = len;
        model.habits[model.habit_count] = habit;
        model.habit_count += 1;
        model.next_id += 1;
    }

    fn addGeneratedHabit(model: *Model) void {
        var buffer: [max_habit_name]u8 = undefined;
        const text = std.fmt.bufPrint(&buffer, "Habit {d}", .{model.next_id}) catch return;
        model.addHabit(text, 0);
    }

    pub fn habitById(model: *Model, id: u32) ?*Habit {
        for (model.habits[0..model.habit_count]) |*habit| {
            if (habit.id == id) return habit;
        }
        return null;
    }

    pub fn totalDays(model: *const Model) usize {
        var total: usize = 0;
        for (model.habits[0..model.habit_count]) |habit| total += habit.streak;
        return total;
    }

    /// Habits under the current filter, copied into the build arena for
    /// the view pass. `active` means the streak is non-zero.
    pub fn visible(model: *const Model, arena: std.mem.Allocator) []const Habit {
        const out = arena.alloc(Habit, model.habit_count) catch return &.{};
        var count: usize = 0;
        for (model.habits[0..model.habit_count]) |habit| {
            const keep = switch (model.filter) {
                .all => true,
                .active => habit.streak > 0,
            };
            if (keep) {
                out[count] = habit;
                count += 1;
            }
        }
        return out[0..count];
    }
};

pub fn update(model: *Model, msg: Msg) void {
    switch (msg) {
        .add => model.addGeneratedHabit(),
        .done => |id| if (model.habitById(id)) |habit| {
            habit.streak += 1;
        },
        .set_filter => |filter| model.filter = filter,
    }
}

// ------------------------------------------------------------------- view

pub const HabitsUi = canvas.Ui(Msg);
pub const habits_markup = @embedFile("habits.zml");

// -------------------------------------------------------------------- app

const HabitsApp = zero_native.UiApp(Model, Msg);

pub fn initialModel() Model {
    var model = Model{};
    model.addHabit("Meditate", 12);
    model.addHabit("Exercise", 0);
    model.addHabit("Read 20 pages", 9);
    return model;
}

pub fn main(init: std.process.Init) !void {
    const app_state = try std.heap.page_allocator.create(HabitsApp);
    defer std.heap.page_allocator.destroy(app_state);
    app_state.* = HabitsApp.init(std.heap.page_allocator, initialModel(), .{
        .name = "habits",
        .scene = shell_scene,
        .canvas_label = canvas_label,
        .update = update,
        .markup = .{ .source = habits_markup, .watch_path = "src/habits.zml", .io = init.io },
    });
    defer app_state.deinit();
    try runner.runWithOptions(app_state.app(), .{
        .app_name = "habits",
        .window_title = "zero-native Habits",
        .bundle_id = "dev.zero_native.habits",
        .icon_path = "assets/icon.icns",
        .default_frame = geometry.RectF.init(0, 0, window_width, window_height),
        .restore_state = false,
        .js_window_api = false,
        .security = .{
            .permissions = &app_permissions,
            .navigation = .{ .allowed_origins = &.{ "zero://inline", "zero://app" } },
        },
    }, init);
}

test {
    _ = @import("tests.zig");
}
