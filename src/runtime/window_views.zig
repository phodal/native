const std = @import("std");
const geometry = @import("geometry");
const validation = @import("validation.zig");
const runtime_api = @import("api.zig");
const bridge_payload = @import("bridge_payload.zig");
const bridge_responses = @import("bridge_responses.zig");
const runtime_canvas_widget_events = @import("canvas_widget_events.zig");
const runtime_clock = @import("clock.zig");
const shell_layout = @import("shell_layout.zig");
const runtime_state = @import("state.zig");
const canvas = @import("canvas");
const app_manifest = @import("app_manifest");
const platform = @import("../platform/root.zig");
const security = @import("../security/root.zig");

const validateCommandName = validation.validateCommandName;
const validateWindowFrame = validation.validateWindowFrame;
const isMainWebViewLabel = validation.isMainWebViewLabel;
const validateWebViewLabel = validation.validateWebViewLabel;
const validateChildWebViewLabel = validation.validateChildWebViewLabel;
const validateViewOptions = validation.validateViewOptions;
const validateViewLabel = validation.validateViewLabel;
const validateViewFrame = validation.validateViewFrame;
const isValidWebViewFrame = validation.isValidWebViewFrame;

const jsonStringField = bridge_payload.jsonStringField;
const webViewWindowIdFromJson = bridge_payload.webViewWindowIdFromJson;
const viewKindFromString = bridge_payload.viewKindFromString;
const viewWindowIdFromJson = bridge_payload.viewWindowIdFromJson;
const viewFrameFromJson = bridge_payload.viewFrameFromJson;
const viewLayerFromJson = bridge_payload.viewLayerFromJson;
const webViewUrlOrigin = bridge_payload.webViewUrlOrigin;
const webViewFrameFromJson = bridge_payload.webViewFrameFromJson;
const webViewLayerFromJson = bridge_payload.webViewLayerFromJson;
const writeWindowJson = bridge_responses.writeWindowJson;
const writeWebViewJson = bridge_responses.writeWebViewJson;
const writeViewJson = bridge_responses.writeViewJson;
const writeViewJsonToWriter = bridge_responses.writeViewJsonToWriter;
const writeWebViewJsonToWriter = bridge_responses.writeWebViewJsonToWriter;
const viewInfoFromWebView = bridge_responses.viewInfoFromWebView;
const RuntimeMainWebViewState = runtime_state.RuntimeMainWebViewState;
const RuntimeWebView = runtime_state.RuntimeWebView;
const ShellApplyMode = runtime_state.ShellApplyMode;
const WindowSourcePolicy = runtime_state.WindowSourcePolicy;
const FocusTraversalDirection = runtime_state.FocusTraversalDirection;
const copySourceInto = runtime_state.copySourceInto;
const sourceWebViewUrl = runtime_state.sourceWebViewUrl;
const RuntimeShellLayout = shell_layout.RuntimeShellLayout;
const ShellLayout = shell_layout.ShellLayout;
const shellRestorePolicy = shell_layout.shellRestorePolicy;
const shellViewOptions = shell_layout.shellViewOptions;
const combinedViewportInsets = shell_layout.combinedViewportInsets;
const nowNanoseconds = runtime_clock.nowNanoseconds;
const timestampToU64 = runtime_clock.timestampToU64;
const CommandSource = runtime_api.CommandSource;

fn copyInto(buffer: []u8, value: []const u8) ![]const u8 {
    if (value.len > buffer.len) return error.NoSpaceLeft;
    @memcpy(buffer[0..value.len], value);
    return buffer[0..value.len];
}

fn isFocusableViewInfo(view: platform.ViewInfo) bool {
    return view.open and view.visible and view.enabled;
}

