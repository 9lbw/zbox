const std = @import("std");

pub fn mkdir_main(args: []const []const u8) !void {
    const stderr = std.io.getStdErr().writer();
    var parents = false;
    var i: usize = 0;

    // Parse options (-p/--parents)
    while (i < args.len and args[i][0] == '-') {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-p") or std.mem.eql(u8, arg, "--parents")) {
            parents = true;
        } else {
            try stderr.print("mkdir: unknown option: {s}\n", .{arg});
            std.process.exit(1);
        }
        i += 1;
    }

    // Validate directory arguments
    const dirs = args[i..];
    if (dirs.len == 0) {
        try stderr.writeAll("mkdir: missing operand\n");
        std.process.exit(1);
    }

    const cwd = std.fs.cwd();
    for (dirs) |dir| {
        if (parents) {
            // Create parent directories if needed
            cwd.makePath(dir) catch |err| {
                try stderr.print("mkdir: cannot create directory '{s}': {s}\n", .{ dir, @errorName(err) });
            };
        } else {
            // Create single directory (fails if parents don't exist)
            cwd.makeDir(dir) catch |err| {
                try stderr.print("mkdir: cannot create directory '{s}': {s}\n", .{ dir, @errorName(err) });
            };
        }
    }
}
