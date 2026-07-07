const std = @import("std");
const geometry = @import("geometry");
const drawing_model = @import("drawing.zig");
const token_model = @import("tokens.zig");
const widget_model = @import("widgets.zig");

const Color = drawing_model.Color;
const Fill = drawing_model.Fill;
const Radius = drawing_model.Radius;
const DesignTokens = token_model.DesignTokens;
const ControlVisualTokens = token_model.ControlVisualTokens;
const Widget = widget_model.Widget;
const WidgetState = widget_model.WidgetState;

/// How far the focus ring sits outside the control's border — the
/// ring-offset treatment: the control keeps its own border and the ring
/// floats a hairline gap outside it, so focus never restyles the control.
pub const focus_ring_offset: f32 = 2;

/// The frame the focus ring strokes: the control rect pushed out by the
/// ring offset.
pub fn focusRingRect(rect: geometry.RectF) geometry.RectF {
    return rect.normalized().inflate(geometry.InsetsF.all(focus_ring_offset));
}

/// The ring's corner radius: the control's own radius grown by the
/// offset so the ring stays concentric with the border it wraps.
pub fn focusRingRadius(radius: Radius) Radius {
    return .{
        .top_left = radius.top_left + focus_ring_offset,
        .top_right = radius.top_right + focus_ring_offset,
        .bottom_right = radius.bottom_right + focus_ring_offset,
        .bottom_left = radius.bottom_left + focus_ring_offset,
    };
}

/// The caret and composition-underline ink of an editable field: the
/// field's own text color. The caret is the primary "you are typing
/// HERE" signal, so it must read at the same contrast as the glyphs
/// beside it — the soft focus-ring gray that used to fill this role
/// hints at focus but disappears as an insertion point.
pub fn textEditingInkColor(widget: Widget, tokens: DesignTokens) Color {
    const visual = textInputControlVisualTokens(widget, tokens);
    return widgetForegroundColor(widget, tokens, visual.foreground orelse tokens.colors.text);
}

/// The selection highlight of an editable field: the solid accent. The
/// emitters repaint the selected glyphs in `textSelectionTextColor`
/// (the inverted-selection treatment), so the fill takes the full
/// accent block instead of a see-through wash — unmissable in both
/// schemes, including the monochrome register where the accent is
/// near-black on light surfaces.
pub fn textSelectionFillColor(widget: Widget, tokens: DesignTokens) Color {
    return widget.style.accent orelse tokens.colors.accent;
}

/// The glyph ink inside an editable field's selection: the accent's own
/// foreground, so the selected run inverts against the solid fill the
/// way filled-primary controls pair accent with accent_text.
pub fn textSelectionTextColor(widget: Widget, tokens: DesignTokens) Color {
    return widget.style.accent_foreground orelse tokens.colors.accent_text;
}

/// The selection wash of static (read-only) text: the accent at a
/// strength that reads as selection at a glance while the glyphs above
/// it stay in their own ink. Static paragraphs keep per-span colors
/// (links, emphasis, code), so the highlight sits under them as a
/// translucent band instead of inverting them like editable fields do.
pub fn staticTextSelectionFillColor(widget: Widget, tokens: DesignTokens) Color {
    return colorWithAlpha(widget.style.accent orelse tokens.colors.accent, 0.3);
}

pub fn colorWithAlpha(color: Color, alpha: f32) Color {
    return Color.rgba(color.r, color.g, color.b, std.math.clamp(alpha, 0, 1));
}

pub fn colorFill(color: Color) Fill {
    return .{ .color = color };
}

pub fn widgetBackgroundFill(widget: Widget, fallback: Color) Fill {
    return colorFill(widget.style.background orelse fallback);
}

pub fn widgetAccentFill(widget: Widget, fallback: Color) Fill {
    return colorFill(widget.style.accent orelse fallback);
}

pub fn widgetBorderFill(widget: Widget, fallback: Color) Fill {
    return colorFill(widget.style.border orelse fallback);
}

pub fn widgetFocusRingFill(widget: Widget, tokens: DesignTokens) Fill {
    return colorFill(widget.style.focus_ring orelse tokens.colors.focus_ring);
}

