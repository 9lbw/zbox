const std = @import("std");

pub fn seq_main(args: []const []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    if (args.len == 0) {
        try stderr.print("seq: missing operand\n", .{});
        std.process.exit(1);
    }

    var start: f64 = 1;
    var increment: f64 = 1;
    var end: f64 = undefined;

    // Parse arguments based on count
    switch (args.len) {
        1 => {
            // seq LAST
            end = std.fmt.parseFloat(f64, args[0]) catch {
                try stderr.print("seq: invalid floating point argument: '{s}'\n", .{args[0]});
                std.process.exit(1);
            };
        },
        2 => {
            // seq FIRST LAST
            start = std.fmt.parseFloat(f64, args[0]) catch {
                try stderr.print("seq: invalid floating point argument: '{s}'\n", .{args[0]});
                std.process.exit(1);
            };
            end = std.fmt.parseFloat(f64, args[1]) catch {
                try stderr.print("seq: invalid floating point argument: '{s}'\n", .{args[1]});
                std.process.exit(1);
            };
        },
        3 => {
            // seq FIRST INCREMENT LAST
            start = std.fmt.parseFloat(f64, args[0]) catch {
                try stderr.print("seq: invalid floating point argument: '{s}'\n", .{args[0]});
                std.process.exit(1);
            };
            increment = std.fmt.parseFloat(f64, args[1]) catch {
                try stderr.print("seq: invalid floating point argument: '{s}'\n", .{args[1]});
                std.process.exit(1);
            };
            end = std.fmt.parseFloat(f64, args[2]) catch {
                try stderr.print("seq: invalid floating point argument: '{s}'\n", .{args[2]});
                std.process.exit(1);
            };
        },
        else => {
            try stderr.print("seq: too many arguments\n", .{});
            std.process.exit(1);
        },
    }

    // Handle zero increment
    if (increment == 0) {
        try stderr.print("seq: increment must not be zero\n", .{});
        std.process.exit(1);
    }

    // Generate sequence
    var current = start;
    if (increment > 0) {
        while (current <= end) {
            // Check if it's a whole number to avoid unnecessary decimals
            if (@floor(current) == current) {
                try stdout.print("{d}\n", .{@as(i64, @intFromFloat(current))});
            } else {
                try stdout.print("{d}\n", .{current});
            }
            current += increment;
        }
    } else {
        while (current >= end) {
            // Check if it's a whole number to avoid unnecessary decimals
            if (@floor(current) == current) {
                try stdout.print("{d}\n", .{@as(i64, @intFromFloat(current))});
            } else {
                try stdout.print("{d}\n", .{current});
            }
            current += increment;
        }
    }
}
