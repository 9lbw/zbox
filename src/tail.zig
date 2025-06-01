const std = @import("std");

pub fn tail_main(args: []const []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    var num_lines: i32 = 10; // default
    var file_args: []const []const u8 = args;

    // Parse arguments
    if (args.len > 0 and args[0].len > 1 and args[0][0] == '-') {
        if (std.mem.eql(u8, args[0], "--help")) {
            try stdout.print("Usage: tail [OPTION]... [FILE]...\n", .{});
            try stdout.print("Print the last 10 lines of each FILE to standard output.\n", .{});
            try stdout.print("With more than one FILE, precede each with a header giving the file name.\n", .{});
            try stdout.print("\n", .{});
            try stdout.print("  -n, --lines=[-]NUM       print the last NUM lines instead of the last 10\n", .{});
            try stdout.print("      --help               display this help and exit\n", .{});
            return;
        }

        if (std.mem.startsWith(u8, args[0], "-n")) {
            var num_str: []const u8 = undefined;
            if (args[0].len > 2) {
                num_str = args[0][2..];
            } else if (args.len > 1) {
                num_str = args[1];
                file_args = args[2..];
            } else {
                try stderr.print("tail: option requires an argument -- 'n'\n", .{});
                std.process.exit(1);
            }

            num_lines = std.fmt.parseInt(i32, num_str, 10) catch {
                try stderr.print("tail: invalid number of lines: '{s}'\n", .{num_str});
                std.process.exit(1);
            };

            if (args[0].len > 2) {
                file_args = args[1..];
            }
        } else if (args[0].len > 1 and std.ascii.isDigit(args[0][1])) {
            // Handle -NUM format
            num_lines = std.fmt.parseInt(i32, args[0][1..], 10) catch {
                try stderr.print("tail: invalid number of lines: '{s}'\n", .{args[0][1..]});
                std.process.exit(1);
            };
            file_args = args[1..];
        }
    }

    if (num_lines < 0) {
        try stderr.print("tail: invalid number of lines: '{d}'\n", .{num_lines});
        std.process.exit(1);
    }

    // If no files specified, read from stdin
    if (file_args.len == 0) {
        try tail_file(allocator, null, @intCast(num_lines), false);
        return;
    }

    // Process each file
    for (file_args, 0..) |filename, i| {
        if (file_args.len > 1) {
            if (i > 0) try stdout.print("\n", .{});
            try stdout.print("==> {s} <==\n", .{filename});
        }

        tail_file(allocator, filename, @intCast(num_lines), file_args.len > 1) catch |err| switch (err) {
            error.FileNotFound => {
                try stderr.print("tail: cannot open '{s}' for reading: No such file or directory\n", .{filename});
                std.process.exit(1);
            },
            error.BrokenPipe => return,
            else => return err,
        };
    }
}

fn tail_file(allocator: std.mem.Allocator, filename: ?[]const u8, num_lines: u32, _: bool) !void {
    const stdout = std.io.getStdOut().writer();

    var file: std.fs.File = undefined;
    var should_close = false;

    if (filename) |fname| {
        file = std.fs.cwd().openFile(fname, .{}) catch |err| return err;
        should_close = true;
    } else {
        file = std.io.getStdIn();
    }
    defer if (should_close) file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var reader = buf_reader.reader();

    // Read all lines into a circular buffer
    var lines = std.ArrayList([]u8).init(allocator);
    defer {
        for (lines.items) |line| {
            allocator.free(line);
        }
        lines.deinit();
    }

    while (true) {
        const line = reader.readUntilDelimiterAlloc(allocator, '\n', 8192) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };

        try lines.append(line);

        // Keep only the last num_lines lines
        if (lines.items.len > num_lines) {
            allocator.free(lines.orderedRemove(0));
        }
    }

    // Print the stored lines
    for (lines.items) |line| {
        stdout.print("{s}\n", .{line}) catch |err| switch (err) {
            error.BrokenPipe => return error.BrokenPipe,
            else => return err,
        };
    }
}
