const std = @import("std");
const geometry = @import("geometry");
const canvas = @import("root.zig");
const drawing_model = @import("drawing.zig");
const token_model = @import("tokens.zig");
const widget_model = @import("widgets.zig");
const event_model = @import("events.zig");
const equality_model = @import("equality.zig");
const widget_tree = @import("widget_tree.zig");
const widget_access = @import("widget_access.zig");
const widget_routing = @import("widget_routing.zig");
const widget_semantics = @import("widget_semantics.zig");
const widget_metrics = @import("widget_metrics.zig");
const widget_text_input = @import("widget_text_input.zig");
const widget_layout = @import("widget_layout.zig");
const widget_render = @import("widget_render.zig");

const Error = canvas.Error;
const ObjectId = canvas.ObjectId;
const Builder = canvas.Builder;
const Color = drawing_model.Color;
const Affine = drawing_model.Affine;
const Radius = drawing_model.Radius;
const DesignTokens = token_model.DesignTokens;
const ControlVisualTokens = token_model.ControlVisualTokens;
const VirtualListRange = token_model.VirtualListRange;
const widgetTransform = widget_tree.widgetTransform;
const widgetClipsContent = widget_tree.widgetClipsContent;
const widgetIndexById = widget_tree.widgetIndexById;
const isWidgetHiddenInAncestors = widget_tree.isWidgetHiddenInAncestors;
const WidgetKind = widget_model.WidgetKind;
const WidgetCursor = widget_model.WidgetCursor;
const WidgetState = widget_model.WidgetState;
const WidgetRenderState = widget_model.WidgetRenderState;
const WidgetMainAlignment = widget_model.WidgetMainAlignment;
const WidgetCrossAlignment = widget_model.WidgetCrossAlignment;
const WidgetLayoutStyle = widget_model.WidgetLayoutStyle;
const WidgetStyle = widget_model.WidgetStyle;
const WidgetActions = widget_model.WidgetActions;
const WidgetSemantics = widget_model.WidgetSemantics;
const Widget = widget_model.Widget;
const WidgetLayoutNode = event_model.WidgetLayoutNode;
const WidgetHit = event_model.WidgetHit;
const WidgetPointerEvent = event_model.WidgetPointerEvent;
const WidgetKeyboardEvent = event_model.WidgetKeyboardEvent;
const WidgetFileDropEvent = event_model.WidgetFileDropEvent;
const WidgetDragEvent = event_model.WidgetDragEvent;
const WidgetEventRouteEntry = event_model.WidgetEventRouteEntry;
const WidgetEventRoute = event_model.WidgetEventRoute;
const WidgetKeyboardRoute = event_model.WidgetKeyboardRoute;
const WidgetFocusDirection = event_model.WidgetFocusDirection;
const WidgetFocusTarget = event_model.WidgetFocusTarget;
const WidgetScrollMetrics = event_model.WidgetScrollMetrics;
const WidgetSemanticsNode = event_model.WidgetSemanticsNode;
const WidgetInvalidationKind = event_model.WidgetInvalidationKind;
const WidgetInvalidation = event_model.WidgetInvalidation;
const strokeBounds = drawing_model.strokeBounds;
const shadowBounds = drawing_model.shadowBounds;
const rectsEqual = equality_model.rectsEqual;
const optionalRectsEqual = equality_model.optionalRectsEqual;
const sizesEqual = equality_model.sizesEqual;
const insetsEqual = equality_model.insetsEqual;
const optionalColorsEqual = equality_model.optionalColorsEqual;
const affinesEqual = equality_model.affinesEqual;
const optionalF32Equal = equality_model.optionalF32Equal;
const optionalTextSelectionsEqual = equality_model.optionalTextSelectionsEqual;
const optionalTextRangesEqual = equality_model.optionalTextRangesEqual;

pub const max_widget_depth = widget_layout.max_widget_depth;
pub const max_widget_text_range_rects: usize = 4;
pub const widgetControlHeight = widget_metrics.widgetControlHeight;
pub const WidgetTextGeometry = widget_text_input.WidgetTextGeometry;
pub const textSelectionForWidgetPoint = widget_text_input.textSelectionForWidgetPoint;
pub const textOffsetForWidgetPoint = widget_text_input.textOffsetForWidgetPoint;
pub const textInputViewportForWidget = widget_text_input.textInputViewportForWidget;
pub const textInputContentExtentForWidget = widget_text_input.textInputContentExtentForWidget;
pub const textInputMaxScrollOffsetForWidget = widget_text_input.textInputMaxScrollOffsetForWidget;
pub const clampedTextInputScrollOffsetForWidget = widget_text_input.clampedTextInputScrollOffsetForWidget;
pub const textGeometryForWidget = widget_text_input.textGeometryForWidget;