pub fn widgetBackgroundColor(widget: Widget, fallback: Color) Color {
    return widget.style.background orelse fallback;
}

pub fn widgetAccentColor(widget: Widget, fallback: Color) Color {
    return widget.style.accent orelse fallback;
}

pub fn widgetBorderColor(widget: Widget, fallback: Color) Color {
    return widget.style.border orelse fallback;
}

pub fn widgetForegroundColor(widget: Widget, tokens: DesignTokens, fallback: Color) Color {
    if (widget.state.disabled) return tokens.colors.text_muted;
    return widget.style.foreground orelse fallback;
}

pub fn widgetAccentForegroundColor(widget: Widget, tokens: DesignTokens, fallback: Color) Color {
    if (widget.state.disabled) return tokens.colors.text_muted;
    return widget.style.accent_foreground orelse fallback;
}

pub fn widgetRadius(widget: Widget, fallback: f32) Radius {
    if (widget.style.radius) |radius| return Radius.all(nonNegative(radius));
    return Radius.all(nonNegative(widgetSizedRadiusValue(widget, fallback)));
}

pub fn controlRadius(widget: Widget, visual: ControlVisualTokens, fallback: f32) Radius {
    if (widget.style.radius) |radius| return Radius.all(nonNegative(radius));
    return Radius.all(nonNegative(widgetSizedRadiusValue(widget, visual.radius orelse fallback)));
}

/// Button corners hold ONE radius across the size ladder (unlike
/// `controlRadius`, which steps with the size): a sm button with a
/// tighter corner reads as a chip and a lg one with a rounder corner
/// reads as a card — sizes change the box, never the corner language.
pub fn buttonControlRadius(widget: Widget, visual: ControlVisualTokens, tokens: DesignTokens) Radius {
    if (widget.style.radius) |radius| return Radius.all(nonNegative(radius));
    return Radius.all(nonNegative(visual.radius orelse tokens.radius.md));
}

pub fn widgetSizedRadiusValue(widget: Widget, fallback: f32) f32 {
    return switch (widget.size) {
        .sm => @max(0, fallback - 2),
        // heading/display are text-leaf typography rungs; radii are
        // control chrome, so they sit at the default step.
        .default, .icon, .heading, .display => fallback,
        .lg => fallback + 2,
    };
}

pub fn widgetStrokeWidth(widget: Widget, fallback: f32) f32 {
    return nonNegative(widget.style.stroke_width orelse fallback);
}

pub fn controlStrokeWidth(widget: Widget, visual: ControlVisualTokens, fallback: f32) f32 {
    return nonNegative(widget.style.stroke_width orelse visual.stroke_width orelse fallback);
}

pub fn buttonFill(widget: Widget, tokens: DesignTokens) Fill {
    return colorFill(buttonFillColor(widget, tokens));
}

pub fn buttonFillColor(widget: Widget, tokens: DesignTokens) Color {
    // Disabled keeps the variant's identity at half strength — the same
    // wash the selection controls wear — instead of collapsing every
    // variant to one gray block (which used to hand a disabled GHOST a
    // filled box it never had). A quiet variant's transparent body stays
    // transparent; the label and border carry the muted read.
    if (widget.state.disabled) return disabledWash(buttonFillColor(restStateWidget(widget), tokens), true);
    const pressed = widget.state.pressed;
    const selected = widget.state.selected;
    const hovered = widget.state.hovered;
    // On the quiet variants `selected` means two different things by
    // kind: a toggle's on-state earns the muted wash, while a nav
    // button's currency (the current page, the open trigger) shows
    // through its variant chrome alone — a permanently washed page
    // number would read as stuck hover.
    const toggle_kind = widget.kind == .toggle_button or widget.kind == .toggle;
    const selected_toggle = selected and toggle_kind;
    const visual = buttonControlVisualTokens(widget, tokens);
    return switch (widget.variant) {
        .default => if (pressed or selected)
            widgetAccentColor(widget, visual.active_background orelse tokens.colors.accent)
        else if (hovered)
            widgetBackgroundColor(widget, visual.hover_background orelse tokens.colors.surface_subtle)
        else
            widgetBackgroundColor(widget, visual.background orelse tokens.colors.surface),
        // Filled variants speak one wash channel: rest at full strength,
        // hover at 90%, pressed one step past hover at 80% — the wash
        // lightens on light surfaces and deepens on dark ones without a
        // second color per scheme. A persistent `selected` keeps the
        // rest fill: an on-state is identity, not feedback.
        .primary => widgetAccentColor(widget, filledStateBackground(visual, tokens.colors.accent, pressed, selected, hovered)),
        .destructive => widgetAccentColor(widget, filledStateBackground(visual, tokens.colors.destructive, pressed, selected, hovered)),
        .secondary => widgetBackgroundColor(widget, buttonStateBackground(visual, pressed or selected, hovered, if (pressed or selected) tokens.colors.surface_pressed else hoverWash(tokens.colors.surface_subtle, false, hovered, 0.8))),
        // The quiet variants step through the neutral washes: hover and
        // a toggle's on-state sit on the muted wash, a press deepens one
        // step further so the moment of commitment is visible under the
        // pointer, and rest is bare.
        .outline, .ghost => widgetBackgroundColor(widget, quietStateBackground(visual, tokens, pressed, selected_toggle, hovered)),
    };
}

