const std = @import("std");

pub fn yes_main(args: []const []const u8) !void {
    const stdout = std.io.getStdOut().writer();

    const output = if (args.len > 0) args[0] else "y";

    while (true) {
        stdout.print("{s}\n", .{output}) catch |err| {
            // Handle broken pipe gracefully (e.g., when piped to head)
            if (err == error.BrokenPipe) return;
            return err;
        };
    }
}
