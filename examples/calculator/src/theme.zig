//! calculator theme: near-monochrome graphite with one strong accent —
//! the classic calculator orange — reserved for the operator column and
//! equals key. Digit keys are quiet surfaces, function keys one step
//! darker, and the display sits directly on the window background so the
//! numbers are the loudest thing on screen.
//!
//! High-contrast requests fall back to the framework's high-contrast
//! palettes (accessibility beats brand) and reduce-motion zeroes the
//! motion tokens through the theme options. Keypad glyphs render at 18px
//! through `typography.button_size`; the active operator inverts to a
//! deeper orange through `controls.button_primary.active_background`.

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
        // The active (pending) operator key inverts to a deeper orange so
        // the selected state reads even against the accent fill.
        out.controls.button_primary.active_background = switch (scheme) {
            .light => Color.rgb8(154, 52, 18),
            .dark => Color.rgb8(255, 190, 92),
        };
    }
    // Calculator keys carry 18px glyphs; the sm theme button derives 17.
    out.typography.button_size = 18;
    out.radius = .{ .sm = 7, .md = 10, .lg = 14, .xl = 18 };
    out.pixel_snap = .{ .geometry = true, .text = true, .scale = 1 };
    return out;
}

/// Warm paper neutrals; deep orange tuned for white key glyphs.
pub const light_colors = canvas.ColorTokens{
    .background = Color.rgb8(245, 244, 241),
    .surface = Color.rgb8(255, 255, 255),
    .surface_subtle = Color.rgb8(233, 232, 227),
    .surface_pressed = Color.rgb8(219, 217, 211),
    .text = Color.rgb8(28, 27, 25),
    .text_muted = Color.rgb8(138, 134, 126),
    .border = Color.rgb8(226, 224, 218),
    .accent = Color.rgb8(234, 88, 12),
    .accent_text = Color.rgb8(255, 251, 247),
    .destructive = Color.rgb8(206, 44, 49),
    .destructive_text = Color.rgb8(255, 251, 251),
    .success = Color.rgb8(22, 137, 80),
    .success_text = Color.rgb8(247, 253, 250),
    .warning = Color.rgb8(184, 119, 8),
    .warning_text = Color.rgb8(255, 252, 245),
    .focus_ring = Color.rgb8(234, 88, 12),
    .shadow = Color.rgba8(40, 34, 24, 26),
    .disabled = Color.rgb8(236, 234, 229),
};

/// True graphite; the accent brightens to the iOS-calculator orange and
/// flips to near-black glyphs for contrast.
pub const dark_colors = canvas.ColorTokens{
    .background = Color.rgb8(16, 16, 17),
    .surface = Color.rgb8(30, 30, 32),
    .surface_subtle = Color.rgb8(44, 44, 47),
    .surface_pressed = Color.rgb8(58, 58, 62),
    .text = Color.rgb8(244, 244, 245),
    .text_muted = Color.rgb8(150, 150, 156),
    .border = Color.rgb8(44, 44, 47),
    .accent = Color.rgb8(255, 159, 10),
    .accent_text = Color.rgb8(38, 23, 3),
    .destructive = Color.rgb8(244, 106, 106),
    .destructive_text = Color.rgb8(31, 14, 14),
    .success = Color.rgb8(94, 210, 141),
    .success_text = Color.rgb8(10, 28, 18),
    .warning = Color.rgb8(240, 177, 62),
    .warning_text = Color.rgb8(33, 23, 5),
    .focus_ring = Color.rgb8(255, 178, 66),
    .shadow = Color.rgba8(0, 0, 0, 150),
    .disabled = Color.rgb8(40, 40, 43),
};