/// The filled variants' state ladder over one base color, honoring any
/// themed control tokens first: pressed prefers `active_background`,
/// hover prefers `hover_background`, both fall back to the base at a
/// reduced alpha (90% hover, 80% pressed). Selected-at-rest keeps the
/// full-strength fill.
fn filledStateBackground(visual: ControlVisualTokens, base: Color, pressed: bool, selected: bool, hovered: bool) Color {
    if (pressed) return visual.active_background orelse visual.hover_background orelse visual.background orelse colorWithAlpha(base, 0.8 * base.a);
    if (selected) return visual.active_background orelse visual.hover_background orelse visual.background orelse base;
    if (hovered) return visual.hover_background orelse visual.background orelse colorWithAlpha(base, 0.9 * base.a);
    return visual.background orelse base;
}

/// The quiet (outline/ghost) state ladder: transparent at rest, the
/// muted wash on hover and on a toggle's on-state, the pressed wash —
/// one neutral step deeper — while the pointer is down.
fn quietStateBackground(visual: ControlVisualTokens, tokens: DesignTokens, pressed: bool, selected_toggle: bool, hovered: bool) Color {
    if (pressed) return visual.active_background orelse visual.hover_background orelse tokens.colors.surface_pressed;
    if (selected_toggle) return visual.active_background orelse visual.hover_background orelse tokens.colors.surface_subtle;
    if (hovered) return visual.hover_background orelse tokens.colors.surface_subtle;
    return visual.background orelse transparentColor();
}

/// The same widget with interaction FEEDBACK cleared: the appearance
/// the disabled wash mutes. `selected` survives — it is identity, not
/// feedback — so a disabled toggle that is ON still reads as on (the
/// same rule the selection controls' disabled register follows).
fn restStateWidget(widget: Widget) Widget {
    var rest = widget;
    rest.state.disabled = false;
    rest.state.pressed = false;
    rest.state.hovered = false;
    rest.state.focused = false;
    return rest;
}

/// The hover state of a filled control: the base color at reduced
/// alpha while hovered (and not pressed), the base color otherwise.
fn hoverWash(base: Color, active: bool, hovered: bool, alpha: f32) Color {
    if (hovered and !active) return colorWithAlpha(base, alpha * base.a);
    return base;
}

/// The disabled state of a selection control's chrome (checkbox box,
/// radio dot, switch track): the same color at half alpha — the house
/// disabled register keeps the control's shape and checked hue muted
/// to half strength instead of swapping to a different color, so a
/// checked-but-disabled control still reads as checked.
pub fn disabledWash(color: Color, disabled: bool) Color {
    if (!disabled) return color;
    return colorWithAlpha(color, 0.5 * color.a);
}

