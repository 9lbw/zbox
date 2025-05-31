const std = @import("std");

fn listDirectory(cwd: std.fs.Dir, path: []const u8, writer: anytype, stderr_writer: anytype) !void {
    var dir = cwd.openDir(path, .{ .iterate = true }) catch |err| {
        // Handle file instead of directory
        if (err == error.NotDir) {
            try writer.print("{s}\n", .{path});
            return;
        }
        try stderr_writer.print("ls: {s}: {s}\n", .{ path, @errorName(err) });
        return;
    };
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        try writer.print("{s}\n", .{entry.name});
    }
}

pub fn ls_main(args: []const []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();
    const cwd = std.fs.cwd();

    // Handle no arguments (current directory)
    if (args.len == 0) {
        try listDirectory(cwd, ".", stdout, stderr);
        return;
    }

    // Handle each argument
    for (args) |path| {
        try listDirectory(cwd, path, stdout, stderr);
    }
}
