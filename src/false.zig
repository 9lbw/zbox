const std = @import("std");

pub fn false_main(args: []const []const u8) !void {
    _ = args; // false ignores all arguments
    std.process.exit(1);
}