pub fn buttonTextColorForWidget(widget: Widget, tokens: DesignTokens) Color {
    // Disabled ink is the variant's own ink at half strength, matching
    // the half-strength fill — the whole control fades as one piece
    // (primary keeps knockout text on its washed fill; the quiet
    // variants keep their body ink) instead of swapping to the shared
    // muted gray, which read as a live-but-secondary label.
    if (widget.state.disabled) return disabledWash(buttonTextColorForWidget(restStateWidget(widget), tokens), true);
    const active = widget.state.pressed or widget.state.selected;
    const visual = buttonControlVisualTokens(widget, tokens);
    return switch (widget.variant) {
        .default => if (active)
            widgetAccentForegroundColor(widget, tokens, visual.foreground orelse tokens.colors.accent_text)
        else
            widgetForegroundColor(widget, tokens, visual.foreground orelse tokens.colors.text),
        .primary => widgetAccentForegroundColor(widget, tokens, visual.foreground orelse tokens.colors.accent_text),
        .secondary, .outline, .ghost => widgetForegroundColor(widget, tokens, visual.foreground orelse tokens.colors.text),
        .destructive => widgetAccentForegroundColor(widget, tokens, visual.foreground orelse tokens.colors.destructive_text),
    };
}

pub fn buttonBorderFill(widget: Widget, tokens: DesignTokens) Fill {
    // The disabled edge is the variant's own edge at half strength, so
    // it fades in lockstep with the half-strength fill and ink — a
    // full-strength edge around a washed body would read as a live
    // control wearing a ring. Ghost keeps its no-border shape.
    const border = widget.style.border orelse blk: {
        const visual = buttonControlVisualTokens(widget, tokens);
        break :blk switch (widget.variant) {
            .primary => widgetAccentColor(widget, visual.border orelse tokens.colors.accent),
            .destructive => widgetAccentColor(widget, visual.border orelse tokens.colors.destructive),
            .ghost => widgetBorderColor(widget, visual.border orelse transparentColor()),
            else => widgetBorderColor(widget, visual.border orelse tokens.colors.border),
        };
    };
    return colorFill(disabledWash(border, widget.state.disabled));
}

pub fn buttonControlVisualTokens(widget: Widget, tokens: DesignTokens) ControlVisualTokens {
    const variant = switch (widget.variant) {
        .default => tokens.controls.button_default,
        .primary => tokens.controls.button_primary,
        .secondary => tokens.controls.button_secondary,
        .outline => tokens.controls.button_outline,
        .ghost => tokens.controls.button_ghost,
        .destructive => tokens.controls.button_destructive,
    };
    if (widget.kind == .toggle_button or widget.kind == .toggle) return controlVisualTokensWithFallback(tokens.controls.toggle_button, variant);
    return variant;
}

pub fn selectControlVisualTokens(tokens: DesignTokens) ControlVisualTokens {
    return controlVisualTokensWithFallback(tokens.controls.select, tokens.controls.button_outline);
}

pub fn controlVisualTokensWithFallback(primary: ControlVisualTokens, fallback: ControlVisualTokens) ControlVisualTokens {
    return .{
        .background = primary.background orelse fallback.background,
        .hover_background = primary.hover_background orelse fallback.hover_background,
        .active_background = primary.active_background orelse fallback.active_background,
        .foreground = primary.foreground orelse fallback.foreground,
        .border = primary.border orelse fallback.border,
        .radius = primary.radius orelse fallback.radius,
        .stroke_width = primary.stroke_width orelse fallback.stroke_width,
    };
}

pub fn buttonStateBackground(visual: ControlVisualTokens, active: bool, hovered: bool, fallback: Color) Color {
    if (active) return visual.active_background orelse visual.hover_background orelse visual.background orelse fallback;
    if (hovered) return visual.hover_background orelse visual.background orelse fallback;
    return visual.background orelse fallback;
}

pub fn textInputControlVisualTokens(widget: Widget, tokens: DesignTokens) ControlVisualTokens {
    return switch (widget.kind) {
        .input => controlVisualTokensWithFallback(tokens.controls.input, tokens.controls.text_field),
        .search_field => tokens.controls.search_field,
        .combobox => controlVisualTokensWithFallback(tokens.controls.combobox, tokens.controls.search_field),
        // The grouped input wears the textarea's visual class: the group
        // IS the field (its entry's own chrome dissolves), so both draw
        // from one control register.
        .textarea, .input_group => tokens.controls.textarea,
        else => tokens.controls.text_field,
    };
}

