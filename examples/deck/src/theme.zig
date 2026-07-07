//! deck theme: the whole skin, expressed as design tokens — no widget
//! code knows it is dressed as hardware.
//!
//! THIS SKIN IS CUSTOM BY DESIGN. It deliberately does not follow the
//! framework's theme packs or the OS color scheme: the deck is a piece
//! of vintage rack hardware, and hardware has exactly one finish — warm
//! cream/putty enamel chassis panels around dark smoked-glass display
//! bays that print in phosphor green. Every value below is this
//! product's identity, not a restatement of the house register; apps
//! that want the house look should start from `DesignTokens.theme` and
//! stop there.
//!
//! The palette is split across two physical materials, and the token
//! table allocates its slots by MATERIAL rather than by the house
//! semantics:
//!   - enamel (the chassis): `surface` is the enamel, `text` is the
//!     silkscreened ink, `text_muted` the lighter engraving gray,
//!     `border` the putty hairline between plates.
//!   - glass (the display bays): `background` is the smoked glass —
//!     every bay fills with it — `accent` is the LIVE phosphor,
//!     `success` the pale phosphor a readout prints in at rest, and
//!     `info` the dim phosphor of engraved-on-glass captions (this app
//!     has no informational-violet surface, so the slot is spent on the
//!     third phosphor register; a teaching trade, stated here).
//! Signal amber (`warning`) is reserved for the queue and the failure
//! stamps — the one non-green hue on the glass.
//!
//! Accessibility still beats brand: a high-contrast request abandons the
//! skin for the framework's high-contrast light palette and stock
//! control chrome, and reduce-motion zeroes the motion tokens.

const native_sdk = @import("native_sdk");

const canvas = native_sdk.canvas;
const Color = canvas.Color;

/// Paragraph base size (the typography token below): public because the
/// views derive their pitch-snapped mono scales from it.
pub const body_size: f32 = 12;

pub fn tokens(high_contrast: bool, reduce_motion: bool) canvas.DesignTokens {
    var out = canvas.DesignTokens.theme(.{
        // One finish: the OS scheme never reaches this call. The light
        // base keeps the framework's light-scheme control washes under
        // the cream enamel overrides below.
        .color_scheme = .light,
        .contrast = if (high_contrast) .high else .standard,
        .density = .compact,
        .reduce_motion = reduce_motion,
    });
    out.pixel_snap = .{ .geometry = true, .text = true, .scale = 1 };
    if (high_contrast) return out;

    out.colors = chassis_colors;
    // Softly beveled hardware: chunkier than machined chamfers, still
    // nothing close to a pill.
    out.radius = .{ .sm = 2, .md = 3, .lg = 4, .xl = 5 };
    // Dense faceplate type; readouts go mono through paragraph spans.
    out.typography.body_size = body_size;
    out.typography.label_size = 11;
    out.typography.title_size = 15;
    out.typography.button_size = 12;
    // The long-travel fader: a slim track with a squared cap, stated as
    // metric tokens so both engines cut the same thumb.
    out.metrics.slider_track_height = 4;
    out.metrics.slider_thumb_width = 10;
    out.metrics.slider_thumb_height = 16;

    // ---- control plating -------------------------------------------
    // Chunky enamel keys with dark glyphs; the chrome pass adds the 3D
    // bevel edges on the transport plates, so the tokens only state the
    // fills and inks.
    out.controls.button_outline = .{
        .background = key_face,
        .hover_background = key_hover,
        .active_background = key_pressed,
        .foreground = ink,
        .border = key_edge,
    };
    out.controls.button_ghost = .{
        .hover_background = key_hover,
        .active_background = key_pressed,
        .foreground = ink,
    };
    // No filled-primary control exists on this faceplate; keep the slot
    // on the enamel register so any stray primary reads as hardware.
    out.controls.button_primary = .{
        .background = key_face,
        .hover_background = key_hover,
        .active_background = key_pressed,
        .foreground = ink,
        .border = key_edge,
    };
    // The PL key: a latching hardware toggle — pressed-in enamel while
    // the playlist rack is out.
    out.controls.toggle_button = .{
        .background = key_face,
        .hover_background = key_hover,
        .active_background = key_latched,
        .foreground = ink,
        .border = key_edge,
    };
    // The search field is a small glass inset in the rack's enamel
    // status strip: smoked fill, phosphor print.
    out.controls.search_field = .{
        .background = glass,
        .foreground = phosphor_pale,
        .border = hairline,
    };
    // Faders: putty groove, phosphor filled range, enamel cap with a
    // dark rim (the radius squares the cap into a hardware slider).
    out.controls.slider = .{
        .background = groove,
        .active_background = phosphor,
        .foreground = key_face,
        .border = ink,
        .radius = 1,
    };
    out.controls.progress = .{
        .background = glass_deep,
        .active_background = phosphor,
        .radius = 1,
    };
    out.controls.scrollbar = .{
        .background = Color.rgba8(0, 0, 0, 0),
        .foreground = Color.rgba8(94, 125, 104, 110),
    };
    out.controls.badge = .{
        .radius = 1,
    };
    // Default panel plates read as GLASS rows, not enamel: the only
    // panels that keep the default fill are the playlist bay's ledger
    // rows (every chassis surface states its material explicitly), and
    // a row plate one step above the smoked glass gives the bay its
    // subtle striping.
    out.controls.panel = .{
        .background = glass_row,
    };
    return out;
}

