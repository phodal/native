const std = @import("std");
const geometry = @import("geometry");
const protocol = @import("protocol.zig");
const snapshot = @import("snapshot.zig");

/// The dropbox protocol is filesystem-backed; targets without one
/// (freestanding wasm) publish and consume nothing. Comptime-known so
/// `std.Io.Dir.cwd()` (posix) is never analyzed on those targets.
const has_filesystem = switch (@import("builtin").os.tag) {
    .freestanding, .emscripten => false,
    else => true,
};

const snapshot_initial_capacity: usize = 16 * 1024;
const windows_initial_capacity: usize = 1024;

pub const Server = struct {
    io: std.Io,
    directory: []const u8 = protocol.default_dir,
    title: []const u8 = "native-sdk",

    pub fn init(io: std.Io, directory: []const u8, title: []const u8) Server {
        return .{ .io = io, .directory = directory, .title = title };
    }

    pub fn publish(self: Server, input_value: snapshot.Input) !void {
        if (!has_filesystem) return;
        var cwd = std.Io.Dir.cwd();
        try cwd.createDirPath(self.io, self.directory);
        var writer = try std.Io.Writer.Allocating.initCapacity(std.heap.page_allocator, snapshot_initial_capacity);
        defer writer.deinit();
        try snapshot.writeText(input_value, &writer.writer);
        var path_buffer: [256]u8 = undefined;
        try writePath(self.io, self.path("snapshot.txt", &path_buffer), writer.written());
        var a11y_writer = try std.Io.Writer.Allocating.initCapacity(std.heap.page_allocator, snapshot_initial_capacity);
        defer a11y_writer.deinit();
        try snapshot.writeA11yText(input_value, &a11y_writer.writer);
        try writePath(self.io, self.path("accessibility.txt", &path_buffer), a11y_writer.written());
        var windows_writer = try std.Io.Writer.Allocating.initCapacity(std.heap.page_allocator, windows_initial_capacity);
        defer windows_writer.deinit();
        for (input_value.windows) |window| {
            try windows_writer.writer.print("window @w{d} \"{s}\" focused={any}\n", .{ window.id, window.title, window.focused });
        }
        try writePath(self.io, self.path("windows.txt", &path_buffer), windows_writer.written());
    }

    pub fn publishBridgeResponse(self: Server, response: []const u8) !void {
        if (!has_filesystem) return;
        var cwd = std.Io.Dir.cwd();
        try cwd.createDirPath(self.io, self.directory);
        var path_buffer: [256]u8 = undefined;
        try writePath(self.io, self.path("bridge-response.txt", &path_buffer), response);
    }

    /// Response artifact for the `provenance` verb: the queried widget's
    /// authored-markup record, or the teaching error saying why there is
    /// none. One command in flight at a time, like the bridge response.
    pub fn publishProvenanceResponse(self: Server, response: []const u8) !void {
        if (!has_filesystem) return;
        var cwd = std.Io.Dir.cwd();
        try cwd.createDirPath(self.io, self.directory);
        var path_buffer: [256]u8 = undefined;
        try writePath(self.io, self.path("provenance.txt", &path_buffer), response);
    }

    /// Write a view screenshot artifact (`screenshot-<label>.png`). The
    /// bytes land in a temporary file first and are renamed into place so
    /// pollers never observe a partially written PNG.
    pub fn publishScreenshot(self: Server, view_label: []const u8, png_bytes: []const u8) !void {
        if (!has_filesystem) return;
        var cwd = std.Io.Dir.cwd();
        try cwd.createDirPath(self.io, self.directory);
        var name_buffer: [128]u8 = undefined;
        const name = try protocol.screenshotFileName(view_label, &name_buffer);
        var temp_name_buffer: [160]u8 = undefined;
        const temp_name = try std.fmt.bufPrint(&temp_name_buffer, "{s}.tmp", .{name});
        var path_buffer: [256]u8 = undefined;
        var temp_path_buffer: [256]u8 = undefined;
        const final_path = self.path(name, &path_buffer);
        const temp_path = self.path(temp_name, &temp_path_buffer);
        try writePath(self.io, temp_path, png_bytes);
        try std.Io.Dir.cwd().rename(temp_path, std.Io.Dir.cwd(), final_path, self.io);
    }

    pub fn takeCommand(self: Server, buffer: []u8) !?protocol.Command {
        if (!has_filesystem) return null;
        var path_buffer: [256]u8 = undefined;
        const command_path = self.path("command.txt", &path_buffer);
        const bytes = readPath(self.io, command_path, buffer) catch return null;
        const line = std.mem.trim(u8, bytes, " \n\r\t");
        if (line.len == 0 or std.mem.eql(u8, line, "done")) return null;
        // EVERY non-empty line is consumed (acked to `done`), even one
        // that cannot be dispatched. Leaving an oversized or malformed
        // line in place would strand the single-entry slot forever: the
        // driver's next command times out on a busy slot, and the
        // arrival watcher keeps waking the loop for a line the drain can
        // never retire. Ack first, then report the failure as an error
        // so the runtime records it where snapshots surface it.
        try writePath(self.io, command_path, "done\n");
        if (bytes.len == buffer.len) return error.CommandTooLarge;
        return try protocol.Command.parse(line);
    }

    /// True when the dropbox slot holds an unconsumed command line —
    /// non-empty and not the `done` ack. The same pending test
    /// `takeCommand` starts from, WITHOUT consuming: the arrival watcher
    /// polls this from its own thread and nudges the platform loop, and
    /// the drain on the loop thread stays the only consumer, so command
    /// order and the one-command-per-frame cadence are untouched.
    pub fn hasPendingCommand(self: Server) bool {
        if (!has_filesystem) return false;
        var buffer: [protocol.max_command_bytes]u8 = undefined;
        var path_buffer: [256]u8 = undefined;
        const bytes = readPath(self.io, self.path("command.txt", &path_buffer), &buffer) catch return false;
        const line = std.mem.trim(u8, bytes, " \n\r\t");
        return line.len != 0 and !std.mem.eql(u8, line, "done");
    }

    fn path(self: Server, name: []const u8, buffer: []u8) []const u8 {
        return std.fmt.bufPrint(buffer, "{s}/{s}", .{ self.directory, name }) catch unreachable;
    }
};

