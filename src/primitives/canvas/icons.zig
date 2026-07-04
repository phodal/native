//! The curated built-in icon set: Lucide-style stroke icons (24x24
//! viewBox, stroke-width 2, round caps and joins, `currentColor`)
//! authored for this framework and parsed at COMPTIME from the SVG
//! sources in `icons/` — the binary carries only lowered path elements,
//! and an invalid icon source is a compile error.
//!
//! Names are the closed vocabulary behind `<icon name="..."/>` in markup
//! and `Ui.icon` in Zig views; both engines validate against
//! `known_icon_names` (markup at comptime in the compiled engine, at
//! build/parse time in the validator and interpreter).
//!
//! Apps can parse their own `assets/icons/*.svg` (any Lucide/Feather/
//! Tabler-dialect file) with `svg_icon.parseComptime(@embedFile(...))`
//! and draw them through the same widget path; the built-in set is just
//! the names the markup grammar knows.

const svg_icon = @import("svg_icon.zig");

pub const Icon = svg_icon.Icon;

pub const Entry = struct {
    name: []const u8,
    icon: *const Icon,
};

fn builtin(comptime name: []const u8) Icon {
    return svg_icon.parseComptime(@embedFile("icons/" ++ name ++ ".svg"));
}

const alert = builtin("alert");
const arrow_right = builtin("arrow-right");
const check = builtin("check");
const chevron_down = builtin("chevron-down");
const chevron_left = builtin("chevron-left");
const chevron_right = builtin("chevron-right");
const chevron_up = builtin("chevron-up");
const copy = builtin("copy");
const download = builtin("download");
const edit = builtin("edit");
const external_link = builtin("external-link");
const info = builtin("info");
const menu = builtin("menu");
const pause = builtin("pause");
const play = builtin("play");
const plus = builtin("plus");
const search = builtin("search");
const settings = builtin("settings");
const trash = builtin("trash");
const x = builtin("x");

/// Sorted by name; kept in lockstep with `known_icon_names` below (a
/// unit test enforces it).
pub const entries = [_]Entry{
    .{ .name = "alert", .icon = &alert },
    .{ .name = "arrow-right", .icon = &arrow_right },
    .{ .name = "check", .icon = &check },
    .{ .name = "chevron-down", .icon = &chevron_down },
    .{ .name = "chevron-left", .icon = &chevron_left },
    .{ .name = "chevron-right", .icon = &chevron_right },
    .{ .name = "chevron-up", .icon = &chevron_up },
    .{ .name = "copy", .icon = &copy },
    .{ .name = "download", .icon = &download },
    .{ .name = "edit", .icon = &edit },
    .{ .name = "external-link", .icon = &external_link },
    .{ .name = "info", .icon = &info },
    .{ .name = "menu", .icon = &menu },
    .{ .name = "pause", .icon = &pause },
    .{ .name = "play", .icon = &play },
    .{ .name = "plus", .icon = &plus },
    .{ .name = "search", .icon = &search },
    .{ .name = "settings", .icon = &settings },
    .{ .name = "trash", .icon = &trash },
    .{ .name = "x", .icon = &x },
};

/// The markup-facing name list (comptime-validated attribute values).
pub const known_icon_names = blk: {
    var names: [entries.len][]const u8 = undefined;
    for (entries, 0..) |entry, index| names[index] = entry.name;
    const const_names = names;
    break :blk &const_names;
};

/// Resolve a built-in icon by name; null lets callers fall back (the
/// icon widget keeps its historical text-glyph rendering for unknown
/// names, so existing apps that put literal glyphs in `icon.text` are
/// untouched).
pub fn find(name: []const u8) ?*const Icon {
    for (&entries) |*entry| {
        if (stringsEqual(entry.name, name)) return entry.icon;
    }
    return null;
}

fn stringsEqual(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |left, right| {
        if (left != right) return false;
    }
    return true;
}
