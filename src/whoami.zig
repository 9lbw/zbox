const std = @import("std");

pub fn whoami_main(args: []const []const u8) !void {
    _ = args; // whoami doesn't take arguments

    const stdout = std.io.getStdOut().writer();

    // Get current user ID
    const uid = std.os.linux.getuid();

    // Try to get username from environment first
    if (std.process.getEnvVarOwned(std.heap.page_allocator, "USER")) |username| {
        defer std.heap.page_allocator.free(username);
        try stdout.print("{s}\n", .{username});
        return;
    } else |_| {}

    // Fallback: try to read from /etc/passwd
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const passwd_file = std.fs.openFileAbsolute("/etc/passwd", .{}) catch {
        // If all else fails, just print the UID
        try stdout.print("{d}\n", .{uid});
        return;
    };
    defer passwd_file.close();

    const content = passwd_file.readToEndAlloc(allocator, 1024 * 1024) catch {
        try stdout.print("{d}\n", .{uid});
        return;
    };

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, ':');

        const username = fields.next() orelse continue;
        _ = fields.next() orelse continue; // password field
        const uid_str = fields.next() orelse continue;

        const line_uid = std.fmt.parseInt(u32, uid_str, 10) catch continue;
        if (line_uid == uid) {
            try stdout.print("{s}\n", .{username});
            return;
        }
    }

    // If we couldn't find the user, just print the UID
    try stdout.print("{d}\n", .{uid});
}