pub const WidgetLayoutTree = struct {
    nodes: []const WidgetLayoutNode = &.{},

    pub fn nodeCount(self: WidgetLayoutTree) usize {
        return self.nodes.len;
    }

    pub fn findById(self: WidgetLayoutTree, id: ObjectId) ?WidgetLayoutNode {
        if (id == 0) return null;
        for (self.nodes) |node| {
            if (node.widget.id == id) return node;
        }
        return null;
    }

    pub fn virtualRangeById(self: WidgetLayoutTree, id: ObjectId) ?VirtualListRange {
        if (id == 0) return null;
        for (self.nodes) |node| {
            if (node.widget.id == id) return widget_semantics.widgetVirtualRangeForLayoutNode(node);
        }
        return null;
    }

    pub fn virtualRangeAt(self: WidgetLayoutTree, index: usize) ?VirtualListRange {
        if (index >= self.nodes.len) return null;
        return widget_semantics.widgetVirtualRangeForLayoutNode(self.nodes[index]);
    }

    pub fn hitTest(self: WidgetLayoutTree, point: geometry.PointF) ?WidgetHit {
        return widget_routing.hitTestWidgetLayout(self, point, .{});
    }

    pub fn hitTestWithTokens(self: WidgetLayoutTree, point: geometry.PointF, tokens: DesignTokens) ?WidgetHit {
        return widget_routing.hitTestWidgetLayout(self, point, tokens);
    }

    pub fn cursorForHit(self: WidgetLayoutTree, hit: ?WidgetHit) WidgetCursor {
        _ = self;
        return widget_access.cursorForWidgetHit(hit);
    }

    pub fn routePointerEvent(self: WidgetLayoutTree, event: WidgetPointerEvent, output: []WidgetEventRouteEntry) Error!WidgetEventRoute {
        return widget_routing.routeWidgetPointerEvent(self, event, .{}, output);
    }

    pub fn routePointerEventWithTokens(self: WidgetLayoutTree, event: WidgetPointerEvent, tokens: DesignTokens, output: []WidgetEventRouteEntry) Error!WidgetEventRoute {
        return widget_routing.routeWidgetPointerEvent(self, event, tokens, output);
    }

    pub fn routeKeyboardEvent(self: WidgetLayoutTree, event: WidgetKeyboardEvent, output: []WidgetEventRouteEntry) Error!WidgetKeyboardRoute {
        return widget_routing.routeWidgetKeyboardEvent(self, event, output, widgetScrollSemantics);
    }

    pub fn routeFileDropEvent(self: WidgetLayoutTree, event: WidgetFileDropEvent, output: []WidgetEventRouteEntry) Error!WidgetEventRoute {
        return widget_routing.routeWidgetFileDropEvent(self, event, output);
    }

    pub fn routeDragEvent(self: WidgetLayoutTree, event: WidgetDragEvent, output: []WidgetEventRouteEntry) Error!WidgetEventRoute {
        return widget_routing.routeWidgetDragEvent(self, event, output);
    }

    pub fn focusTarget(self: WidgetLayoutTree, current_id: ?ObjectId, direction: WidgetFocusDirection) ?WidgetFocusTarget {
        return widget_routing.focusWidgetTarget(self, current_id, direction, widgetScrollSemantics);
    }

    pub fn focusTargetById(self: WidgetLayoutTree, id: ObjectId) ?WidgetFocusTarget {
        return widget_routing.focusWidgetTargetById(self, id, widgetScrollSemantics);
    }

    pub fn collectSemantics(self: WidgetLayoutTree, output: []WidgetSemanticsNode) Error![]const WidgetSemanticsNode {
        return collectWidgetSemantics(self, output);
    }

    pub fn textGeometry(self: WidgetLayoutTree, id: ObjectId, tokens: DesignTokens) ?WidgetTextGeometry {
        const node = self.findById(id) orelse return null;
        return textGeometryForWidget(node.widget, tokens);
    }

    pub fn emitDisplayList(self: WidgetLayoutTree, builder: *Builder, tokens: DesignTokens) Error!void {
        return emitWidgetLayout(builder, self, tokens);
    }

    pub fn emitDisplayListWithState(self: WidgetLayoutTree, builder: *Builder, tokens: DesignTokens, state: WidgetRenderState) Error!void {
        return emitWidgetLayoutWithState(builder, self, tokens, state);
    }

    pub fn renderStateDirtyBounds(self: WidgetLayoutTree, previous: WidgetRenderState, next: WidgetRenderState) ?geometry.RectF {
        return self.renderStateDirtyBoundsWithTokens(previous, next, .{});
    }

    pub fn renderStateDirtyBoundsWithTokens(self: WidgetLayoutTree, previous: WidgetRenderState, next: WidgetRenderState, tokens: DesignTokens) ?geometry.RectF {
        return widgetRenderStateDirtyBounds(self, previous, next, tokens);
    }

    pub fn diff(previous: WidgetLayoutTree, next: WidgetLayoutTree, output: []WidgetInvalidation) Error![]const WidgetInvalidation {
        return diffWithTokens(previous, next, .{}, output);
    }

    pub fn diffWithTokens(previous: WidgetLayoutTree, next: WidgetLayoutTree, tokens: DesignTokens, output: []WidgetInvalidation) Error![]const WidgetInvalidation {
        return diffWidgetLayoutTrees(previous, next, tokens, output);
    }
};

