const std = @import("std");
const geometry = @import("geometry");
const canvas = @import("root.zig");
const drawing_model = @import("drawing.zig");
const text_model = @import("text.zig");
const token_model = @import("tokens.zig");
const widget_model = @import("widgets.zig");
const event_model = @import("events.zig");
const equality_model = @import("equality.zig");
const widget_tree = @import("widget_tree.zig");
const widget_layout = @import("widget_layout.zig");
const widget_access = @import("widget_access.zig");
const widget_semantics = @import("widget_semantics.zig");
const widget_metrics = @import("widget_metrics.zig");
const widget_text_input = @import("widget_text_input.zig");
const widget_render_style = @import("widget_render_style.zig");
const widget_render_scroll = @import("widget_render_scroll.zig");
const widget_render_surfaces = @import("widget_render_surfaces.zig");

const Error = canvas.Error;
const ObjectId = canvas.ObjectId;
const Builder = canvas.Builder;
const Color = drawing_model.Color;
const Affine = drawing_model.Affine;
const Radius = drawing_model.Radius;
const Fill = drawing_model.Fill;
const Stroke = drawing_model.Stroke;
const Clip = drawing_model.Clip;
const Shadow = drawing_model.Shadow;
const DrawText = text_model.DrawText;
const TextWrap = text_model.TextWrap;
const TextAlign = text_model.TextAlign;
const TextLayoutOptions = text_model.TextLayoutOptions;
const TextLine = text_model.TextLine;
const TextRange = text_model.TextRange;
const TextSelectionRect = text_model.TextSelectionRect;
const DesignTokens = token_model.DesignTokens;
const ControlVisualTokens = token_model.ControlVisualTokens;
const WidgetPaintOrder = widget_tree.WidgetPaintOrder;
const widgetPaintLayer = widget_tree.widgetPaintLayer;
const nextWidgetPaintChild = widget_tree.nextWidgetPaintChild;
const widgetLayoutDirectChildCount = widget_tree.widgetLayoutDirectChildCount;
const nextWidgetLayoutPaintChild = widget_tree.nextWidgetLayoutPaintChild;
const widgetTransform = widget_tree.widgetTransform;
const widgetClipsContent = widget_tree.widgetClipsContent;
const booleanControlSelected = widget_access.booleanControlSelected;
const widgetTextSelectionRange = widget_access.widgetTextSelectionRange;
const widgetTextCompositionRange = widget_access.widgetTextCompositionRange;
const widgetPlaceholder = widget_text_input.widgetPlaceholder;
const widgetTextInputSize = widget_text_input.widgetTextInputSize;
const widgetTextInputLayoutOptions = widget_text_input.widgetTextInputLayoutOptions;
const widgetTextInputOrigin = widget_text_input.widgetTextInputOrigin;
const widgetTextInputClipRect = widget_text_input.widgetTextInputClipRect;
const widgetTextInputDrawText = widget_text_input.widgetTextInputDrawText;
const widgetTextInputInset = widget_text_input.widgetTextInputInset;
const widgetButtonTextSize = widget_metrics.widgetButtonTextSize;
const widgetBodyTextSize = widget_metrics.widgetBodyTextSize;
const widgetLabelTextSize = widget_metrics.widgetLabelTextSize;
const widgetLineHeight = widget_metrics.widgetLineHeight;
const widgetTypographySize = widget_metrics.widgetTypographySize;
const widgetButtonInset = widget_metrics.widgetButtonInset;
const widgetControlInset = widget_metrics.widgetControlInset;
const widgetSizedDensityValue = widget_metrics.widgetSizedDensityValue;
const widgetSizedTokenValue = widget_metrics.widgetSizedTokenValue;
const widgetControlHeight = widget_metrics.widgetControlHeight;
const densityValue = widget_metrics.densityValue;
const WidgetKind = widget_model.WidgetKind;
const WidgetState = widget_model.WidgetState;
const WidgetRenderState = widget_model.WidgetRenderState;
const WidgetSize = widget_model.WidgetSize;
const Widget = widget_model.Widget;
const estimateTextWidth = text_model.estimateTextWidth;
const estimateTextWidthForFont = text_model.estimateTextWidthForFont;
const layoutTextCaretRect = text_model.layoutTextCaretRect;
const layoutTextSelectionRects = text_model.layoutTextSelectionRects;
const affinesEqual = equality_model.affinesEqual;
const textInputAffordanceColor = widget_render_style.textInputAffordanceColor;
pub const textSelectionFillColor = widget_render_style.textSelectionFillColor;
pub const colorWithAlpha = widget_render_style.colorWithAlpha;
const colorFill = widget_render_style.colorFill;
const widgetBackgroundFill = widget_render_style.widgetBackgroundFill;
const widgetAccentFill = widget_render_style.widgetAccentFill;
const widgetBorderFill = widget_render_style.widgetBorderFill;
const widgetFocusRingFill = widget_render_style.widgetFocusRingFill;
const widgetBackgroundColor = widget_render_style.widgetBackgroundColor;
const widgetAccentColor = widget_render_style.widgetAccentColor;
const widgetBorderColor = widget_render_style.widgetBorderColor;
const widgetForegroundColor = widget_render_style.widgetForegroundColor;
const widgetAccentForegroundColor = widget_render_style.widgetAccentForegroundColor;
const widgetRadius = widget_render_style.widgetRadius;
pub const controlRadius = widget_render_style.controlRadius;
pub const controlStrokeWidth = widget_render_style.controlStrokeWidth;
const buttonFill = widget_render_style.buttonFill;
const buttonTextColorForWidget = widget_render_style.buttonTextColorForWidget;
const buttonBorderFill = widget_render_style.buttonBorderFill;
const buttonControlVisualTokens = widget_render_style.buttonControlVisualTokens;
pub const selectControlVisualTokens = widget_render_style.selectControlVisualTokens;
const buttonStateBackground = widget_render_style.buttonStateBackground;
pub const textInputControlVisualTokens = widget_render_style.textInputControlVisualTokens;
const textInputFill = widget_render_style.textInputFill;
const textInputBorderFill = widget_render_style.textInputBorderFill;
const alertControlVisualTokens = widget_render_style.alertControlVisualTokens;
const cardControlVisualTokens = widget_render_style.cardControlVisualTokens;
const dialogControlVisualTokens = widget_render_style.dialogControlVisualTokens;
const drawerControlVisualTokens = widget_render_style.drawerControlVisualTokens;
const sheetControlVisualTokens = widget_render_style.sheetControlVisualTokens;
pub const listItemControlVisualTokens = widget_render_style.listItemControlVisualTokens;
pub const selectionControlVisualTokens = widget_render_style.selectionControlVisualTokens;
pub const surfaceControlVisualTokens = widget_render_style.surfaceControlVisualTokens;
pub const componentControlVisualTokens = widget_render_style.componentControlVisualTokens;
const componentPillRadius = widget_render_style.componentPillRadius;
const badgeBackgroundColor = widget_render_style.badgeBackgroundColor;
const badgeBorderColor = widget_render_style.badgeBorderColor;
const badgeTextColor = widget_render_style.badgeTextColor;
const badgeStrokeWidth = widget_render_style.badgeStrokeWidth;
pub const buttonStrokeWidth = widget_render_style.buttonStrokeWidth;
const listItemFillColor = widget_render_style.listItemFillColor;
pub const transparentColor = widget_render_style.transparentColor;

const max_widget_depth: usize = 32;
const max_widget_text_range_rects: usize = 4;
const max_widget_text_layout_lines: usize = 16;

const SpinnerSegment = struct { x: f32, y: f32 };
const spinner_segments = [_]SpinnerSegment{
    .{ .x = 0, .y = -1 },
    .{ .x = 0.707, .y = -0.707 },
    .{ .x = 1, .y = 0 },
    .{ .x = 0.707, .y = 0.707 },
    .{ .x = 0, .y = 1 },
    .{ .x = -0.707, .y = 0.707 },
    .{ .x = -1, .y = 0 },
    .{ .x = -0.707, .y = -0.707 },
};

pub fn emitWidgetTree(builder: *Builder, widget: Widget, tokens: DesignTokens) Error!void {
    try emitWidgetDepth(builder, widget, tokens, 0);
}

pub fn emitWidgetLayout(builder: *Builder, layout: anytype, tokens: DesignTokens) Error!void {
    return emitWidgetLayoutWithState(builder, layout, tokens, .{});
}

pub fn emitWidgetLayoutWithState(builder: *Builder, layout: anytype, tokens: DesignTokens, state: WidgetRenderState) Error!void {
    try emitWidgetLayoutChildren(builder, layout, null, tokens, state);
}

fn emitWidgetDepth(builder: *Builder, widget: Widget, tokens: DesignTokens, depth: usize) Error!void {
    if (depth >= max_widget_depth) return error.WidgetDepthExceeded;
    if (widget.semantics.hidden) return;

    const opacity = widgetOpacity(widget);
    if (opacity <= 0) return;
    const wrap_opacity = opacity < 1;
    const transform = widgetTransform(widget);
    const wrap_transform = !affinesEqual(transform, Affine.identity());
    const inverse_transform = if (wrap_transform) transform.inverse() orelse return error.InvalidTransform else Affine.identity();
    if (wrap_opacity) try builder.pushOpacity(opacity);
    if (wrap_transform) try builder.transform(transform);
    try emitWidgetDepthContent(builder, widget, tokens, depth);
    if (wrap_transform) try builder.transform(inverse_transform);
    if (wrap_opacity) try builder.popOpacity();
}

