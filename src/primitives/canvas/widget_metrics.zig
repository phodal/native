const std = @import("std");
const token_model = @import("tokens.zig");
const widget_model = @import("widgets.zig");
const text_spans_model = @import("text_spans.zig");

const Density = token_model.Density;
const DesignTokens = token_model.DesignTokens;
const Widget = widget_model.Widget;

const default_widget_row_extent: f32 = 28;

/// Button labels hold ONE size across the whole control ladder: sm and
/// lg buttons change chrome (height, inset, gap), never the glyphs — a
/// stepped label would make a small button read as a small caption
/// instead of the same command in a tighter box.
pub fn widgetButtonTextSize(widget: Widget, tokens: DesignTokens) f32 {
    _ = widget;
    return tokens.typography.button_size;
}

pub fn widgetBodyTextSize(widget: Widget, tokens: DesignTokens) f32 {
    // heading/display are typography-token rungs, honored on text leaves
    // only: they REPLACE the body base with the named token instead of
    // stepping it, so the whole type scale stays themable through
    // `TypographyTokenOverrides`. Like the other typography sizes they do
    // not density-scale (density scales chrome — insets, heights — never
    // glyph sizes). On any other widget kind they fall through to the
    // default control step (the markup layer rejects them there; Zig
    // views get a Debug warning from `Ui.el`).
    if (widget.kind == .text) {
        switch (widget.size) {
            .heading => return tokens.typography.heading_size,
            .display => return tokens.typography.display_size,
            else => {},
        }
    }
    return widgetTypographySize(widget, tokens.typography.body_size);
}

pub fn widgetLabelTextSize(widget: Widget, tokens: DesignTokens) f32 {
    return widgetTypographySize(widget, tokens.typography.label_size);
}

/// Badge text sits one rung below the label size (12 on the default
/// scale) — the compact chip register.
pub fn widgetBadgeTextSize(widget: Widget, tokens: DesignTokens) f32 {
    return widgetTypographySize(widget, @max(8, tokens.typography.label_size - 1));
}

pub fn widgetTypographySize(widget: Widget, base: f32) f32 {
    return switch (widget.size) {
        .sm => @max(8, base - 1),
        // heading/display are text-leaf typography rungs (resolved in
        // `widgetBodyTextSize`); on the control scale they sit at the
        // default step.
        .default, .icon, .heading, .display => base,
        .lg => base + 1,
    };
}

pub fn widgetLineHeight(text_size: f32) f32 {
    return text_size * 1.25;
}

/// Wrap budget for text painted inside a pixel-snapped frame. Geometry
/// snapping can shave up to half a device pixel off the layout frame
/// that intrinsic sizing measured with the exact same metrics — enough
/// to word-wrap an exact-fit line mid-word ("Sort" painting as
/// "Sor"/"t"). Hand the shaved quantum back to the wrap so snapping
/// never changes line breaks; glyph origins still snap independently.
/// (Elision has its own exact-fit slack — `text_elision_slack` — so
/// label budgets stay byte-identical for alignment.)
pub fn textWrapMaxWidth(tokens: DesignTokens, width: f32) f32 {
    if (!tokens.pixel_snap.geometry) return width;
    const scale = tokens.pixel_snap.scale;
    if (!std.math.isFinite(scale) or scale <= 0) return width;
    return width + 0.5 / scale;
}

/// The single source of truth for how a span paragraph (`.text` widget
/// with `spans`) lays out: intrinsic sizing, wrapped-height reservation,
/// link hit-area frames, and command emission all build their options
/// here so they agree byte-for-byte. One deliberate exception: emission
/// widens `max_width` by the pixel-snap quantum (`textWrapMaxWidth`) so
/// a snapped paint frame never wraps a line the layout frame fit —
/// painted lines are therefore always <= the reserved line count.
pub fn widgetTextSpanLayoutOptions(widget: Widget, tokens: DesignTokens, max_width: f32) text_spans_model.TextSpanLayoutOptions {
    return .{
        .size = widgetBodyTextSize(widget, tokens),
        .max_width = max_width,
        .wrap = .word,
        .alignment = widget.text_alignment,
        .typography = tokens.typography,
        .measure = tokens.text_measure,
    };
}

/// The ONE control height register — buttons, inputs, and select
/// triggers all sit on the whole-pixel 32/36/40 ladder (sm/default/lg)
/// instead of the multiplicative size scale (which lands on 31.5/40.5):
/// heights on the 4px grid keep a mixed toolbar row at exactly one
/// height and pixel-snap cleanly at every scale factor. The `icon`
/// size is the default square.
pub fn widgetControlHeight(widget: Widget, tokens: DesignTokens) f32 {
    const base: f32 = switch (widget.size) {
        .sm => 32,
        .default, .icon, .heading, .display => 36,
        .lg => 40,
    };
    return densityValue(tokens, base);
}