fn writePath(io: std.Io, path: []const u8, bytes: []const u8) !void {
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = bytes });
}

fn readPath(io: std.Io, path: []const u8, buffer: []u8) ![]const u8 {
    var file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    return buffer[0..try file.readPositionalAll(io, buffer, 0)];
}

fn resetTestDirectory(io: std.Io, path: []const u8) !void {
    var cwd = std.Io.Dir.cwd();
    cwd.deleteTree(io, path) catch {};
    try cwd.createDirPath(io, path);
}

test "server stores directory metadata" {
    const server = Server.init(std.testing.io, ".zig-cache/test-webview-automation", "Test");
    try std.testing.expectEqualStrings("Test", server.title);
}

test "server writes bridge response artifact" {
    const server = Server.init(std.testing.io, ".zig-cache/test-webview-automation", "Test");
    try server.publishBridgeResponse("{\"id\":\"1\",\"ok\":true}");

    var buffer: [128]u8 = undefined;
    var path_buffer: [256]u8 = undefined;
    const bytes = try readPath(std.testing.io, server.path("bridge-response.txt", &path_buffer), &buffer);
    try std.testing.expectEqualStrings("{\"id\":\"1\",\"ok\":true}", bytes);
}

test "server publishes large retained widget snapshots" {
    const directory = ".zig-cache/test-webview-automation-large-snapshot";
    try resetTestDirectory(std.testing.io, directory);
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, directory) catch {};

    const windows = [_]snapshot.Window{.{
        .title = "Large Widget Snapshot",
        .bounds = geometry.RectF.init(0, 0, 1200, 760),
    }};
    var widgets: [80]snapshot.Widget = undefined;
    for (&widgets, 0..) |*widget, index| {
        widget.* = .{
            .view_label = "components-canvas",
            .id = 1000 + index,
            .role = "textbox",
            .name = "Retained component field with a descriptive accessible name",
            .text_value = "native-sdk retained widget snapshot payload",
            .bounds = geometry.RectF.init(@floatFromInt(index), @floatFromInt(index), 180, 28),
            .actions = .{ .focus = true, .set_text = true, .set_selection = true },
            .text_selection = .{ .start = 1, .end = 12 },
        };
    }

    const server = Server.init(std.testing.io, directory, "Large");
    try server.publish(.{
        .windows = &windows,
        .widgets = &widgets,
    });

    var path_buffer: [256]u8 = undefined;
    var buffer: [32 * 1024]u8 = undefined;
    const text = try readPath(std.testing.io, server.path("snapshot.txt", &path_buffer), &buffer);
    try std.testing.expect(text.len > 4 * 1024);
    try std.testing.expect(std.mem.indexOf(u8, text, "widget @w1/components-canvas#1079") != null);

    const a11y = try readPath(std.testing.io, server.path("accessibility.txt", &path_buffer), &buffer);
    try std.testing.expect(a11y.len > 4 * 1024);
    try std.testing.expect(std.mem.indexOf(u8, a11y, "@w1/components-canvas#1079 role=textbox") != null);
}

