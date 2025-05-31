const std = @import("std");

pub fn dirname_main(args: []const []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    if (args.len == 0) {
        try stderr.print("dirname: missing operand\n", .{});
        std.process.exit(1);
    }

    const path = args[0];
    const result = std.fs.path.dirname(path) orelse ".";

    try stdout.print("{s}\n", .{result});
}
