const std = @import("std");
const geometry = @import("geometry");
const canvas = @import("canvas");
const platform = @import("../platform/root.zig");
const validation = @import("validation.zig");
const runtime_api = @import("api.zig");
const canvas_limits = @import("canvas_limits.zig");
const canvas_frame_helpers = @import("canvas_frame.zig");
const canvas_widget_runtime = @import("canvas_widget_runtime.zig");
const runtime_canvas_widget_scroll_drivers = @import("canvas_widget_scroll_drivers.zig");
const launch_timing = @import("launch_timing.zig");
const runtime_canvas_widget_display = @import("canvas_widget_display.zig");
const runtime_canvas_widget_events = @import("canvas_widget_events.zig");
const runtime_automation_widget_dispatch = @import("automation_widget_dispatch.zig");
const widget_bridge = @import("widget_bridge.zig");

const validateViewLabel = validation.validateViewLabel;
const max_canvas_widget_nodes_per_view = canvas_limits.max_canvas_widget_nodes_per_view;
const max_canvas_widget_semantics_per_view = canvas_limits.max_canvas_widget_semantics_per_view;
const max_canvas_widget_text_bytes_per_view = canvas_limits.max_canvas_widget_text_bytes_per_view;
const max_canvas_widget_invalidations_per_view = canvas_limits.max_canvas_widget_invalidations_per_view;
const CanvasWidgetControlReconcileEntry = canvas_widget_runtime.CanvasWidgetControlReconcileEntry;
const CanvasWidgetTextReconcileEntry = canvas_widget_runtime.CanvasWidgetTextReconcileEntry;
const canvasWidgetLayoutTreeWithRuntimeReconcileState = canvas_widget_runtime.canvasWidgetLayoutTreeWithRuntimeReconcileState;
const canvasWidgetEditableTextKind = canvas_widget_runtime.canvasWidgetEditableTextKind;
const canvasWidgetAccessibilityActionSupported = widget_bridge.canvasWidgetAccessibilityActionSupported;
const canvasWidgetAccessibilitySemanticAction = widget_bridge.canvasWidgetAccessibilitySemanticAction;