fn emitWidgetDepthContent(builder: *Builder, widget: Widget, tokens: DesignTokens, depth: usize) Error!void {
    const paint_widget = widgetWithFrame(widget, pixelSnapGeometryRect(tokens, widget.frame));
    try emitWidgetBackdropBlur(builder, paint_widget, tokens);
    switch (paint_widget.kind) {
        .stack, .row, .column, .grid, .data_grid, .table, .list, .breadcrumb, .button_group, .pagination, .radio_group, .tabs, .toggle_group, .data_row => try emitWidgetClippedChildren(builder, paint_widget, tokens, depth),
        .scroll_view => try emitScrollViewWidget(builder, paint_widget, tokens, depth),
        .alert => try emitAlertWidget(builder, paint_widget, tokens, depth),
        .card => try emitCardWidget(builder, paint_widget, tokens, depth),
        .dialog => try emitDialogSurfaceWidget(builder, paint_widget, tokens, depth),
        .drawer => try emitDrawerSurfaceWidget(builder, paint_widget, tokens, depth),
        .sheet => try emitSheetSurfaceWidget(builder, paint_widget, tokens, depth),
        .accordion, .bubble, .resizable, .panel => try emitPanelWidget(builder, paint_widget, tokens, depth),
        .popover => try emitPopoverWidget(builder, paint_widget, tokens, depth),
        .menu_surface, .dropdown_menu => try emitMenuSurfaceWidget(builder, paint_widget, tokens, depth),
        .text => try emitTextWidget(builder, paint_widget, tokens),
        .icon => try emitIconWidget(builder, paint_widget, tokens),
        .image => try emitImageWidget(builder, paint_widget),
        .avatar => try emitAvatarWidget(builder, paint_widget, tokens),
        .badge => try emitBadgeWidget(builder, paint_widget, tokens),
        .button, .toggle_button => try emitButtonWidget(builder, paint_widget, tokens),
        .icon_button => try emitIconButtonWidget(builder, paint_widget, tokens),
        .select => try emitSelectWidget(builder, paint_widget, tokens),
        .input, .text_field, .textarea => try emitTextFieldWidget(builder, paint_widget, tokens),
        .search_field, .combobox => try emitSearchFieldWidget(builder, paint_widget, tokens),
        .tooltip => try emitTooltipWidget(builder, paint_widget, tokens),
        .menu_item => try emitMenuItemWidget(builder, paint_widget, tokens),
        .list_item => try emitListItemWidget(builder, paint_widget, tokens),
        .data_cell => try emitDataCellWidget(builder, paint_widget, tokens),
        .status_bar => try emitStatusBarWidget(builder, paint_widget, tokens),
        .segmented_control => try emitSegmentedControlWidget(builder, paint_widget, tokens),
        .checkbox => try emitCheckboxWidget(builder, paint_widget, tokens),
        .radio => try emitRadioWidget(builder, paint_widget, tokens),
        .switch_control, .toggle => try emitToggleWidget(builder, paint_widget, tokens),
        .slider => try emitSliderWidget(builder, paint_widget, tokens),
        .progress => try emitProgressWidget(builder, paint_widget, tokens),
        .separator => try emitSeparatorWidget(builder, paint_widget, tokens),
        .skeleton => try emitSkeletonWidget(builder, paint_widget, tokens),
        .spinner => try emitSpinnerWidget(builder, paint_widget, tokens),
    }
}

fn emitWidgetChildren(builder: *Builder, children: []const Widget, tokens: DesignTokens, depth: usize) Error!void {
    var emitted: usize = 0;
    var previous: ?WidgetPaintOrder = null;
    while (emitted < children.len) : (emitted += 1) {
        const child_index = nextWidgetPaintChild(children, tokens, previous) orelse return;
        const child = children[child_index];
        try emitWidgetDepth(builder, child, tokens, depth + 1);
        previous = .{ .layer = widgetPaintLayer(child, tokens), .index = child_index };
    }
}

fn emitWidgetLayoutChildren(
    builder: *Builder,
    layout: anytype,
    parent_index: ?usize,
    tokens: DesignTokens,
    state: WidgetRenderState,
) Error!void {
    const child_count = widgetLayoutDirectChildCount(layout, parent_index);
    var emitted: usize = 0;
    var previous: ?WidgetPaintOrder = null;
    while (emitted < child_count) : (emitted += 1) {
        const child_index = nextWidgetLayoutPaintChild(layout, parent_index, tokens, previous) orelse return;
        try emitWidgetLayoutNode(builder, layout, child_index, tokens, state);
        previous = .{ .layer = widgetPaintLayer(layout.nodes[child_index].widget, tokens), .index = child_index };
    }
}

fn emitWidgetLayoutNode(
    builder: *Builder,
    layout: anytype,
    node_index: usize,
    tokens: DesignTokens,
    state: WidgetRenderState,
) Error!void {
    const node = layout.nodes[node_index];
    if (node.widget.semantics.hidden) return;

    const widget = widgetWithRenderState(widgetWithFrame(node.widget, node.frame), state);
    const opacity = widgetOpacity(widget);
    if (opacity <= 0) return;
    const wrap_opacity = opacity < 1;
    const transform = widgetTransform(widget);
    const wrap_transform = !affinesEqual(transform, Affine.identity());
    const inverse_transform = if (wrap_transform) transform.inverse() orelse return error.InvalidTransform else Affine.identity();
    if (wrap_opacity) try builder.pushOpacity(opacity);
    if (wrap_transform) try builder.transform(transform);
    try emitWidgetLayoutNodeContent(builder, layout, node_index, tokens, state, widget);
    if (wrap_transform) try builder.transform(inverse_transform);
    if (wrap_opacity) try builder.popOpacity();
}

fn emitWidgetLayoutNodeContent(
    builder: *Builder,
    layout: anytype,
    node_index: usize,
    tokens: DesignTokens,
    state: WidgetRenderState,
    widget: Widget,
) Error!void {
    const paint_widget = widgetWithFrame(widget, pixelSnapGeometryRect(tokens, widget.frame));
    try emitWidgetBackdropBlur(builder, paint_widget, tokens);
    switch (paint_widget.kind) {
        .stack, .row, .column, .breadcrumb, .button_group, .pagination, .radio_group, .tabs, .toggle_group, .data_row => {},
        .grid, .data_grid, .table, .list => if (paint_widget.layout.virtualized) {
            try emitWidgetLayoutScrollableChildren(builder, layout, node_index, tokens, state, paint_widget);
            return;
        },
        .scroll_view => {
            try builder.pushClip(.{ .id = widgetPartId(paint_widget.id, 1), .rect = paint_widget.frame });
            try emitWidgetLayoutChildren(builder, layout, node_index, tokens, state);
            try builder.popClip();
            try widget_render_scroll.emitScrollViewScrollbar(builder, paint_widget.frame, widgetScrollSemantics(layout, node_index).metrics, tokens, paint_widget.id);
            return;
        },
        .alert => try widget_render_surfaces.emitAlertWidgetChrome(builder, paint_widget, tokens),
        .card => try widget_render_surfaces.emitCardWidgetChrome(builder, paint_widget, tokens),
        .dialog => try widget_render_surfaces.emitDialogSurfaceWidgetChrome(builder, paint_widget, tokens),
        .drawer => try widget_render_surfaces.emitDrawerSurfaceWidgetChrome(builder, paint_widget, tokens),
        .sheet => try widget_render_surfaces.emitSheetSurfaceWidgetChrome(builder, paint_widget, tokens),
        .accordion, .bubble, .resizable, .panel => try widget_render_surfaces.emitPanelWidgetChrome(builder, paint_widget, tokens),
        .popover => try widget_render_surfaces.emitPopoverWidgetChrome(builder, paint_widget, tokens),
        .menu_surface, .dropdown_menu => try widget_render_surfaces.emitMenuSurfaceWidgetChrome(builder, paint_widget, tokens),
        .text => try emitTextWidget(builder, paint_widget, tokens),
        .icon => try emitIconWidget(builder, paint_widget, tokens),
        .image => try emitImageWidget(builder, paint_widget),
        .avatar => try emitAvatarWidget(builder, paint_widget, tokens),
        .badge => try emitBadgeWidget(builder, paint_widget, tokens),
        .button, .toggle_button => try emitButtonWidget(builder, paint_widget, tokens),
        .icon_button => try emitIconButtonWidget(builder, paint_widget, tokens),
        .select => try emitSelectWidget(builder, paint_widget, tokens),
        .input, .text_field, .textarea => try emitTextFieldWidget(builder, paint_widget, tokens),
        .search_field, .combobox => try emitSearchFieldWidget(builder, paint_widget, tokens),
        .tooltip => try emitTooltipWidget(builder, paint_widget, tokens),
        .menu_item => try emitMenuItemWidget(builder, paint_widget, tokens),
        .list_item => try emitListItemWidget(builder, paint_widget, tokens),
        .data_cell => try emitDataCellWidget(builder, paint_widget, tokens),
        .status_bar => try emitStatusBarWidget(builder, paint_widget, tokens),
        .segmented_control => try emitSegmentedControlWidget(builder, paint_widget, tokens),
        .checkbox => try emitCheckboxWidget(builder, paint_widget, tokens),
        .radio => try emitRadioWidget(builder, paint_widget, tokens),
        .switch_control, .toggle => try emitToggleWidget(builder, paint_widget, tokens),
        .slider => try emitSliderWidget(builder, paint_widget, tokens),
        .progress => try emitProgressWidget(builder, paint_widget, tokens),
        .separator => try emitSeparatorWidget(builder, paint_widget, tokens),
        .skeleton => try emitSkeletonWidget(builder, paint_widget, tokens),
        .spinner => try emitSpinnerWidget(builder, paint_widget, tokens),
    }

    try emitWidgetLayoutClippedChildren(builder, layout, node_index, tokens, state, paint_widget);
}

fn emitWidgetLayoutScrollableChildren(
    builder: *Builder,
    layout: anytype,
    parent_index: usize,
    tokens: DesignTokens,
    state: WidgetRenderState,
    widget: Widget,
) Error!void {
    const clip = if (widget.layout.clip_content) widgetContentClip(widget, tokens) else Clip{
        .id = widgetPartId(widget.id, 1),
        .rect = widget.frame,
    };
    try builder.pushClip(clip);
    try emitWidgetLayoutChildren(builder, layout, parent_index, tokens, state);
    try builder.popClip();
    try widget_render_scroll.emitScrollViewScrollbar(builder, widget.frame, widgetScrollSemantics(layout, parent_index).metrics, tokens, widget.id);
}

fn widgetOpacity(widget: Widget) f32 {
    return std.math.clamp(widget.opacity, 0, 1);
}

fn pixelSnapScale(tokens: DesignTokens) ?f32 {
    const scale = tokens.pixel_snap.scale;
    if (!std.math.isFinite(scale) or scale <= 0) return null;
    return scale;
}

fn pixelSnapValueWithScale(value: f32, scale: f32) f32 {
    return @round(value * scale) / scale;
}

fn pixelSnapGeometryRect(tokens: DesignTokens, rect: geometry.RectF) geometry.RectF {
    if (!tokens.pixel_snap.geometry) return rect;
    const scale = pixelSnapScale(tokens) orelse return rect;
    const normalized = rect.normalized();
    const x0 = pixelSnapValueWithScale(normalized.x, scale);
    const y0 = pixelSnapValueWithScale(normalized.y, scale);
    const x1 = pixelSnapValueWithScale(normalized.maxX(), scale);
    const y1 = pixelSnapValueWithScale(normalized.maxY(), scale);
    return geometry.RectF.init(x0, y0, @max(0, x1 - x0), @max(0, y1 - y0));
}

