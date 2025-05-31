const std = @import("std");

pub fn echo_main(args: []const []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    for (args, 0..) |arg, i| {
        if (i > 0) try stdout.writeAll(" ");
        try stdout.writeAll(arg);
    }
    try stdout.writeAll("\n");
}