pub fn RuntimeCanvasWidgetState(comptime Runtime: type) type {
    return struct {
        pub fn setCanvasWidgetLayout(self: *Runtime, window_id: platform.WindowId, label: []const u8, layout: canvas.WidgetLayoutTree) anyerror!platform.ViewInfo {
            try validateRuntimeViewParent(self, window_id);
            try validateViewLabel(label);
            const index = runtimeFindViewIndex(self, window_id, label) orelse return error.ViewNotFound;
            if (self.views[index].kind != .gpu_surface) return error.InvalidViewOptions;
            if (layout.nodes.len > max_canvas_widget_nodes_per_view) return error.WidgetNodeLimitReached;

            // Frame-profile `reconcile` stage: reconcile + diff + state
            // copies, ending BEFORE the display-list refresh below so the
            // `emit` stage (stamped at its own choke point) is never
            // double-counted. No-op unless profiling is on.
            const reconcile_begin = self.frame_profile.begin();
            // Launch lap (env-gated, once per process): the startup
            // frame's reconcile begins here, splitting view build from
            // reconcile+emit inside the built -> emitted window.
            launch_timing.lapOnce("first_reconcile_begin");

            // Source-driven autofocus resolves against the PREVIOUS
            // rebuild's flags (edge-triggered) before any state is
            // replaced; the focus applies after the new tree lands.
            const autofocus_target = self.views[index].canvasWidgetAutofocusTarget(layout);
            const previous_layout = self.views[index].widgetLayoutTree();
            const source_semantics = try layout.collectSemantics(&self.canvas_widget_source_semantics_scratch);
            const reconciled_nodes = &self.canvas_widget_reconcile_nodes;
            const tokens = self.views[index].widget_tokens;
            // Reconcile scratch lives on the Runtime, not the stack: at
            // the 1024-node budget these arrays total several hundred
            // KiB, and the single-threaded event loop makes the shared
            // buffers safe.
            const reconciled_layout = try canvasWidgetLayoutTreeWithRuntimeReconcileState(
                previous_layout,
                layout,
                source_semantics,
                self.views[index].widgetSourceTextEntries(),
                self.views[index].widgetSourceScrollEntries(),
                self.views[index].widgetSourceControlEntries(),
                reconciled_nodes,
                &self.canvas_widget_reconcile_control_entries,
                &self.canvas_widget_reconcile_scroll_entries,
                &self.canvas_widget_reconcile_text_entries,
                &self.canvas_widget_reconcile_text_bytes,
                tokens,
            );
            // Native scroll drivers: mark natively driven scroll
            // regions before the copy so rebuild-time clamping and display
            // emission both see the flag (engine scrollbar + engine clamp
            // stand down; the OS scroller owns them).
            ScrollDriverMethods(Runtime).stampCanvasWidgetNativeScroll(self, reconciled_nodes[0..reconciled_layout.nodes.len]);
            // Engine-side rebuild clamp AFTER the stamp: natively driven
            // regions skip it, so a rebuild landing mid-rubber-band keeps
            // the OS scroller's overscrolled offset instead of clamping it
            // and force-pushing the clamp into the live bounce (visible
            // jitter). Non-driver platforms clamp exactly as before.
            canvas_widget_runtime.clampCanvasWidgetLayoutScrollOffsets(reconciled_nodes[0..reconciled_layout.nodes.len], null);
            const invalidations = try canvas.WidgetLayoutTree.diffWithTokens(previous_layout, reconciled_layout, tokens, &self.canvas_widget_invalidations_scratch);
            const previous_render_state = self.views[index].canvasWidgetRenderState();
            const next_render_state = CanvasWidgetEventMethods(Runtime).canvasWidgetRenderStateAfterLayout(previous_render_state, reconciled_layout);
            const render_state_changed = !CanvasWidgetEventMethods(Runtime).canvasWidgetRenderStatesEqual(previous_render_state, next_render_state);
            const render_state_dirty = if (render_state_changed)
                previous_layout.renderStateDirtyBoundsWithTokens(previous_render_state, next_render_state, tokens)
            else
                null;
            const previous_cursor = self.views[index].canvas_widget_cursor;
            const previous_widget_revision = self.views[index].widget_revision;
            try self.views[index].copyWidgetLayoutTree(reconciled_layout, &self.canvas_widget_copy_scratch);
            try self.views[index].copyCanvasWidgetSourceText(layout);
            self.views[index].copyCanvasWidgetSourceScroll(layout);
            self.views[index].copyCanvasWidgetSourceControls(layout);
            // Push the reconciled regions (frames, content extents,
            // diverged offsets) to the native scroll drivers.
            ScrollDriverMethods(Runtime).syncCanvasWidgetScrollDriversForView(self, index);
            const widget_revision_changed = self.views[index].widget_revision != previous_widget_revision;
            if (previous_cursor != self.views[index].canvas_widget_cursor) try CanvasWidgetEventMethods(Runtime).syncCanvasWidgetCursorForView(self, index);
            CanvasWidgetEventMethods(Runtime).invalidateForWidgetInvalidations(self, self.views[index].frame, invalidations);
            if (render_state_changed) CanvasWidgetEventMethods(Runtime).invalidateForCanvasWidgetRenderStateDirty(self, index, render_state_dirty);
            const layout_dirty = invalidations.len > 0 or render_state_changed;
            if (autofocus_target) |autofocus_id| {
                // The same focus write every other focus source performs
                // (view focus + focused/visible ids + invalidation);
                // widgets that are not focusable ignore the request.
                if (self.views[index].widgetLayoutTree().focusTargetById(autofocus_id) != null) {
                    try AutomationWidgetMethods(Runtime).focusAutomationCanvasWidget(self, index, autofocus_id);
                }
            }
            self.frame_profile.end(.reconcile, reconcile_begin);
            // Source-declared layout tweens, AFTER the reconciled tree is
            // retained (the arm reads the kept fraction as its `from`)
            // and BEFORE the display refresh (a reduced-motion snap must
            // paint in this rebuild's frame, not the next one). Both
            // markup engines and the Zig builder lower `resize-duration`
            // into the same widget fields, so this one walk is the whole
            // consumer.
            try armSourceDeclaredLayoutTweens(self, index, layout);
            const requested_frame = try CanvasWidgetDisplayMethods(Runtime).refreshCanvasWidgetDisplayListIfOwned(self, index);
            if ((layout_dirty or widget_revision_changed) and !requested_frame) try CanvasFrameMethods(Runtime).requestCanvasFrameForView(self, index);
            return self.views[index].info();
        }

        pub fn canvasWidgetLayout(self: *const Runtime, window_id: platform.WindowId, label: []const u8) anyerror!canvas.WidgetLayoutTree {
            try validateRuntimeViewParent(self, window_id);
            try validateViewLabel(label);
            const index = runtimeFindViewIndex(self, window_id, label) orelse return error.ViewNotFound;
            if (self.views[index].kind != .gpu_surface) return error.InvalidViewOptions;
            return self.views[index].widgetLayoutTree();
        }

        pub fn canvasWidgetSemantics(self: *const Runtime, window_id: platform.WindowId, label: []const u8) anyerror![]const canvas.WidgetSemanticsNode {
            try validateRuntimeViewParent(self, window_id);
            try validateViewLabel(label);
            const index = runtimeFindViewIndex(self, window_id, label) orelse return error.ViewNotFound;
            if (self.views[index].kind != .gpu_surface) return error.InvalidViewOptions;
            return self.views[index].widgetSemantics();
        }

        pub fn dispatchCanvasWidgetAccessibilityAction(
            self: *Runtime,
            app: runtime_api.App(Runtime),
            window_id: platform.WindowId,
            label: []const u8,
            action: runtime_api.CanvasWidgetAccessibilityAction,
        ) anyerror!platform.ViewInfo {
            try validateRuntimeViewParent(self, window_id);
            try validateViewLabel(label);
            if (action.id == 0) return error.InvalidCommand;
            const index = runtimeFindViewIndex(self, window_id, label) orelse return error.ViewNotFound;
            if (self.views[index].kind != .gpu_surface) return error.InvalidViewOptions;
            const actions = AutomationWidgetMethods(Runtime).canvasWidgetActionsForId(self, index, action.id) orelse return error.InvalidCommand;
            if (!canvasWidgetAccessibilityActionSupported(actions, action.action)) return error.InvalidCommand;

            if (canvasWidgetAccessibilitySemanticAction(action.action)) |semantic_action| {
                if (try AutomationWidgetMethods(Runtime).dispatchCanvasWidgetSemanticControlAction(self, app, index, action.id, semantic_action, actions)) {
                    // The AX client that initiated this action reads the
                    // platform tree next: force-flush the publish the
                    // gesture's refresh batch deferred so it observes the
                    // post-action tree, not the pre-action one.
                    try CanvasWidgetDisplayMethods(Runtime).flushDeferredCanvasWidgetAccessibility(self);
                    return self.views[index].info();
                }
            }

            switch (action.action) {
                .focus => try AutomationWidgetMethods(Runtime).focusAutomationCanvasWidget(self, index, action.id),
                .press => try AutomationWidgetMethods(Runtime).dispatchAutomationWidgetKey(self, app, index, action.id, "enter"),
                .toggle => try AutomationWidgetMethods(Runtime).dispatchAutomationWidgetKey(self, app, index, action.id, "space"),
                .increment => try AutomationWidgetMethods(Runtime).dispatchAutomationWidgetKey(self, app, index, action.id, self.views[index].canvasWidgetStepKey(action.id, .increment)),
                .decrement => try AutomationWidgetMethods(Runtime).dispatchAutomationWidgetKey(self, app, index, action.id, self.views[index].canvasWidgetStepKey(action.id, .decrement)),
                .set_text => try AutomationWidgetMethods(Runtime).setAutomationCanvasWidgetText(self, app, index, action.id, action.text),
                .set_selection => try AutomationWidgetMethods(Runtime).editAutomationCanvasWidgetText(self, index, action.id, .{ .set_selection = action.selection orelse return error.InvalidCommand }),
                .set_composition => try AutomationWidgetMethods(Runtime).editAutomationCanvasWidgetText(self, index, action.id, .{ .set_composition = .{ .text = action.text } }),
                .commit_composition => try AutomationWidgetMethods(Runtime).editAutomationCanvasWidgetText(self, index, action.id, .commit_composition),
                .cancel_composition => try AutomationWidgetMethods(Runtime).editAutomationCanvasWidgetText(self, index, action.id, .cancel_composition),
                .select => try AutomationWidgetMethods(Runtime).selectAutomationCanvasWidget(self, index, action.id),
                .drag => try AutomationWidgetMethods(Runtime).dispatchAutomationCanvasWidgetDrag(self, app, index, action.id, action.text),
                .drop_files => try AutomationWidgetMethods(Runtime).dispatchAutomationCanvasWidgetFileDrop(self, app, index, action.id, action.text),
                .dismiss => try AutomationWidgetMethods(Runtime).dismissAutomationCanvasWidget(self, app, index, action.id),
            }
            // Key-driven action routes above dispatch real input events
            // whose refresh batches defer the platform publish; the AX
            // client reads the tree next, so force-flush here too.
            try CanvasWidgetDisplayMethods(Runtime).flushDeferredCanvasWidgetAccessibility(self);
            return self.views[index].info();
        }

        pub fn stepCanvasWidgetKineticScroll(self: *Runtime, window_id: platform.WindowId, label: []const u8, dt_ms: f32) anyerror!platform.ViewInfo {
            try validateRuntimeViewParent(self, window_id);
            try validateViewLabel(label);
            const index = runtimeFindViewIndex(self, window_id, label) orelse return error.ViewNotFound;
            if (self.views[index].kind != .gpu_surface) return error.InvalidViewOptions;

            const dirty = try self.views[index].stepCanvasWidgetKineticScroll(dt_ms) orelse return self.views[index].info();
            const previous_cursor = self.views[index].canvas_widget_cursor;
            self.views[index].reconcileCanvasWidgetRenderStateAfterScroll(null);
            if (previous_cursor != self.views[index].canvas_widget_cursor) try CanvasWidgetEventMethods(Runtime).syncCanvasWidgetCursorForView(self, index);
            try CanvasWidgetEventMethods(Runtime).invalidateForCanvasWidgetDirty(self, index, dirty);
            _ = try CanvasWidgetDisplayMethods(Runtime).refreshCanvasWidgetDisplayListIfOwned(self, index);
            return self.views[index].info();
        }

        /// Arm (or retarget) a runtime-driven layout tween: the split's
        /// first-pane fraction eases from its CURRENT retained value to
        /// `tween.to` over `tween.duration_ms`, one step per presented
        /// frame, sampled from the frame event's recorded timestamp —
        /// so a recorded session replays to identical frames and idle
        /// apps present nothing (the tween itself keeps the frame
        /// channel armed only while it runs).
        ///
        /// Contract, in declaration order:
        ///   - id 0 or a non-split id is a teaching error;
        ///   - already at the target (and nothing armed): no-op;
        ///   - reduce-motion appearance or duration 0: SNAP through the
        ///     same mutation path a divider drag uses (dirty region,
        ///     resize event, reconcile survival), never animate;
        ///   - re-declared with the same target while armed: no-op —
        ///     the per-rebuild declarative hook calls this every
        ///     rebuild and must not restart the clock;
        ///   - re-declared with a NEW target while armed: retarget from
        ///     the current animated value, fresh clock;
        ///   - every tween slot taken: snap (motion degrades under
        ///     pressure; the state change always lands).
        pub fn startCanvasWidgetLayoutTween(self: *Runtime, window_id: platform.WindowId, label: []const u8, tween: canvas.CanvasWidgetLayoutTween) anyerror!platform.ViewInfo {
            try validateRuntimeViewParent(self, window_id);
            try validateViewLabel(label);
            const index = runtimeFindViewIndex(self, window_id, label) orelse return error.ViewNotFound;
            if (self.views[index].kind != .gpu_surface) return error.InvalidViewOptions;
            try startCanvasWidgetLayoutTweenForView(self, index, tween);
            return self.views[index].info();
        }

        /// The tween contract's core, shared by the public command above
        /// and the source-declared lowering in `setCanvasWidgetLayout`
        /// (a split whose SOURCE declares `resize_duration_ms` arms the
        /// same tween the Zig hook would, so both authoring surfaces
        /// step identical fractions on identical frame clocks).
        fn startCanvasWidgetLayoutTweenForView(self: *Runtime, index: usize, tween: canvas.CanvasWidgetLayoutTween) anyerror!void {
            if (tween.id == 0) return error.InvalidCommand;
            if (!std.math.isFinite(tween.to)) return error.InvalidCommand;
            const node_index = self.views[index].canvasWidgetNodeIndexById(tween.id) orelse return error.InvalidCommand;
            if (self.views[index].widget_layout_nodes[node_index].widget.kind != .split) return error.InvalidCommand;
            const current = self.views[index].widget_layout_nodes[node_index].widget.value;

            const snap = self.appearance.reduce_motion or tween.duration_ms == 0;
            if (self.views[index].findCanvasWidgetLayoutTween(tween.id)) |active| {
                if (snap) {
                    // Reduce motion arrived (or the declaration turned
                    // instant) while armed: retire the tween and land
                    // on the target through the snap path below.
                    self.views[index].removeCanvasWidgetLayoutTween(tween.id);
                } else {
                    if (active.spec.to == tween.to) return;
                    active.spec = tween;
                    active.from = current;
                    active.start_ns = 0;
                    try CanvasFrameMethods(Runtime).requestCanvasFrameForView(self, index);
                    return;
                }
            }
            if (current == tween.to) return;

            if (!snap and self.views[index].armCanvasWidgetLayoutTween(.{ .spec = tween, .from = current })) {
                try CanvasFrameMethods(Runtime).requestCanvasFrameForView(self, index);
                return;
            }
            if (try self.views[index].applyCanvasWidgetSplitFraction(node_index, tween.to)) |dirty| {
                try CanvasWidgetEventMethods(Runtime).invalidateForCanvasWidgetDirty(self, index, dirty);
            }
        }

        /// The SOURCE-declared half of the layout tween: a split whose
        /// tree declares a nonzero `resize_duration_ms` treats its
        /// declared `value` as the tween target. Called by
        /// `setCanvasWidgetLayout` after the reconciled tree lands (the
        /// reconcile kept the rendered fraction instead of snapping it
        /// to the moved source), so every rebuild re-declares the tween
        /// exactly like the Zig `layout_tweens` hook does — idempotent
        /// per target, retargeting on a new one, snapping under reduced
        /// motion. Skips:
        ///   - value 0: the "unset" sentinel (a bare split lays out at
        ///     0.5); nothing declares a target, so nothing tweens;
        ///   - a pressed divider: a live drag owns the fraction — the
        ///     tween re-arms on the first rebuild after release.
        fn armSourceDeclaredLayoutTweens(self: *Runtime, index: usize, source: canvas.WidgetLayoutTree) anyerror!void {
            for (source.nodes) |node| {
                if (node.widget.kind != .split or node.widget.id == 0) continue;
                if (node.widget.resize_duration_ms == 0) continue;
                if (node.widget.value == 0) continue;
                if (canvasWidgetSplitDividerPressed(self, index, node.widget.id)) continue;
                startCanvasWidgetLayoutTweenForView(self, index, .{
                    .id = node.widget.id,
                    .to = node.widget.value,
                    .duration_ms = node.widget.resize_duration_ms,
                    .easing = node.widget.resize_easing,
                }) catch |err| switch (err) {
                    // The id vanished in reconcile (hidden pane, dropped
                    // subtree): nothing to move — same tolerance as the
                    // Zig hook's stale-id skip.
                    error.InvalidCommand => continue,
                    else => return err,
                };
            }
        }

        /// Whether the RETAINED tree's pressed widget is this split's
        /// synthesized divider — a live drag. The drag owns the fraction
        /// while it lasts, so the source-declared tween stands down and
        /// re-arms on the first rebuild after release.
        fn canvasWidgetSplitDividerPressed(self: *Runtime, index: usize, split_id: canvas.ObjectId) bool {
            const pressed_id = self.views[index].canvas_widget_pressed_id;
            if (pressed_id == 0) return false;
            const divider_index = self.views[index].canvasWidgetNodeIndexById(pressed_id) orelse return false;
            const divider = self.views[index].widget_layout_nodes[divider_index];
            if (divider.widget.kind != .split_divider) return false;
            const parent_index = divider.parent_index orelse return false;
            if (parent_index >= self.views[index].widget_layout_node_count) return false;
            return self.views[index].widget_layout_nodes[parent_index].widget.id == split_id;
        }

        /// One presented frame's worth of layout-tween motion for a
        /// view, called from the frame event dispatch (the kinetic
        /// scroll's sibling). Each active tween samples its eased
        /// fraction at the frame's timestamp and lands it through the
        /// split-drag mutation path — retained-diff dirty regions and
        /// `on_resize` events for free. Completed tweens snap to the
        /// exact target and retire; while any remain active the next
        /// frame is requested, so the channel disarms itself the frame
        /// after the last tween settles.
        pub fn advanceCanvasWidgetLayoutTweensForFrame(self: *Runtime, view_index: usize, timestamp_ns: u64) anyerror!void {
            if (view_index >= self.view_count) return;
            if (self.views[view_index].kind != .gpu_surface) return;
            if (!self.views[view_index].canvasWidgetLayoutTweensActive()) return;

            var tween_index: usize = 0;
            while (tween_index < self.views[view_index].canvas_widget_layout_tween_count) {
                const tween = &self.views[view_index].canvas_widget_layout_tweens[tween_index];
                // The widget vanished from the tree (the model dropped
                // the split): retire silently, nothing to move.
                const node_index = self.views[view_index].canvasWidgetNodeIndexById(tween.spec.id) orelse {
                    self.views[view_index].removeCanvasWidgetLayoutTween(tween.spec.id);
                    continue;
                };
                // First advancing frame stamps the clock: the ramp runs
                // on the frame clock from the first frame that could
                // have painted it, the manual idiom's discipline.
                if (tween.start_ns == 0 or timestamp_ns < tween.start_ns) {
                    tween.start_ns = timestamp_ns;
                }
                const progress = canvas.layoutTweenProgress(tween.spec.easing, tween.spec.spring, tween.start_ns, tween.spec.duration_ms, timestamp_ns);
                const done = progress >= 1;
                const value = if (done) tween.spec.to else tween.from + (tween.spec.to - tween.from) * progress;
                if (try self.views[view_index].applyCanvasWidgetSplitFraction(node_index, value)) |dirty| {
                    try CanvasWidgetEventMethods(Runtime).invalidateForCanvasWidgetDirty(self, view_index, dirty);
                }
                if (done) {
                    // removeCanvasWidgetLayoutTween swap-removes, so the
                    // slot at tween_index now holds an unvisited tween.
                    self.views[view_index].removeCanvasWidgetLayoutTween(tween.spec.id);
                    continue;
                }
                tween_index += 1;
            }
            if (self.views[view_index].canvasWidgetLayoutTweensActive()) {
                try CanvasFrameMethods(Runtime).requestCanvasFrameForView(self, view_index);
            }
        }

        pub fn setCanvasWidgetDesignTokens(self: *Runtime, window_id: platform.WindowId, label: []const u8, tokens: canvas.DesignTokens) anyerror!platform.ViewInfo {
            try validateRuntimeViewParent(self, window_id);
            try validateViewLabel(label);
            const index = runtimeFindViewIndex(self, window_id, label) orelse return error.ViewNotFound;
            if (self.views[index].kind != .gpu_surface) return error.InvalidViewOptions;
            if (std.meta.eql(self.views[index].widget_tokens, tokens)) return self.views[index].info();
            self.views[index].widget_tokens = tokens;
            self.views[index].widget_revision += 1;
            if (self.views[index].canvas_display_list_widget_owned) {
                _ = try CanvasWidgetDisplayMethods(Runtime).refreshCanvasWidgetDisplayList(self, index);
            }
            return self.views[index].info();
        }

        pub fn canvasWidgetDesignTokens(self: *const Runtime, window_id: platform.WindowId, label: []const u8) anyerror!canvas.DesignTokens {
            try validateRuntimeViewParent(self, window_id);
            try validateViewLabel(label);
            const index = runtimeFindViewIndex(self, window_id, label) orelse return error.ViewNotFound;
            if (self.views[index].kind != .gpu_surface) return error.InvalidViewOptions;
            return self.views[index].widget_tokens;
        }

        pub fn canvasWidgetTextGeometry(self: *const Runtime, window_id: platform.WindowId, label: []const u8, id: canvas.ObjectId) anyerror!canvas.WidgetTextGeometry {
            try validateRuntimeViewParent(self, window_id);
            try validateViewLabel(label);
            if (id == 0) return error.InvalidCommand;
            const index = runtimeFindViewIndex(self, window_id, label) orelse return error.ViewNotFound;
            if (self.views[index].kind != .gpu_surface) return error.InvalidViewOptions;
            const node = self.views[index].widgetLayoutTree().findById(id) orelse return error.InvalidCommand;
            if (!canvasWidgetEditableTextKind(node.widget.kind)) return error.InvalidCommand;
            return canvas.textGeometryForWidget(node.widget, self.views[index].widget_tokens);
        }

        pub fn editCanvasWidgetText(self: *Runtime, window_id: platform.WindowId, label: []const u8, id: canvas.ObjectId, edit: canvas.TextInputEvent) anyerror!platform.ViewInfo {
            try validateRuntimeViewParent(self, window_id);
            try validateViewLabel(label);
            if (id == 0) return error.InvalidCommand;
            const index = runtimeFindViewIndex(self, window_id, label) orelse return error.ViewNotFound;
            if (self.views[index].kind != .gpu_surface) return error.InvalidViewOptions;
            if (!self.views[index].canEditCanvasWidgetText(id)) return error.InvalidCommand;

            const dirty = try self.views[index].applyCanvasWidgetTextEdit(id, edit) orelse return self.views[index].info();
            try CanvasWidgetEventMethods(Runtime).invalidateForCanvasWidgetDirty(self, index, dirty);
            _ = try CanvasWidgetDisplayMethods(Runtime).refreshCanvasWidgetDisplayListIfOwned(self, index);
            return self.views[index].info();
        }
    };
}

