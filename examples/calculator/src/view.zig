//! calculator views. Markup-first: the header and the whole keypad are
//! compiled `.zml` views; this file holds the one section the closed
//! markup grammar cannot express — the display block, which needs a
//! scaled, right-aligned result paragraph (markup text tops out at the
//! `lg` body size) — plus the root view composing all three.
//!
//! The display's expression line is a real `text_field` and it is the
//! app's keyboard seam: focusing it (click, or Tab) routes every typed
//! character through the widget keyboard path as `TextInputEvent`s that
//! `update` parses as calculator keys, backspace edits the entry, and
//! enter submits as equals. The field's text is model-derived (the live
//! expression), so unknown characters can never appear in it.

const std = @import("std");
const native_sdk = @import("native_sdk");
const model_mod = @import("model.zig");

const canvas = native_sdk.canvas;

pub const Model = model_mod.Model;
pub const Msg = model_mod.Msg;
pub const Ui = canvas.Ui(Msg);

pub const header_markup = @embedFile("header.zml");
pub const keypad_markup = @embedFile("keypad.zml");
pub const CompiledHeaderView = canvas.CompiledMarkupView(Model, Msg, header_markup);
pub const CompiledKeypadView = canvas.CompiledMarkupView(Model, Msg, keypad_markup);

// Keypad metrics (kept in lockstep with keypad.zml; the layout test
// asserts the rendered frames match these numbers exactly).
pub const key_width: f32 = 66;
pub const key_height: f32 = 54;
pub const key_gap: f32 = 8;
pub const zero_width: f32 = key_width * 2 + key_gap; // 140
pub const content_width: f32 = key_width * 4 + key_gap * 3; // 288
pub const window_padding: f32 = 16;

/// The big result line: body size x scale = 36px digits, 12 typed digits
/// wide inside the 288pt content column.
pub const result_scale: f32 = 2.6;

pub fn rootView(ui: *Ui, model: *const Model) Ui.Node {
    return ui.column(.{
        .padding = window_padding,
        .gap = 14,
        .grow = 1,
        .style_tokens = .{ .background = .background },
    }, .{
        CompiledHeaderView.build(ui, model),
        displayView(ui, model),
        CompiledKeypadView.build(ui, model),
    });
}

// ---------------------------------------------------------------- display

/// Memory line, expression field, and the big result — all sitting
/// directly on the window background so the digits carry the design.
fn displayView(ui: *Ui, model: *const Model) Ui.Node {
    return ui.column(.{ .gap = 4, .semantics = .{ .label = "Display" } }, .{
        memoryLine(ui, model),
        expressionField(ui, model),
        resultLine(ui, model),
    });
}

/// The last completed calculation, right-aligned and quiet. The explicit
/// height keeps the layout steady while it is empty.
fn memoryLine(ui: *Ui, model: *const Model) Ui.Node {
    var node = ui.text(.{
        .width = content_width,
        .height = 18,
        .size = .sm,
        .style_tokens = .{ .foreground = .text_muted },
        .semantics = .{ .label = "Last calculation" },
    }, model.memoryText(ui.arena));
    node.widget.text_alignment = .end;
    return node;
}

/// The live expression and the keyboard seam (see the module doc). The
/// field blends into the background until focused, when the theme's
/// focus ring shows exactly where keystrokes go.
fn expressionField(ui: *Ui, model: *const Model) Ui.Node {
    return ui.el(.text_field, .{
        .width = content_width,
        .height = 32,
        .text = model.expressionText(ui.arena),
        .placeholder = "Type a calculation",
        .on_input = Ui.inputMsg(.typed),
        .on_submit = .equals,
        .style_tokens = .{ .background = .background, .border_color = .background },
        .semantics = .{ .label = "Expression" },
    }, .{});
}

/// The result: one scaled span, right-aligned. The explicit width carries
/// the whole content column so host-side re-measurement (the macOS packet
/// rasterizer uses its own font metrics) can never wrap it. Its semantic
/// label IS the value, so assistive tech (and the automation snapshot)
/// reads the result directly.
fn resultLine(ui: *Ui, model: *const Model) Ui.Node {
    const value = model.displayText(ui.arena);
    var node = ui.paragraph(.{
        .width = content_width,
        .semantics = .{ .label = value },
    }, &.{
        .{ .text = value, .weight = .medium, .scale = result_scale },
    });
    node.widget.text_alignment = .end;
    return node;
}
