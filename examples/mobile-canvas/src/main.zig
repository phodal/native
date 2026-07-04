//! mobile-canvas: the smallest UiApp compiled into the mobile embed
//! static library. `native_sdk.addMobileLib` wires this module as the
//! `"app"` import of the library root; the embed host instantiates the
//! UiApp on a gpu_surface canvas scene (window 1, "mobile-surface") and
//! pumps it from the shim's frame callback over the `native_sdk_app_*`
//! C ABI.

const native_sdk = @import("native_sdk");
const canvas = native_sdk.canvas;

pub const Model = struct {
    count: u32 = 0,
    note: canvas.TextBuffer(64) = .{},
};

pub const Msg = union(enum) {
    increment,
    reset,
    note_edit: canvas.TextInputEvent,
};

const App = native_sdk.UiApp(Model, Msg);

pub fn initModel() Model {
    return .{};
}

pub fn mobileOptions() App.Options {
    return .{
        .name = "mobile-canvas",
        .scene = native_sdk.embed.mobile_shell_scene,
        .canvas_label = native_sdk.embed.mobile_gpu_surface_label,
        .update = update,
        .view = view,
    };
}

fn update(model: *Model, msg: Msg) void {
    switch (msg) {
        .increment => model.count += 1,
        .reset => model.count = 0,
        .note_edit => |edit| model.note.apply(edit),
    }
}

fn view(ui: *App.Ui, model: *const Model) App.Ui.Node {
    return ui.column(.{ .gap = 12, .padding = 16 }, .{
        ui.text(.{}, ui.fmt("Taps {d}", .{model.count})),
        ui.button(.{ .variant = .primary, .on_press = .increment }, "Tap"),
        ui.button(.{ .on_press = .reset }, "Reset"),
        ui.textField(.{
            .text = model.note.text(),
            .placeholder = "Note",
            .on_input = App.Ui.inputMsg(.note_edit),
        }),
    });
}