test "server writes screenshot artifacts atomically" {
    const directory = ".zig-cache/test-webview-automation-screenshot";
    try resetTestDirectory(std.testing.io, directory);
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, directory) catch {};

    const server = Server.init(std.testing.io, directory, "Test");
    const png_bytes = "\x89PNG\r\n\x1a\nfake-png-payload";
    try server.publishScreenshot("inbox-canvas", png_bytes);

    var buffer: [64]u8 = undefined;
    var path_buffer: [256]u8 = undefined;
    const bytes = try readPath(std.testing.io, server.path("screenshot-inbox-canvas.png", &path_buffer), &buffer);
    try std.testing.expectEqualStrings(png_bytes, bytes);

    // No temporary file is left behind.
    var temp_buffer: [64]u8 = undefined;
    try std.testing.expectError(
        error.FileNotFound,
        readPath(std.testing.io, server.path("screenshot-inbox-canvas.png.tmp", &path_buffer), &temp_buffer),
    );

    // Republish overwrites the previous artifact.
    try server.publishScreenshot("inbox-canvas", "\x89PNG\r\n\x1a\nsecond");
    const second = try readPath(std.testing.io, server.path("screenshot-inbox-canvas.png", &path_buffer), &buffer);
    try std.testing.expectEqualStrings("\x89PNG\r\n\x1a\nsecond", second);
}

