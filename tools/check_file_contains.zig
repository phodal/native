const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 3) {
        std.debug.print("usage: check_file_contains <path> <pattern>\n", .{});
        std.process.exit(2);
    }

    const path = args[1];
    const pattern = args[2];
    const content = std.Io.Dir.cwd().readFileAlloc(init.io, path, allocator, .limited(16 * 1024 * 1024)) catch |err| {
        std.debug.print("failed to read {s}: {s}\n", .{ path, @errorName(err) });
        std.process.exit(1);
    };

    if (std.mem.indexOf(u8, content, pattern) == null) {
        std.debug.print("missing pattern in {s}: {s}\n", .{ path, pattern });
        std.process.exit(1);
    }
}
