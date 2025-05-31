const std = @import("std");

pub fn printenv_main(args: []const []const u8) !void {
    const stdout = std.io.getStdOut().writer();

    if (args.len == 0) {
        // Print all environment variables (same as env)
        var env_map = try std.process.getEnvMap(std.heap.page_allocator);
        defer env_map.deinit();

        var iterator = env_map.iterator();
        while (iterator.next()) |entry| {
            stdout.print("{s}={s}\n", .{ entry.key_ptr.*, entry.value_ptr.* }) catch |err| {
                if (err == error.BrokenPipe) return;
                return err;
            };
        }
    } else {
        // Print specific environment variables
        for (args) |var_name| {
            if (std.process.getEnvVarOwned(std.heap.page_allocator, var_name)) |value| {
                defer std.heap.page_allocator.free(value);
                try stdout.print("{s}\n", .{value});
            } else |err| {
                switch (err) {
                    error.EnvironmentVariableNotFound => {
                        // Just continue to next variable (GNU printenv behavior)
                        continue;
                    },
                    else => return err,
                }
            }
        }
    }
}