fn pixelSnapGeometryPoint(tokens: DesignTokens, point: geometry.PointF) geometry.PointF {
    if (!tokens.pixel_snap.geometry) return point;
    const scale = pixelSnapScale(tokens) orelse return point;
    return geometry.PointF.init(
        pixelSnapValueWithScale(point.x, scale),
        pixelSnapValueWithScale(point.y, scale),
    );
}

fn pixelSnapTextPoint(tokens: DesignTokens, point: geometry.PointF) geometry.PointF {
    if (!tokens.pixel_snap.text) return point;
    const scale = pixelSnapScale(tokens) orelse return point;
    return geometry.PointF.init(
        pixelSnapValueWithScale(point.x, scale),
        pixelSnapValueWithScale(point.y, scale),
    );
}

fn emitWidgetBackdropBlur(builder: *Builder, widget: Widget, tokens: DesignTokens) Error!void {
    const radius = widgetBackdropBlur(widget, tokens);
    if (radius <= 0 or widget.frame.normalized().isEmpty()) return;
    try builder.blur(.{
        .id = widgetPartId(widget.id, 12),
        .rect = widget.frame,
        .radius = radius,
    });
}

pub fn widgetBackdropBlur(widget: Widget, tokens: DesignTokens) f32 {
    const explicit = nonNegative(widget.backdrop_blur);
    if (explicit > 0) return explicit;
    if (widget.backdrop_blur_token) |token| return nonNegative(tokens.blur.value(token));
    return 0;
}

fn widgetContentClip(widget: Widget, tokens: DesignTokens) Clip {
    return .{
        .id = widgetPartId(widget.id, 9),
        .rect = widget.frame,
        .radius = widgetContentClipRadius(widget, tokens),
    };
}

fn widgetContentClipRadius(widget: Widget, tokens: DesignTokens) Radius {
    if (!widget.layout.clip_content) return .{};
    return switch (widget.kind) {
        .accordion, .alert, .bubble, .card, .resizable, .panel, .menu_surface, .dropdown_menu => Radius.all(tokens.radius.lg),
        .dialog, .popover => Radius.all(tokens.radius.xl),
        .drawer, .sheet => Radius.all(tokens.radius.lg),
        .tooltip => Radius.all(tokens.radius.md),
        else => .{},
    };
}

fn emitAlertWidget(builder: *Builder, widget: Widget, tokens: DesignTokens, depth: usize) Error!void {
    try widget_render_surfaces.emitAlertWidgetChrome(builder, widget, tokens);
    try emitWidgetClippedChildren(builder, widget, tokens, depth);
}

fn emitCardWidget(builder: *Builder, widget: Widget, tokens: DesignTokens, depth: usize) Error!void {
    try widget_render_surfaces.emitCardWidgetChrome(builder, widget, tokens);
    try emitWidgetClippedChildren(builder, widget, tokens, depth);
}

fn emitDialogSurfaceWidget(builder: *Builder, widget: Widget, tokens: DesignTokens, depth: usize) Error!void {
    try widget_render_surfaces.emitDialogSurfaceWidgetChrome(builder, widget, tokens);
    try emitWidgetClippedChildren(builder, widget, tokens, depth);
}

fn emitDrawerSurfaceWidget(builder: *Builder, widget: Widget, tokens: DesignTokens, depth: usize) Error!void {
    try widget_render_surfaces.emitDrawerSurfaceWidgetChrome(builder, widget, tokens);
    try emitWidgetClippedChildren(builder, widget, tokens, depth);
}

fn emitSheetSurfaceWidget(builder: *Builder, widget: Widget, tokens: DesignTokens, depth: usize) Error!void {
    try widget_render_surfaces.emitSheetSurfaceWidgetChrome(builder, widget, tokens);
    try emitWidgetClippedChildren(builder, widget, tokens, depth);
}

fn emitPanelWidget(builder: *Builder, widget: Widget, tokens: DesignTokens, depth: usize) Error!void {
    try widget_render_surfaces.emitPanelWidgetChrome(builder, widget, tokens);
    if (!accordionChildrenVisible(widget)) return;
    try emitWidgetClippedChildren(builder, widget, tokens, depth);
}

fn emitPopoverWidget(builder: *Builder, widget: Widget, tokens: DesignTokens, depth: usize) Error!void {
    try widget_render_surfaces.emitPopoverWidgetChrome(builder, widget, tokens);
    try emitWidgetClippedChildren(builder, widget, tokens, depth);
}

fn emitMenuSurfaceWidget(builder: *Builder, widget: Widget, tokens: DesignTokens, depth: usize) Error!void {
    try widget_render_surfaces.emitMenuSurfaceWidgetChrome(builder, widget, tokens);
    try emitWidgetClippedChildren(builder, widget, tokens, depth);
}

fn emitScrollViewWidget(builder: *Builder, widget: Widget, tokens: DesignTokens, depth: usize) Error!void {
    try builder.pushClip(.{ .id = widgetPartId(widget.id, 1), .rect = widget.frame });
    try emitWidgetChildren(builder, widget.children, tokens, depth);
    try builder.popClip();
    try widget_render_scroll.emitScrollViewScrollbar(builder, widget.frame, widget_render_scroll.widgetScrollMetricsForWidget(widget, tokens), tokens, widget.id);
}

fn emitWidgetClippedChildren(builder: *Builder, widget: Widget, tokens: DesignTokens, depth: usize) Error!void {
    if (widget.layout.clip_content) try builder.pushClip(widgetContentClip(widget, tokens));
    try emitWidgetChildren(builder, widget.children, tokens, depth);
    if (widget.layout.clip_content) try builder.popClip();
}

fn widgetScrollSemantics(layout: anytype, node_index: usize) widget_semantics.WidgetScrollSemantics {
    return widget_semantics.widgetScrollSemantics(layout, node_index, widget_layout.virtualWidgetScrollContentExtent);
}

fn emitWidgetLayoutClippedChildren(
    builder: *Builder,
    layout: anytype,
    parent_index: usize,
    tokens: DesignTokens,
    state: WidgetRenderState,
    widget: Widget,
) Error!void {
    if (widget.layout.clip_content) try builder.pushClip(widgetContentClip(widget, tokens));
    try emitWidgetLayoutChildren(builder, layout, parent_index, tokens, state);
    if (widget.layout.clip_content) try builder.popClip();
}

fn emitTextWidget(builder: *Builder, widget: Widget, tokens: DesignTokens) Error!void {
    const text_size = widgetBodyTextSize(widget, tokens);
    try builder.drawText(.{
        .id = widgetPartId(widget.id, 1),
        .font_id = tokens.typography.font_id,
        .size = text_size,
        .origin = pixelSnapTextPoint(tokens, textOrigin(widget.frame, text_size, 0)),
        .color = widgetForegroundColor(widget, tokens, tokens.colors.text),
        .text = widget.text,
        .text_layout = .{
            .max_width = widget.frame.width,
            .line_height = text_size * 1.25,
            .wrap = .word,
            .alignment = widget.text_alignment,
        },
    });
}

fn emitIconWidget(builder: *Builder, widget: Widget, tokens: DesignTokens) Error!void {
    if (widget.text.len == 0) return;
    const size = iconGlyphSize(widget, tokens);
    try builder.drawText(.{
        .id = widgetPartId(widget.id, 1),
        .font_id = tokens.typography.font_id,
        .size = size,
        .origin = pixelSnapTextPoint(tokens, centeredTextOrigin(widget.frame, widget.text, size)),
        .color = widgetForegroundColor(widget, tokens, tokens.colors.text),
        .text = widget.text,
    });
}

fn emitImageWidget(builder: *Builder, widget: Widget) Error!void {
    if (widget.image_id == 0 or widget.frame.normalized().isEmpty()) return;
    const clips_image = widget.image_fit == .cover;
    if (clips_image) try builder.pushClip(.{ .id = widgetPartId(widget.id, 2), .rect = widget.frame });
    try builder.drawImage(.{
        .id = widgetPartId(widget.id, 1),
        .image_id = widget.image_id,
        .src = widget.image_src,
        .dst = widget.frame,
        .opacity = widget.image_opacity,
        .fit = widget.image_fit,
        .sampling = widget.image_sampling,
    });
    if (clips_image) try builder.popClip();
}

fn emitAvatarWidget(builder: *Builder, widget: Widget, tokens: DesignTokens) Error!void {
    const visual = componentControlVisualTokens(widget, tokens);
    const radius = componentPillRadius(widget, visual, widget.frame.height * 0.5);
    const background = widgetBackgroundColor(widget, visual.background orelse tokens.colors.surface_subtle);
    try builder.fillRoundedRect(.{
        .id = widgetPartId(widget.id, 1),
        .rect = widget.frame,
        .radius = radius,
        .fill = colorFill(background),
    });

    if (widget.image_id != 0) {
        try builder.pushClip(.{
            .id = widgetPartId(widget.id, 2),
            .rect = widget.frame,
            .radius = radius,
        });
        try builder.drawImage(.{
            .id = widgetPartId(widget.id, 3),
            .image_id = widget.image_id,
            .src = widget.image_src,
            .dst = widget.frame,
            .opacity = widget.image_opacity,
            .fit = widget.image_fit,
            .sampling = widget.image_sampling,
        });
        try builder.popClip();
    } else if (widget.text.len > 0) {
        const text_size = widgetLabelTextSize(widget, tokens);
        try builder.drawText(.{
            .id = widgetPartId(widget.id, 3),
            .font_id = tokens.typography.font_id,
            .size = text_size,
            .origin = pixelSnapTextPoint(tokens, centeredTextOrigin(widget.frame, widget.text, text_size)),
            .color = widgetForegroundColor(widget, tokens, visual.foreground orelse tokens.colors.text_muted),
            .text = widget.text,
            .text_layout = boundedTextLayout(widget.frame, text_size, 0, .center, .none),
        });
    }

    try builder.strokeRect(.{
        .id = widgetPartId(widget.id, 4),
        .rect = widget.frame,
        .radius = radius,
        .stroke = .{
            .fill = widgetBorderFill(widget, visual.border orelse tokens.colors.border),
            .width = controlStrokeWidth(widget, visual, tokens.stroke.hairline),
        },
    });
}

