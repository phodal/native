const std = @import("std");
const geometry = @import("geometry");
const canvas = @import("canvas");
const canvas_frame_helpers = @import("canvas_frame.zig");
const canvas_widget_runtime = @import("canvas_widget_runtime.zig");

const unionRects = canvas_frame_helpers.unionRects;
const canvasWidgetResizableMinWidth = canvas_widget_runtime.canvasWidgetResizableMinWidth;
const canvasWidgetBooleanSelected = canvas_widget_runtime.canvasWidgetBooleanSelected;
const canvasWidgetSwitchControlKind = canvas_widget_runtime.canvasWidgetSwitchControlKind;
const canvasWidgetSelectableSelected = canvas_widget_runtime.canvasWidgetSelectableSelected;
const canvasWidgetSelectionClearsSiblings = canvas_widget_runtime.canvasWidgetSelectionClearsSiblings;

pub const CanvasWidgetToggleAnimation = struct {
    id: canvas.ObjectId,
    selected: bool,
    travel: f32,
    dirty_bounds: ?geometry.RectF,
};

pub fn RuntimeViewCanvasWidgetControl(comptime RuntimeView: type) type {
    return struct {
        pub fn canvasWidgetToggleAnimation(self: *const RuntimeView, id: canvas.ObjectId) ?CanvasWidgetToggleAnimation {
            const index = self.canvasWidgetNodeIndexById(id) orelse return null;
            const widget = self.widget_layout_nodes[index].widget;
            if (!canvasWidgetSwitchControlKind(widget.kind) or widget.state.disabled) return null;
            const travel = canvas.toggleWidgetKnobTravel(widget, self.widget_tokens);
            if (travel <= 0) return null;
            return .{
                .id = id,
                .selected = canvasWidgetBooleanSelected(widget),
                .travel = travel,
                .dirty_bounds = self.canvasWidgetDirtyBounds(index, widget.frame),
            };
        }

        pub fn canvasWidgetToggleAnimationForPointer(
            self: *const RuntimeView,
            pointer: canvas.WidgetPointerEvent,
            target: ?canvas.WidgetHit,
            pressed_id: canvas.ObjectId,
        ) ?CanvasWidgetToggleAnimation {
            if (pointer.phase != .up or pressed_id == 0) return null;
            const hit = target orelse return null;
            if (!canvasWidgetSwitchControlKind(hit.kind) or hit.id != pressed_id) return null;
            if (!hit.bounds.normalized().containsPoint(pointer.point)) return null;
            return self.canvasWidgetToggleAnimation(pressed_id);
        }

        pub fn canvasWidgetToggleAnimationForKeyboard(self: *const RuntimeView, id: canvas.ObjectId, keyboard: canvas.WidgetKeyboardEvent) ?CanvasWidgetToggleAnimation {
            if (keyboard.phase != .key_down or keyboard.modifiers.hasNavigationModifier()) return null;
            if (!canvas.isWidgetActivationKey(keyboard.key)) return null;
            return self.canvasWidgetToggleAnimation(id);
        }

        pub fn applyCanvasWidgetControlPointer(self: *RuntimeView, pointer: canvas.WidgetPointerEvent, target: ?canvas.WidgetHit, pressed_id: canvas.ObjectId) anyerror!?geometry.RectF {
            return switch (pointer.phase) {
                .down => if (target) |hit| try self.applyCanvasWidgetSliderValue(hit.id, pointer.point) else null,
                .move => if (pressed_id != 0) blk: {
                    if (try self.applyCanvasWidgetSliderValue(pressed_id, pointer.point)) |dirty| break :blk dirty;
                    break :blk try self.applyCanvasWidgetResizableDelta(pressed_id, pointer.delta.dx);
                } else null,
                .up => blk: {
                    if (pressed_id == 0) break :blk null;
                    if (try self.applyCanvasWidgetSliderValue(pressed_id, pointer.point)) |dirty| break :blk dirty;
                    const hit = target orelse break :blk null;
                    if (!hit.bounds.normalized().containsPoint(pointer.point)) break :blk null;
                    if (hit.id != pressed_id) break :blk null;
                    if (try self.toggleCanvasWidgetBooleanControl(pressed_id)) |dirty| break :blk dirty;
                    break :blk try self.setCanvasWidgetSelected(pressed_id, true);
                },
                .hover, .cancel, .wheel => null,
            };
        }

        pub fn applyCanvasWidgetResizableDelta(self: *RuntimeView, id: canvas.ObjectId, delta_x: f32) anyerror!?geometry.RectF {
            if (!std.math.isFinite(delta_x) or delta_x == 0) return null;
            const index = self.canvasWidgetNodeIndexById(id) orelse return null;
            const widget = self.widget_layout_nodes[index].widget;
            if (widget.kind != .resizable or widget.state.disabled) return null;
            if (!std.math.isFinite(widget.frame.width)) return null;

            const previous_frame = self.widget_layout_nodes[index].frame;
            const min_width = canvasWidgetResizableMinWidth(widget);
            const next_width = @max(min_width, previous_frame.width + delta_x);
            if (next_width == previous_frame.width) return null;

            self.widget_layout_nodes[index].frame.width = next_width;
            self.widget_layout_nodes[index].widget.frame.width = next_width;
            try self.refreshCanvasWidgetSemantics();
            self.widget_revision += 1;
            const dirty = unionRects(previous_frame, self.widget_layout_nodes[index].frame) orelse self.widget_layout_nodes[index].frame;
            return self.canvasWidgetDirtyBounds(index, dirty);
        }

        pub fn applyCanvasWidgetControlKeyboard(self: *RuntimeView, id: canvas.ObjectId, keyboard: canvas.WidgetKeyboardEvent) anyerror!?geometry.RectF {
            const index = self.canvasWidgetNodeIndexById(id) orelse return null;
            const widget = self.widget_layout_nodes[index].widget;

            const intent = canvas.widgetKeyboardControlIntent(widget, keyboard) orelse return null;
            return self.applyCanvasWidgetControlIntent(index, intent);
        }

        pub fn applyCanvasWidgetControlIntent(self: *RuntimeView, index: usize, intent: canvas.WidgetControlIntent) anyerror!?geometry.RectF {
            if (index >= self.widget_layout_node_count) return null;
            const id = self.widget_layout_nodes[index].widget.id;
            return switch (intent.kind) {
                .toggle => try self.toggleCanvasWidgetBooleanControl(id),
                .set_value => if (intent.value) |next_value| try self.setCanvasWidgetValue(index, next_value) else null,
                .select => try self.setCanvasWidgetSelected(id, true),
                .scroll_to_start => try self.applyCanvasWidgetScrollKeyboardTarget(index, .start),
                .scroll_to_end => try self.applyCanvasWidgetScrollKeyboardTarget(index, .end),
                .scroll_by => try self.applyCanvasWidgetScroll(index, intent.delta, .discrete, false),
                .press => null,
            };
        }

        pub fn applyCanvasWidgetSliderValue(self: *RuntimeView, id: canvas.ObjectId, point: geometry.PointF) anyerror!?geometry.RectF {
            const index = self.canvasWidgetNodeIndexById(id) orelse return null;
            const widget = self.widget_layout_nodes[index].widget;
            if (widget.kind != .slider or widget.state.disabled or widget.frame.width <= 0) return null;

            const next_value = std.math.clamp((point.x - widget.frame.x) / widget.frame.width, 0, 1);
            return self.setCanvasWidgetValue(index, next_value);
        }

        pub fn toggleCanvasWidgetBooleanControl(self: *RuntimeView, id: canvas.ObjectId) anyerror!?geometry.RectF {
            const index = self.canvasWidgetNodeIndexById(id) orelse return null;
            const widget = self.widget_layout_nodes[index].widget;
            if ((widget.kind != .accordion and widget.kind != .checkbox and widget.kind != .toggle_button and !canvasWidgetSwitchControlKind(widget.kind)) or widget.state.disabled) return null;

            const selected = canvasWidgetBooleanSelected(widget);
            self.widget_layout_nodes[index].widget.state.selected = !selected;
            self.widget_layout_nodes[index].widget.value = if (!selected) 1 else 0;
            try self.refreshCanvasWidgetSemantics();
            self.widget_revision += 1;
            return self.canvasWidgetDirtyBounds(index, widget.frame);
        }

        pub fn setCanvasWidgetSelected(self: *RuntimeView, id: canvas.ObjectId, selected: bool) anyerror!?geometry.RectF {
            const index = self.canvasWidgetNodeIndexById(id) orelse return null;
            const widget = self.widget_layout_nodes[index].widget;
            if (widget.state.disabled) return null;
            switch (widget.kind) {
                .list_item, .menu_item, .data_cell, .segmented_control, .radio => {},
                else => return null,
            }

            var dirty: ?geometry.RectF = null;
            var changed = false;
            if (selected and canvasWidgetSelectionClearsSiblings(widget.kind)) {
                const parent_index = self.widget_layout_nodes[index].parent_index;
                for (self.widget_layout_nodes[0..self.widget_layout_node_count], 0..) |*node, sibling_index| {
                    if (sibling_index == index) continue;
                    if (node.parent_index != parent_index or node.widget.kind != widget.kind) continue;
                    if (!canvasWidgetSelectableSelected(node.widget)) continue;
                    node.widget.state.selected = false;
                    node.widget.value = 0;
                    dirty = unionRects(dirty, self.canvasWidgetDirtyBounds(sibling_index, node.frame));
                    changed = true;
                }
            }

            const target_value: f32 = if (selected) 1 else 0;
            if (self.widget_layout_nodes[index].widget.state.selected != selected or self.widget_layout_nodes[index].widget.value != target_value) {
                dirty = unionRects(dirty, self.canvasWidgetDirtyBounds(index, self.widget_layout_nodes[index].frame));
                changed = true;
            }
            if (!changed) return null;
            self.widget_layout_nodes[index].widget.state.selected = selected;
            self.widget_layout_nodes[index].widget.value = target_value;
            try self.refreshCanvasWidgetSemantics();
            self.widget_revision += 1;
            return dirty orelse self.widget_layout_nodes[index].frame;
        }

        pub fn setCanvasWidgetValue(self: *RuntimeView, index: usize, value: f32) anyerror!?geometry.RectF {
            if (index >= self.widget_layout_node_count) return null;
            const widget = self.widget_layout_nodes[index].widget;
            const next_value = std.math.clamp(value, 0, 1);
            if (next_value == widget.value) return null;
            self.widget_layout_nodes[index].widget.value = next_value;
            try self.refreshCanvasWidgetSemantics();
            self.widget_revision += 1;
            return self.canvasWidgetDirtyBounds(index, widget.frame);
        }
    };
}
