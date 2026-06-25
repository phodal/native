const std = @import("std");
const runner = @import("runner");
const zero_native = @import("zero-native");

pub const panic = std.debug.FullPanic(zero_native.debug.capturePanic);

const window_width: f32 = 860;
const window_height: f32 = 560;
const toolbar_height: f32 = 48;
const statusbar_height: f32 = 34;
const command_id = "app.sync";

const html =
    \\<!doctype html>
    \\<html>
    \\<head>
    \\  <meta charset="utf-8">
    \\  <meta name="viewport" content="width=device-width, initial-scale=1">
    \\  <meta http-equiv="Content-Security-Policy" content="default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:;">
    \\  <style>
    \\    :root { color-scheme: light dark; }
    \\    * { box-sizing: border-box; }
    \\    body {
    \\      margin: 0;
    \\      min-height: 100vh;
    \\      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", Segoe UI, system-ui, sans-serif;
    \\      background: #f7f8fa;
    \\      color: #171717;
    \\    }
    \\    main {
    \\      width: min(680px, calc(100vw - 48px));
    \\      padding: 42px 0;
    \\      margin: 0 auto;
    \\      display: grid;
    \\      gap: 18px;
    \\    }
    \\    h1 { margin: 0; font-size: 30px; line-height: 1.1; font-weight: 650; letter-spacing: 0; }
    \\    p { margin: 0; color: #606975; line-height: 1.55; }
    \\    .panel {
    \\      display: grid;
    \\      grid-template-columns: 1fr auto;
    \\      gap: 18px;
    \\      align-items: center;
    \\      padding: 18px 0;
    \\      border-top: 1px solid #e3e6ea;
    \\      border-bottom: 1px solid #e3e6ea;
    \\    }
    \\    button {
    \\      min-width: 116px;
    \\      border: 1px solid #171717;
    \\      border-radius: 7px;
    \\      padding: 9px 13px;
    \\      font: inherit;
    \\      font-weight: 590;
    \\      color: white;
    \\      background: #171717;
    \\      cursor: pointer;
    \\    }
    \\    pre {
    \\      min-height: 92px;
    \\      margin: 0;
    \\      padding: 14px 16px;
    \\      overflow: auto;
    \\      border: 1px solid #dde1e6;
    \\      border-radius: 7px;
    \\      background: white;
    \\      color: #374151;
    \\      font-size: 13px;
    \\      line-height: 1.45;
    \\    }
    \\    @media (prefers-color-scheme: dark) {
    \\      body { background: #111316; color: #f4f4f5; }
    \\      p { color: #a1a1aa; }
    \\      .panel { border-color: #2b2f37; }
    \\      button { color: #111316; background: #f4f4f5; border-color: #f4f4f5; }
    \\      pre { color: #d4d4d8; background: #171a20; border-color: #2b2f37; }
    \\    }
    \\  </style>
    \\</head>
    \\<body>
    \\  <main>
    \\    <h1>One command, four entry points</h1>
    \\    <p>The toolbar button, View menu, primary shortcut, and WebView button all dispatch app.sync into the same Zig command handler.</p>
    \\    <div class="panel">
    \\      <p>Dispatch from the WebView through the built-in command bridge.</p>
    \\      <button id="sync" type="button">Sync</button>
    \\    </div>
    \\    <pre id="output">Ready.</pre>
    \\  </main>
    \\  <script>
    \\    const output = document.querySelector("#output");
    \\    const show = (value) => { output.textContent = JSON.stringify(value, null, 2); };
    \\    const fail = (error) => { output.textContent = `${error.code || "error"}: ${error.message}`; };
    \\    const invokeCommand = (name) => {
    \\      if (window.zero && window.zero.commands && window.zero.commands.invoke) {
    \\        return window.zero.commands.invoke(name);
    \\      }
    \\      return window.zero.invoke("zero-native.command.invoke", { name });
    \\    };
    \\    document.querySelector("#sync").addEventListener("click", async () => {
    \\      try { show(await invokeCommand("app.sync")); } catch (error) { fail(error); }
    \\    });
    \\  </script>
    \\</body>
    \\</html>
;

const app_permissions = [_][]const u8{zero_native.security.permission_command};
const bridge_origins = [_][]const u8{ "zero://inline", "zero://app" };
const command_permission = [_][]const u8{zero_native.security.permission_command};
const builtin_policies = [_]zero_native.BridgeCommandPolicy{
    .{ .name = "zero-native.command.invoke", .permissions = &command_permission, .origins = &bridge_origins },
};
const shortcuts = [_]zero_native.Shortcut{
    .{ .id = command_id, .key = "s", .modifiers = .{ .primary = true } },
};
const command_menu_items = [_]zero_native.MenuItem{
    .{ .label = "Sync", .command = command_id, .key = "s", .modifiers = .{ .primary = true } },
};
const menus = [_]zero_native.Menu{
    .{ .title = "View", .items = &command_menu_items },
};
const shell_views = [_]zero_native.ShellView{
    .{ .label = "toolbar", .kind = .toolbar, .edge = .top, .height = toolbar_height, .layer = 20, .role = "Toolbar" },
    .{ .label = "sync-button", .kind = .button, .parent = "toolbar", .x = 12, .y = 9, .width = 92, .height = 30, .layer = 21, .text = "Sync", .command = command_id },
    .{ .label = "main", .kind = .webview, .url = "zero://inline", .fill = true },
    .{ .label = "statusbar", .kind = .statusbar, .edge = .bottom, .height = statusbar_height, .layer = 20, .role = "Status" },
    .{ .label = "status-label", .kind = .label, .parent = "statusbar", .x = 14, .y = 8, .width = 520, .height = 18, .layer = 21, .text = "Ready. Use the toolbar, menu, shortcut, or WebView button." },
};
const shell_windows = [_]zero_native.ShellWindow{.{
    .label = "main",
    .title = "zero-native Command App",
    .width = window_width,
    .height = window_height,
    .views = &shell_views,
}};
const shell_scene: zero_native.ShellConfig = .{ .windows = &shell_windows };

const CommandApp = struct {
    command_count: u32 = 0,
    sources: [8]zero_native.CommandSource = [_]zero_native.CommandSource{.runtime} ** 8,
    last_command_name: []const u8 = "",

    fn app(self: *@This()) zero_native.App {
        return .{
            .context = self,
            .name = "command-app",
            .source = zero_native.WebViewSource.html(html),
            .scene_fn = scene,
            .event_fn = event,
        };
    }

    fn scene(context: *anyopaque) anyerror!zero_native.ShellConfig {
        _ = context;
        return shell_scene;
    }

    fn event(context: *anyopaque, runtime: *zero_native.Runtime, event_value: zero_native.Event) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(context));
        switch (event_value) {
            .command => |command| {
                if (std.mem.eql(u8, command.name, command_id)) {
                    try self.handleCommand(runtime, command);
                }
            },
            .shortcut, .files_dropped, .lifecycle => {},
        }
    }

    fn handleCommand(self: *@This(), runtime: *zero_native.Runtime, command: zero_native.CommandEvent) anyerror!void {
        if (self.command_count < self.sources.len) {
            self.sources[self.command_count] = command.source;
        }
        self.command_count += 1;
        self.last_command_name = command.name;

        var status_buffer: [128]u8 = undefined;
        const status = try std.fmt.bufPrint(
            &status_buffer,
            "Handled {s} from {s}. Count {d}.",
            .{ command.name, @tagName(command.source), self.command_count },
        );
        _ = try runtime.updateView(command.window_id, "status-label", .{ .text = status });
    }
};

pub fn main(init: std.process.Init) !void {
    var app = CommandApp{};
    try runner.runWithOptions(app.app(), .{
        .app_name = "command-app",
        .window_title = "zero-native Command App",
        .bundle_id = "dev.zero_native.command_app",
        .icon_path = "assets/icon.icns",
        .default_frame = zero_native.geometry.RectF.init(0, 0, window_width, window_height),
        .builtin_bridge = .{ .enabled = true, .commands = &builtin_policies },
        .js_window_api = true,
        .security = .{
            .permissions = &app_permissions,
            .navigation = .{ .allowed_origins = &bridge_origins },
        },
        .menus = &menus,
        .shortcuts = &shortcuts,
    }, init);
}

test "command app routes toolbar menu shortcut and bridge commands" {
    var harness: zero_native.TestHarness() = undefined;
    harness.init(.{ .size = zero_native.geometry.SizeF.init(window_width, window_height) });
    harness.runtime.options.builtin_bridge = .{ .enabled = true, .commands = &builtin_policies };
    harness.runtime.options.js_window_api = true;
    harness.runtime.options.security = .{
        .permissions = &app_permissions,
        .navigation = .{ .allowed_origins = &bridge_origins },
    };

    var app = CommandApp{};
    try harness.start(app.app());

    try harness.runtime.dispatchPlatformEvent(app.app(), .{ .native_command = .{
        .name = command_id,
        .window_id = 1,
        .view_label = "sync-button",
    } });
    try harness.runtime.dispatchPlatformEvent(app.app(), .{ .menu_command = .{
        .name = command_id,
        .window_id = 1,
    } });
    try harness.runtime.dispatchPlatformEvent(app.app(), .{ .shortcut = .{
        .id = command_id,
        .key = "s",
        .window_id = 1,
        .modifiers = .{ .primary = true },
    } });
    try harness.runtime.dispatchPlatformEvent(app.app(), .{ .bridge_message = .{
        .bytes = "{\"id\":\"1\",\"command\":\"zero-native.command.invoke\",\"payload\":{\"name\":\"app.sync\"}}",
        .origin = "zero://inline",
        .window_id = 1,
        .webview_label = "main",
    } });

    try std.testing.expectEqual(@as(u32, 4), app.command_count);
    try std.testing.expectEqualStrings(command_id, app.last_command_name);
    try std.testing.expectEqual(zero_native.CommandSource.toolbar, app.sources[0]);
    try std.testing.expectEqual(zero_native.CommandSource.menu, app.sources[1]);
    try std.testing.expectEqual(zero_native.CommandSource.shortcut, app.sources[2]);
    try std.testing.expectEqual(zero_native.CommandSource.bridge, app.sources[3]);
    try std.testing.expect(std.mem.indexOf(u8, harness.null_platform.lastBridgeResponse(), "\"ok\":true") != null);
}
