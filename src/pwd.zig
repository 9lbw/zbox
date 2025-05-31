const std = @import("std");

const PwdOptions = struct {
    logical: bool = true, // -L: use PWD from environment (default)
    physical: bool = false, // -P: avoid all symlinks
};

fn parseOptions(args: []const []const u8) !struct { options: PwdOptions, files: []const []const u8 } {
    var options = PwdOptions{};
    var i: usize = 0;

    // Parse flags
    while (i < args.len and args[i][0] == '-') {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-L") or std.mem.eql(u8, arg, "--logical")) {
            options.logical = true;
            options.physical = false;
        } else if (std.mem.eql(u8, arg, "-P") or std.mem.eql(u8, arg, "--physical")) {
            options.physical = true;
            options.logical = false;
        } else if (std.mem.eql(u8, arg, "--")) {
            i += 1;
            break;
        } else {
            // Handle combined flags
            if (arg.len > 1 and arg[1] != '-') {
                for (arg[1..]) |flag| {
                    switch (flag) {
                        'L' => {
                            options.logical = true;
                            options.physical = false;
                        },
                        'P' => {
                            options.physical = true;
                            options.logical = false;
                        },
                        else => {
                            const stderr = std.io.getStdErr().writer();
                            try stderr.print("pwd: unknown option: -{c}\n", .{flag});
                            std.process.exit(1);
                        },
                    }
                }
            } else {
                const stderr = std.io.getStdErr().writer();
                try stderr.print("pwd: unknown option: {s}\n", .{arg});
                std.process.exit(1);
            }
        }
        i += 1;
    }

    return .{ .options = options, .files = args[i..] };
}

pub fn pwd_main(args: []const []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const parsed = try parseOptions(args);
    const options = parsed.options;
    const files = parsed.files;

    // pwd doesn't take file arguments
    if (files.len > 0) {
        const stderr = std.io.getStdErr().writer();
        try stderr.writeAll("pwd: too many arguments\n");
        std.process.exit(1);
    }

    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    if (options.logical) {
        // Try to get PWD from environment first (logical path with symlinks preserved)
        if (std.process.getEnvVarOwned(allocator, "PWD")) |pwd_env| {
            defer allocator.free(pwd_env);
            // Verify that PWD actually points to the current directory
            var cwd_buffer: [std.fs.max_path_bytes]u8 = undefined;
            const cwd_real = std.process.getCwd(&cwd_buffer) catch |err| {
                try stderr.print("pwd: cannot get current directory: {s}\n", .{@errorName(err)});
                std.process.exit(1);
            };

            // For simplicity, we'll just use the real path
            // A full implementation would verify PWD points to the same inode
            try stdout.print("{s}\n", .{cwd_real});
        } else |_| {
            // PWD not available, fall back to physical path
            var cwd_buffer: [std.fs.max_path_bytes]u8 = undefined;
            const cwd = std.process.getCwd(&cwd_buffer) catch |err| {
                try stderr.print("pwd: cannot get current directory: {s}\n", .{@errorName(err)});
                std.process.exit(1);
            };
            try stdout.print("{s}\n", .{cwd});
        }
    } else {
        // Physical path: resolve all symlinks
        var cwd_buffer: [std.fs.max_path_bytes]u8 = undefined;
        const cwd = std.process.getCwd(&cwd_buffer) catch |err| {
            try stderr.print("pwd: cannot get current directory: {s}\n", .{@errorName(err)});
            std.process.exit(1);
        };
        try stdout.print("{s}\n", .{cwd});
    }
}
