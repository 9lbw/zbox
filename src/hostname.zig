const std = @import("std");

pub fn hostname_main(args: []const []const u8) !void {
    _ = args; // hostname doesn't take arguments (we'll ignore -f, -s, etc. for simplicity)

    const stdout = std.io.getStdOut().writer();

    var buffer: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const hostname = std.posix.gethostname(&buffer) catch {
        try stdout.print("localhost\n", .{});
        return;
    };

    try stdout.print("{s}\n", .{hostname});
}