fn emitBadgeWidget(builder: *Builder, widget: Widget, tokens: DesignTokens) Error!void {
    const visual = componentControlVisualTokens(widget, tokens);
    const radius = componentPillRadius(widget, visual, widget.frame.height * 0.5);
    const text_size = widgetLabelTextSize(widget, tokens);
    const text_inset = widgetControlInset(widget, tokens, tokens.spacing.sm);
    try builder.fillRoundedRect(.{
        .id = widgetPartId(widget.id, 1),
        .rect = widget.frame,
        .radius = radius,
        .fill = colorFill(badgeBackgroundColor(widget, tokens, visual)),
    });
    try builder.strokeRect(.{
        .id = widgetPartId(widget.id, 2),
        .rect = widget.frame,
        .radius = radius,
        .stroke = .{
            .fill = widgetBorderFill(widget, badgeBorderColor(widget, tokens, visual)),
            .width = badgeStrokeWidth(widget, tokens, visual),
        },
    });
    if (widget.text.len > 0) {
        try builder.drawText(.{
            .id = widgetPartId(widget.id, 3),
            .font_id = tokens.typography.font_id,
            .size = text_size,
            .origin = pixelSnapTextPoint(tokens, boundedTextOrigin(widget.frame, text_size, text_inset)),
            .color = badgeTextColor(widget, tokens, visual),
            .text = widget.text,
            .text_layout = boundedTextLayout(widget.frame, text_size, text_inset, .center, .none),
        });
    }
}

fn emitSeparatorWidget(builder: *Builder, widget: Widget, tokens: DesignTokens) Error!void {
    const visual = componentControlVisualTokens(widget, tokens);
    const normalized = widget.frame.normalized();
    if (normalized.isEmpty()) return;
    const thickness = controlStrokeWidth(widget, visual, tokens.stroke.hairline);
    const line_rect = if (normalized.width >= normalized.height)
        geometry.RectF.init(normalized.x, normalized.y + (normalized.height - thickness) * 0.5, normalized.width, thickness)
    else
        geometry.RectF.init(normalized.x + (normalized.width - thickness) * 0.5, normalized.y, thickness, normalized.height);
    try builder.fillRect(.{
        .id = widgetPartId(widget.id, 1),
        .rect = pixelSnapGeometryRect(tokens, line_rect),
        .fill = colorFill(widgetBackgroundColor(widget, visual.background orelse visual.border orelse tokens.colors.border)),
    });
}

fn emitStatusBarWidget(builder: *Builder, widget: Widget, tokens: DesignTokens) Error!void {
    const frame = widget.frame.normalized();
    if (frame.isEmpty()) return;

    try builder.fillRect(.{
        .id = widgetPartId(widget.id, 1),
        .rect = pixelSnapGeometryRect(tokens, frame),
        .fill = colorFill(widgetBackgroundColor(widget, tokens.colors.surface)),
    });

    const separator_height = @max(tokens.stroke.hairline, widget.style.stroke_width orelse tokens.stroke.hairline);
    try builder.fillRect(.{
        .id = widgetPartId(widget.id, 2),
        .rect = pixelSnapGeometryRect(tokens, geometry.RectF.init(frame.x, frame.y, frame.width, separator_height)),
        .fill = widgetBorderFill(widget, tokens.colors.border),
    });

    if (widget.text.len == 0) return;

    const text_size = widgetBodyTextSize(widget, tokens);
    const padding = widgetStatusBarPadding(widget);
    const content = frame.inset(padding).normalized();
    if (content.isEmpty()) return;
    const line_height = text_size * 1.25;
    const text_frame = geometry.RectF.init(
        content.x,
        frame.y + @max(0, (frame.height - line_height) * 0.5),
        content.width,
        @min(content.height, line_height),
    );
    try builder.drawText(.{
        .id = widgetPartId(widget.id, 3),
        .font_id = tokens.typography.font_id,
        .size = text_size,
        .origin = pixelSnapTextPoint(tokens, textOrigin(text_frame, text_size, 0)),
        .color = widgetForegroundColor(widget, tokens, tokens.colors.text),
        .text = widget.text,
        .text_layout = .{
            .max_width = text_frame.width,
            .line_height = line_height,
            .wrap = .none,
            .alignment = widget.text_alignment,
        },
    });
}

pub fn widgetStatusBarPadding(widget: Widget) geometry.InsetsF {
    const padding = widget.layout.padding;
    if (padding.top == 0 and padding.right == 0 and padding.bottom == 0 and padding.left == 0) {
        return geometry.InsetsF.symmetric(7, 14);
    }
    return padding;
}

fn emitSkeletonWidget(builder: *Builder, widget: Widget, tokens: DesignTokens) Error!void {
    const visual = componentControlVisualTokens(widget, tokens);
    try builder.fillRoundedRect(.{
        .id = widgetPartId(widget.id, 1),
        .rect = widget.frame,
        .radius = controlRadius(widget, visual, tokens.radius.md),
        .fill = colorFill(widgetBackgroundColor(widget, visual.background orelse tokens.colors.surface_subtle)),
    });
}

fn emitSpinnerWidget(builder: *Builder, widget: Widget, tokens: DesignTokens) Error!void {
    const visual = componentControlVisualTokens(widget, tokens);
    const normalized = widget.frame.normalized();
    if (normalized.isEmpty()) return;
    const size = @min(normalized.width, normalized.height);
    if (size <= 0) return;

    const center = geometry.PointF.init(normalized.x + normalized.width * 0.5, normalized.y + normalized.height * 0.5);
    const radius = size * 0.42;
    const inner = radius * 0.58;
    const stroke_width = controlStrokeWidth(widget, visual, @max(1, size * 0.09));
    const color = widgetForegroundColor(widget, tokens, visual.foreground orelse visual.active_background orelse tokens.colors.accent);
    const phase = @as(usize, @intFromFloat(@floor(std.math.clamp(widget.value, 0, 1) * 8))) % spinner_segments.len;

    for (spinner_segments, 0..) |segment, index| {
        const segment_index = (index + phase) % spinner_segments.len;
        const alpha = 0.28 + @as(f32, @floatFromInt(segment_index)) * 0.09;
        try builder.drawLine(.{
            .id = widgetPartId(widget.id, @as(ObjectId, @intCast(index + 1))),
            .from = pixelSnapGeometryPoint(tokens, geometry.PointF.init(center.x + segment.x * inner, center.y + segment.y * inner)),
            .to = pixelSnapGeometryPoint(tokens, geometry.PointF.init(center.x + segment.x * radius, center.y + segment.y * radius)),
            .stroke = .{
                .fill = colorFill(colorWithAlpha(color, alpha)),
                .width = stroke_width,
            },
        });
    }
}

fn emitButtonWidget(builder: *Builder, widget: Widget, tokens: DesignTokens) Error!void {
    const visual = buttonControlVisualTokens(widget, tokens);
    const radius = controlRadius(widget, visual, tokens.radius.md);
    const text_size = widgetButtonTextSize(widget, tokens);
    const text_inset = widgetButtonInset(widget, tokens);
    try builder.fillRoundedRect(.{
        .id = widgetPartId(widget.id, 1),
        .rect = widget.frame,
        .radius = radius,
        .fill = buttonFill(widget, tokens),
    });
    try builder.strokeRect(.{
        .id = widgetPartId(widget.id, 2),
        .rect = widget.frame,
        .radius = radius,
        .stroke = .{
            .fill = buttonBorderFill(widget, tokens),
            .width = buttonStrokeWidth(widget, tokens),
        },
    });
    if (widget.state.focused) {
        try builder.strokeRect(.{
            .id = widgetPartId(widget.id, 3),
            .rect = widget.frame,
            .radius = radius,
            .stroke = .{
                .fill = widgetFocusRingFill(widget, tokens),
                .width = tokens.stroke.focus,
            },
        });
    }
    try builder.drawText(.{
        .id = widgetPartId(widget.id, 4),
        .font_id = tokens.typography.font_id,
        .size = text_size,
        .origin = pixelSnapTextPoint(tokens, boundedTextOrigin(widget.frame, text_size, text_inset)),
        .color = buttonTextColorForWidget(widget, tokens),
        .text = widget.text,
        .text_layout = boundedTextLayout(widget.frame, text_size, text_inset, .center, .none),
    });
}

fn emitIconButtonWidget(builder: *Builder, widget: Widget, tokens: DesignTokens) Error!void {
    const visual = buttonControlVisualTokens(widget, tokens);
    const radius = controlRadius(widget, visual, tokens.radius.md);
    try builder.fillRoundedRect(.{
        .id = widgetPartId(widget.id, 1),
        .rect = widget.frame,
        .radius = radius,
        .fill = buttonFill(widget, tokens),
    });
    try builder.strokeRect(.{
        .id = widgetPartId(widget.id, 2),
        .rect = widget.frame,
        .radius = radius,
        .stroke = .{
            .fill = if (widget.state.focused) widgetFocusRingFill(widget, tokens) else buttonBorderFill(widget, tokens),
            .width = if (widget.state.focused) tokens.stroke.focus else buttonStrokeWidth(widget, tokens),
        },
    });
    if (widget.text.len > 0) {
        const size = iconGlyphSize(widget, tokens);
        try builder.drawText(.{
            .id = widgetPartId(widget.id, 3),
            .font_id = tokens.typography.font_id,
            .size = size,
            .origin = pixelSnapTextPoint(tokens, centeredTextOrigin(widget.frame, widget.text, size)),
            .color = buttonTextColorForWidget(widget, tokens),
            .text = widget.text,
        });
    }
}