pub fn emitWidgetTree(builder: *Builder, widget: Widget, tokens: DesignTokens) Error!void {
    return widget_render.emitWidgetTree(builder, widget, tokens);
}

pub fn layoutWidgetTree(widget: Widget, bounds: geometry.RectF, output: []WidgetLayoutNode) Error!WidgetLayoutTree {
    return layoutWidgetTreeWithTokens(widget, bounds, .{}, output);
}

pub fn layoutWidgetTreeWithTokens(widget: Widget, bounds: geometry.RectF, tokens: DesignTokens, output: []WidgetLayoutNode) Error!WidgetLayoutTree {
    var len: usize = 0;
    _ = try widget_layout.layoutWidgetDepth(widget, bounds.normalized(), null, 0, output, &len, tokens);
    return .{ .nodes = output[0..len] };
}

pub fn intrinsicWidgetSize(widget: Widget, tokens: DesignTokens) geometry.SizeF {
    return widget_layout.intrinsicWidgetSize(widget, tokens);
}

pub fn virtualWidgetScrollContentExtent(widget: Widget, viewport_extent: f32) f32 {
    return widget_layout.virtualWidgetScrollContentExtent(widget, viewport_extent);
}

pub fn virtualWidgetScrollContentExtentWithTokens(widget: Widget, viewport_extent: f32, tokens: DesignTokens) f32 {
    return widget_layout.virtualWidgetScrollContentExtentWithTokens(widget, viewport_extent, tokens);
}

pub fn emitWidgetLayout(builder: *Builder, layout: WidgetLayoutTree, tokens: DesignTokens) Error!void {
    return widget_render.emitWidgetLayout(builder, layout, tokens);
}

fn emitWidgetLayoutWithState(builder: *Builder, layout: WidgetLayoutTree, tokens: DesignTokens, state: WidgetRenderState) Error!void {
    return widget_render.emitWidgetLayoutWithState(builder, layout, tokens, state);
}

pub fn toggleWidgetKnobCommandId(id: ObjectId) ObjectId {
    return widget_render.toggleWidgetKnobCommandId(id);
}

pub fn toggleWidgetKnobTravel(widget: Widget, tokens: DesignTokens) f32 {
    return widget_render.toggleWidgetKnobTravel(widget, tokens);
}

pub fn widgetPartId(id: ObjectId, slot: ObjectId) ObjectId {
    return widget_render.widgetPartId(id, slot);
}

pub fn textSelectionFillColor(widget: Widget, tokens: DesignTokens) Color {
    return widget_render.textSelectionFillColor(widget, tokens);
}

pub fn colorWithAlpha(color: Color, alpha: f32) Color {
    return widget_render.colorWithAlpha(color, alpha);
}

pub fn transparentColor() Color {
    return widget_render.transparentColor();
}

fn widgetBackdropBlur(widget: Widget, tokens: DesignTokens) f32 {
    return widget_render.widgetBackdropBlur(widget, tokens);
}

fn widgetStatusBarPadding(widget: Widget) geometry.InsetsF {
    return widget_render.widgetStatusBarPadding(widget);
}

fn checkboxWidgetBoxRect(widget: Widget, tokens: DesignTokens) geometry.RectF {
    return widget_render.checkboxWidgetBoxRect(widget, tokens);
}

fn radioWidgetCircleRect(widget: Widget, tokens: DesignTokens) geometry.RectF {
    return widget_render.radioWidgetCircleRect(widget, tokens);
}

fn toggleWidgetTrackRect(widget: Widget, tokens: DesignTokens) geometry.RectF {
    return widget_render.toggleWidgetTrackRect(widget, tokens);
}

fn sliderWidgetKnobRect(widget: Widget, tokens: DesignTokens) geometry.RectF {
    return widget_render.sliderWidgetKnobRect(widget, tokens);
}

fn controlRadius(widget: Widget, visual: ControlVisualTokens, fallback: f32) Radius {
    return widget_render.controlRadius(widget, visual, fallback);
}

fn controlStrokeWidth(widget: Widget, visual: ControlVisualTokens, fallback: f32) f32 {
    return widget_render.controlStrokeWidth(widget, visual, fallback);
}

fn componentControlVisualTokens(widget: Widget, tokens: DesignTokens) ControlVisualTokens {
    return widget_render.componentControlVisualTokens(widget, tokens);
}

fn surfaceControlVisualTokens(widget: Widget, tokens: DesignTokens) ControlVisualTokens {
    return widget_render.surfaceControlVisualTokens(widget, tokens);
}

fn buttonStrokeWidth(widget: Widget, tokens: DesignTokens) f32 {
    return widget_render.buttonStrokeWidth(widget, tokens);
}

fn selectControlVisualTokens(tokens: DesignTokens) ControlVisualTokens {
    return widget_render.selectControlVisualTokens(tokens);
}

fn textInputControlVisualTokens(widget: Widget, tokens: DesignTokens) ControlVisualTokens {
    return widget_render.textInputControlVisualTokens(widget, tokens);
}

