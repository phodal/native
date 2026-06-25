const std = @import("std");

pub const permission_window = "window";
pub const permission_command = "command";
pub const permission_view = "view";
pub const permission_dialog = "dialog";
pub const permission_filesystem = "filesystem";
pub const permission_clipboard = "clipboard";
pub const permission_network = "network";
pub const permission_notifications = "notifications";
pub const permission_credentials = "credentials";

pub const ExternalLinkAction = enum(c_int) {
    deny = 0,
    open_system_browser = 1,
};

pub const ExternalLinkPolicy = struct {
    action: ExternalLinkAction = .deny,
    allowed_urls: []const []const u8 = &.{},
};

pub const NavigationPolicy = struct {
    allowed_origins: []const []const u8 = &.{ "zero://app", "zero://inline" },
    external_links: ExternalLinkPolicy = .{},
};

pub const Policy = struct {
    permissions: []const []const u8 = &.{},
    navigation: NavigationPolicy = .{},
};

pub fn hasPermission(grants: []const []const u8, permission: []const u8) bool {
    for (grants) |grant| {
        if (std.mem.eql(u8, grant, permission)) return true;
    }
    return false;
}

pub fn hasPermissions(grants: []const []const u8, required: []const []const u8) bool {
    for (required) |permission| {
        if (!hasPermission(grants, permission)) return false;
    }
    return true;
}

pub fn allowsOrigin(allowed_origins: []const []const u8, origin: []const u8) bool {
    for (allowed_origins) |allowed| {
        if (std.mem.eql(u8, allowed, "*")) return true;
        if (std.mem.eql(u8, allowed, origin)) return true;
    }
    return false;
}

pub fn allowsExternalUrl(policy: ExternalLinkPolicy, url: []const u8) bool {
    if (policy.action != .open_system_browser) return false;
    for (policy.allowed_urls) |allowed| {
        if (std.mem.eql(u8, allowed, "*")) return true;
        if (std.mem.eql(u8, allowed, url)) return true;
        if (std.mem.endsWith(u8, allowed, "*")) {
            const prefix = allowed[0 .. allowed.len - 1];
            if (std.mem.startsWith(u8, url, prefix)) return true;
        }
    }
    return false;
}

test "permission checks require every requested grant" {
    try std.testing.expect(hasPermissions(&.{ permission_window, permission_filesystem }, &.{permission_window}));
    try std.testing.expect(!hasPermissions(&.{permission_window}, &.{ permission_window, permission_filesystem }));
}

test "origin checks support exact origins and wildcard" {
    try std.testing.expect(allowsOrigin(&.{ "zero://app", "zero://inline" }, "zero://inline"));
    try std.testing.expect(allowsOrigin(&.{"*"}, "https://example.invalid"));
    try std.testing.expect(!allowsOrigin(&.{"zero://app"}, "https://example.invalid"));
}

test "external URL checks require open-browser action and allowed URL pattern" {
    try std.testing.expect(!allowsExternalUrl(.{
        .action = .deny,
        .allowed_urls = &.{"https://example.com/*"},
    }, "https://example.com/docs"));
    try std.testing.expect(allowsExternalUrl(.{
        .action = .open_system_browser,
        .allowed_urls = &.{"https://example.com/*"},
    }, "https://example.com/docs"));
    try std.testing.expect(allowsExternalUrl(.{
        .action = .open_system_browser,
        .allowed_urls = &.{"https://example.com/docs"},
    }, "https://example.com/docs"));
    try std.testing.expect(!allowsExternalUrl(.{
        .action = .open_system_browser,
        .allowed_urls = &.{"https://example.com/*"},
    }, "https://other.example/docs"));
}