test "server consumes automation command files" {
    const directory = ".zig-cache/test-webview-automation-command";
    try resetTestDirectory(std.testing.io, directory);
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, directory) catch {};

    const server = Server.init(std.testing.io, directory, "Test");
    var path_buffer: [256]u8 = undefined;
    const command_path = server.path("command.txt", &path_buffer);

    try writePath(std.testing.io, command_path, "native-command app.refresh refresh-button\n");

    var command_buffer: [256]u8 = undefined;
    const native_command = (try server.takeCommand(&command_buffer)).?;
    try std.testing.expectEqual(protocol.Action.native_command, native_command.action);
    try std.testing.expectEqualStrings("app.refresh refresh-button", native_command.value);

    var done_buffer: [16]u8 = undefined;
    const done = try readPath(std.testing.io, command_path, &done_buffer);
    try std.testing.expectEqualStrings("done\n", done);
    try std.testing.expect(try server.takeCommand(&command_buffer) == null);

    try writePath(std.testing.io, command_path, "focus-next\n");
    const focus_next = (try server.takeCommand(&command_buffer)).?;
    try std.testing.expectEqual(protocol.Action.focus_next_view, focus_next.action);
    try std.testing.expectEqualStrings("", focus_next.value);

    try writePath(std.testing.io, command_path, "widget-action canvas 2 press\n");
    const widget_action = (try server.takeCommand(&command_buffer)).?;
    try std.testing.expectEqual(protocol.Action.widget_action, widget_action.action);
    try std.testing.expectEqualStrings("canvas 2 press", widget_action.value);

    try writePath(std.testing.io, command_path, "widget-click canvas 2\n");
    const widget_click = (try server.takeCommand(&command_buffer)).?;
    try std.testing.expectEqual(protocol.Action.widget_click, widget_click.action);
    try std.testing.expectEqualStrings("canvas 2", widget_click.value);

    try writePath(std.testing.io, command_path, "widget-drag canvas 2 0.25 0.82\n");
    const widget_drag = (try server.takeCommand(&command_buffer)).?;
    try std.testing.expectEqual(protocol.Action.widget_drag, widget_drag.action);
    try std.testing.expectEqualStrings("canvas 2 0.25 0.82", widget_drag.value);

    try writePath(std.testing.io, command_path, "widget-key canvas tab\n");
    const widget_key = (try server.takeCommand(&command_buffer)).?;
    try std.testing.expectEqual(protocol.Action.widget_key, widget_key.action);
    try std.testing.expectEqualStrings("canvas tab", widget_key.value);

    try writePath(std.testing.io, command_path, "tray-action 11\n");
    const tray_action = (try server.takeCommand(&command_buffer)).?;
    try std.testing.expectEqual(protocol.Action.tray_action, tray_action.action);
    try std.testing.expectEqualStrings("11", tray_action.value);
}

test "server acks undispatchable command lines instead of stranding the slot" {
    const directory = ".zig-cache/test-webview-automation-bad-command";
    try resetTestDirectory(std.testing.io, directory);
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, directory) catch {};

    const server = Server.init(std.testing.io, directory, "Test");
    var path_buffer: [256]u8 = undefined;
    const command_path = server.path("command.txt", &path_buffer);
    var command_buffer: [256]u8 = undefined;
    var done_buffer: [16]u8 = undefined;

    // A malformed line is consumed with a loud error, never left behind
    // to block the single-entry slot (and to wake the loop forever).
    try writePath(std.testing.io, command_path, "no-such-verb whatever\n");
    try std.testing.expectError(error.InvalidCommand, server.takeCommand(&command_buffer));
    try std.testing.expectEqualStrings("done\n", try readPath(std.testing.io, command_path, &done_buffer));
    try std.testing.expect(try server.takeCommand(&command_buffer) == null);

    // Same for a line larger than the caller's buffer.
    const oversized = "widget-key canvas " ++ "x" ** 256 ++ "\n";
    try writePath(std.testing.io, command_path, oversized);
    try std.testing.expectError(error.CommandTooLarge, server.takeCommand(&command_buffer));
    try std.testing.expectEqualStrings("done\n", try readPath(std.testing.io, command_path, &done_buffer));
}

test "server reports pending commands without consuming them" {
    const directory = ".zig-cache/test-webview-automation-pending";
    try resetTestDirectory(std.testing.io, directory);
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, directory) catch {};

    const server = Server.init(std.testing.io, directory, "Test");
    var path_buffer: [256]u8 = undefined;
    const command_path = server.path("command.txt", &path_buffer);

    // Missing file, empty slot, and the `done` ack all read as idle.
    try std.testing.expect(!server.hasPendingCommand());
    try writePath(std.testing.io, command_path, "\n");
    try std.testing.expect(!server.hasPendingCommand());
    try writePath(std.testing.io, command_path, "done\n");
    try std.testing.expect(!server.hasPendingCommand());

    // A queued line is pending — and STAYS pending across probes; only
    // takeCommand (the loop-thread drain) consumes it.
    try writePath(std.testing.io, command_path, "widget-click canvas 7\n");
    try std.testing.expect(server.hasPendingCommand());
    try std.testing.expect(server.hasPendingCommand());
    var command_buffer: [256]u8 = undefined;
    const command = (try server.takeCommand(&command_buffer)).?;
    try std.testing.expectEqual(protocol.Action.widget_click, command.action);
    try std.testing.expect(!server.hasPendingCommand());
}
