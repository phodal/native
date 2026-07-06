//! soundboard theme: a custom "studio" token set layered over the built-in
//! light/dark themes — the register's warm (stone) neutrals by day, its
//! cool (zinc) neutrals after dark, an electric violet accent, and
//! slightly softer radii. High-contrast requests fall back to the
//! framework's high-contrast palettes (accessibility beats brand), and
//! reduce-motion zeroes the motion tokens through the theme options.

const native_sdk = @import("native_sdk");

const canvas = native_sdk.canvas;
const Color = canvas.Color;

pub fn tokens(scheme: native_sdk.ColorScheme, high_contrast: bool, reduce_motion: bool) canvas.DesignTokens {
    var out = canvas.DesignTokens.theme(.{
        .color_scheme = switch (scheme) {
            .light => .light,
            .dark => .dark,
        },
        .contrast = if (high_contrast) .high else .standard,
        .reduce_motion = reduce_motion,
    });
    if (!high_contrast) {
        out.colors = switch (scheme) {
            .light => light_colors,
            .dark => dark_colors,
        };
    }
    out.radius = .{ .sm = 6, .md = 9, .lg = 12, .xl = 16 };
    out.pixel_snap = .{ .geometry = true, .text = true, .scale = 1 };
    return out;
}

/// Warm paper on the register's stone (warm-neutral) scale — every
/// neutral is a scale anchor converted from its published oklch value —
/// with the electric violet identity carried by the accent alone
/// (oklch(0.491 0.27 292.581) = #7008e7).
pub const light_colors = canvas.ColorTokens{
    .background = Color.rgb8(250, 250, 249),
    .surface = Color.rgb8(255, 255, 255),
    .surface_subtle = Color.rgb8(245, 245, 244),
    .surface_pressed = Color.rgb8(231, 229, 228),
    .text = Color.rgb8(12, 10, 9),
    .text_muted = Color.rgb8(121, 113, 107),
    .border = Color.rgb8(231, 229, 228),
    .accent = Color.rgb8(112, 8, 231),
    .accent_text = Color.rgb8(245, 243, 255),
    .destructive = Color.rgb8(231, 0, 11),
    .destructive_text = Color.rgb8(250, 250, 250),
    .success = Color.rgb8(22, 163, 74),
    .success_text = Color.rgb8(250, 250, 250),
    .warning = Color.rgb8(217, 119, 6),
    .warning_text = Color.rgb8(250, 250, 250),
    .focus_ring = Color.rgb8(166, 160, 155),
    .shadow = Color.rgba8(0, 0, 0, 26),
    .disabled = Color.rgb8(245, 245, 244),
};

/// Club dark on the register's cool (zinc) scale: translucent-white
/// hairlines and pressed washes, with the violet lifted to the scale's
/// bright step (oklch(0.702 0.183 293.541) = #a684ff) and flipped to
/// near-black accent text for contrast.
pub const dark_colors = canvas.ColorTokens{
    .background = Color.rgb8(9, 9, 11),
    .surface = Color.rgb8(24, 24, 27),
    .surface_subtle = Color.rgb8(39, 39, 42),
    .surface_pressed = Color.rgba8(255, 255, 255, 38),
    .text = Color.rgb8(250, 250, 250),
    .text_muted = Color.rgb8(159, 159, 169),
    .border = Color.rgba8(255, 255, 255, 26),
    .accent = Color.rgb8(166, 132, 255),
    .accent_text = Color.rgb8(9, 9, 11),
    .destructive = Color.rgb8(255, 100, 103),
    .destructive_text = Color.rgb8(250, 250, 250),
    .success = Color.rgb8(34, 197, 94),
    .success_text = Color.rgb8(9, 9, 11),
    .warning = Color.rgb8(245, 158, 11),
    .warning_text = Color.rgb8(9, 9, 11),
    .info = Color.rgb8(167, 139, 250),
    .info_text = Color.rgb8(9, 9, 11),
    .focus_ring = Color.rgb8(113, 113, 123),
    .shadow = Color.rgba8(0, 0, 0, 150),
    .disabled = Color.rgb8(39, 39, 42),
};