fn selectionControlVisualTokens(widget: Widget, tokens: DesignTokens) ControlVisualTokens {
    return widget_render.selectionControlVisualTokens(widget, tokens);
}

fn listItemControlVisualTokens(widget: Widget, tokens: DesignTokens) ControlVisualTokens {
    return widget_render.listItemControlVisualTokens(widget, tokens);
}
pub fn cursorForWidgetHit(hit: ?WidgetHit) WidgetCursor {
    return widget_access.cursorForWidgetHit(hit);
}

pub fn cursorForWidgetTarget(kind: WidgetKind, state: WidgetState) WidgetCursor {
    return widget_access.cursorForWidgetTarget(kind, state);
}

fn collectWidgetSemantics(layout: WidgetLayoutTree, output: []WidgetSemanticsNode) Error![]const WidgetSemanticsNode {
    return widget_semantics.collectWidgetSemantics(layout, output, widgetScrollSemantics);
}

fn widgetScrollSemantics(layout: WidgetLayoutTree, node_index: usize) widget_semantics.WidgetScrollSemantics {
    return widget_semantics.widgetScrollSemantics(layout, node_index, widget_layout.virtualWidgetScrollContentExtent);
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

fn diffWidgetLayoutTrees(previous: WidgetLayoutTree, next: WidgetLayoutTree, tokens: DesignTokens, output: []WidgetInvalidation) Error![]const WidgetInvalidation {
    try validateUniqueWidgetIds(previous);
    try validateUniqueWidgetIds(next);

    var len: usize = 0;
    for (previous.nodes, 0..) |previous_node, previous_index| {
        const id = previous_node.widget.id;
        if (id == 0) continue;
        const next_ref = findWidgetNodeById(next, id) orelse {
            try appendWidgetInvalidation(output, &len, .{
                .kind = .removed,
                .id = id,
                .previous_index = previous_index,
                .dirty_bounds = widgetClippedDirtyBounds(previous, previous_index, widgetFullPaintBounds(previous_node, tokens)),
                .layout_dirty = true,
                .paint_dirty = true,
                .semantics_dirty = true,
            });
            continue;
        };

        var change = widgetChange(previous_node, next_ref.node, previous_index, next_ref.index, tokens);
        if (previous_node.widget.semantics.hidden != next_ref.node.widget.semantics.hidden) {
            change.dirty_bounds = unionOptionalBounds(
                widgetVisibleSubtreeFullPaintBounds(previous, previous_index, tokens),
                widgetVisibleSubtreeFullPaintBounds(next, next_ref.index, tokens),
            );
        } else if (previous_node.widget.opacity != next_ref.node.widget.opacity or !affinesEqual(previous_node.widget.transform, next_ref.node.widget.transform)) {
            change.dirty_bounds = unionOptionalBounds(
                widgetVisibleSubtreeFullPaintBounds(previous, previous_index, tokens),
                widgetVisibleSubtreeFullPaintBounds(next, next_ref.index, tokens),
            );
        } else {
            change.dirty_bounds = widgetChangedClippedDirtyBounds(previous, previous_index, next, next_ref.index, change.dirty_bounds);
        }
        if (change.layout_dirty or change.paint_dirty or change.semantics_dirty) {
            try appendWidgetInvalidation(output, &len, change);
        }
    }

    for (next.nodes, 0..) |next_node, next_index| {
        const id = next_node.widget.id;
        if (id == 0) continue;
        if (findWidgetNodeById(previous, id) == null) {
            try appendWidgetInvalidation(output, &len, .{
                .kind = .added,
                .id = id,
                .next_index = next_index,
                .dirty_bounds = widgetClippedDirtyBounds(next, next_index, widgetFullPaintBounds(next_node, tokens)),
                .layout_dirty = true,
                .paint_dirty = true,
                .semantics_dirty = true,
            });
        }
    }

    return output[0..len];
}

fn appendWidgetInvalidation(output: []WidgetInvalidation, len: *usize, invalidation: WidgetInvalidation) Error!void {
    if (len.* >= output.len) return error.WidgetInvalidationListFull;
    output[len.*] = invalidation;
    len.* += 1;
}

const WidgetNodeRef = struct {
    index: usize,
    node: WidgetLayoutNode,
};

fn findWidgetNodeById(layout: WidgetLayoutTree, id: ObjectId) ?WidgetNodeRef {
    if (id == 0) return null;
    for (layout.nodes, 0..) |node, index| {
        if (node.widget.id == id) return .{ .index = index, .node = node };
    }
    return null;
}

fn validateUniqueWidgetIds(layout: WidgetLayoutTree) Error!void {
    for (layout.nodes, 0..) |node, index| {
        const id = node.widget.id;
        if (id == 0) continue;
        var cursor = index + 1;
        while (cursor < layout.nodes.len) : (cursor += 1) {
            if (layout.nodes[cursor].widget.id == id) return error.DuplicateWidgetId;
        }
    }
}

fn widgetChange(previous: WidgetLayoutNode, next: WidgetLayoutNode, previous_index: usize, next_index: usize, tokens: DesignTokens) WidgetInvalidation {
    const layout_dirty =
        previous.widget.kind != next.widget.kind or
        previous.depth != next.depth or
        previous.parent_index != next.parent_index or
        !rectsEqual(previous.frame, next.frame) or
        !widgetLayoutStylesEqual(previous.widget.layout, next.widget.layout);
    const content_dirty = !std.mem.eql(u8, previous.widget.text, next.widget.text) or
        !std.mem.eql(u8, previous.widget.placeholder, next.widget.placeholder) or
        previous.widget.value != next.widget.value or
        previous.widget.image_id != next.widget.image_id or
        !optionalRectsEqual(previous.widget.image_src, next.widget.image_src) or
        previous.widget.image_fit != next.widget.image_fit or
        previous.widget.image_sampling != next.widget.image_sampling or
        previous.widget.image_opacity != next.widget.image_opacity or
        !optionalTextSelectionsEqual(previous.widget.text_selection, next.widget.text_selection) or
        !optionalTextRangesEqual(previous.widget.text_composition, next.widget.text_composition);
    const behavior_dirty = !std.mem.eql(u8, previous.widget.command, next.widget.command);
    const visual_dirty = previous.widget.opacity != next.widget.opacity or
        !affinesEqual(previous.widget.transform, next.widget.transform) or
        previous.widget.backdrop_blur != next.widget.backdrop_blur or
        previous.widget.backdrop_blur_token != next.widget.backdrop_blur_token or
        previous.widget.text_alignment != next.widget.text_alignment or
        previous.widget.variant != next.widget.variant or
        previous.widget.size != next.widget.size or
        !widgetStylesEqual(previous.widget.style, next.widget.style);
    const state_dirty = !widgetStatesEqual(previous.widget.state, next.widget.state);
    const visibility_dirty = previous.widget.semantics.hidden != next.widget.semantics.hidden;
    const layer_dirty = previous.widget.layer != next.widget.layer;
    const semantics_dirty =
        layout_dirty or
        content_dirty or
        behavior_dirty or
        state_dirty or
        !widgetSemanticsEqual(previous.widget.semantics, next.widget.semantics);
    const paint_dirty = layout_dirty or content_dirty or visual_dirty or state_dirty or visibility_dirty or layer_dirty;

    const dirty_bounds = if (layout_dirty or visibility_dirty or layer_dirty)
        unionOptionalBounds(widgetFullPaintBounds(previous, tokens), widgetFullPaintBounds(next, tokens))
    else if (paint_dirty)
        widgetPaintChangeBounds(previous.widget, next.widget, tokens)
    else
        null;

    return .{
        .kind = .changed,
        .id = previous.widget.id,
        .previous_index = previous_index,
        .next_index = next_index,
        .dirty_bounds = dirty_bounds,
        .layout_dirty = layout_dirty,
        .paint_dirty = paint_dirty,
        .semantics_dirty = semantics_dirty,
    };
}

fn widgetRenderStateDirtyBounds(layout: WidgetLayoutTree, previous: WidgetRenderState, next: WidgetRenderState, tokens: DesignTokens) ?geometry.RectF {
    var ids: [8]?ObjectId = [_]?ObjectId{null} ** 8;
    var id_len: usize = 0;
    if (previous.focused_id != next.focused_id) {
        appendOptionalObjectId(&ids, &id_len, previous.focused_id);
        appendOptionalObjectId(&ids, &id_len, next.focused_id);
    }
    if (previous.focus_visible_id != next.focus_visible_id) {
        appendOptionalObjectId(&ids, &id_len, previous.focus_visible_id);
        appendOptionalObjectId(&ids, &id_len, next.focus_visible_id);
    }
    if (previous.hovered_id != next.hovered_id) {
        appendOptionalObjectId(&ids, &id_len, previous.hovered_id);
        appendOptionalObjectId(&ids, &id_len, next.hovered_id);
    }
    if (previous.pressed_id != next.pressed_id) {
        appendOptionalObjectId(&ids, &id_len, previous.pressed_id);
        appendOptionalObjectId(&ids, &id_len, next.pressed_id);
    }

    var bounds: ?geometry.RectF = null;
    for (ids[0..id_len]) |maybe_id| {
        const id = maybe_id orelse continue;
        const index = widgetIndexById(layout, id) orelse continue;
        const node = layout.nodes[index];
        const base = widgetWithFrame(node.widget, node.frame);
        const previous_widget = widgetWithRenderState(base, previous);
        const next_widget = widgetWithRenderState(base, next);
        if (widgetStatesEqual(previous_widget.state, next_widget.state)) continue;
        bounds = unionOptionalBounds(bounds, widgetClippedDirtyBounds(layout, index, widgetRenderStatePaintChangeBounds(previous_widget, next_widget, tokens)));
    }
    return bounds;
}

fn appendOptionalObjectId(output: []?ObjectId, len: *usize, maybe_id: ?ObjectId) void {
    const id = maybe_id orelse return;
    if (id == 0) return;
    for (output[0..len.*]) |existing| {
        if (existing != null and existing.? == id) return;
    }
    if (len.* >= output.len) return;
    output[len.*] = id;
    len.* += 1;
}

fn widgetFullPaintBounds(node: WidgetLayoutNode, tokens: DesignTokens) geometry.RectF {
    return widgetFullPaintBoundsWithTransform(node, widgetTransform(node.widget), tokens);
}

fn widgetFullPaintBoundsWithTransform(node: WidgetLayoutNode, transform: Affine, tokens: DesignTokens) geometry.RectF {
    var bounds = node.frame.normalized();
    if (widgetFrameStrokeBounds(node.widget, tokens)) |stroke_bounds| {
        bounds = geometry.RectF.unionWith(bounds, stroke_bounds.normalized());
    }
    if (widgetShadowPaintBounds(node.widget, tokens)) |shadow_bounds| {
        bounds = geometry.RectF.unionWith(bounds, shadow_bounds.normalized());
    }
    if (widgetBackdropBlurPaintBounds(node.widget, tokens)) |blur_bounds| {
        bounds = geometry.RectF.unionWith(bounds, blur_bounds.normalized());
    }
    return transform.transformRect(bounds).normalized();
}

fn widgetVisibleSubtreeFullPaintBounds(layout: WidgetLayoutTree, root_index: usize, tokens: DesignTokens) ?geometry.RectF {
    if (root_index >= layout.nodes.len) return null;

    const root_depth = layout.nodes[root_index].depth;
    var bounds: ?geometry.RectF = null;
    var hidden_depth: ?usize = null;
    var index = root_index;
    while (index < layout.nodes.len) : (index += 1) {
        const node = layout.nodes[index];
        if (index != root_index and node.depth <= root_depth) break;
        if (hidden_depth) |depth| {
            if (node.depth > depth) continue;
            hidden_depth = null;
        }
        if (node.widget.semantics.hidden) {
            hidden_depth = node.depth;
            continue;
        }
        bounds = unionOptionalBounds(bounds, widgetClippedDirtyBounds(layout, index, widgetFullPaintBoundsWithTransform(node, widgetAccumulatedTransform(layout, index), tokens)));
    }
    return bounds;
}

fn widgetAccumulatedTransform(layout: WidgetLayoutTree, node_index: usize) Affine {
    var indices: [max_widget_depth]usize = undefined;
    var len: usize = 0;
    var current: ?usize = node_index;
    while (current) |index| {
        if (index >= layout.nodes.len or len >= indices.len) break;
        indices[len] = index;
        len += 1;
        current = layout.nodes[index].parent_index;
    }

    var transform = Affine.identity();
    while (len > 0) {
        len -= 1;
        transform = transform.multiply(widgetTransform(layout.nodes[indices[len]].widget));
    }
    return transform;
}

fn widgetChangedClippedDirtyBounds(
    previous: WidgetLayoutTree,
    previous_index: usize,
    next: WidgetLayoutTree,
    next_index: usize,
    bounds: ?geometry.RectF,
) ?geometry.RectF {
    return unionOptionalBounds(
        widgetClippedDirtyBounds(previous, previous_index, bounds),
        widgetClippedDirtyBounds(next, next_index, bounds),
    );
}

fn widgetClippedDirtyBounds(layout: WidgetLayoutTree, node_index: usize, bounds: ?geometry.RectF) ?geometry.RectF {
    if (node_index >= layout.nodes.len) return null;
    if (isWidgetHiddenInAncestors(layout, node_index)) return null;

    var clipped = (bounds orelse return null).normalized();
    var current = layout.nodes[node_index].parent_index;
    while (current) |parent_index| {
        if (parent_index >= layout.nodes.len) return null;
        const parent = layout.nodes[parent_index];
        if (widgetClipsContent(parent.widget)) {
            clipped = geometry.RectF.intersection(clipped, parent.frame.normalized());
            if (clipped.isEmpty()) return null;
        }
        current = parent.parent_index;
    }
    return clipped;
}

fn widgetPaintChangeBounds(previous: Widget, next: Widget, tokens: DesignTokens) ?geometry.RectF {
    var bounds = unionOptionalBounds(previous.frame, next.frame);
    if (widgetFrameStrokePaintChanged(previous, next, tokens)) {
        bounds = unionOptionalBounds(bounds, widgetFrameStrokeBounds(previous, tokens));
        bounds = unionOptionalBounds(bounds, widgetFrameStrokeBounds(next, tokens));
    }
    bounds = unionOptionalBounds(bounds, widgetFocusPaintBounds(previous, tokens));
    bounds = unionOptionalBounds(bounds, widgetFocusPaintBounds(next, tokens));
    bounds = unionOptionalBounds(bounds, widgetBackdropBlurPaintBounds(previous, tokens));
    bounds = unionOptionalBounds(bounds, widgetBackdropBlurPaintBounds(next, tokens));
    return bounds;
}

fn widgetRenderStatePaintChangeBounds(previous: Widget, next: Widget, tokens: DesignTokens) ?geometry.RectF {
    var bounds: ?geometry.RectF = null;
    if (widgetFrameStrokePaintChanged(previous, next, tokens)) {
        bounds = unionOptionalBounds(bounds, widgetFrameStrokeBounds(previous, tokens));
        bounds = unionOptionalBounds(bounds, widgetFrameStrokeBounds(next, tokens));
    }
    if (previous.state.focused != next.state.focused) {
        bounds = unionOptionalBounds(bounds, widgetFocusPaintBounds(previous, tokens));
        bounds = unionOptionalBounds(bounds, widgetFocusPaintBounds(next, tokens));
    }
    if (previous.state.hovered != next.state.hovered or previous.state.pressed != next.state.pressed) {
        bounds = unionOptionalBounds(bounds, widgetInteractiveStatePaintBounds(previous, tokens));
        bounds = unionOptionalBounds(bounds, widgetInteractiveStatePaintBounds(next, tokens));
    }
    return bounds;
}

fn widgetFrameStrokePaintChanged(previous: Widget, next: Widget, tokens: DesignTokens) bool {
    return widgetFrameStrokeWidth(previous, tokens) != widgetFrameStrokeWidth(next, tokens) or
        !optionalColorsEqual(previous.style.border, next.style.border);
}

fn widgetFrameStrokeBounds(widget: Widget, tokens: DesignTokens) ?geometry.RectF {
    const width = widgetFrameStrokeWidth(widget, tokens);
    if (width <= 0) return null;
    return strokeBounds(widgetChromeStrokeRect(widget, tokens), width);
}

fn widgetFocusPaintBounds(widget: Widget, tokens: DesignTokens) ?geometry.RectF {
    if (!widget.state.focused or widgetFocusStrokeWidth(widget, tokens) <= 0) return null;
    return strokeBounds(widgetFocusPaintRect(widget, tokens), tokens.stroke.focus);
}

fn widgetInteractiveStatePaintBounds(widget: Widget, tokens: DesignTokens) geometry.RectF {
    return switch (widget.kind) {
        .checkbox => checkboxWidgetBoxRect(widget, tokens),
        .radio => radioWidgetCircleRect(widget, tokens),
        .switch_control, .toggle => toggleWidgetTrackRect(widget, tokens),
        .slider => sliderWidgetKnobRect(widget, tokens),
        else => widget.frame,
    };
}

fn widgetChromeStrokeRect(widget: Widget, tokens: DesignTokens) geometry.RectF {
    return switch (widget.kind) {
        .checkbox => checkboxWidgetBoxRect(widget, tokens),
        .radio => radioWidgetCircleRect(widget, tokens),
        .switch_control, .toggle => toggleWidgetTrackRect(widget, tokens),
        .slider => sliderWidgetKnobRect(widget, tokens),
        else => widget.frame,
    };
}

fn widgetFocusPaintRect(widget: Widget, tokens: DesignTokens) geometry.RectF {
    return switch (widget.kind) {
        .checkbox => checkboxWidgetBoxRect(widget, tokens),
        .radio => radioWidgetCircleRect(widget, tokens),
        .switch_control, .toggle => toggleWidgetTrackRect(widget, tokens),
        .slider => sliderWidgetKnobRect(widget, tokens),
        else => widget.frame,
    };
}

fn widgetFrameStrokeWidth(widget: Widget, tokens: DesignTokens) f32 {
    return switch (widget.kind) {
        .accordion, .alert, .bubble, .card, .dialog, .drawer, .sheet, .resizable, .panel, .popover, .menu_surface, .dropdown_menu => controlStrokeWidth(widget, surfaceControlVisualTokens(widget, tokens), tokens.stroke.hairline),
        .button, .toggle_button, .icon_button => if (widget.state.focused) tokens.stroke.focus else buttonStrokeWidth(widget, tokens),
        .select => if (widget.state.focused) tokens.stroke.focus else controlStrokeWidth(widget, selectControlVisualTokens(tokens), tokens.stroke.regular),
        .input, .text_field, .search_field, .combobox, .textarea => if (widget.state.focused) tokens.stroke.focus else controlStrokeWidth(widget, textInputControlVisualTokens(widget, tokens), tokens.stroke.regular),
        .segmented_control => if (widget.state.focused) tokens.stroke.focus else controlStrokeWidth(widget, selectionControlVisualTokens(widget, tokens), tokens.stroke.regular),
        .data_cell => if (widget.state.focused) tokens.stroke.focus else controlStrokeWidth(widget, listItemControlVisualTokens(widget, tokens), tokens.stroke.hairline),
        .checkbox, .radio, .switch_control, .toggle, .slider => if (widget.state.focused) tokens.stroke.focus else controlStrokeWidth(widget, selectionControlVisualTokens(widget, tokens), tokens.stroke.regular),
        .avatar, .badge => controlStrokeWidth(widget, componentControlVisualTokens(widget, tokens), tokens.stroke.hairline),
        .list_item, .menu_item => if (widget.state.focused) tokens.stroke.focus else 0,
        else => 0,
    };
}

fn widgetFocusStrokeWidth(widget: Widget, tokens: DesignTokens) f32 {
    return switch (widget.kind) {
        .button,
        .toggle_button,
        .icon_button,
        .select,
        .input,
        .text_field,
        .search_field,
        .combobox,
        .textarea,
        .menu_item,
        .list_item,
        .data_cell,
        .segmented_control,
        .checkbox,
        .radio,
        .switch_control,
        .toggle,
        .slider,
        => tokens.stroke.focus,
        else => 0,
    };
}

fn widgetShadowPaintBounds(widget: Widget, tokens: DesignTokens) ?geometry.RectF {
    const token = switch (widget.kind) {
        .accordion, .bubble, .resizable, .panel, .tooltip => tokens.shadow.sm,
        .dialog, .drawer, .sheet, .popover, .menu_surface, .dropdown_menu => tokens.shadow.md,
        else => return null,
    };
    if (token.y == 0 and token.blur == 0 and token.spread == 0) return null;
    return shadowBounds(.{
        .rect = widget.frame,
        .radius = widgetShadowRadius(widget, tokens),
        .offset = .{ .dx = 0, .dy = token.y },
        .blur = token.blur,
        .spread = token.spread,
        .color = tokens.colors.shadow,
    });
}

fn widgetBackdropBlurPaintBounds(widget: Widget, tokens: DesignTokens) ?geometry.RectF {
    const radius = widgetBackdropBlur(widget, tokens);
    if (radius <= 0) return null;
    return widget.frame.normalized().inflate(geometry.InsetsF.all(radius));
}

fn widgetShadowRadius(widget: Widget, tokens: DesignTokens) Radius {
    return switch (widget.kind) {
        .dialog, .drawer, .popover => controlRadius(widget, surfaceControlVisualTokens(widget, tokens), tokens.radius.xl),
        .sheet => controlRadius(widget, surfaceControlVisualTokens(widget, tokens), tokens.radius.lg),
        .accordion, .alert, .bubble, .card, .resizable, .panel, .menu_surface, .dropdown_menu => controlRadius(widget, surfaceControlVisualTokens(widget, tokens), tokens.radius.lg),
        .tooltip => controlRadius(widget, surfaceControlVisualTokens(widget, tokens), tokens.radius.md),
        else => Radius.all(0),
    };
}

fn widgetStatesEqual(a: WidgetState, b: WidgetState) bool {
    return a.hovered == b.hovered and
        a.pressed == b.pressed and
        a.focused == b.focused and
        a.disabled == b.disabled and
        a.selected == b.selected and
        a.expanded == b.expanded and
        a.required == b.required and
        a.read_only == b.read_only and
        a.invalid == b.invalid;
}

fn widgetLayoutStylesEqual(a: WidgetLayoutStyle, b: WidgetLayoutStyle) bool {
    return insetsEqual(a.padding, b.padding) and
        a.gap == b.gap and
        a.grow == b.grow and
        a.main_alignment == b.main_alignment and
        a.cross_alignment == b.cross_alignment and
        a.clip_content == b.clip_content and
        a.columns == b.columns and
        a.virtualized == b.virtualized and
        a.virtual_item_extent == b.virtual_item_extent and
        a.virtual_overscan == b.virtual_overscan and
        sizesEqual(a.min_size, b.min_size);
}

fn widgetStylesEqual(a: WidgetStyle, b: WidgetStyle) bool {
    return optionalColorsEqual(a.background, b.background) and
        optionalColorsEqual(a.foreground, b.foreground) and
        optionalColorsEqual(a.accent, b.accent) and
        optionalColorsEqual(a.accent_foreground, b.accent_foreground) and
        optionalColorsEqual(a.border, b.border) and
        optionalColorsEqual(a.focus_ring, b.focus_ring) and
        optionalF32Equal(a.radius, b.radius) and
        optionalF32Equal(a.stroke_width, b.stroke_width);
}

fn widgetSemanticsEqual(a: WidgetSemantics, b: WidgetSemantics) bool {
    return a.role == b.role and
        std.mem.eql(u8, a.label, b.label) and
        optionalF32Equal(a.value, b.value) and
        a.list_item_index == b.list_item_index and
        a.list_item_count == b.list_item_count and
        widgetActionsEqual(a.actions, b.actions) and
        a.hidden == b.hidden and
        a.focusable == b.focusable;
}

fn widgetActionsEqual(a: WidgetActions, b: WidgetActions) bool {
    return a.focus == b.focus and
        a.press == b.press and
        a.toggle == b.toggle and
        a.increment == b.increment and
        a.decrement == b.decrement and
        a.set_text == b.set_text and
        a.set_selection == b.set_selection and
        a.select == b.select and
        a.drag == b.drag and
        a.drop_files == b.drop_files and
        a.dismiss == b.dismiss;
}
fn unionOptionalBounds(a: ?geometry.RectF, b: ?geometry.RectF) ?geometry.RectF {
    if (a) |rect_a| {
        if (b) |rect_b| return geometry.RectF.unionWith(rect_a.normalized(), rect_b.normalized());
        return rect_a.normalized();
    }
    if (b) |rect_b| return rect_b.normalized();
    return null;
}

fn nonNegative(value: f32) f32 {
    return @max(0, value);
}