fn emitSelectWidget(builder: *Builder, widget: Widget, tokens: DesignTokens) Error!void {
    const visual = selectControlVisualTokens(tokens);
    const radius = controlRadius(widget, visual, tokens.radius.md);
    const text_size = widgetBodyTextSize(widget, tokens);
    const inset = widgetControlInset(widget, tokens, tokens.spacing.md);
    const chevron_size = @max(widgetSizedDensityValue(widget, tokens, 8), text_size - 4);
    const chevron_extent = chevron_size + inset;
    const text_frame = geometry.RectF.init(
        widget.frame.x + inset,
        widget.frame.y,
        @max(1, widget.frame.width - inset * 2 - chevron_extent),
        widget.frame.height,
    );
    const placeholder = widgetPlaceholder(widget);
    const visible_text = if (widget.text.len > 0) widget.text else placeholder;
    const is_placeholder = widget.text.len == 0 and placeholder.len > 0;

    try builder.fillRoundedRect(.{
        .id = widgetPartId(widget.id, 1),
        .rect = widget.frame,
        .radius = radius,
        .fill = colorFill(widgetBackgroundColor(widget, buttonStateBackground(visual, widget.state.pressed, widget.state.hovered, tokens.colors.surface))),
    });
    try builder.strokeRect(.{
        .id = widgetPartId(widget.id, 2),
        .rect = widget.frame,
        .radius = radius,
        .stroke = .{
            .fill = if (widget.state.focused) widgetFocusRingFill(widget, tokens) else widgetBorderFill(widget, visual.border orelse tokens.colors.border),
            .width = if (widget.state.focused) tokens.stroke.focus else controlStrokeWidth(widget, visual, tokens.stroke.regular),
        },
    });
    if (visible_text.len > 0) {
        const text_color = if (is_placeholder)
            widgetForegroundColor(widget, tokens, tokens.colors.text_muted)
        else
            widgetForegroundColor(widget, tokens, visual.foreground orelse tokens.colors.text);
        try builder.drawText(.{
            .id = widgetPartId(widget.id, 3),
            .font_id = tokens.typography.font_id,
            .size = text_size,
            .origin = pixelSnapTextPoint(tokens, boundedTextOrigin(text_frame, text_size, 0)),
            .color = text_color,
            .text = visible_text,
            .text_layout = boundedTextLayout(text_frame, text_size, 0, .start, .none),
        });
    }
    try emitSelectChevron(builder, widget, tokens, visual, inset, chevron_size);
}

fn emitSelectChevron(builder: *Builder, widget: Widget, tokens: DesignTokens, visual: ControlVisualTokens, inset: f32, chevron_size: f32) Error!void {
    const center = geometry.PointF.init(widget.frame.x + widget.frame.width - inset - chevron_size * 0.5, widget.frame.y + widget.frame.height * 0.5);
    const half = chevron_size * 0.36;
    const drop = chevron_size * 0.28;
    const left = pixelSnapGeometryPoint(tokens, geometry.PointF.init(center.x - half, center.y - drop * 0.5));
    const mid = pixelSnapGeometryPoint(tokens, geometry.PointF.init(center.x, center.y + drop * 0.5));
    const right = pixelSnapGeometryPoint(tokens, geometry.PointF.init(center.x + half, center.y - drop * 0.5));
    const stroke = Stroke{
        .fill = colorFill(widgetForegroundColor(widget, tokens, visual.foreground orelse tokens.colors.text_muted)),
        .width = tokens.stroke.regular,
    };
    try builder.drawLine(.{ .id = widgetPartId(widget.id, 4), .from = left, .to = mid, .stroke = stroke });
    try builder.drawLine(.{ .id = widgetPartId(widget.id, 5), .from = mid, .to = right, .stroke = stroke });
}

fn emitTextFieldWidget(builder: *Builder, widget: Widget, tokens: DesignTokens) Error!void {
    const visual = textInputControlVisualTokens(widget, tokens);
    const radius = controlRadius(widget, visual, tokens.radius.md);
    const text_size = widgetTextInputSize(widget, tokens);
    const text_inset = widgetTextInputInset(widget, tokens);
    const layout_options = widgetTextInputLayoutOptions(widget, text_size, text_inset);
    const clip_rect = widgetTextInputClipRect(widget, tokens, text_size, text_inset, layout_options);
    const origin = widgetTextInputOrigin(widget, tokens, text_size, text_inset, layout_options);
    const text_color = widgetForegroundColor(widget, tokens, visual.foreground orelse tokens.colors.text);
    const draw_text = widgetTextInputDrawText(widget, tokens, text_size, origin, text_color, layout_options);
    const selection_range = widgetTextSelectionRange(widget);
    const composition_range = widgetTextCompositionRange(widget);
    const has_text_affordances = selection_range != null or composition_range != null;
    const clips_text = widget.kind == .textarea;

    try builder.fillRoundedRect(.{
        .id = widgetPartId(widget.id, 1),
        .rect = widget.frame,
        .radius = radius,
        .fill = textInputFill(widget, tokens, visual),
    });
    try builder.strokeRect(.{
        .id = widgetPartId(widget.id, 2),
        .rect = widget.frame,
        .radius = radius,
        .stroke = .{
            .fill = if (widget.state.focused) widgetFocusRingFill(widget, tokens) else textInputBorderFill(widget, visual, tokens.colors.border),
            .width = if (widget.state.focused) tokens.stroke.focus else controlStrokeWidth(widget, visual, tokens.stroke.regular),
        },
    });
    if (clips_text) try builder.pushClip(.{ .id = widgetPartId(widget.id, 16), .rect = clip_rect, .radius = radius });
    if (selection_range) |range| {
        if (!range.isCollapsed(widget.text.len)) {
            try emitWidgetTextSelectionRects(builder, widget, draw_text, layout_options, range, 3, 13, max_widget_text_range_rects, tokens);
        }
    }
    const placeholder = widgetPlaceholder(widget);
    const visible_text = if (widget.text.len > 0) widget.text else placeholder;
    if (visible_text.len > 0) {
        var command = draw_text;
        command.id = widgetPartId(widget.id, if (has_text_affordances) 4 else 3);
        command.text = visible_text;
        if (widget.text.len == 0) {
            command.color = widgetForegroundColor(widget, tokens, tokens.colors.text_muted);
        }
        try builder.drawText(command);
    }
    if (composition_range) |range| {
        if (!range.isCollapsed(widget.text.len)) {
            try emitWidgetTextCompositionLines(builder, widget, draw_text, layout_options, range, 5, 10, max_widget_text_range_rects, tokens);
        }
    }
    if (widget.state.focused) {
        if (selection_range) |range| {
            if (range.isCollapsed(widget.text.len)) {
                try emitWidgetTextCaret(builder, widget, draw_text, layout_options, range.start, 6, tokens);
            }
        }
    }
    if (clips_text) try builder.popClip();
}

fn emitSearchFieldWidget(builder: *Builder, widget: Widget, tokens: DesignTokens) Error!void {
    const visual = textInputControlVisualTokens(widget, tokens);
    const radius = controlRadius(widget, visual, tokens.radius.md);
    const text_size = widgetTextInputSize(widget, tokens);
    const icon_size = @max(8, text_size - 2);
    const text_inset = widgetTextInputInset(widget, tokens);
    const layout_options = widgetTextInputLayoutOptions(widget, text_size, text_inset);
    const origin = widgetTextInputOrigin(widget, tokens, text_size, text_inset, layout_options);
    const selection_range = widgetTextSelectionRange(widget);
    const composition_range = widgetTextCompositionRange(widget);
    const text_color = widgetForegroundColor(widget, tokens, visual.foreground orelse tokens.colors.text);
    const draw_text = widgetTextInputDrawText(widget, tokens, text_size, origin, text_color, layout_options);

    try builder.fillRoundedRect(.{
        .id = widgetPartId(widget.id, 1),
        .rect = widget.frame,
        .radius = radius,
        .fill = textInputFill(widget, tokens, visual),
    });
    try builder.strokeRect(.{
        .id = widgetPartId(widget.id, 2),
        .rect = widget.frame,
        .radius = radius,
        .stroke = .{
            .fill = if (widget.state.focused) widgetFocusRingFill(widget, tokens) else textInputBorderFill(widget, visual, tokens.colors.border),
            .width = if (widget.state.focused) tokens.stroke.focus else controlStrokeWidth(widget, visual, tokens.stroke.regular),
        },
    });
    try emitSearchFieldIcon(builder, widget, tokens, icon_size);
    if (selection_range) |range| {
        if (!range.isCollapsed(widget.text.len)) {
            try emitWidgetTextSelectionRects(builder, widget, draw_text, layout_options, range, 8, 0, 1, tokens);
        }
    }
    const placeholder = widgetPlaceholder(widget);
    const visible_text = if (widget.text.len > 0) widget.text else placeholder;
    if (visible_text.len > 0) {
        var command = draw_text;
        command.id = widgetPartId(widget.id, 9);
        command.text = visible_text;
        command.color = if (widget.text.len > 0) text_color else widgetForegroundColor(widget, tokens, visual.foreground orelse tokens.colors.text_muted);
        try builder.drawText(command);
    }
    if (composition_range) |range| {
        if (!range.isCollapsed(widget.text.len)) {
            try emitWidgetTextCompositionLines(builder, widget, draw_text, layout_options, range, 10, 0, 1, tokens);
        }
    }
    if (widget.state.focused) {
        if (selection_range) |range| {
            if (range.isCollapsed(widget.text.len)) {
                try emitWidgetTextCaret(builder, widget, draw_text, layout_options, range.start, 11, tokens);
            }
        }
    }
    if (widget.kind == .combobox) {
        try emitComboboxChevron(builder, widget, tokens, visual, text_size);
    }
}

fn emitComboboxChevron(builder: *Builder, widget: Widget, tokens: DesignTokens, visual: ControlVisualTokens, text_size: f32) Error!void {
    const inset = widgetControlInset(widget, tokens, tokens.spacing.md);
    const chevron_size = @max(widgetSizedDensityValue(widget, tokens, 8), text_size - 4);
    const center = geometry.PointF.init(widget.frame.x + widget.frame.width - inset - chevron_size * 0.5, widget.frame.y + widget.frame.height * 0.5);
    const half = chevron_size * 0.36;
    const drop = chevron_size * 0.28;
    const left = pixelSnapGeometryPoint(tokens, geometry.PointF.init(center.x - half, center.y - drop * 0.5));
    const mid = pixelSnapGeometryPoint(tokens, geometry.PointF.init(center.x, center.y + drop * 0.5));
    const right = pixelSnapGeometryPoint(tokens, geometry.PointF.init(center.x + half, center.y - drop * 0.5));
    const stroke = Stroke{
        .fill = colorFill(widgetForegroundColor(widget, tokens, visual.foreground orelse tokens.colors.text_muted)),
        .width = tokens.stroke.regular,
    };
    try builder.drawLine(.{ .id = widgetPartId(widget.id, 12), .from = left, .to = mid, .stroke = stroke });
    try builder.drawLine(.{ .id = widgetPartId(widget.id, 13), .from = mid, .to = right, .stroke = stroke });
}

