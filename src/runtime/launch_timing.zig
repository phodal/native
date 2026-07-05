//! Launch-to-glass lap channel: wall-clock stamps at the startup
//! phase boundaries, printed to stderr when `NATIVE_SDK_WINDOW_TIMING`
//! is set (the same gate as the host's window-shown line, so one env
//! var yields the whole launch timeline).
//!
//! Zero-cost when the gate is off: the env var is read once and cached,
//! and every lap site pays one branch on the cached state. Stamps are
//! REALTIME nanoseconds so an external harness can difference them
//! against a wall-clock taken before process spawn — the same clock
//! domain the host's `wall_ns` values use.

const std = @import("std");
const builtin = @import("builtin");
const runtime_clock = @import("clock.zig");

const GateState = enum { unknown, off, on };
var gate: GateState = .unknown;

/// True when `NATIVE_SDK_WINDOW_TIMING` is set. Cached after the first
/// read; only meaningful on OS targets with an environment (returns
/// false elsewhere, keeping wasm/freestanding builds inert).
pub fn enabled() bool {
    if (comptime !builtin.link_libc) return false;
    if (comptime builtin.os.tag != .macos and builtin.os.tag != .linux) return false;
    if (gate == .unknown) {
        gate = if (std.c.getenv("NATIVE_SDK_WINDOW_TIMING") != null) .on else .off;
    }
    return gate == .on;
}

/// Print one launch lap: `native-sdk: launch <name> wall_ns=<ns>`.
pub fn lap(comptime name: []const u8) void {
    if (!enabled()) return;
    std.debug.print("native-sdk: launch " ++ name ++ " wall_ns={d}\n", .{runtime_clock.nowNanoseconds()});
}

/// Like `lap`, but fires at most once per process per name — for sites
/// that run repeatedly (the first rebuild, the first present record).
pub fn lapOnce(comptime name: []const u8) void {
    const Once = struct {
        var done: bool = false;
    };
    if (Once.done) return;
    if (!enabled()) return;
    Once.done = true;
    lap(name);
}
