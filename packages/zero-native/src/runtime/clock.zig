const std = @import("std");

pub fn nowNanoseconds() i128 {
    switch (@import("builtin").os.tag) {
        .windows, .wasi => return 0,
        else => {
            var ts: std.posix.timespec = undefined;
            switch (std.posix.errno(std.posix.system.clock_gettime(.REALTIME, &ts))) {
                .SUCCESS => return @as(i128, ts.sec) * std.time.ns_per_s + ts.nsec,
                else => return 0,
            }
        },
    }
}

pub fn timestampToU64(value: i128) u64 {
    if (value <= 0) return 0;
    return @intCast(@min(value, std.math.maxInt(u64)));
}

pub fn automationInputTimestampNs() u64 {
    return timestampToU64(nowNanoseconds());
}