fn emitSearchFieldIcon(builder: *Builder, widget: Widget, tokens: DesignTokens, icon_size: f32) Error!void {
    const left = widget.frame.x + widgetControlInset(widget, tokens, tokens.spacing.md);
    const top = widget.frame.y + @max(0, (widget.frame.height - icon_size) * 0.5);
    const box = icon_size * 0.58;
    const p0 = pixelSnapGeometryPoint(tokens, geometry.PointF.init(left, top));
    const p1 = pixelSnapGeometryPoint(tokens, geometry.PointF.init(left + box, top));
    const p2 = pixelSnapGeometryPoint(tokens, geometry.PointF.init(left + box, top + box));
    const p3 = pixelSnapGeometryPoint(tokens, geometry.PointF.init(left, top + box));
    const tail = pixelSnapGeometryPoint(tokens, geometry.PointF.init(left + icon_size, top + icon_size));
    const visual = textInputControlVisualTokens(widget, tokens);
    const stroke = Stroke{ .fill = colorFill(widgetForegroundColor(widget, tokens, visual.foreground orelse tokens.colors.text_muted)), .width = tokens.stroke.regular };

    try builder.drawLine(.{ .id = widgetPartId(widget.id, 3), .from = p0, .to = p1, .stroke = stroke });
    try builder.drawLine(.{ .id = widgetPartId(widget.id, 4), .from = p1, .to = p2, .stroke = stroke });
    try builder.drawLine(.{ .id = widgetPartId(widget.id, 5), .from = p2, .to = p3, .stroke = stroke });
    try builder.drawLine(.{ .id = widgetPartId(widget.id, 6), .from = p3, .to = p0, .stroke = stroke });
    try builder.drawLine(.{ .id = widgetPartId(widget.id, 7), .from = p2, .to = tail, .stroke = stroke });
}

fn emitTooltipWidget(builder: *Builder, widget: Widget, tokens: DesignTokens) Error!void {
    const visual = surfaceControlVisualTokens(widget, tokens);
    const radius = controlRadius(widget, visual, tokens.radius.md);
    const shadow_token = tokens.shadow.sm;
    if (shadow_token.y != 0 or shadow_token.blur != 0 or shadow_token.spread != 0) {
        try builder.shadow(.{
            .id = widgetPartId(widget.id, 1),
            .rect = widget.frame,
            .radius = radius,
            .offset = .{ .dx = 0, .dy = shadow_token.y },
            .blur = shadow_token.blur,
            .spread = shadow_token.spread,
            .color = tokens.colors.shadow,
        });
    }
    try builder.fillRoundedRect(.{
        .id = widgetPartId(widget.id, 2),
        .rect = widget.frame,
        .radius = radius,
        .fill = widgetAccentFill(widget, buttonStateBackground(visual, widget.state.pressed or widget.state.selected, widget.state.hovered, tokens.colors.accent)),
    });
    if (widget.text.len > 0) {
        const text_size = widgetLabelTextSize(widget, tokens);
        const text_inset = widgetControlInset(widget, tokens, tokens.spacing.sm);
        try builder.drawText(.{
            .id = widgetPartId(widget.id, 3),
            .font_id = tokens.typography.font_id,
            .size = text_size,
            .origin = pixelSnapTextPoint(tokens, boundedTextOrigin(widget.frame, text_size, text_inset)),
            .color = widgetAccentForegroundColor(widget, tokens, visual.foreground orelse tokens.colors.accent_text),
            .text = widget.text,
            .text_layout = boundedTextLayout(widget.frame, text_size, text_inset, .start, .none),
        });
    }
}

fn emitMenuItemWidget(builder: *Builder, widget: Widget, tokens: DesignTokens) Error!void {
    try emitListItemWidget(builder, widget, tokens);
}

fn emitListItemWidget(builder: *Builder, widget: Widget, tokens: DesignTokens) Error!void {
    const visual = listItemControlVisualTokens(widget, tokens);
    const radius = controlRadius(widget, visual, tokens.radius.md);
    const fill = listItemFillColor(widget, tokens, widget.state);
    if (fill.a > 0) {
        try builder.fillRoundedRect(.{
            .id = widgetPartId(widget.id, 1),
            .rect = widget.frame,
            .radius = radius,
            .fill = widgetBackgroundFill(widget, fill),
        });
    }
    if (widget.state.focused) try emitWidgetFocusRing(builder, widget, tokens, 2);
    const text_size = widgetBodyTextSize(widget, tokens);
    const text_inset = widgetControlInset(widget, tokens, tokens.spacing.md);
    try builder.drawText(.{
        .id = widgetPartId(widget.id, 3),
        .font_id = tokens.typography.font_id,
        .size = text_size,
        .origin = pixelSnapTextPoint(tokens, boundedTextOrigin(widget.frame, text_size, text_inset)),
        .color = widgetForegroundColor(widget, tokens, visual.foreground orelse tokens.colors.text),
        .text = widget.text,
        .text_layout = boundedTextLayout(widget.frame, text_size, text_inset, .start, .none),
    });
}

fn emitDataCellWidget(builder: *Builder, widget: Widget, tokens: DesignTokens) Error!void {
    const visual = listItemControlVisualTokens(widget, tokens);
    const state_fill = listItemFillColor(widget, tokens, widget.state);
    if (state_fill.a > 0) {
        try builder.fillRect(.{
            .id = widgetPartId(widget.id, 1),
            .rect = widget.frame,
            .fill = widgetBackgroundFill(widget, state_fill),
        });
    }
    try builder.strokeRect(.{
        .id = widgetPartId(widget.id, 2),
        .rect = widget.frame,
        .stroke = .{
            .fill = widgetBorderFill(widget, visual.border orelse tokens.colors.border),
            .width = controlStrokeWidth(widget, visual, tokens.stroke.hairline),
        },
    });
    if (widget.state.focused) try emitWidgetFocusRing(builder, widget, tokens, 3);
    if (widget.text.len > 0) {
        const text_size = widgetBodyTextSize(widget, tokens);
        const text_inset = widgetControlInset(widget, tokens, tokens.spacing.md);
        try builder.drawText(.{
            .id = widgetPartId(widget.id, 4),
            .font_id = tokens.typography.font_id,
            .size = text_size,
            .origin = pixelSnapTextPoint(tokens, boundedTextOrigin(widget.frame, text_size, text_inset)),
            .color = widgetForegroundColor(widget, tokens, visual.foreground orelse tokens.colors.text),
            .text = widget.text,
            .text_layout = boundedTextLayout(widget.frame, text_size, text_inset, .start, .none),
        });
    }
}

fn emitSegmentedControlWidget(builder: *Builder, widget: Widget, tokens: DesignTokens) Error!void {
    const selected = widget.state.selected or widget.value >= 0.5;
    const visual = selectionControlVisualTokens(widget, tokens);
    const radius = controlRadius(widget, visual, tokens.radius.md);
    const text_size = widgetLabelTextSize(widget, tokens);
    const text_inset = widgetControlInset(widget, tokens, tokens.spacing.md);
    try builder.fillRoundedRect(.{
        .id = widgetPartId(widget.id, 1),
        .rect = widget.frame,
        .radius = radius,
        .fill = if (selected)
            colorFill(widgetAccentColor(widget, visual.active_background orelse tokens.colors.accent))
        else
            colorFill(widgetBackgroundColor(widget, buttonStateBackground(visual, false, widget.state.hovered, tokens.colors.surface))),
    });
    try builder.strokeRect(.{
        .id = widgetPartId(widget.id, 2),
        .rect = widget.frame,
        .radius = radius,
        .stroke = .{
            .fill = if (widget.state.focused) widgetFocusRingFill(widget, tokens) else widgetBorderFill(widget, visual.border orelse tokens.colors.border),
            .width = if (widget.state.focused) tokens.stroke.focus else controlStrokeWidth(widget, visual, tokens.stroke.regular),
        },
    });
    try builder.drawText(.{
        .id = widgetPartId(widget.id, 3),
        .font_id = tokens.typography.font_id,
        .size = text_size,
        .origin = pixelSnapTextPoint(tokens, boundedTextOrigin(widget.frame, text_size, text_inset)),
        .color = if (selected) widgetAccentForegroundColor(widget, tokens, visual.foreground orelse tokens.colors.accent_text) else widgetForegroundColor(widget, tokens, visual.foreground orelse tokens.colors.text),
        .text = widget.text,
        .text_layout = boundedTextLayout(widget.frame, text_size, text_inset, .center, .none),
    });
}

fn emitCheckboxWidget(builder: *Builder, widget: Widget, tokens: DesignTokens) Error!void {
    const visual = selectionControlVisualTokens(widget, tokens);
    const box = checkboxWidgetBoxRect(widget, tokens);
    const selected = booleanControlSelected(widget);
    const radius = controlRadius(widget, visual, tokens.radius.sm);
    try builder.fillRoundedRect(.{
        .id = widgetPartId(widget.id, 1),
        .rect = box,
        .radius = radius,
        .fill = if (selected)
            colorFill(widgetAccentColor(widget, visual.active_background orelse tokens.colors.accent))
        else
            colorFill(widgetBackgroundColor(widget, buttonStateBackground(visual, false, widget.state.hovered, tokens.colors.surface))),
    });
    try builder.strokeRect(.{
        .id = widgetPartId(widget.id, 2),
        .rect = box,
        .radius = radius,
        .stroke = .{
            .fill = if (selected) widgetAccentFill(widget, visual.border orelse visual.active_background orelse tokens.colors.accent) else widgetBorderFill(widget, visual.border orelse tokens.colors.border),
            .width = controlStrokeWidth(widget, visual, tokens.stroke.regular),
        },
    });
    if (widget.state.focused) try emitWidgetFocusRingForRect(builder, widget, tokens, 3, box, radius);
    if (selected) {
        const left = pixelSnapGeometryPoint(tokens, geometry.PointF.init(box.x + box.width * 0.26, box.y + box.height * 0.54));
        const mid = pixelSnapGeometryPoint(tokens, geometry.PointF.init(box.x + box.width * 0.43, box.y + box.height * 0.70));
        const right = pixelSnapGeometryPoint(tokens, geometry.PointF.init(box.x + box.width * 0.76, box.y + box.height * 0.32));
        try builder.drawLine(.{
            .id = widgetPartId(widget.id, 4),
            .from = left,
            .to = mid,
            .stroke = .{ .fill = colorFill(widgetAccentForegroundColor(widget, tokens, visual.foreground orelse tokens.colors.accent_text)), .width = 2 },
        });
        try builder.drawLine(.{
            .id = widgetPartId(widget.id, 5),
            .from = mid,
            .to = right,
            .stroke = .{ .fill = colorFill(widgetAccentForegroundColor(widget, tokens, visual.foreground orelse tokens.colors.accent_text)), .width = 2 },
        });
    }
    try emitControlLabelWithColor(builder, widget, tokens, box.x + box.width + widgetControlInset(widget, tokens, tokens.spacing.sm), 6, visual.foreground orelse tokens.colors.text);
}