pub fn textInputFill(widget: Widget, tokens: DesignTokens, visual: ControlVisualTokens) Fill {
    if (widget.state.disabled) return colorFill(tokens.colors.disabled);
    return colorFill(widgetBackgroundColor(widget, buttonStateBackground(visual, false, widget.state.hovered, tokens.colors.surface)));
}

pub fn textInputBorderFill(widget: Widget, visual: ControlVisualTokens, fallback: Color) Fill {
    return colorFill(widgetBorderColor(widget, visual.border orelse fallback));
}

pub fn accordionControlVisualTokens(tokens: DesignTokens) ControlVisualTokens {
    return controlVisualTokensWithFallback(tokens.controls.accordion, tokens.controls.panel);
}

pub fn alertControlVisualTokens(tokens: DesignTokens) ControlVisualTokens {
    return controlVisualTokensWithFallback(tokens.controls.alert, tokens.controls.panel);
}

pub fn bubbleControlVisualTokens(tokens: DesignTokens) ControlVisualTokens {
    return controlVisualTokensWithFallback(tokens.controls.bubble, tokens.controls.panel);
}

pub fn cardControlVisualTokens(tokens: DesignTokens) ControlVisualTokens {
    return controlVisualTokensWithFallback(tokens.controls.card, tokens.controls.panel);
}

pub fn dialogControlVisualTokens(tokens: DesignTokens) ControlVisualTokens {
    return controlVisualTokensWithFallback(tokens.controls.dialog, tokens.controls.popover);
}

pub fn drawerControlVisualTokens(tokens: DesignTokens) ControlVisualTokens {
    return controlVisualTokensWithFallback(tokens.controls.drawer, tokens.controls.popover);
}

pub fn sheetControlVisualTokens(tokens: DesignTokens) ControlVisualTokens {
    return controlVisualTokensWithFallback(tokens.controls.sheet, tokens.controls.popover);
}

pub fn listItemControlVisualTokens(widget: Widget, tokens: DesignTokens) ControlVisualTokens {
    return switch (widget.kind) {
        .data_cell => controlVisualTokensWithFallback(tokens.controls.data_cell, tokens.controls.list_item),
        .menu_item => controlVisualTokensWithFallback(tokens.controls.menu_item, tokens.controls.list_item),
        .list_item => tokens.controls.list_item,
        else => .{},
    };
}

pub fn selectionControlVisualTokens(widget: Widget, tokens: DesignTokens) ControlVisualTokens {
    return switch (widget.kind) {
        .segmented_control => tokens.controls.segmented_control,
        .checkbox => tokens.controls.checkbox,
        .radio => tokens.controls.radio,
        .switch_control => tokens.controls.switch_control,
        .slider => tokens.controls.slider,
        .progress => tokens.controls.progress,
        else => .{},
    };
}

pub fn surfaceControlVisualTokens(widget: Widget, tokens: DesignTokens) ControlVisualTokens {
    return switch (widget.kind) {
        .accordion => accordionControlVisualTokens(tokens),
        .alert => alertControlVisualTokens(tokens),
        .bubble => bubbleControlVisualTokens(tokens),
        .card => cardControlVisualTokens(tokens),
        .dialog => dialogControlVisualTokens(tokens),
        .drawer => drawerControlVisualTokens(tokens),
        .sheet => sheetControlVisualTokens(tokens),
        .panel => tokens.controls.panel,
        .resizable => resizableControlVisualTokens(tokens),
        .popover => tokens.controls.popover,
        .menu_surface => tokens.controls.menu_surface,
        .dropdown_menu => controlVisualTokensWithFallback(tokens.controls.dropdown_menu, tokens.controls.menu_surface),
        .tooltip => tokens.controls.tooltip,
        else => .{},
    };
}

pub fn resizableControlVisualTokens(tokens: DesignTokens) ControlVisualTokens {
    return controlVisualTokensWithFallback(tokens.controls.resizable, tokens.controls.panel);
}

pub fn componentControlVisualTokens(widget: Widget, tokens: DesignTokens) ControlVisualTokens {
    return switch (widget.kind) {
        .avatar => tokens.controls.avatar,
        .badge => tokens.controls.badge,
        .separator => tokens.controls.separator,
        .skeleton => tokens.controls.skeleton,
        .spinner => tokens.controls.spinner,
        else => .{},
    };
}

