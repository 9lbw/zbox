const std = @import("std");

pub fn sleep_main(args: []const []const u8) !void {
    const stderr = std.io.getStdErr().writer();

    if (args.len == 0) {
        try stderr.print("sleep: missing operand\n", .{});
        std.process.exit(1);
    }

    if (args.len > 1) {
        try stderr.print("sleep: too many arguments\n", .{});
        std.process.exit(1);
    }

    const duration_str = args[0];

    // Parse the duration (support integer seconds for simplicity)
    const seconds = std.fmt.parseFloat(f64, duration_str) catch {
        try stderr.print("sleep: invalid time interval '{s}'\n", .{duration_str});
        std.process.exit(1);
    };

    if (seconds < 0) {
        try stderr.print("sleep: invalid time interval '{s}'\n", .{duration_str});
        std.process.exit(1);
    }

    // Convert to nanoseconds
    const nanoseconds = @as(u64, @intFromFloat(seconds * 1_000_000_000));

    std.time.sleep(nanoseconds);
}
