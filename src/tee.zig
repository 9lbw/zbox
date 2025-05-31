const std = @import("std");

pub fn tee_main(args: []const []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();
    const stdin = std.io.getStdIn().reader();

    var append_mode = false;
    var file_args: []const []const u8 = args;

    // Parse arguments
    if (args.len > 0 and args[0].len > 1 and args[0][0] == '-') {
        if (std.mem.eql(u8, args[0], "--help")) {
            try stdout.print("Usage: tee [OPTION]... [FILE]...\n", .{});
            try stdout.print("Copy standard input to each FILE, and also to standard output.\n", .{});
            try stdout.print("\n", .{});
            try stdout.print("  -a, --append             append to the given FILEs, do not overwrite\n", .{});
            try stdout.print("      --help               display this help and exit\n", .{});
            return;
        } else if (std.mem.eql(u8, args[0], "-a") or std.mem.eql(u8, args[0], "--append")) {
            append_mode = true;
            file_args = args[1..];
        } else {
            try stderr.print("tee: invalid option -- '{s}'\n", .{args[0][1..]});
            std.process.exit(1);
        }
    }

    // Open output files
    var files = std.ArrayList(std.fs.File).init(allocator);
    defer {
        for (files.items) |file| {
            file.close();
        }
        files.deinit();
    }

    for (file_args) |filename| {
        const file = if (append_mode)
            std.fs.cwd().createFile(filename, .{ .truncate = false }) catch |err| blk: {
                if (err == error.FileNotFound) {
                    break :blk std.fs.cwd().createFile(filename, .{}) catch |create_err| {
                        try stderr.print("tee: {s}: {}\n", .{ filename, create_err });
                        continue;
                    };
                } else {
                    try stderr.print("tee: {s}: {}\n", .{ filename, err });
                    continue;
                }
            }
        else
            std.fs.cwd().createFile(filename, .{}) catch |err| {
                try stderr.print("tee: {s}: {}\n", .{ filename, err });
                continue;
            };

        if (append_mode) {
            try file.seekFromEnd(0);
        }

        try files.append(file);
    }

    // Read from stdin and write to stdout and all files
    var buffer: [4096]u8 = undefined;
    while (true) {
        const bytes_read = stdin.read(buffer[0..]) catch |err| switch (err) {
            error.BrokenPipe => return,
            else => return err,
        };

        if (bytes_read == 0) break;

        const data = buffer[0..bytes_read];

        // Write to stdout
        stdout.writeAll(data) catch |err| switch (err) {
            error.BrokenPipe => {
                // Continue writing to files even if stdout is broken
            },
            else => return err,
        };

        // Write to all files
        for (files.items) |file| {
            file.writeAll(data) catch |err| {
                try stderr.print("tee: write error: {}\n", .{err});
            };
        }
    }
}
