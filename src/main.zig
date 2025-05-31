const std = @import("std");

pub fn main() !void {
    const stdout_writer = std.io.getStdOut().writer();
    var args_it = std.process.args();

    _ = args_it.next();

    var first_arg = true;
    while (args_it.next()) |arg| {
        if (!first_arg) {
            try stdout_writer.print(" ", .{});
        }
        try stdout_writer.print("{s}", .{arg});
        first_arg = false;
    }
    try stdout_writer.print("\n", .{});
}

test "basic echo" {
    try std.testing.ok(true);
}
