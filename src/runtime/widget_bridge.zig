const canvas = @import("canvas");
const platform = @import("../platform/root.zig");

pub fn platformCursorFromCanvas(cursor: canvas.WidgetCursor) platform.Cursor {
    return switch (cursor) {
        .arrow => .arrow,
        .pointing_hand => .pointing_hand,
        .text => .text,
        .resize_horizontal => .resize_horizontal,
    };
}
