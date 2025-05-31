const std = @import("std");

pub fn id_main(args: []const []const u8) !void {
    const stdout = std.io.getStdOut().writer();

    // For simplicity, ignore user arguments and just show current user
    _ = args;

    // Get current user and group IDs
    const uid = std.os.linux.getuid();
    const gid = std.os.linux.getgid();
    const euid = std.os.linux.geteuid();
    const egid = std.os.linux.getegid();

    // Try to get username from environment
    const username = std.process.getEnvVarOwned(std.heap.page_allocator, "USER") catch "unknown";
    defer if (!std.mem.eql(u8, username, "unknown")) std.heap.page_allocator.free(username);

    // Basic id output format: uid=1000(username) gid=1000(groupname) groups=...
    try stdout.print("uid={d}({s}) gid={d}", .{ uid, username, gid });

    // Show effective IDs if different
    if (euid != uid) {
        try stdout.print(" euid={d}", .{euid});
    }
    if (egid != gid) {
        try stdout.print(" egid={d}", .{egid});
    }

    // For groups, we'll just show the primary group for simplicity
    try stdout.print(" groups={d}", .{gid});

    try stdout.print("\n", .{});
}