fn CanvasFrameMethods(comptime Runtime: type) type {
    return canvas_frame_helpers.RuntimeCanvasFrames(Runtime);
}

fn CanvasWidgetDisplayMethods(comptime Runtime: type) type {
    return runtime_canvas_widget_display.RuntimeCanvasWidgetDisplay(Runtime);
}

fn CanvasWidgetEventMethods(comptime Runtime: type) type {
    return runtime_canvas_widget_events.RuntimeCanvasWidgetEvents(Runtime);
}

fn AutomationWidgetMethods(comptime Runtime: type) type {
    return runtime_automation_widget_dispatch.RuntimeAutomationWidgetDispatch(Runtime);
}

fn ScrollDriverMethods(comptime Runtime: type) type {
    return runtime_canvas_widget_scroll_drivers.RuntimeCanvasWidgetScrollDrivers(Runtime);
}

fn validateRuntimeViewParent(self: anytype, window_id: platform.WindowId) !void {
    const index = runtimeFindWindowIndexById(self, window_id) orelse return error.WindowNotFound;
    if (!self.windows[index].info.open) return error.WindowNotFound;
}

fn runtimeFindWindowIndexById(self: anytype, id: platform.WindowId) ?usize {
    for (self.windows[0..self.window_count], 0..) |window, index| {
        if (window.info.id == id) return index;
    }
    return null;
}

fn runtimeFindViewIndex(self: anytype, window_id: platform.WindowId, label: []const u8) ?usize {
    for (self.views[0..self.view_count], 0..) |*view, index| {
        if (view.open and view.window_id == window_id and std.mem.eql(u8, view.label, label)) return index;
    }
    return null;
}
