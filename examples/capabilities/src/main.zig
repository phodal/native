const std = @import("std");
const runner = @import("runner");
const zero_native = @import("zero-native");

pub const panic = std.debug.FullPanic(zero_native.debug.capturePanic);

const window_width: f32 = 900;
const window_height: f32 = 620;
const statusbar_height: f32 = 34;

const html =
    \\<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
    \\<meta http-equiv="Content-Security-Policy" content="default-src 'self';script-src 'self' 'unsafe-inline';style-src 'self' 'unsafe-inline'">
    \\<style>:root{color-scheme:light dark}*{box-sizing:border-box}body{margin:0;min-height:100vh;font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",Segoe UI,system-ui,sans-serif;background:#f8f9fb;color:#18181b}main{padding:34px 38px 48px;display:grid;gap:20px}h1{margin:0;font-size:30px;line-height:1.1;font-weight:650;letter-spacing:0}p{margin:0;max-width:680px;color:#636b76;line-height:1.55}.actions{display:grid;grid-template-columns:repeat(2,minmax(180px,1fr));gap:10px;max-width:620px}button{min-height:40px;border:1px solid #d8dde4;border-radius:7px;padding:9px 13px;font:inherit;font-weight:590;text-align:left;color:#18181b;background:white;cursor:pointer}.primary{color:white;background:#18181b;border-color:#18181b}pre{width:min(720px,100%);min-height:130px;margin:0;padding:14px 16px;overflow:auto;border:1px solid #dde2e8;border-radius:7px;background:white;color:#374151;font-size:13px;line-height:1.45}@media (prefers-color-scheme:dark){body{background:#101214;color:#f4f4f5}p{color:#a1a1aa}button{color:#f4f4f5;background:#171a20;border-color:#2b3038}.primary{color:#101214;background:#f4f4f5;border-color:#f4f4f5}pre{color:#d4d4d8;background:#171a20;border-color:#2b3038}}</style>
    \\<main><h1>Capabilities</h1><p>Trusted WebView code can call native OS services only after the app grants explicit permissions and command policies.</p><div class="actions"><button class="primary" id="notify" type="button">Send Notification</button><button id="clipboard" type="button">Clipboard Round Trip</button><button id="message" type="button">Show Message</button><button id="credentials" type="button">Credential Round Trip</button></div><pre id="output">Ready.</pre></main>
    \\<script>const out=document.querySelector("#output"),show=v=>out.textContent=JSON.stringify(v,null,2),fail=e=>out.textContent=`${e.code||"error"}: ${e.message}`,invoke=(c,p)=>window.zero.invoke(c,p);document.querySelector("#notify").onclick=async()=>{try{show(await invoke("zero-native.os.showNotification",{title:"Capabilities",subtitle:"zero-native",body:"Notification bridge succeeded."}))}catch(e){fail(e)}};document.querySelector("#clipboard").onclick=async()=>{try{await invoke("zero-native.clipboard.writeText",{text:"Copied from zero-native"});show({text:await invoke("zero-native.clipboard.readText",{})})}catch(e){fail(e)}};document.querySelector("#message").onclick=async()=>{try{show(await invoke("zero-native.dialog.showMessage",{style:"info",title:"Capabilities",message:"Native dialog bridge succeeded.",primaryButton:"OK"}))}catch(e){fail(e)}};document.querySelector("#credentials").onclick=async()=>{try{const key={service:"dev.zero-native.capabilities",account:"demo"};await invoke("zero-native.credentials.set",{...key,secret:"demo-token"});const token=await invoke("zero-native.credentials.get",key),deleted=await invoke("zero-native.credentials.delete",key);show({token,deleted})}catch(e){fail(e)}};window.addEventListener("zero:drop:files",e=>show(e.detail));</script>
;

const app_permissions = [_][]const u8{
    zero_native.security.permission_notifications,
    zero_native.security.permission_dialog,
    zero_native.security.permission_clipboard,
    zero_native.security.permission_credentials,
};
const bridge_origins = [_][]const u8{ "zero://inline", "zero://app" };
const notification_permission = [_][]const u8{zero_native.security.permission_notifications};
const dialog_permission = [_][]const u8{zero_native.security.permission_dialog};
const clipboard_permission = [_][]const u8{zero_native.security.permission_clipboard};
const credential_permission = [_][]const u8{zero_native.security.permission_credentials};
const builtin_policies = [_]zero_native.BridgeCommandPolicy{
    .{ .name = "zero-native.os.showNotification", .permissions = &notification_permission, .origins = &bridge_origins },
    .{ .name = "zero-native.dialog.showMessage", .permissions = &dialog_permission, .origins = &bridge_origins },
    .{ .name = "zero-native.clipboard.readText", .permissions = &clipboard_permission, .origins = &bridge_origins },
    .{ .name = "zero-native.clipboard.writeText", .permissions = &clipboard_permission, .origins = &bridge_origins },
    .{ .name = "zero-native.clipboard.read", .permissions = &clipboard_permission, .origins = &bridge_origins },
    .{ .name = "zero-native.clipboard.write", .permissions = &clipboard_permission, .origins = &bridge_origins },
    .{ .name = "zero-native.credentials.set", .permissions = &credential_permission, .origins = &bridge_origins },
    .{ .name = "zero-native.credentials.get", .permissions = &credential_permission, .origins = &bridge_origins },
    .{ .name = "zero-native.credentials.delete", .permissions = &credential_permission, .origins = &bridge_origins },
};
const shell_views = [_]zero_native.ShellView{
    .{ .label = "main", .kind = .webview, .url = "zero://inline", .fill = true },
    .{ .label = "statusbar", .kind = .statusbar, .edge = .bottom, .height = statusbar_height, .layer = 20, .role = "Status" },
    .{ .label = "status-label", .kind = .label, .parent = "statusbar", .x = 14, .y = 8, .width = 640, .height = 18, .layer = 21, .text = "Ready." },
};
const shell_windows = [_]zero_native.ShellWindow{.{
    .label = "main",
    .title = "zero-native Capabilities",
    .width = window_width,
    .height = window_height,
    .views = &shell_views,
}};
const shell_scene: zero_native.ShellConfig = .{ .windows = &shell_windows };

const CapabilitiesApp = struct {
    drop_count: u32 = 0,
    last_drop_paths: []const u8 = "",

    fn app(self: *@This()) zero_native.App {
        return .{
            .context = self,
            .name = "capabilities",
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
            .files_dropped => |drop| {
                self.drop_count += 1;
                self.last_drop_paths = drop.paths;
                var status_buffer: [160]u8 = undefined;
                const status = try std.fmt.bufPrint(&status_buffer, "Received file drop {d}: {s}", .{ self.drop_count, drop.paths });
                _ = try runtime.updateView(drop.window_id, "status-label", .{ .text = status });
            },
            .command, .shortcut, .lifecycle => {},
        }
    }
};

pub fn main(init: std.process.Init) !void {
    var app = CapabilitiesApp{};
    try runner.runWithOptions(app.app(), .{
        .app_name = "capabilities",
        .window_title = "zero-native Capabilities",
        .bundle_id = "dev.zero_native.capabilities",
        .icon_path = "assets/icon.icns",
        .default_frame = zero_native.geometry.RectF.init(0, 0, window_width, window_height),
        .builtin_bridge = .{ .enabled = true, .commands = &builtin_policies },
        .security = .{
            .permissions = &app_permissions,
            .navigation = .{ .allowed_origins = &bridge_origins },
        },
    }, init);
}

test "capabilities bridge gates native services and dispatches file drops" {
    var harness: zero_native.TestHarness() = undefined;
    harness.init(.{ .size = zero_native.geometry.SizeF.init(window_width, window_height) });
    harness.runtime.options.builtin_bridge = .{ .enabled = true, .commands = &builtin_policies };
    harness.runtime.options.security = .{
        .permissions = &app_permissions,
        .navigation = .{ .allowed_origins = &bridge_origins },
    };

    var app_state = CapabilitiesApp{};
    const app = app_state.app();
    try harness.start(app);

    try dispatchBridge(&harness, app, "{\"id\":\"notify\",\"command\":\"zero-native.os.showNotification\",\"payload\":{\"title\":\"Capabilities\",\"subtitle\":\"zero-native\",\"body\":\"Done\"}}");
    try std.testing.expect(std.mem.indexOf(u8, harness.null_platform.lastBridgeResponse(), "\"ok\":true") != null);
    try std.testing.expectEqual(@as(usize, 1), harness.null_platform.notificationCount());
    try std.testing.expectEqualStrings("Capabilities", harness.null_platform.lastNotificationTitle());

    try dispatchBridge(&harness, app, "{\"id\":\"write\",\"command\":\"zero-native.clipboard.writeText\",\"payload\":{\"text\":\"plain text\"}}");
    try std.testing.expect(std.mem.indexOf(u8, harness.null_platform.lastBridgeResponse(), "\"ok\":true") != null);
    try std.testing.expectEqualStrings("plain text", harness.null_platform.lastClipboardData());
    try dispatchBridge(&harness, app, "{\"id\":\"read\",\"command\":\"zero-native.clipboard.readText\",\"payload\":{}}");
    try std.testing.expect(std.mem.indexOf(u8, harness.null_platform.lastBridgeResponse(), "\"result\":\"plain text\"") != null);

    try dispatchBridge(&harness, app, "{\"id\":\"set\",\"command\":\"zero-native.credentials.set\",\"payload\":{\"service\":\"dev.zero-native.capabilities\",\"account\":\"demo\",\"secret\":\"demo-token\"}}");
    try std.testing.expectEqual(@as(usize, 1), harness.null_platform.credentialSetCount());
    try dispatchBridge(&harness, app, "{\"id\":\"get\",\"command\":\"zero-native.credentials.get\",\"payload\":{\"service\":\"dev.zero-native.capabilities\",\"account\":\"demo\"}}");
    try std.testing.expect(std.mem.indexOf(u8, harness.null_platform.lastBridgeResponse(), "\"result\":\"demo-token\"") != null);
    try dispatchBridge(&harness, app, "{\"id\":\"delete\",\"command\":\"zero-native.credentials.delete\",\"payload\":{\"service\":\"dev.zero-native.capabilities\",\"account\":\"demo\"}}");
    try std.testing.expect(std.mem.indexOf(u8, harness.null_platform.lastBridgeResponse(), "\"result\":true") != null);

    try harness.runtime.dispatchPlatformEvent(app, .{ .files_dropped = .{
        .window_id = 1,
        .paths = "/tmp/one.txt\n/tmp/two.txt",
    } });
    try std.testing.expectEqual(@as(u32, 1), app_state.drop_count);
    try std.testing.expectEqualStrings("/tmp/one.txt\n/tmp/two.txt", app_state.last_drop_paths);
    try std.testing.expectEqualStrings("drop:files", harness.null_platform.lastWindowEventName());
}

fn dispatchBridge(harness: *zero_native.TestHarness(), app: zero_native.App, bytes: []const u8) !void {
    try harness.runtime.dispatchPlatformEvent(app, .{ .bridge_message = .{
        .bytes = bytes,
        .origin = "zero://inline",
        .window_id = 1,
        .webview_label = "main",
    } });
}