fn emitRadioWidget(builder: *Builder, widget: Widget, tokens: DesignTokens) Error!void {
    const visual = selectionControlVisualTokens(widget, tokens);
    const circle = radioWidgetCircleRect(widget, tokens);
    const selected = booleanControlSelected(widget);
    const radius = controlRadius(widget, visual, circle.height * 0.5);
    try builder.fillRoundedRect(.{
        .id = widgetPartId(widget.id, 1),
        .rect = circle,
        .radius = radius,
        .fill = colorFill(widgetBackgroundColor(widget, buttonStateBackground(visual, false, widget.state.hovered, tokens.colors.surface))),
    });
    try builder.strokeRect(.{
        .id = widgetPartId(widget.id, 2),
        .rect = circle,
        .radius = radius,
        .stroke = .{
            .fill = if (selected) widgetAccentFill(widget, visual.border orelse visual.active_background orelse tokens.colors.accent) else widgetBorderFill(widget, visual.border orelse tokens.colors.border),
            .width = controlStrokeWidth(widget, visual, tokens.stroke.regular),
        },
    });
    if (widget.state.focused) try emitWidgetFocusRingForRect(builder, widget, tokens, 3, circle, radius);
    if (selected) {
        const dot_size = @max(0, circle.height * 0.48);
        const dot = pixelSnapGeometryRect(tokens, geometry.RectF.init(
            circle.x + (circle.width - dot_size) * 0.5,
            circle.y + (circle.height - dot_size) * 0.5,
            dot_size,
            dot_size,
        ));
        try builder.fillRoundedRect(.{
            .id = widgetPartId(widget.id, 4),
            .rect = dot,
            .radius = Radius.all(dot.height * 0.5),
            .fill = colorFill(widgetAccentColor(widget, visual.active_background orelse tokens.colors.accent)),
        });
    }
    try emitControlLabelWithColor(builder, widget, tokens, circle.x + circle.width + widgetControlInset(widget, tokens, tokens.spacing.sm), 5, visual.foreground orelse tokens.colors.text);
}

fn emitToggleWidget(builder: *Builder, widget: Widget, tokens: DesignTokens) Error!void {
    const selected = booleanControlSelected(widget);
    const visual = selectionControlVisualTokens(widget, tokens);
    const knob_inset = widgetSizedDensityValue(widget, tokens, 2);
    const track = toggleWidgetTrackRect(widget, tokens);
    const track_radius = controlRadius(widget, visual, track.height * 0.5);
    const knob_size = @max(0, track.height - knob_inset * 2);
    const knob_x = if (selected)
        track.x + track.width - knob_size - knob_inset
    else
        track.x + knob_inset;
    const knob = pixelSnapGeometryRect(tokens, geometry.RectF.init(knob_x, track.y + knob_inset, knob_size, knob_size));

    try builder.fillRoundedRect(.{
        .id = widgetPartId(widget.id, 1),
        .rect = track,
        .radius = track_radius,
        .fill = if (selected)
            colorFill(widgetAccentColor(widget, visual.active_background orelse tokens.colors.accent))
        else
            colorFill(widgetBackgroundColor(widget, buttonStateBackground(visual, false, widget.state.hovered, tokens.colors.surface_pressed))),
    });
    try builder.strokeRect(.{
        .id = widgetPartId(widget.id, 2),
        .rect = track,
        .radius = track_radius,
        .stroke = .{
            .fill = widgetBorderFill(widget, visual.border orelse tokens.colors.border),
            .width = controlStrokeWidth(widget, visual, tokens.stroke.regular),
        },
    });
    try builder.fillRoundedRect(.{
        .id = widgetPartId(widget.id, 3),
        .rect = knob,
        .radius = controlRadius(widget, visual, knob.height * 0.5),
        .fill = colorFill(if (selected) widgetAccentForegroundColor(widget, tokens, visual.foreground orelse tokens.colors.accent_text) else widgetBackgroundColor(widget, visual.foreground orelse tokens.colors.surface)),
    });
    if (widget.state.focused) try emitWidgetFocusRingForRect(builder, widget, tokens, 4, track, track_radius);
    try emitControlLabelWithColor(builder, widget, tokens, track.x + track.width + widgetControlInset(widget, tokens, tokens.spacing.sm), 5, visual.foreground orelse tokens.colors.text);
}

fn emitSliderWidget(builder: *Builder, widget: Widget, tokens: DesignTokens) Error!void {
    const value = std.math.clamp(widget.value, 0, 1);
    const visual = selectionControlVisualTokens(widget, tokens);
    const track = sliderWidgetTrackRect(widget, tokens);
    const active = pixelSnapGeometryRect(tokens, geometry.RectF.init(track.x, track.y, track.width * value, track.height));
    const knob = sliderWidgetKnobRect(widget, tokens);
    const track_radius = controlRadius(widget, visual, track.height * 0.5);
    const knob_radius = controlRadius(widget, visual, knob.height * 0.5);

    try builder.fillRoundedRect(.{
        .id = widgetPartId(widget.id, 1),
        .rect = track,
        .radius = track_radius,
        .fill = colorFill(widgetBackgroundColor(widget, visual.background orelse tokens.colors.surface_pressed)),
    });
    try builder.fillRoundedRect(.{
        .id = widgetPartId(widget.id, 2),
        .rect = active,
        .radius = track_radius,
        .fill = colorFill(widgetAccentColor(widget, visual.active_background orelse tokens.colors.accent)),
    });
    try builder.fillRoundedRect(.{
        .id = widgetPartId(widget.id, 3),
        .rect = knob,
        .radius = knob_radius,
        .fill = colorFill(if (widget.state.disabled) tokens.colors.disabled else widgetBackgroundColor(widget, visual.foreground orelse tokens.colors.surface)),
    });
    try builder.strokeRect(.{
        .id = widgetPartId(widget.id, 4),
        .rect = knob,
        .radius = knob_radius,
        .stroke = .{
            .fill = if (widget.state.focused) widgetFocusRingFill(widget, tokens) else widgetBorderFill(widget, visual.border orelse tokens.colors.border),
            .width = if (widget.state.focused) tokens.stroke.focus else controlStrokeWidth(widget, visual, tokens.stroke.regular),
        },
    });
}

pub fn checkboxWidgetBoxRect(widget: Widget, tokens: DesignTokens) geometry.RectF {
    const box_size = @min(@max(widgetSizedDensityValue(widget, tokens, 14), widget.frame.height * 0.55), widgetSizedDensityValue(widget, tokens, 20));
    return pixelSnapGeometryRect(tokens, geometry.RectF.init(
        widget.frame.x,
        widget.frame.y + (widget.frame.height - box_size) * 0.5,
        box_size,
        box_size,
    ));
}

pub fn radioWidgetCircleRect(widget: Widget, tokens: DesignTokens) geometry.RectF {
    const circle_size = @min(@max(widgetSizedDensityValue(widget, tokens, 14), widget.frame.height * 0.55), widgetSizedDensityValue(widget, tokens, 20));
    return pixelSnapGeometryRect(tokens, geometry.RectF.init(
        widget.frame.x,
        widget.frame.y + (widget.frame.height - circle_size) * 0.5,
        circle_size,
        circle_size,
    ));
}

pub fn toggleWidgetTrackRect(widget: Widget, tokens: DesignTokens) geometry.RectF {
    const track_width = @min(widget.frame.width, @max(widgetSizedDensityValue(widget, tokens, 36), widget.frame.height * 1.75));
    const track_height = @min(widget.frame.height, widgetSizedDensityValue(widget, tokens, 24));
    return pixelSnapGeometryRect(tokens, geometry.RectF.init(
        widget.frame.x,
        widget.frame.y + (widget.frame.height - track_height) * 0.5,
        track_width,
        track_height,
    ));
}

fn sliderWidgetTrackRect(widget: Widget, tokens: DesignTokens) geometry.RectF {
    const track_height: f32 = widgetSizedDensityValue(widget, tokens, 4);
    return pixelSnapGeometryRect(tokens, geometry.RectF.init(
        widget.frame.x,
        widget.frame.y + (widget.frame.height - track_height) * 0.5,
        widget.frame.width,
        track_height,
    ));
}

pub fn sliderWidgetKnobRect(widget: Widget, tokens: DesignTokens) geometry.RectF {
    const value = std.math.clamp(widget.value, 0, 1);
    const knob_size = @min(@max(widgetSizedDensityValue(widget, tokens, 14), widget.frame.height * 0.55), widgetSizedDensityValue(widget, tokens, 20));
    const knob_x = std.math.clamp(
        widget.frame.x + widget.frame.width * value - knob_size * 0.5,
        widget.frame.x,
        widget.frame.x + @max(0, widget.frame.width - knob_size),
    );
    return pixelSnapGeometryRect(tokens, geometry.RectF.init(
        knob_x,
        widget.frame.y + (widget.frame.height - knob_size) * 0.5,
        knob_size,
        knob_size,
    ));
}

fn emitProgressWidget(builder: *Builder, widget: Widget, tokens: DesignTokens) Error!void {
    const progress = std.math.clamp(widget.value, 0, 1);
    const visual = selectionControlVisualTokens(widget, tokens);
    const radius = controlRadius(widget, visual, @min(tokens.radius.md, widget.frame.height * 0.5));
    if (progress < 1) {
        try builder.fillRoundedRect(.{
            .id = widgetPartId(widget.id, 1),
            .rect = widget.frame,
            .radius = radius,
            .fill = colorFill(widgetBackgroundColor(widget, visual.background orelse tokens.colors.surface_pressed)),
        });
    }
    if (progress > 0) {
        try builder.fillRoundedRect(.{
            .id = widgetPartId(widget.id, 2),
            .rect = pixelSnapGeometryRect(tokens, geometry.RectF.init(widget.frame.x, widget.frame.y, widget.frame.width * progress, widget.frame.height)),
            .radius = radius,
            .fill = colorFill(widgetAccentColor(widget, visual.active_background orelse tokens.colors.accent)),
        });
    }
}

