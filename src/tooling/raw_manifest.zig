const web_engine = @import("web_engine.zig");

pub const RawManifest = struct {
    id: []const u8,
    name: []const u8,
    display_name: ?[]const u8 = null,
    version: []const u8,
    icons: []const []const u8 = &.{},
    platforms: []const []const u8 = &.{},
    permissions: []const []const u8 = &.{},
    capabilities: []const []const u8 = &.{},
    bridge: RawBridge = .{},
    web_engine: []const u8 = @tagName(web_engine.default_engine),
    cef: RawCef = .{},
    frontend: ?RawFrontend = null,
    security: RawSecurity = .{},
    windows: []const RawWindow = &.{},
    shell: RawShell = .{},
    shortcuts: []const RawShortcut = &.{},
    file_associations: []const RawFileAssociation = &.{},
    url_schemes: []const RawUrlScheme = &.{},
};

pub const RawCef = struct {
    dir: []const u8 = web_engine.default_cef_dir,
    auto_install: bool = false,
};

pub const RawBridge = struct {
    commands: []const RawBridgeCommand = &.{},
};

pub const RawBridgeCommand = struct {
    name: []const u8,
    permissions: []const []const u8 = &.{},
    origins: []const []const u8 = &.{},
};

pub const RawFrontend = struct {
    dist: []const u8 = "dist",
    entry: []const u8 = "index.html",
    spa_fallback: bool = true,
    dev: ?RawFrontendDev = null,
};

pub const RawFrontendDev = struct {
    url: []const u8,
    command: []const []const u8 = &.{},
    ready_path: []const u8 = "/",
    timeout_ms: u32 = 30_000,
};

pub const RawSecurity = struct {
    navigation: RawNavigation = .{},
};

pub const RawNavigation = struct {
    allowed_origins: []const []const u8 = &.{},
    external_links: RawExternalLinks = .{},
};

pub const RawExternalLinks = struct {
    action: []const u8 = "deny",
    allowed_urls: []const []const u8 = &.{},
};

pub const RawWindow = struct {
    label: []const u8 = "main",
    title: ?[]const u8 = null,
    width: f32 = 720,
    height: f32 = 480,
    x: ?f32 = null,
    y: ?f32 = null,
    restore_state: bool = true,
};

pub const RawShell = struct {
    windows: []const RawShellWindow = &.{},
};

pub const RawShellWindow = struct {
    label: []const u8 = "main",
    title: ?[]const u8 = null,
    width: f32 = 720,
    height: f32 = 480,
    x: ?f32 = null,
    y: ?f32 = null,
    resizable: bool = true,
    restore_state: bool = true,
    restore_policy: []const u8 = "clamp_to_visible_screen",
    views: []const RawShellView = &.{},
};

pub const RawShellView = struct {
    label: []const u8,
    kind: []const u8,
    parent: ?[]const u8 = null,
    edge: ?[]const u8 = null,
    x: ?f32 = null,
    y: ?f32 = null,
    width: ?f32 = null,
    height: ?f32 = null,
    min_width: ?f32 = null,
    min_height: ?f32 = null,
    max_width: ?f32 = null,
    max_height: ?f32 = null,
    fill: bool = false,
    layer: i32 = 0,
    visible: bool = true,
    enabled: bool = true,
    role: ?[]const u8 = null,
    url: ?[]const u8 = null,
    text: ?[]const u8 = null,
    command: ?[]const u8 = null,
};

pub const RawShortcut = struct {
    id: []const u8,
    key: []const u8,
    modifiers: []const []const u8 = &.{},
};

pub const RawFileAssociation = struct {
    name: []const u8,
    role: []const u8 = "viewer",
    extensions: []const []const u8 = &.{},
    mime_types: []const []const u8 = &.{},
    icon: ?[]const u8 = null,
};

pub const RawUrlScheme = struct {
    scheme: []const u8,
    role: []const u8 = "viewer",
};