pub fn RuntimeWindowViews(comptime Runtime: type) type {
    const CanvasWidgetEventMethods = runtime_canvas_widget_events.RuntimeCanvasWidgetEvents(Runtime);

    return struct {
        const Self = @This();
        pub fn createWindow(self: *Runtime, options: platform.WindowCreateOptions) anyerror!platform.WindowInfo {
            return Self.createWindowWithSourceMode(self, options, options.source == null, .require_source);
        }

        pub fn listWindows(self: *const Runtime, output: []platform.WindowInfo) []const platform.WindowInfo {
            const count = @min(output.len, self.window_count);
            for (self.windows[0..count], 0..) |window, index| {
                output[index] = window.info;
            }
            return output[0..count];
        }

        pub fn focusWindow(self: *Runtime, window_id: platform.WindowId) anyerror!void {
            const index = Self.findWindowIndexById(self, window_id) orelse return error.WindowNotFound;
            try self.options.platform.services.focusWindow(window_id);
            Self.setFocusedIndex(self, index);
            self.invalidated = true;
        }

        pub fn closeWindow(self: *Runtime, window_id: platform.WindowId) anyerror!void {
            const index = Self.findWindowIndexById(self, window_id) orelse return error.WindowNotFound;
            try self.options.platform.services.closeWindow(window_id);
            self.windows[index].info.open = false;
            self.windows[index].info.focused = false;
            Self.removeWindowRuntimeViews(self, window_id);
            self.invalidated = true;
        }

        pub fn createShellWindow(self: *Runtime, shell_window: app_manifest.ShellWindow, source: ?platform.WebViewSource) anyerror!platform.WindowInfo {
            return Self.createShellWindowWithSourceMode(self, shell_window, source, source == null);
        }

        pub fn createShellWindowWithSourceMode(self: *Runtime, shell_window: app_manifest.ShellWindow, source: ?platform.WebViewSource, source_reloads_from_app: bool) anyerror!platform.WindowInfo {
            const window_frame = geometry.RectF.init(
                shell_window.x orelse 0,
                shell_window.y orelse 0,
                shell_window.width,
                shell_window.height,
            );
            const info = try Self.createWindowWithSourceMode(self, .{
                .label = shell_window.label,
                .title = shell_window.title orelse "",
                .default_frame = window_frame,
                .resizable = shell_window.resizable,
                .restore_state = shell_window.restore_state,
                .restore_policy = shellRestorePolicy(shell_window.restore_policy),
                .source = source,
            }, source_reloads_from_app, .allow_source_less);
            errdefer Self.closeWindow(self, info.id) catch {};

            try Self.createShellViews(self, info.id, shell_window.views, Self.shellBoundsForWindow(self, info.id));
            return info;
        }

        pub fn createShellViews(self: *Runtime, window_id: platform.WindowId, views: []const app_manifest.ShellView, bounds: geometry.RectF) anyerror!void {
            if (views.len > app_manifest.max_shell_views_per_window) return error.ViewLimitReached;
            try Self.validateShellViewCreatePlan(self, window_id, views);

            var main_state: RuntimeMainWebViewState = undefined;
            try Self.captureMainWebViewState(self, window_id, &main_state);
            errdefer Self.restoreMainWebViewState(self, window_id, &main_state) catch {};

            var created_labels: [app_manifest.max_shell_views_per_window][]const u8 = undefined;
            var created_count: usize = 0;
            errdefer Self.rollbackCreatedShellViews(self, window_id, created_labels[0..created_count]);

            try Self.applyShellViews(self, window_id, views, bounds, .create, &created_labels, &created_count);
            try Self.bindShellViews(self, window_id, views);
        }

        pub fn relayoutShellViews(self: *Runtime, window_id: platform.WindowId) anyerror!void {
            const binding = Self.shellLayoutForWindow(self, window_id) orelse return;
            try Self.applyShellViews(self, window_id, binding.viewSlice(), Self.shellBoundsForWindow(self, window_id), .update, null, null);
        }

        pub fn validateShellViewCreatePlan(self: *Runtime, window_id: platform.WindowId, views: []const app_manifest.ShellView) anyerror!void {
            try Self.validateViewParent(self, window_id);

            var native_view_count: usize = 0;
            var child_webview_count: usize = 0;
            for (views, 0..) |view, index| {
                for (views[0..index]) |previous| {
                    if (std.mem.eql(u8, previous.label, view.label)) return error.DuplicateViewLabel;
                }

                if (view.kind == .webview and isMainWebViewLabel(view.label)) continue;
                if (Self.viewLabelExists(self, window_id, view.label)) return error.DuplicateViewLabel;

                if (view.kind == .webview) {
                    child_webview_count += 1;
                } else {
                    native_view_count += 1;
                }
            }

            if (native_view_count > platform.max_views - self.view_count) return error.ViewLimitReached;
            if (child_webview_count > platform.max_webviews - self.webview_count) return error.WebViewLimitReached;
        }

        pub fn applyShellViews(self: *Runtime, window_id: platform.WindowId, views: []const app_manifest.ShellView, bounds: geometry.RectF, mode: ShellApplyMode, tracked_labels: ?*[app_manifest.max_shell_views_per_window][]const u8, tracked_count: ?*usize) anyerror!void {
            var layout = ShellLayout.init(bounds, views);
            var created: [app_manifest.max_shell_views_per_window]bool = [_]bool{false} ** app_manifest.max_shell_views_per_window;
            var created_count: usize = 0;
            while (created_count < views.len) {
                var progressed = false;
                for (views, 0..) |view, index| {
                    if (created[index]) continue;
                    if (view.parent) |parent| {
                        if (!layout.containsView(parent)) continue;
                    }
                    const did_create = try Self.applyShellView(self, try shellViewOptions(window_id, view, &layout), mode);
                    if (did_create) {
                        if (tracked_labels) |labels| {
                            const count = tracked_count.?;
                            labels[count.*] = view.label;
                            count.* += 1;
                        }
                    }
                    created[index] = true;
                    created_count += 1;
                    progressed = true;
                }
                if (!progressed) return error.InvalidViewOptions;
            }
        }

        pub fn applyShellView(self: *Runtime, options: platform.ViewOptions, mode: ShellApplyMode) anyerror!bool {
            switch (mode) {
                .create => {
                    if (options.kind == .webview and isMainWebViewLabel(options.label)) {
                        try Self.setMainWebViewParent(self, options.window_id, options.parent);
                        _ = try Self.updateView(self, options.window_id, options.label, .{
                            .frame = options.frame,
                            .layer = options.layer,
                        });
                        return false;
                    }
                    _ = try Self.createView(self, options);
                    return true;
                },
                .update => {
                    if (options.kind == .webview and isMainWebViewLabel(options.label)) {
                        try Self.setMainWebViewParent(self, options.window_id, options.parent);
                    }
                    _ = Self.updateView(self, options.window_id, options.label, .{
                        .frame = options.frame,
                        .layer = options.layer,
                    }) catch |err| switch (err) {
                        error.ViewNotFound,
                        error.WebViewNotFound,
                        => return false,
                        else => return err,
                    };
                    return false;
                },
            }
        }

        pub fn rollbackCreatedShellViews(self: *Runtime, window_id: platform.WindowId, labels: []const []const u8) void {
            var index = labels.len;
            while (index > 0) {
                index -= 1;
                Self.closeView(self, window_id, labels[index]) catch {};
            }
        }

        pub fn captureMainWebViewState(self: *Runtime, window_id: platform.WindowId, state: *RuntimeMainWebViewState) !void {
            const index = Self.findWindowIndexById(self, window_id) orelse return error.WindowNotFound;
            const window = self.windows[index];
            state.* = .{
                .frame = window.main_frame,
                .frame_set = window.main_frame_set,
                .layer = window.main_layer,
            };
            state.parent = if (window.main_parent) |parent| try copyInto(&state.parent_storage, parent) else null;
        }

        pub fn restoreMainWebViewState(self: *Runtime, window_id: platform.WindowId, state: *const RuntimeMainWebViewState) !void {
            const index = Self.findWindowIndexById(self, window_id) orelse return error.WindowNotFound;
            const window = self.windows[index];
            var restore_error: ?anyerror = null;

            if (window.source != null) {
                if (window.main_frame_set != state.frame_set or !Self.rectsEqual(window.main_frame, state.frame)) {
                    self.options.platform.services.setWebViewFrame(window_id, "main", state.frame) catch |err| {
                        restore_error = err;
                    };
                }
                if (window.main_layer != state.layer) {
                    self.options.platform.services.setWebViewLayer(window_id, "main", state.layer) catch |err| {
                        if (restore_error == null) restore_error = err;
                    };
                }
            }

            self.windows[index].main_frame = state.frame;
            self.windows[index].main_frame_set = state.frame_set;
            self.windows[index].main_layer = state.layer;
            self.windows[index].main_parent = if (state.parent) |parent| try copyInto(&self.windows[index].main_parent_storage, parent) else null;

            if (restore_error) |err| return err;
        }

        pub fn createView(self: *Runtime, options: platform.ViewOptions) anyerror!platform.ViewInfo {
            try Self.validateViewParent(self, options.window_id);
            try validateViewOptions(options);
            if (Self.viewLabelExists(self, options.window_id, options.label)) return error.DuplicateViewLabel;
            try Self.validateViewParentLink(self, options.window_id, options.label, options.parent);
            if (options.kind == .webview) return Self.createWebViewView(self, options);
            if (self.view_count >= platform.max_views) return error.ViewLimitReached;

            try self.options.platform.services.createView(options);
            var reserved = false;
            errdefer {
                if (reserved) {
                    if (Self.findViewIndex(self, options.window_id, options.label)) |index| Self.removeViewAt(self, index);
                }
                self.options.platform.services.closeView(options.window_id, options.label) catch {};
            }
            try Self.reserveView(self, options);
            reserved = true;
            self.invalidateFor(.command, options.frame);
            return self.views[self.view_count - 1].info();
        }

        pub fn updateView(self: *Runtime, window_id: platform.WindowId, label: []const u8, patch: platform.ViewPatch) anyerror!platform.ViewInfo {
            try Self.validateViewParent(self, window_id);
            try validateViewLabel(label);
            if (patch.frame) |view_frame| try validateViewFrame(view_frame);
            if (patch.role) |role| {
                if (role.len > platform.max_view_role_bytes) return error.ViewRoleTooLarge;
            }
            if (patch.accessibility_label) |accessibility_label| {
                if (accessibility_label.len > platform.max_view_accessibility_label_bytes) return error.ViewAccessibilityLabelTooLarge;
            }
            if (patch.text) |text| {
                if (text.len > platform.max_view_text_bytes) return error.ViewTextTooLarge;
            }
            if (patch.command) |command| {
                if (command.len > 0) try validateCommandName(command);
            }
            if (patch.url != null and !isMainWebViewLabel(label) and Self.findWebViewIndex(self, window_id, label) == null) return error.InvalidViewOptions;

            if (isMainWebViewLabel(label) or Self.findWebViewIndex(self, window_id, label) != null) {
                return Self.updateWebViewView(self, window_id, label, patch);
            }

            const index = Self.findViewIndex(self, window_id, label) orelse return error.ViewNotFound;
            try self.options.platform.services.updateView(window_id, label, patch);
            if (patch.frame) |view_frame| self.views[index].frame = view_frame;
            if (patch.layer) |layer| self.views[index].layer = layer;
            if (patch.visible) |visible| self.views[index].visible = visible;
            if (patch.enabled) |enabled| self.views[index].enabled = enabled;
            if (patch.role) |role| self.views[index].role = try copyInto(&self.views[index].role_storage, role);
            if (patch.accessibility_label) |accessibility_label| self.views[index].accessibility_label = try copyInto(&self.views[index].accessibility_label_storage, accessibility_label);
            if (patch.text) |text| self.views[index].text = try copyInto(&self.views[index].text_storage, text);
            if (patch.command) |command| self.views[index].command = try copyInto(&self.views[index].command_storage, command);
            if (patch.frame != null) try Self.relayoutDescendantWebViewBackends(self, window_id, label);
            self.invalidateFor(.command, patch.frame);
            if (self.views[index].focused and !isFocusableViewInfo(self.views[index].info())) {
                Self.ensureFocusableViewFocused(self, window_id);
            }
            return self.views[index].info();
        }

        pub fn closeView(self: *Runtime, window_id: platform.WindowId, label: []const u8) anyerror!void {
            try Self.validateViewParent(self, window_id);
            try validateViewLabel(label);
            if (isMainWebViewLabel(label)) return error.InvalidViewOptions;

            if (Self.findWebViewIndex(self, window_id, label)) |webview_index| {
                const was_focused = self.webviews[webview_index].focused;
                try self.options.platform.services.closeWebView(window_id, label);
                Self.removeWebViewAt(self, webview_index);
                if (was_focused) Self.ensureFocusableViewFocused(self, window_id);
                self.invalidateFor(.command, null);
                return;
            }

            _ = Self.findViewIndex(self, window_id, label) orelse return error.ViewNotFound;
            const was_focused = Self.viewTreeHasFocused(self, window_id, label);
            try Self.closeDescendantWebViewBackends(self, window_id, label);
            try self.options.platform.services.closeView(window_id, label);
            Self.removeDescendantViewsForParent(self, window_id, label);
            Self.removeDescendantWebViewsForParent(self, window_id, label);
            if (Self.findViewIndex(self, window_id, label)) |current_index| Self.removeViewAt(self, current_index);
            if (was_focused) Self.ensureFocusableViewFocused(self, window_id);
            self.invalidateFor(.command, null);
        }

        pub fn listViews(self: *const Runtime, window_id: platform.WindowId, output: []platform.ViewInfo) []const platform.ViewInfo {
            const window_index = Self.findWindowIndexById(self, window_id) orelse return output[0..0];
            if (!self.windows[window_index].info.open) return output[0..0];

            var count: usize = 0;
            if (self.windows[window_index].source != null and count < output.len) {
                output[count] = viewInfoFromWebView(Self.mainWebViewInfo(self, window_index));
                count += 1;
            }
            for (self.views[0..self.view_count]) |view| {
                if (!view.open or view.window_id != window_id) continue;
                if (count >= output.len) return output[0..count];
                output[count] = view.info();
                count += 1;
            }
            for (self.webviews[0..self.webview_count]) |webview| {
                if (!webview.open or webview.window_id != window_id) continue;
                if (count >= output.len) return output[0..count];
                output[count] = viewInfoFromWebView(webview);
                count += 1;
            }
            return output[0..count];
        }

        pub fn focusView(self: *Runtime, window_id: platform.WindowId, label: []const u8) anyerror!void {
            try Self.validateViewParent(self, window_id);
            try validateViewLabel(label);
            if (!Self.viewLabelExists(self, window_id, label)) return error.ViewNotFound;
            try self.options.platform.services.focusView(window_id, label);
            try Self.setFocusedView(self, window_id, label);
            self.invalidateFor(.command, null);
        }

        pub fn focusNextView(self: *Runtime, window_id: platform.WindowId) anyerror!platform.ViewInfo {
            return Self.focusAdjacentView(self, window_id, .next);
        }

        pub fn focusPreviousView(self: *Runtime, window_id: platform.WindowId) anyerror!platform.ViewInfo {
            return Self.focusAdjacentView(self, window_id, .previous);
        }

        pub fn createWindowWithSourceMode(self: *Runtime, options: platform.WindowCreateOptions, source_reloads_from_app: bool, source_policy: WindowSourcePolicy) anyerror!platform.WindowInfo {
            const source = options.source orelse self.loaded_source orelse switch (source_policy) {
                .require_source => return error.MissingWindowSource,
                .allow_source_less => null,
            };
            const id = if (options.id != 0) options.id else Self.allocateWindowId(
                self,
            );
            const label = if (options.label.len > 0) options.label else return error.InvalidWindowOptions;
            try validateWindowFrame(options.default_frame);
            if (Self.findWindowIndexById(self, id) != null) return error.DuplicateWindowId;
            if (Self.findWindowIndexByLabel(self, label) != null) return error.DuplicateWindowLabel;
            const index = try Self.reserveWindow(self, id, label, options.title, source, source_reloads_from_app);
            var native_created = false;
            errdefer Self.removeWindowAt(self, index);
            errdefer if (native_created) self.options.platform.services.closeWindow(id) catch {};

            const window_options = options.windowOptions(id, self.windows[index].info.label);
            const native_info = try self.options.platform.services.createWindow(window_options);
            native_created = true;
            Self.applyNativeInfo(self, index, native_info);
            if (self.windows[index].source) |window_source| {
                try self.options.platform.services.loadWindowWebView(id, window_source);
            }
            self.invalidated = true;
            return self.windows[index].info;
        }

        pub fn reserveWindow(self: *Runtime, id: platform.WindowId, label: []const u8, title: []const u8, source: ?platform.WebViewSource, source_reloads_from_app: bool) !usize {
            if (self.window_count >= platform.max_windows) return error.WindowLimitReached;
            if (label.len == 0) return error.InvalidWindowOptions;
            const index = self.window_count;
            self.windows[index] = .{};
            const copied_label = try copyInto(&self.windows[index].label_storage, label);
            const copied_title = try copyInto(&self.windows[index].title_storage, title);
            self.windows[index].info = .{
                .id = id,
                .label = copied_label,
                .title = copied_title,
                .open = true,
                .focused = self.window_count == 0,
            };
            self.windows[index].main_view_id = Self.allocateViewId(
                self,
            );
            self.windows[index].source = if (source) |source_value| try Self.copySource(self, index, source_value) else null;
            self.windows[index].source_reloads_from_app = source_reloads_from_app;
            self.windows[index].main_frame = geometry.RectF.init(0, 0, self.windows[index].info.frame.width, self.windows[index].info.frame.height);
            self.windows[index].main_frame_set = false;
            self.windows[index].main_layer = 0;
            self.windows[index].main_zoom = 1.0;
            self.windows[index].main_focused = self.windows[index].info.focused;
            self.window_count += 1;
            self.next_window_id = @max(self.next_window_id, id + 1);
            return index;
        }

        pub fn removeWindowAt(self: *Runtime, index: usize) void {
            if (index >= self.window_count) return;
            Self.removeShellLayoutForWindow(self, self.windows[index].info.id);
            var cursor = index;
            while (cursor + 1 < self.window_count) : (cursor += 1) {
                self.windows[cursor] = self.windows[cursor + 1];
            }
            self.window_count -= 1;
        }

        pub fn copySource(self: *Runtime, index: usize, source: platform.WebViewSource) !platform.WebViewSource {
            return copySourceInto(&self.windows[index].source_storage, source);
        }

        pub fn copyLoadedSource(self: *Runtime, source: platform.WebViewSource) !platform.WebViewSource {
            return copySourceInto(&self.loaded_source_storage, source);
        }

        pub fn applyNativeInfo(self: *Runtime, index: usize, native_info: platform.WindowInfo) void {
            self.windows[index].info.frame = native_info.frame;
            self.windows[index].info.scale_factor = native_info.scale_factor;
            self.windows[index].info.open = native_info.open;
            self.windows[index].info.focused = native_info.focused;
            if (!self.windows[index].main_frame_set) {
                self.windows[index].main_frame = geometry.RectF.init(0, 0, native_info.frame.width, native_info.frame.height);
            }
            if (native_info.focused) Self.setFocusedIndex(self, index);
        }

        pub fn updateWindowState(self: *Runtime, state: platform.WindowState) !void {
            const existing_index = Self.findWindowIndexById(self, state.id);
            const index = existing_index orelse try Self.reserveWindow(self, state.id, state.label, state.title, null, true);
            var info = self.windows[index].info;
            info.frame = state.frame;
            info.scale_factor = state.scale_factor;
            info.open = state.open;
            info.focused = state.focused;
            self.windows[index].info = info;
            if (!self.windows[index].main_frame_set) {
                self.windows[index].main_frame = geometry.RectF.init(0, 0, state.frame.width, state.frame.height);
            }
            if (!state.open) Self.removeWindowRuntimeViews(self, state.id);
            if (state.focused) Self.setFocusedIndex(self, index);
        }

        pub fn runtimeWindowStateForPersistence(self: *const Runtime, state: platform.WindowState) platform.WindowState {
            var persisted = state;
            if (Self.findWindowIndexById(self, state.id)) |index| {
                persisted.label = self.windows[index].info.label;
                persisted.title = self.windows[index].info.title;
            }
            return persisted;
        }

        pub fn removeWindowRuntimeViews(self: *Runtime, window_id: platform.WindowId) void {
            if (Self.findWindowIndexById(self, window_id)) |index| self.windows[index].main_parent = null;
            Self.removeShellLayoutForWindow(self, window_id);
            Self.removeViewsForWindow(self, window_id);
            Self.removeWebViewsForWindow(self, window_id);
        }

        pub fn shellBoundsForWindow(self: *const Runtime, window_id: platform.WindowId) geometry.RectF {
            const index = Self.findWindowIndexById(self, window_id) orelse return geometry.RectF.init(0, 0, 0, 0);
            const frame_value = self.windows[index].info.frame;
            const bounds = geometry.RectF.init(0, 0, frame_value.width, frame_value.height);
            if (self.surface.id != window_id) return bounds;
            return bounds.deflate(combinedViewportInsets(self.surface));
        }

        pub fn startupWindowFrame(native_frame: geometry.RectF, manifest_frame: geometry.RectF) geometry.RectF {
            const default_frame = (platform.WindowOptions{}).default_frame;
            if (!Self.rectsEqual(native_frame, default_frame)) return native_frame;
            return manifest_frame;
        }

        pub fn rectsEqual(a: geometry.RectF, b: geometry.RectF) bool {
            return a.x == b.x and a.y == b.y and a.width == b.width and a.height == b.height;
        }

        pub fn canvasDirtyRegionForView(view_frame: geometry.RectF, local_dirty: geometry.RectF) ?geometry.RectF {
            const normalized_view = view_frame.normalized();
            const surface_bounds = geometry.RectF.init(0, 0, normalized_view.width, normalized_view.height);
            const clipped = geometry.RectF.intersection(surface_bounds, local_dirty.normalized());
            if (clipped.isEmpty()) return null;
            return clipped.translate(.{ .dx = normalized_view.x, .dy = normalized_view.y });
        }

        pub fn bindShellViews(self: *Runtime, window_id: platform.WindowId, views: []const app_manifest.ShellView) !void {
            if (Self.findShellLayoutIndex(self, window_id)) |index| {
                try self.shell_layouts[index].copyViews(views);
                return;
            }
            if (self.shell_layout_count >= self.shell_layouts.len) return error.WindowLimitReached;
            self.shell_layouts[self.shell_layout_count].window_id = window_id;
            try self.shell_layouts[self.shell_layout_count].copyViews(views);
            self.shell_layout_count += 1;
        }

        pub fn shellLayoutForWindow(self: *const Runtime, window_id: platform.WindowId) ?*const RuntimeShellLayout {
            const index = Self.findShellLayoutIndex(self, window_id) orelse return null;
            return &self.shell_layouts[index];
        }

        pub fn findShellLayoutIndex(self: *const Runtime, window_id: platform.WindowId) ?usize {
            for (self.shell_layouts[0..self.shell_layout_count], 0..) |layout, index| {
                if (layout.window_id == window_id) return index;
            }
            return null;
        }

        pub fn removeShellLayoutForWindow(self: *Runtime, window_id: platform.WindowId) void {
            const index = Self.findShellLayoutIndex(self, window_id) orelse return;
            var cursor = index;
            while (cursor + 1 < self.shell_layout_count) : (cursor += 1) {
                self.shell_layouts[cursor] = self.shell_layouts[cursor + 1];
            }
            self.shell_layout_count -= 1;
        }

        pub fn setFocusedIndex(self: *Runtime, focused_index: usize) void {
            for (self.windows[0..self.window_count], 0..) |*window, index| {
                window.info.focused = index == focused_index;
            }
        }

        pub fn findWindowIndexById(self: *const Runtime, id: platform.WindowId) ?usize {
            for (self.windows[0..self.window_count], 0..) |window, index| {
                if (window.info.id == id) return index;
            }
            return null;
        }

        pub fn findWindowIndexByLabel(self: *const Runtime, label: []const u8) ?usize {
            for (self.windows[0..self.window_count], 0..) |window, index| {
                if (std.mem.eql(u8, window.info.label, label)) return index;
            }
            return null;
        }

        pub fn allocateWindowId(self: *Runtime) platform.WindowId {
            while (Self.findWindowIndexById(self, self.next_window_id) != null) self.next_window_id += 1;
            const id = self.next_window_id;
            self.next_window_id += 1;
            return id;
        }

        pub fn allocateViewId(self: *Runtime) platform.ViewId {
            const id = self.next_view_id;
            self.next_view_id += 1;
            return id;
        }

        pub fn validateWebViewParent(self: *Runtime, window_id: platform.WindowId) !void {
            const index = Self.findWindowIndexById(self, window_id) orelse return error.WindowNotFound;
            if (!self.windows[index].info.open) return error.WindowNotFound;
        }

        pub fn validateWebViewUrl(self: *Runtime, url: []const u8) !void {
            if (url.len == 0) return error.MissingWebViewUrl;
            if (url.len > platform.max_webview_url_bytes) return error.WebViewUrlTooLarge;
            var origin_buffer: [512]u8 = undefined;
            const origin = try webViewUrlOrigin(url, &origin_buffer);
            if (!security.allowsOrigin(self.options.security.navigation.allowed_origins, origin)) return error.NavigationDenied;
        }

        pub fn writeWebViewListJson(self: *Runtime, source_window_id: platform.WindowId, output: []u8) ![]const u8 {
            try Self.validateWebViewParent(self, source_window_id);
            var writer = std.Io.Writer.fixed(output);
            try writer.writeByte('[');
            const window_index = Self.findWindowIndexById(self, source_window_id) orelse return error.WindowNotFound;
            try writeWebViewJsonToWriter(Self.mainWebViewInfo(self, window_index), &writer);
            var written: usize = 1;
            for (self.webviews[0..self.webview_count]) |webview| {
                if (webview.window_id != source_window_id or !webview.open) continue;
                if (written > 0) try writer.writeByte(',');
                try writeWebViewJsonToWriter(webview, &writer);
                written += 1;
            }
            try writer.writeByte(']');
            return writer.buffered();
        }

        pub fn reserveWebView(self: *Runtime, id: platform.ViewId, window_id: platform.WindowId, label: []const u8, parent: ?[]const u8, url: []const u8, local_frame: geometry.RectF, platform_frame: geometry.RectF, layer: i32, transparent: bool, bridge_enabled: bool) !void {
            const index = self.webview_count;
            self.webviews[index] = .{
                .id = id,
                .window_id = window_id,
                .frame = platform_frame,
                .local_frame = local_frame,
                .layer = layer,
                .transparent = transparent,
                .bridge_enabled = bridge_enabled,
                .open = true,
            };
            self.webviews[index].label = try copyInto(&self.webviews[index].label_storage, label);
            self.webviews[index].parent = if (parent) |value| try copyInto(&self.webviews[index].parent_storage, value) else null;
            self.webviews[index].url = try copyInto(&self.webviews[index].url_storage, url);
            self.webview_count += 1;
        }

        pub fn findWebViewIndex(self: *const Runtime, window_id: platform.WindowId, label: []const u8) ?usize {
            for (self.webviews[0..self.webview_count], 0..) |webview, index| {
                if (webview.open and webview.window_id == window_id and std.mem.eql(u8, webview.label, label)) return index;
            }
            return null;
        }

        pub fn removeWebViewAt(self: *Runtime, index: usize) void {
            if (index >= self.webview_count) return;
            var cursor = index;
            while (cursor + 1 < self.webview_count) : (cursor += 1) {
                const next = self.webviews[cursor + 1];
                self.webviews[cursor] = .{
                    .id = next.id,
                    .window_id = next.window_id,
                    .frame = next.frame,
                    .local_frame = next.local_frame,
                    .layer = next.layer,
                    .zoom = next.zoom,
                    .transparent = next.transparent,
                    .bridge_enabled = next.bridge_enabled,
                    .focused = next.focused,
                    .open = next.open,
                };
                self.webviews[cursor].label = copyInto(&self.webviews[cursor].label_storage, next.label) catch unreachable;
                self.webviews[cursor].parent = if (next.parent) |parent| copyInto(&self.webviews[cursor].parent_storage, parent) catch unreachable else null;
                self.webviews[cursor].url = copyInto(&self.webviews[cursor].url_storage, next.url) catch unreachable;
            }
            self.webview_count -= 1;
        }

        pub fn removeWebViewsForWindow(self: *Runtime, window_id: platform.WindowId) void {
            var index: usize = 0;
            while (index < self.webview_count) {
                if (self.webviews[index].window_id == window_id) {
                    Self.removeWebViewAt(self, index);
                } else {
                    index += 1;
                }
            }
        }

        pub fn mainWebViewInfo(self: *const Runtime, window_index: usize) RuntimeWebView {
            const window = self.windows[window_index];
            const fallback_frame = geometry.RectF.init(0, 0, window.info.frame.width, window.info.frame.height);
            return .{
                .id = window.main_view_id,
                .window_id = window.info.id,
                .label = "main",
                .parent = window.main_parent,
                .url = sourceWebViewUrl(window.source),
                .frame = if (window.main_frame_set) window.main_frame else fallback_frame,
                .layer = window.main_layer,
                .zoom = window.main_zoom,
                .transparent = false,
                .bridge_enabled = true,
                .focused = window.main_focused,
                .open = window.info.open,
            };
        }

        pub fn createWebViewView(self: *Runtime, options: platform.ViewOptions) !platform.ViewInfo {
            try validateChildWebViewLabel(options.label);
            try Self.validateWebViewUrl(self, options.url);
            if (!isValidWebViewFrame(options.frame)) return error.InvalidWebViewOptions;
            if (self.webview_count >= platform.max_webviews) return error.WebViewLimitReached;
            var platform_options = options;
            platform_options.frame = try Self.platformFrameForView(self, options.window_id, options.parent, options.frame);
            try self.options.platform.services.createView(platform_options);
            var reserved = false;
            errdefer {
                if (reserved) {
                    if (Self.findWebViewIndex(self, options.window_id, options.label)) |index| Self.removeWebViewAt(self, index);
                }
                self.options.platform.services.closeView(options.window_id, options.label) catch {};
            }
            try Self.reserveWebView(self, Self.allocateViewId(
                self,
            ), options.window_id, options.label, options.parent, options.url, options.frame, platform_options.frame, options.layer, options.transparent, options.bridge_enabled);
            reserved = true;
            self.invalidateFor(.command, platform_options.frame);
            return viewInfoFromWebView(self.webviews[self.webview_count - 1]);
        }

        pub fn setMainWebViewParent(self: *Runtime, window_id: platform.WindowId, parent: ?[]const u8) !void {
            const index = Self.findWindowIndexById(self, window_id) orelse return error.WindowNotFound;
            self.windows[index].main_parent = if (parent) |value| try copyInto(&self.windows[index].main_parent_storage, value) else null;
        }

        pub fn updateWebViewView(self: *Runtime, window_id: platform.WindowId, label: []const u8, patch: platform.ViewPatch) !platform.ViewInfo {
            if (patch.visible != null or patch.enabled != null or patch.role != null or patch.accessibility_label != null or patch.text != null or patch.command != null) return error.InvalidViewOptions;
            if (isMainWebViewLabel(label)) {
                const window_index = Self.findWindowIndexById(self, window_id) orelse return error.WindowNotFound;
                if (patch.url != null) return error.InvalidViewOptions;
                if (patch.frame) |view_frame| {
                    if (!isValidWebViewFrame(view_frame)) return error.InvalidWebViewOptions;
                    if (self.windows[window_index].source != null) {
                        try self.options.platform.services.setWebViewFrame(window_id, label, view_frame);
                    }
                    self.windows[window_index].main_frame = view_frame;
                    self.windows[window_index].main_frame_set = true;
                    try Self.relayoutDescendantWebViewBackends(self, window_id, label);
                }
                if (patch.layer) |layer| {
                    if (self.windows[window_index].source != null) {
                        try self.options.platform.services.setWebViewLayer(window_id, label, layer);
                    }
                    self.windows[window_index].main_layer = layer;
                }
                self.invalidateFor(.command, patch.frame);
                return viewInfoFromWebView(Self.mainWebViewInfo(self, window_index));
            }

            const webview_index = Self.findWebViewIndex(self, window_id, label) orelse return error.WebViewNotFound;
            if (patch.frame) |view_frame| {
                if (!isValidWebViewFrame(view_frame)) return error.InvalidWebViewOptions;
                const platform_frame = try Self.platformFrameForView(self, window_id, self.webviews[webview_index].parent, view_frame);
                try self.options.platform.services.setWebViewFrame(window_id, label, platform_frame);
                self.webviews[webview_index].local_frame = view_frame;
                self.webviews[webview_index].frame = platform_frame;
                try Self.relayoutDescendantWebViewBackends(self, window_id, label);
            }
            if (patch.layer) |layer| {
                try self.options.platform.services.setWebViewLayer(window_id, label, layer);
                self.webviews[webview_index].layer = layer;
            }
            if (patch.url) |url| {
                try Self.validateWebViewUrl(self, url);
                try self.options.platform.services.navigateWebView(window_id, label, url);
                self.webviews[webview_index].url = try copyInto(&self.webviews[webview_index].url_storage, url);
            }
            self.invalidateFor(.command, patch.frame);
            return viewInfoFromWebView(self.webviews[webview_index]);
        }

        pub fn validateViewParent(self: *const Runtime, window_id: platform.WindowId) !void {
            const index = Self.findWindowIndexById(self, window_id) orelse return error.WindowNotFound;
            if (!self.windows[index].info.open) return error.WindowNotFound;
        }

        pub fn validateViewParentLink(self: *const Runtime, window_id: platform.WindowId, label: []const u8, parent: ?[]const u8) !void {
            const parent_label = parent orelse return;
            if (std.mem.eql(u8, parent_label, label)) return error.InvalidViewOptions;
            if (!Self.viewLabelExists(self, window_id, parent_label)) return error.ViewNotFound;
        }

        pub fn platformFrameForView(self: *const Runtime, window_id: platform.WindowId, parent: ?[]const u8, base_frame: geometry.RectF) !geometry.RectF {
            var platform_frame = base_frame;
            if (parent) |parent_label| {
                const parent_frame = try Self.absoluteViewFrame(self, window_id, parent_label, 0);
                platform_frame.x += parent_frame.x;
                platform_frame.y += parent_frame.y;
            }
            return platform_frame;
        }

        pub fn localFrameForView(self: *const Runtime, window_id: platform.WindowId, parent: ?[]const u8, base_frame: geometry.RectF) !geometry.RectF {
            var local_frame = base_frame;
            if (parent) |parent_label| {
                const parent_frame = try Self.absoluteViewFrame(self, window_id, parent_label, 0);
                local_frame.x -= parent_frame.x;
                local_frame.y -= parent_frame.y;
            }
            return local_frame;
        }

        pub fn absoluteViewFrame(self: *const Runtime, window_id: platform.WindowId, label: []const u8, depth: usize) !geometry.RectF {
            if (depth >= platform.max_views + platform.max_webviews + 1) return error.InvalidViewOptions;
            if (isMainWebViewLabel(label)) {
                const window_index = Self.findWindowIndexById(self, window_id) orelse return error.WindowNotFound;
                return Self.mainWebViewInfo(self, window_index).frame;
            }
            if (Self.findViewIndex(self, window_id, label)) |index| {
                var absolute_frame = self.views[index].frame;
                if (self.views[index].parent) |parent| {
                    const parent_frame = try Self.absoluteViewFrame(self, window_id, parent, depth + 1);
                    absolute_frame.x += parent_frame.x;
                    absolute_frame.y += parent_frame.y;
                }
                return absolute_frame;
            }
            if (Self.findWebViewIndex(self, window_id, label)) |index| {
                return self.webviews[index].frame;
            }
            return error.ViewNotFound;
        }

        pub fn relayoutDescendantWebViewBackends(self: *Runtime, window_id: platform.WindowId, parent_label: []const u8) !void {
            try Self.relayoutDescendantWebViewBackendsDepth(self, window_id, parent_label, 0);
        }

        pub fn relayoutDescendantWebViewBackendsDepth(self: *Runtime, window_id: platform.WindowId, parent_label: []const u8, depth: usize) !void {
            if (depth >= platform.max_views + platform.max_webviews) return;
            for (self.views[0..self.view_count]) |view| {
                if (view.window_id != window_id) continue;
                const parent = view.parent orelse continue;
                if (std.mem.eql(u8, parent, parent_label)) {
                    try Self.relayoutDescendantWebViewBackendsDepth(self, window_id, view.label, depth + 1);
                }
            }
            for (self.webviews[0..self.webview_count], 0..) |webview, index| {
                if (webview.window_id != window_id) continue;
                const parent = webview.parent orelse continue;
                if (std.mem.eql(u8, parent, parent_label)) {
                    const platform_frame = try Self.platformFrameForView(self, window_id, webview.parent, webview.local_frame);
                    try self.options.platform.services.setWebViewFrame(window_id, webview.label, platform_frame);
                    self.webviews[index].frame = platform_frame;
                    try Self.relayoutDescendantWebViewBackendsDepth(self, window_id, webview.label, depth + 1);
                }
            }
        }

        pub fn reserveView(self: *Runtime, options: platform.ViewOptions) !void {
            const index = self.view_count;
            self.views[index] = .{
                .id = Self.allocateViewId(
                    self,
                ),
                .window_id = options.window_id,
                .kind = options.kind,
                .frame = options.frame,
                .layer = options.layer,
                .visible = options.visible,
                .enabled = options.enabled,
                .transparent = options.transparent,
                .bridge_enabled = options.bridge_enabled,
                .gpu_size = if (options.kind == .gpu_surface) options.frame.size() else geometry.SizeF.init(0, 0),
                .gpu_backend = if (options.kind == .gpu_surface) options.gpu_surface.backend else .none,
                .gpu_pixel_format = if (options.kind == .gpu_surface) options.gpu_surface.pixel_format else .none,
                .gpu_present_mode = if (options.kind == .gpu_surface) options.gpu_surface.present_mode else .none,
                .gpu_alpha_mode = if (options.kind == .gpu_surface) options.gpu_surface.alpha_mode else .none,
                .gpu_color_space = if (options.kind == .gpu_surface) options.gpu_surface.color_space else .none,
                .gpu_vsync = options.kind == .gpu_surface and options.gpu_surface.vsync,
                .gpu_status = if (options.kind == .gpu_surface) .ready else .unavailable,
                .gpu_surface_created_timestamp_ns = if (options.kind == .gpu_surface) timestampToU64(nowNanoseconds()) else 0,
                .focused = false,
                .open = true,
            };
            self.views[index].label = try copyInto(&self.views[index].label_storage, options.label);
            self.views[index].parent = if (options.parent) |parent| try copyInto(&self.views[index].parent_storage, parent) else null;
            self.views[index].role = try copyInto(&self.views[index].role_storage, options.role);
            self.views[index].accessibility_label = try copyInto(&self.views[index].accessibility_label_storage, options.accessibility_label);
            self.views[index].text = try copyInto(&self.views[index].text_storage, options.text);
            self.views[index].command = try copyInto(&self.views[index].command_storage, options.command);
            self.view_count += 1;
        }

        pub fn findViewIndex(self: *const Runtime, window_id: platform.WindowId, label: []const u8) ?usize {
            for (self.views[0..self.view_count], 0..) |view, index| {
                if (view.open and view.window_id == window_id and std.mem.eql(u8, view.label, label)) return index;
            }
            return null;
        }

        pub fn commandSourceForNativeView(self: *const Runtime, window_id: platform.WindowId, label: []const u8) CommandSource {
            const index = Self.findViewIndex(self, window_id, label) orelse return .native_view;
            var view = self.views[index];
            var depth: usize = 0;
            while (depth < platform.max_views) : (depth += 1) {
                if (view.kind == .toolbar) return .toolbar;
                const parent_label = view.parent orelse return .native_view;
                const parent_index = Self.findViewIndex(self, window_id, parent_label) orelse return .native_view;
                view = self.views[parent_index];
            }
            return .native_view;
        }

        pub fn setFocusedView(self: *Runtime, window_id: platform.WindowId, label: []const u8) anyerror!void {
            if (Self.findWindowIndexById(self, window_id)) |window_index| {
                self.windows[window_index].main_focused = std.mem.eql(u8, label, "main");
            }
            for (self.views[0..self.view_count], 0..) |*view, view_index| {
                if (view.window_id != window_id) continue;
                const previous_state = view.canvasWidgetRenderState();
                view.focused = std.mem.eql(u8, view.label, label);
                const next_state = view.canvasWidgetRenderState();
                if (!CanvasWidgetEventMethods.canvasWidgetRenderStatesEqual(previous_state, next_state)) {
                    try CanvasWidgetEventMethods.invalidateForCanvasWidgetRenderStateChange(self, view_index, previous_state, next_state);
                }
            }
            for (self.webviews[0..self.webview_count]) |*webview| {
                if (webview.window_id == window_id) webview.focused = std.mem.eql(u8, webview.label, label);
            }
        }

        pub fn clearFocusedView(self: *Runtime, window_id: platform.WindowId) anyerror!void {
            if (Self.findWindowIndexById(self, window_id)) |window_index| {
                self.windows[window_index].main_focused = false;
            }
            for (self.views[0..self.view_count], 0..) |*view, view_index| {
                if (view.window_id != window_id) continue;
                const previous_state = view.canvasWidgetRenderState();
                view.focused = false;
                const next_state = view.canvasWidgetRenderState();
                if (!CanvasWidgetEventMethods.canvasWidgetRenderStatesEqual(previous_state, next_state)) {
                    try CanvasWidgetEventMethods.invalidateForCanvasWidgetRenderStateChange(self, view_index, previous_state, next_state);
                }
            }
            for (self.webviews[0..self.webview_count]) |*webview| {
                if (webview.window_id == window_id) webview.focused = false;
            }
        }

        pub fn ensureFocusableViewFocused(self: *Runtime, window_id: platform.WindowId) void {
            var views_buffer: [platform.max_views + platform.max_webviews + 1]platform.ViewInfo = undefined;
            const views = Self.listViews(self, window_id, &views_buffer);
            var first_focusable: ?[]const u8 = null;
            for (views) |view| {
                if (!isFocusableViewInfo(view)) continue;
                if (first_focusable == null) first_focusable = view.label;
                if (view.focused) return;
            }
            if (first_focusable) |label| {
                Self.focusView(self, window_id, label) catch {
                    Self.clearFocusedView(self, window_id) catch {};
                };
            } else {
                Self.clearFocusedView(self, window_id) catch {};
            }
        }

        pub fn focusAdjacentView(self: *Runtime, window_id: platform.WindowId, direction: FocusTraversalDirection) anyerror!platform.ViewInfo {
            try Self.validateViewParent(self, window_id);

            var views_buffer: [platform.max_views + platform.max_webviews + 1]platform.ViewInfo = undefined;
            const views = Self.listViews(self, window_id, &views_buffer);
            var focusable: [platform.max_views + platform.max_webviews + 1]platform.ViewInfo = undefined;
            var focusable_count: usize = 0;
            var focused_index: ?usize = null;
            for (views) |view| {
                if (!isFocusableViewInfo(view)) continue;
                if (view.focused) focused_index = focusable_count;
                focusable[focusable_count] = view;
                focusable_count += 1;
            }
            if (focusable_count == 0) return error.UnsupportedViewFocus;

            const target_index = switch (direction) {
                .next => if (focused_index) |index| (index + 1) % focusable_count else 0,
                .previous => if (focused_index) |index| if (index == 0) focusable_count - 1 else index - 1 else focusable_count - 1,
            };
            const target = focusable[target_index];
            try Self.focusView(self, window_id, target.label);

            var focused = target;
            focused.focused = true;
            return focused;
        }

        pub fn viewLabelExists(self: *const Runtime, window_id: platform.WindowId, label: []const u8) bool {
            if (isMainWebViewLabel(label) and Self.findWindowIndexById(self, window_id) != null) return true;
            return Self.findViewIndex(self, window_id, label) != null or Self.findWebViewIndex(self, window_id, label) != null;
        }

        pub fn removeViewAt(self: *Runtime, index: usize) void {
            if (index >= self.view_count) return;
            var cursor = index;
            while (cursor + 1 < self.view_count) : (cursor += 1) {
                const next = &self.views[cursor + 1];
                self.views[cursor].copyRuntimeStateFrom(next);
            }
            self.view_count -= 1;
        }

        pub fn removeViewsForWindow(self: *Runtime, window_id: platform.WindowId) void {
            var index: usize = 0;
            while (index < self.view_count) {
                if (self.views[index].window_id == window_id) {
                    Self.removeViewAt(self, index);
                } else {
                    index += 1;
                }
            }
        }

        pub fn removeDescendantViewsForParent(self: *Runtime, window_id: platform.WindowId, parent_label: []const u8) void {
            var index: usize = 0;
            while (index < self.view_count) {
                const parent = self.views[index].parent orelse {
                    index += 1;
                    continue;
                };
                if (self.views[index].window_id != window_id or !std.mem.eql(u8, parent, parent_label)) {
                    index += 1;
                    continue;
                }

                var child_label_storage: [platform.max_view_label_bytes]u8 = undefined;
                const child_label = copyInto(&child_label_storage, self.views[index].label) catch unreachable;
                Self.removeDescendantViewsForParent(self, window_id, child_label);
                Self.removeDescendantWebViewsForParent(self, window_id, child_label);
                if (Self.findViewIndex(self, window_id, child_label)) |child_index| Self.removeViewAt(self, child_index);
                index = 0;
            }
        }

        pub fn removeDescendantWebViewsForParent(self: *Runtime, window_id: platform.WindowId, parent_label: []const u8) void {
            var index: usize = 0;
            while (index < self.webview_count) {
                const parent = self.webviews[index].parent orelse {
                    index += 1;
                    continue;
                };
                if (self.webviews[index].window_id != window_id or !std.mem.eql(u8, parent, parent_label)) {
                    index += 1;
                    continue;
                }

                var child_label_storage: [@max(platform.max_view_label_bytes, platform.max_webview_label_bytes)]u8 = undefined;
                const child_label = copyInto(&child_label_storage, self.webviews[index].label) catch unreachable;
                Self.removeDescendantViewsForParent(self, window_id, child_label);
                Self.removeDescendantWebViewsForParent(self, window_id, child_label);
                if (Self.findWebViewIndex(self, window_id, child_label)) |child_index| Self.removeWebViewAt(self, child_index);
                index = 0;
            }
        }

        pub fn closeDescendantWebViewBackends(self: *Runtime, window_id: platform.WindowId, parent_label: []const u8) !void {
            try Self.closeDescendantWebViewBackendsDepth(self, window_id, parent_label, 0);
        }

        pub fn closeDescendantWebViewBackendsDepth(self: *Runtime, window_id: platform.WindowId, parent_label: []const u8, depth: usize) !void {
            if (depth >= platform.max_views + platform.max_webviews) return;
            for (self.views[0..self.view_count]) |view| {
                if (view.window_id != window_id) continue;
                const parent = view.parent orelse continue;
                if (std.mem.eql(u8, parent, parent_label)) {
                    try Self.closeDescendantWebViewBackendsDepth(self, window_id, view.label, depth + 1);
                }
            }
            for (self.webviews[0..self.webview_count]) |webview| {
                if (webview.window_id != window_id) continue;
                const parent = webview.parent orelse continue;
                if (std.mem.eql(u8, parent, parent_label)) {
                    try Self.closeDescendantWebViewBackendsDepth(self, window_id, webview.label, depth + 1);
                    try self.options.platform.services.closeWebView(window_id, webview.label);
                }
            }
        }

        pub fn viewTreeHasFocused(self: *const Runtime, window_id: platform.WindowId, label: []const u8) bool {
            return Self.viewTreeHasFocusedDepth(self, window_id, label, 0);
        }

        pub fn viewTreeHasFocusedDepth(self: *const Runtime, window_id: platform.WindowId, label: []const u8, depth: usize) bool {
            if (depth >= platform.max_views + platform.max_webviews) return false;
            if (Self.findViewIndex(self, window_id, label)) |index| {
                if (self.views[index].focused) return true;
            }
            if (Self.findWebViewIndex(self, window_id, label)) |index| {
                if (self.webviews[index].focused) return true;
            }
            for (self.views[0..self.view_count]) |view| {
                if (view.window_id != window_id) continue;
                const parent = view.parent orelse continue;
                if (std.mem.eql(u8, parent, label) and Self.viewTreeHasFocusedDepth(self, window_id, view.label, depth + 1)) return true;
            }
            for (self.webviews[0..self.webview_count]) |webview| {
                if (webview.window_id != window_id) continue;
                const parent = webview.parent orelse continue;
                if (std.mem.eql(u8, parent, label) and Self.viewTreeHasFocusedDepth(self, window_id, webview.label, depth + 1)) return true;
            }
            return false;
        }
    };
}