/// Vector icon extent inside icon-bearing controls (a button's
/// `widget.icon`): sized just above the label text so icon and label
/// read as one line. Shared by intrinsic layout and render so measured
/// widths and painted pixels agree.
pub fn widgetButtonIconExtent(widget: Widget, tokens: DesignTokens) f32 {
    return widgetButtonTextSize(widget, tokens) + 2;
}

/// Gap between a button's inline icon and its label: 8 at the default
/// and lg steps, 6 at sm. lg does NOT widen the gap — a bigger button
/// earns more air at its edges (the inset ladder), not between an icon
/// and the label it belongs to.
pub fn widgetButtonIconGap(widget: Widget, tokens: DesignTokens) f32 {
    const base: f32 = switch (widget.size) {
        .sm => 6,
        .default, .icon, .heading, .display, .lg => 8,
    };
    return densityValue(tokens, base);
}

/// Extent of a vector icon inside a badge (`widget.icon`): sized just
/// above the badge's label text. Shared by intrinsic layout and render.
pub fn widgetBadgeIconExtent(widget: Widget, tokens: DesignTokens) f32 {
    return widgetLabelTextSize(widget, tokens) + 2;
}

/// Gap between a badge's inline icon and its label.
pub fn widgetBadgeIconGap(widget: Widget, tokens: DesignTokens) f32 {
    return widgetControlInset(widget, tokens, tokens.spacing.sm);
}

/// Extent of a leading vector icon in row-shaped controls (`list_item`,
/// `menu_item` via `widget.icon`): sized just above the body text so
/// icon and label read as one line. Shared by intrinsic layout and
/// render so measured widths and painted pixels agree.
pub fn widgetRowIconExtent(widget: Widget, tokens: DesignTokens) f32 {
    return widgetBodyTextSize(widget, tokens) + 2;
}

/// Gap between a row's leading icon and its label.
pub fn widgetRowIconGap(widget: Widget, tokens: DesignTokens) f32 {
    return widgetControlInset(widget, tokens, tokens.spacing.sm);
}

pub fn widgetDefaultRowHeight(widget: Widget, tokens: DesignTokens) f32 {
    return widgetSizedDensityValue(widget, tokens, default_widget_row_extent);
}

/// A button's horizontal inset. The ladder breathes wider than the
/// generic control inset — 12/16/24 for sm/default/lg — because a
/// command earns air around its label; lg jumps disproportionately (a
/// large call-to-action is mostly presence). An inline icon pulls the
/// inset in one step (10/12/16): the glyph already carries visual
/// weight at the edge, so the icon+label block stays optically
/// centered instead of floating in doubled padding. `icon`-sized
/// buttons center their glyph in the square and need no inset.
pub fn widgetButtonInset(widget: Widget, tokens: DesignTokens) f32 {
    if (widget.size == .icon) return 0;
    const with_icon = widget.icon.len > 0 and widget.text.len > 0;
    const base: f32 = switch (widget.size) {
        .sm => if (with_icon) 10 else 12,
        .default, .icon, .heading, .display => if (with_icon) 12 else 16,
        .lg => if (with_icon) 16 else 24,
    };
    return densityValue(tokens, base);
}

pub fn widgetControlInset(widget: Widget, tokens: DesignTokens, base: f32) f32 {
    return densityValue(tokens, widgetSizedTokenValue(widget, base));
}

pub fn widgetSizedDensityValue(widget: Widget, tokens: DesignTokens, value: f32) f32 {
    return densityValue(tokens, value) * widgetSizeScale(widget);
}

pub fn widgetSizedTokenValue(widget: Widget, value: f32) f32 {
    return switch (widget.size) {
        .sm => @max(0, value - 2),
        // heading/display step type, not chrome: control metrics stay at
        // the default step.
        .default, .icon, .heading, .display => value,
        .lg => value + 2,
    };
}

pub fn widgetSizeScale(widget: Widget) f32 {
    return switch (widget.size) {
        .sm => 0.875,
        .default, .icon, .heading, .display => 1,
        .lg => 1.125,
    };
}

pub fn densityValue(tokens: DesignTokens, value: f32) f32 {
    return value * densityScale(tokens.density);
}

pub fn densityScale(density: Density) f32 {
    return switch (density) {
        .compact => 0.875,
        .regular => 1,
        .spacious => 1.125,
    };
}