fn emitWidgetFocusRing(builder: *Builder, widget: Widget, tokens: DesignTokens, slot: ObjectId) Error!void {
    return emitWidgetFocusRingForRect(builder, widget, tokens, slot, widget.frame, widgetRadius(widget, tokens.radius.md));
}

fn emitWidgetFocusRingForRect(builder: *Builder, widget: Widget, tokens: DesignTokens, slot: ObjectId, rect: geometry.RectF, radius: Radius) Error!void {
    try builder.strokeRect(.{
        .id = widgetPartId(widget.id, slot),
        .rect = rect,
        .radius = radius,
        .stroke = .{
            .fill = widgetFocusRingFill(widget, tokens),
            .width = tokens.stroke.focus,
        },
    });
}

fn emitControlLabel(builder: *Builder, widget: Widget, tokens: DesignTokens, x: f32, slot: ObjectId) Error!void {
    return emitControlLabelWithColor(builder, widget, tokens, x, slot, tokens.colors.text);
}

fn emitControlLabelWithColor(builder: *Builder, widget: Widget, tokens: DesignTokens, x: f32, slot: ObjectId, color: Color) Error!void {
    if (widget.text.len == 0) return;
    const text_size = widgetLabelTextSize(widget, tokens);
    try builder.drawText(.{
        .id = widgetPartId(widget.id, slot),
        .font_id = tokens.typography.font_id,
        .size = text_size,
        .origin = pixelSnapTextPoint(tokens, boundedTextOrigin(labelFrameForControl(widget.frame, x), text_size, 0)),
        .color = widgetForegroundColor(widget, tokens, color),
        .text = widget.text,
        .text_layout = boundedTextLayout(labelFrameForControl(widget.frame, x), text_size, 0, .start, .none),
    });
}

pub fn toggleWidgetKnobCommandId(id: ObjectId) ObjectId {
    return widgetPartId(id, 3);
}

pub fn toggleWidgetKnobTravel(widget: Widget, tokens: DesignTokens) f32 {
    if (!widgetSwitchControlKind(widget.kind)) return 0;
    const knob_inset = densityValue(tokens, 2);
    const track_width = @min(widget.frame.width, @max(densityValue(tokens, 36), widget.frame.height * 1.75));
    const track_height = @min(widget.frame.height, densityValue(tokens, 24));
    const track = pixelSnapGeometryRect(tokens, geometry.RectF.init(
        widget.frame.x,
        widget.frame.y + (widget.frame.height - track_height) * 0.5,
        track_width,
        track_height,
    ));
    const knob_size = @max(0, track.height - knob_inset * 2);
    const off_knob = pixelSnapGeometryRect(tokens, geometry.RectF.init(track.x + knob_inset, track.y + knob_inset, knob_size, knob_size));
    const on_knob = pixelSnapGeometryRect(tokens, geometry.RectF.init(
        track.x + track.width - knob_size - knob_inset,
        track.y + knob_inset,
        knob_size,
        knob_size,
    ));
    return on_knob.x - off_knob.x;
}

fn widgetSwitchControlKind(kind: WidgetKind) bool {
    return kind == .switch_control or kind == .toggle;
}

pub fn widgetPartId(id: ObjectId, slot: ObjectId) ObjectId {
    if (id == 0) return 0;
    const base = id *% 16;
    const part = base +% slot;
    return if (part == 0) id else part;
}

fn textOrigin(frame: geometry.RectF, size: f32, inset: f32) geometry.PointF {
    const line_height = size * 1.25;
    return geometry.PointF.init(
        frame.x + inset,
        frame.y + @max(size, (frame.height - line_height) * 0.5 + size),
    );
}

fn boundedTextOrigin(frame: geometry.RectF, size: f32, inset: f32) geometry.PointF {
    return geometry.PointF.init(frame.x + inset, textOrigin(frame, size, 0).y);
}

fn boundedTextLayout(frame: geometry.RectF, size: f32, inset: f32, alignment: TextAlign, wrap: TextWrap) TextLayoutOptions {
    return .{
        .max_width = @max(1, frame.width - inset * 2),
        .line_height = size * 1.25,
        .wrap = wrap,
        .alignment = alignment,
    };
}

fn labelFrameForControl(frame: geometry.RectF, x: f32) geometry.RectF {
    return geometry.RectF.init(x, frame.y, @max(1, frame.x + frame.width - x), frame.height);
}

fn centeredTextOrigin(frame: geometry.RectF, text: []const u8, size: f32) geometry.PointF {
    return alignedTextOrigin(frame, text, size, 0, .center);
}

fn alignedTextOrigin(frame: geometry.RectF, text: []const u8, size: f32, inset: f32, alignment: TextAlign) geometry.PointF {
    const width = estimateTextWidth(text, size);
    const available_width = @max(0, frame.width - inset * 2);
    const offset = switch (alignment) {
        .start => 0,
        .center => @max(0, (available_width - width) * 0.5),
        .end => @max(0, available_width - width),
    };
    const line_height = size * 1.25;
    return geometry.PointF.init(
        frame.x + inset + offset,
        frame.y + @max(size, (frame.height - line_height) * 0.5 + size),
    );
}

fn iconGlyphSize(widget: Widget, tokens: DesignTokens) f32 {
    const min_size = widgetSizedDensityValue(widget, tokens, 12);
    if (widget.frame.height > 0) return @min(@max(min_size, widget.frame.height * widgetIconGlyphScale(widget)), @max(min_size, widgetTypographySize(widget, tokens.typography.title_size)));
    return widgetButtonTextSize(widget, tokens);
}

fn widgetIconGlyphScale(widget: Widget) f32 {
    return switch (widget.size) {
        .sm => 0.44,
        .default, .icon => 0.48,
        .lg => 0.52,
    };
}

fn emitWidgetTextSelectionRects(
    builder: *Builder,
    widget: Widget,
    text: DrawText,
    options: TextLayoutOptions,
    range: TextRange,
    first_part: ObjectId,
    overflow_first_part: ObjectId,
    max_parts: usize,
    tokens: DesignTokens,
) Error!void {
    var lines: [max_widget_text_layout_lines]TextLine = undefined;
    var rect_buffer: [max_widget_text_range_rects]TextSelectionRect = undefined;
    const rects = try layoutTextSelectionRects(text, options, range, &lines, rect_buffer[0..@min(max_parts, rect_buffer.len)]);
    for (rects, 0..) |selection, index| {
        try builder.fillRoundedRect(.{
            .id = widgetPartId(widget.id, widgetTextRangePart(first_part, overflow_first_part, index)),
            .rect = pixelSnapGeometryRect(tokens, selection.rect),
            .radius = Radius.all(tokens.radius.sm),
            .fill = .{ .color = textSelectionFillColor(widget, tokens) },
        });
    }
}

fn emitWidgetTextCompositionLines(
    builder: *Builder,
    widget: Widget,
    text: DrawText,
    options: TextLayoutOptions,
    range: TextRange,
    first_part: ObjectId,
    overflow_first_part: ObjectId,
    max_parts: usize,
    tokens: DesignTokens,
) Error!void {
    var lines: [max_widget_text_layout_lines]TextLine = undefined;
    var rect_buffer: [max_widget_text_range_rects]TextSelectionRect = undefined;
    const rects = try layoutTextSelectionRects(text, options, range, &lines, rect_buffer[0..@min(max_parts, rect_buffer.len)]);
    for (rects, 0..) |selection, index| {
        const y = pixelSnapGeometryRect(tokens, selection.rect).maxY() - tokens.stroke.regular;
        try builder.drawLine(.{
            .id = widgetPartId(widget.id, widgetTextRangePart(first_part, overflow_first_part, index)),
            .from = pixelSnapGeometryPoint(tokens, geometry.PointF.init(selection.rect.x, y)),
            .to = pixelSnapGeometryPoint(tokens, geometry.PointF.init(selection.rect.x + selection.rect.width, y)),
            .stroke = .{ .fill = .{ .color = textInputAffordanceColor(widget, tokens) }, .width = 1 },
        });
    }
}

fn widgetTextRangePart(first_part: ObjectId, overflow_first_part: ObjectId, index: usize) ObjectId {
    if (index == 0 or overflow_first_part == 0) return first_part + @as(ObjectId, @intCast(index));
    return overflow_first_part + @as(ObjectId, @intCast(index - 1));
}

fn emitWidgetTextCaret(
    builder: *Builder,
    widget: Widget,
    text: DrawText,
    options: TextLayoutOptions,
    offset: usize,
    part: ObjectId,
    tokens: DesignTokens,
) Error!void {
    var lines: [max_widget_text_layout_lines]TextLine = undefined;
    const rect = (try layoutTextCaretRect(text, options, offset, &lines)) orelse return;
    const snapped = pixelSnapGeometryRect(tokens, rect);
    try builder.drawLine(.{
        .id = widgetPartId(widget.id, part),
        .from = geometry.PointF.init(snapped.x, snapped.y),
        .to = geometry.PointF.init(snapped.x, snapped.y + snapped.height),
        .stroke = .{ .fill = .{ .color = textInputAffordanceColor(widget, tokens) }, .width = tokens.stroke.regular },
    });
}

fn widgetWithFrame(widget: Widget, frame: geometry.RectF) Widget {
    var copy = widget;
    copy.frame = frame;
    return copy;
}

fn widgetWithRenderState(widget: Widget, state: WidgetRenderState) Widget {
    var copy = widget;
    if (state.focused_id != null or state.focus_visible_id != null) {
        copy.state.focused = if (state.focus_visible_id) |focus_visible_id|
            copy.id != 0 and copy.id == focus_visible_id
        else
            false;
    }
    if (state.hovered_id) |hovered_id| {
        copy.state.hovered = copy.id != 0 and copy.id == hovered_id;
    }
    if (state.pressed_id) |pressed_id| {
        copy.state.pressed = copy.id != 0 and copy.id == pressed_id;
    }
    return copy;
}

fn accordionChildrenVisible(widget: Widget) bool {
    return widget.kind != .accordion or booleanControlSelected(widget);
}

fn accordionContentFrame(widget: Widget, content: geometry.RectF, tokens: DesignTokens) geometry.RectF {
    const header_height = widgetControlHeight(widget, tokens, tokens.sizes.control_md);
    const gap = nonNegative(widget.layout.gap);
    return geometry.RectF.init(content.x, content.y + header_height + gap, content.width, @max(0, content.height - header_height - gap));
}

fn nonNegative(value: f32) f32 {
    return @max(0, value);
}