// ---- palette -------------------------------------------------------

// The enamel family: warm cream/putty, stepped by machining depth.
const enamel = Color.rgb8(231, 225, 209);
const enamel_bright = Color.rgb8(243, 238, 224);
const key_face = Color.rgb8(238, 232, 217);
const key_hover = Color.rgb8(245, 240, 227);
const key_pressed = Color.rgb8(212, 204, 184);
const key_latched = Color.rgb8(205, 197, 176);
const key_edge = Color.rgb8(158, 150, 128);
const groove = Color.rgb8(186, 178, 155);
const ink = Color.rgb8(44, 40, 32);
const engraving = Color.rgb8(110, 102, 82);
const putty_line = Color.rgb8(169, 161, 138);
const disabled_wash = Color.rgb8(222, 215, 198);

// The glass family: smoked near-black with a green cast, and the one
// phosphor hue at three registers. Public because the chrome pass draws
// its segment readout and band ladders in the same phosphor.
pub const glass = Color.rgb8(12, 16, 13);
const glass_deep = Color.rgb8(8, 11, 9);
const glass_row = Color.rgb8(19, 25, 20);
const glass_lifted = Color.rgb8(24, 40, 30);
pub const phosphor = Color.rgb8(62, 224, 138);
const phosphor_pale = Color.rgb8(168, 216, 180);
const phosphor_dim = Color.rgb8(96, 128, 106);
const hairline = Color.rgb8(56, 68, 58);

pub const chassis_colors = canvas.ColorTokens{
    // Glass register: every display bay fills with `background`.
    .background = glass,
    .surface = enamel,
    // The lifted-glass wash under the loaded ledger row (glass, not
    // enamel: the playlist bay is a display on this machine).
    .surface_subtle = glass_lifted,
    .surface_pressed = key_pressed,
    .text = ink,
    .text_muted = engraving,
    .border = putty_line,
    .accent = phosphor,
    .accent_text = Color.rgb8(7, 21, 13),
    .destructive = Color.rgb8(196, 60, 46),
    .destructive_text = Color.rgb8(250, 246, 236),
    // Pale phosphor: what a readout prints in at rest.
    .success = phosphor_pale,
    .success_text = Color.rgb8(7, 21, 13),
    // Signal amber: the queue's "pending" state and the failure stamps,
    // the one non-green hue on the glass.
    .warning = Color.rgb8(236, 178, 74),
    .warning_text = Color.rgb8(43, 30, 7),
    // Dim phosphor: engraved-on-glass captions (see the module doc for
    // why the info slot carries it).
    .info = phosphor_dim,
    .info_text = Color.rgb8(7, 21, 13),
    // A phosphor focus ring on cream enamel reads as the powered-on
    // cursor of the machine.
    .focus_ring = phosphor,
    // Depth on this product is machined (chrome bevels), never cast.
    .shadow = Color.rgba8(0, 0, 0, 0),
    .disabled = disabled_wash,
};
