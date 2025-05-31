const std = @import("std");

pub fn env_main(args: []const []const u8) !void {
    const stdout = std.io.getStdOut().writer();

    // For simplicity, we'll just print all environment variables
    // The real env command can also run commands with modified environments
    _ = args; // env without args just prints environment

    var env_map = try std.process.getEnvMap(std.heap.page_allocator);
    defer env_map.deinit();

    var iterator = env_map.iterator();
    while (iterator.next()) |entry| {
        stdout.print("{s}={s}\n", .{ entry.key_ptr.*, entry.value_ptr.* }) catch |err| {
            if (err == error.BrokenPipe) return;
            return err;
        };
    }
}
