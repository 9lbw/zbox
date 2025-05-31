const std = @import("std");

pub fn basename_main(args: []const []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    if (args.len == 0) {
        try stderr.print("basename: missing operand\n", .{});
        std.process.exit(1);
    }

    const path = args[0];

    // Handle suffix removal if provided
    const suffix = if (args.len > 1) args[1] else "";

    var result = std.fs.path.basename(path);

    // Remove suffix if specified and present
    if (suffix.len > 0 and std.mem.endsWith(u8, result, suffix)) {
        if (result.len > suffix.len) { // Don't remove if it would make empty string
            result = result[0 .. result.len - suffix.len];
        }
    }

    try stdout.print("{s}\n", .{result});
}
