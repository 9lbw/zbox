const std = @import("std");

pub fn cut_main(args: []const []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    var delimiter: u8 = '\t'; // default delimiter
    var field_list: ?[]const u8 = null;
    var char_list: ?[]const u8 = null;
    var file_args: []const []const u8 = args;

    // Parse arguments
    var i: usize = 0;
    while (i < args.len) {
        const arg = args[i];

        if (arg.len > 1 and arg[0] == '-') {
            if (std.mem.eql(u8, arg, "--help")) {
                try stdout.print("Usage: cut OPTION... [FILE]...\n", .{});
                try stdout.print("Print selected parts of lines from each FILE to standard output.\n", .{});
                try stdout.print("\n", .{});
                try stdout.print("  -c, --characters=LIST    select only these characters\n", .{});
                try stdout.print("  -d, --delimiter=DELIM    use DELIM instead of TAB for field delimiter\n", .{});
                try stdout.print("  -f, --fields=LIST        select only these fields\n", .{});
                try stdout.print("      --help               display this help and exit\n", .{});
                return;
            } else if (std.mem.startsWith(u8, arg, "-d")) {
                if (arg.len > 2) {
                    if (arg.len > 3) {
                        try stderr.print("cut: the delimiter must be a single character\n", .{});
                        std.process.exit(1);
                    }
                    delimiter = arg[2];
                } else if (i + 1 < args.len) {
                    i += 1;
                    if (args[i].len != 1) {
                        try stderr.print("cut: the delimiter must be a single character\n", .{});
                        std.process.exit(1);
                    }
                    delimiter = args[i][0];
                } else {
                    try stderr.print("cut: option requires an argument -- 'd'\n", .{});
                    std.process.exit(1);
                }
            } else if (std.mem.startsWith(u8, arg, "-f")) {
                if (arg.len > 2) {
                    field_list = arg[2..];
                } else if (i + 1 < args.len) {
                    i += 1;
                    field_list = args[i];
                } else {
                    try stderr.print("cut: option requires an argument -- 'f'\n", .{});
                    std.process.exit(1);
                }
            } else if (std.mem.startsWith(u8, arg, "-c")) {
                if (arg.len > 2) {
                    char_list = arg[2..];
                } else if (i + 1 < args.len) {
                    i += 1;
                    char_list = args[i];
                } else {
                    try stderr.print("cut: option requires an argument -- 'c'\n", .{});
                    std.process.exit(1);
                }
            } else {
                try stderr.print("cut: invalid option -- '{s}'\n", .{arg[1..]});
                std.process.exit(1);
            }
        } else {
            file_args = args[i..];
            break;
        }
        i += 1;
    }

    // If we went through all args without finding files, set file_args to empty
    if (i >= args.len) {
        file_args = &[_][]const u8{};
    }

    if (field_list == null and char_list == null) {
        try stderr.print("cut: you must specify a list of bytes, characters or fields\n", .{});
        std.process.exit(1);
    }

    if (field_list != null and char_list != null) {
        try stderr.print("cut: only one type of list may be specified\n", .{});
        std.process.exit(1);
    }

    // Parse the field/character list
    var ranges = std.ArrayList(Range).init(allocator);
    defer ranges.deinit();

    const list = field_list orelse char_list.?;
    try parse_list(allocator, list, &ranges);

    // If no files specified, read from stdin
    if (file_args.len == 0) {
        if (field_list) |_| {
            try cut_fields(allocator, null, delimiter, ranges.items);
        } else {
            try cut_characters(allocator, null, ranges.items);
        }
        return;
    }

    // Process each file
    for (file_args) |filename| {
        if (field_list) |_| {
            try cut_fields(allocator, filename, delimiter, ranges.items);
        } else {
            try cut_characters(allocator, filename, ranges.items);
        }
    }
}

const Range = struct {
    start: usize,
    end: usize,
};

fn parse_list(_: std.mem.Allocator, list: []const u8, ranges: *std.ArrayList(Range)) !void {
    var it = std.mem.splitScalar(u8, list, ',');

    while (it.next()) |part| {
        if (std.mem.indexOf(u8, part, "-")) |dash_pos| {
            if (dash_pos == 0) {
                // -N format
                const end = try std.fmt.parseInt(usize, part[1..], 10);
                try ranges.append(Range{ .start = 1, .end = end });
            } else if (dash_pos == part.len - 1) {
                // N- format
                const start = try std.fmt.parseInt(usize, part[0..dash_pos], 10);
                try ranges.append(Range{ .start = start, .end = std.math.maxInt(usize) });
            } else {
                // N-M format
                const start = try std.fmt.parseInt(usize, part[0..dash_pos], 10);
                const end = try std.fmt.parseInt(usize, part[dash_pos + 1 ..], 10);
                try ranges.append(Range{ .start = start, .end = end });
            }
        } else {
            // Single number
            const num = try std.fmt.parseInt(usize, part, 10);
            try ranges.append(Range{ .start = num, .end = num });
        }
    }
}

fn cut_fields(allocator: std.mem.Allocator, filename: ?[]const u8, delimiter: u8, ranges: []const Range) !void {
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

    while (true) {
        const line = reader.readUntilDelimiterAlloc(allocator, '\n', 8192) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        defer allocator.free(line);

        var fields = std.ArrayList([]const u8).init(allocator);
        defer fields.deinit();

        var field_it = std.mem.splitScalar(u8, line, delimiter);
        while (field_it.next()) |field| {
            try fields.append(field);
        }

        var first = true;
        for (ranges) |range| {
            for (range.start..@min(range.end + 1, fields.items.len + 1)) |field_num| {
                if (field_num > 0 and field_num <= fields.items.len) {
                    if (!first) try stdout.print("{c}", .{delimiter});
                    try stdout.print("{s}", .{fields.items[field_num - 1]});
                    first = false;
                }
            }
        }
        try stdout.print("\n", .{});
    }
}

fn cut_characters(allocator: std.mem.Allocator, filename: ?[]const u8, ranges: []const Range) !void {
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

    while (true) {
        const line = reader.readUntilDelimiterAlloc(allocator, '\n', 8192) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        defer allocator.free(line);

        for (ranges) |range| {
            for (range.start..@min(range.end + 1, line.len + 1)) |char_pos| {
                if (char_pos > 0 and char_pos <= line.len) {
                    try stdout.print("{c}", .{line[char_pos - 1]});
                }
            }
        }
        try stdout.print("\n", .{});
    }
}