pub fn componentPillRadius(widget: Widget, visual: ControlVisualTokens, fallback: f32) Radius {
    if (widget.style.radius) |radius| return Radius.all(nonNegative(radius));
    if (visual.radius) |radius| return Radius.all(nonNegative(radius));
    return Radius.all(nonNegative(fallback));
}

pub fn badgeBackgroundColor(widget: Widget, tokens: DesignTokens, visual: ControlVisualTokens) Color {
    if (widget.state.disabled) return tokens.colors.disabled;
    return switch (widget.variant) {
        .default, .primary => widgetAccentColor(widget, buttonStateBackground(visual, widget.state.pressed or widget.state.selected, widget.state.hovered, tokens.colors.accent)),
        .secondary => widgetBackgroundColor(widget, buttonStateBackground(visual, widget.state.pressed or widget.state.selected, widget.state.hovered, tokens.colors.surface_subtle)),
        .outline, .ghost => widgetBackgroundColor(widget, buttonStateBackground(visual, widget.state.pressed or widget.state.selected, widget.state.hovered, if (widget.state.hovered or widget.state.pressed) tokens.colors.surface_subtle else transparentColor())),
        // The QUIET destructive chip: a translucent destructive wash
        // under destructive text (the composite tracks the scheme —
        // pale pink on light pages, a dark red tint on dark ones)
        // instead of a filled alarm block.
        .destructive => widgetAccentColor(widget, buttonStateBackground(visual, widget.state.pressed or widget.state.selected, widget.state.hovered, colorWithAlpha(tokens.colors.destructive, 0.12))),
    };
}

pub fn badgeBorderColor(widget: Widget, tokens: DesignTokens, visual: ControlVisualTokens) Color {
    return switch (widget.variant) {
        .default, .primary => widgetAccentColor(widget, visual.border orelse tokens.colors.accent),
        .destructive => widgetAccentColor(widget, visual.border orelse tokens.colors.destructive),
        else => widgetBorderColor(widget, visual.border orelse tokens.colors.border),
    };
}

pub fn badgeTextColor(widget: Widget, tokens: DesignTokens, visual: ControlVisualTokens) Color {
    if (widget.state.disabled) return tokens.colors.text_muted;
    return switch (widget.variant) {
        .default, .primary => widgetAccentForegroundColor(widget, tokens, visual.foreground orelse tokens.colors.accent_text),
        // Ink on the quiet wash, not knockout text on a filled block.
        .destructive => widgetAccentForegroundColor(widget, tokens, visual.foreground orelse tokens.colors.destructive),
        else => widgetForegroundColor(widget, tokens, visual.foreground orelse tokens.colors.text),
    };
}

pub fn badgeStrokeWidth(widget: Widget, tokens: DesignTokens, visual: ControlVisualTokens) f32 {
    if (widget.style.stroke_width) |width| return nonNegative(width);
    if (visual.stroke_width) |width| return nonNegative(width);
    // Only the outline variant wears a border; the filled and quiet
    // chips are borderless (the reference badge's transparent border).
    return switch (widget.variant) {
        .outline => tokens.stroke.hairline,
        else => 0,
    };
}

pub fn buttonStrokeWidth(widget: Widget, tokens: DesignTokens) f32 {
    if (widget.style.stroke_width) |width| return nonNegative(width);
    const visual = buttonControlVisualTokens(widget, tokens);
    if (visual.stroke_width) |width| return nonNegative(width);
    return switch (widget.variant) {
        .ghost => 0,
        else => tokens.stroke.regular,
    };
}

pub fn listItemFillColor(widget: Widget, tokens: DesignTokens, state: WidgetState) Color {
    const visual = listItemControlVisualTokens(widget, tokens);
    const fallback = if (state.selected or state.pressed)
        tokens.colors.surface_pressed
    else if (state.hovered)
        tokens.colors.surface_subtle
    else
        transparentColor();
    return buttonStateBackground(visual, state.selected or state.pressed, state.hovered, fallback);
}

pub fn transparentColor() Color {
    return Color.rgba(0, 0, 0, 0);
}

fn nonNegative(value: f32) f32 {
    return @max(0, value);
}
