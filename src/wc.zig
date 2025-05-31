const std = @import("std");

const WcOptions = struct {
    lines: bool = false, // -l: count lines
    words: bool = false, // -w: count words
    chars: bool = false, // -m: count characters
    bytes: bool = false, // -c: count bytes
    max_line_length: bool = false, // -L: print length of longest line
    files0_from: ?[]const u8 = null, // --files0-from=F: read input from file F

    // If no options specified, default to lines, words, and bytes
    fn hasOptions(self: WcOptions) bool {
        return self.lines or self.words or self.chars or self.bytes or self.max_line_length;
    }

    fn getDefaults() WcOptions {
        return WcOptions{
            .lines = true,
            .words = true,
            .bytes = true,
        };
    }
};

const WcCounts = struct {
    lines: u64 = 0,
    words: u64 = 0,
    chars: u64 = 0,
    bytes: u64 = 0,
    max_line_length: u64 = 0,
};

fn parseOptions(args: []const []const u8) !struct { options: WcOptions, files: []const []const u8 } {
    var options = WcOptions{};
    var i: usize = 0;

    // Parse flags
    while (i < args.len and args[i][0] == '-' and args[i].len > 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-l") or std.mem.eql(u8, arg, "--lines")) {
            options.lines = true;
        } else if (std.mem.eql(u8, arg, "-w") or std.mem.eql(u8, arg, "--words")) {
            options.words = true;
        } else if (std.mem.eql(u8, arg, "-m") or std.mem.eql(u8, arg, "--chars")) {
            options.chars = true;
        } else if (std.mem.eql(u8, arg, "-c") or std.mem.eql(u8, arg, "--bytes")) {
            options.bytes = true;
        } else if (std.mem.eql(u8, arg, "-L") or std.mem.eql(u8, arg, "--max-line-length")) {
            options.max_line_length = true;
        } else if (std.mem.startsWith(u8, arg, "--files0-from=")) {
            options.files0_from = arg[14..];
        } else if (std.mem.eql(u8, arg, "--")) {
            i += 1;
            break;
        } else {
            // Handle combined flags
            if (arg.len > 1 and arg[1] != '-') {
                for (arg[1..]) |flag| {
                    switch (flag) {
                        'l' => options.lines = true,
                        'w' => options.words = true,
                        'm' => options.chars = true,
                        'c' => options.bytes = true,
                        'L' => options.max_line_length = true,
                        else => {
                            const stderr = std.io.getStdErr().writer();
                            try stderr.print("wc: unknown option: -{c}\n", .{flag});
                            std.process.exit(1);
                        },
                    }
                }
            } else {
                const stderr = std.io.getStdErr().writer();
                try stderr.print("wc: unknown option: {s}\n", .{arg});
                std.process.exit(1);
            }
        }
        i += 1;
    }

    // If no counting options specified, use defaults
    if (!options.hasOptions()) {
        options = WcOptions.getDefaults();
    }

    return .{ .options = options, .files = args[i..] };
}

fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == '\x0C' or c == '\x0B';
}

fn countInBuffer(buffer: []const u8, options: WcOptions) WcCounts {
    var counts = WcCounts{};
    var in_word = false;
    var current_line_length: u64 = 0;

    for (buffer) |byte| {
        // Count bytes
        if (options.bytes) {
            counts.bytes += 1;
        }

        // Count characters (for ASCII, same as bytes; for UTF-8 would be different)
        if (options.chars) {
            counts.chars += 1;
        }

        // Count lines and track line length
        if (byte == '\n') {
            if (options.lines) {
                counts.lines += 1;
            }
            if (options.max_line_length) {
                if (current_line_length > counts.max_line_length) {
                    counts.max_line_length = current_line_length;
                }
                current_line_length = 0;
            }
        } else if (options.max_line_length) {
            current_line_length += 1;
        }

        // Count words
        if (options.words) {
            const is_ws = isWhitespace(byte);
            if (!is_ws and !in_word) {
                in_word = true;
                counts.words += 1;
            } else if (is_ws and in_word) {
                in_word = false;
            }
        }
    }

    // Handle final line length if file doesn't end with newline
    if (options.max_line_length and current_line_length > counts.max_line_length) {
        counts.max_line_length = current_line_length;
    }

    return counts;
}

fn wcFile(allocator: std.mem.Allocator, file_path: []const u8, options: WcOptions) !WcCounts {
    const file = std.fs.cwd().openFile(file_path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            const stderr = std.io.getStdErr().writer();
            try stderr.print("wc: {s}: No such file or directory\n", .{file_path});
            return WcCounts{};
        },
        error.AccessDenied => {
            const stderr = std.io.getStdErr().writer();
            try stderr.print("wc: {s}: Permission denied\n", .{file_path});
            return WcCounts{};
        },
        error.IsDir => {
            const stderr = std.io.getStdErr().writer();
            try stderr.print("wc: {s}: Is a directory\n", .{file_path});
            return WcCounts{};
        },
        else => return err,
    };
    defer file.close();

    const file_size = try file.getEndPos();
    const buffer = try allocator.alloc(u8, file_size);
    defer allocator.free(buffer);

    _ = try file.readAll(buffer);

    return countInBuffer(buffer, options);
}

fn wcStdin(allocator: std.mem.Allocator, options: WcOptions) !WcCounts {
    const stdin = std.io.getStdIn().reader();
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    // Read all of stdin
    try stdin.readAllArrayList(&buffer, std.math.maxInt(usize));

    return countInBuffer(buffer.items, options);
}

fn printCounts(counts: WcCounts, options: WcOptions, file_path: ?[]const u8) !void {
    const stdout = std.io.getStdOut().writer();

    // Print counts in the order: lines, words, chars/bytes, max_line_length
    if (options.lines) {
        try stdout.print("{:>8}", .{counts.lines});
    }
    if (options.words) {
        try stdout.print("{:>8}", .{counts.words});
    }
    if (options.chars) {
        try stdout.print("{:>8}", .{counts.chars});
    } else if (options.bytes) {
        try stdout.print("{:>8}", .{counts.bytes});
    }
    if (options.max_line_length) {
        try stdout.print("{:>8}", .{counts.max_line_length});
    }

    // Print filename if provided
    if (file_path) |path| {
        try stdout.print(" {s}", .{path});
    }

    try stdout.print("\n", .{});
}

fn addCounts(a: WcCounts, b: WcCounts) WcCounts {
    return WcCounts{
        .lines = a.lines + b.lines,
        .words = a.words + b.words,
        .chars = a.chars + b.chars,
        .bytes = a.bytes + b.bytes,
        .max_line_length = @max(a.max_line_length, b.max_line_length),
    };
}

pub fn wc_main(args: []const []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const parsed = try parseOptions(args);
    const options = parsed.options;
    var files = parsed.files;

    var total_counts = WcCounts{};
    var file_count: usize = 0;

    // Handle --files0-from option
    if (options.files0_from) |files0_file| {
        const file = std.fs.cwd().openFile(files0_file, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                const stderr = std.io.getStdErr().writer();
                try stderr.print("wc: cannot open '{s}' for reading: No such file or directory\n", .{files0_file});
                std.process.exit(1);
            },
            else => return err,
        };
        defer file.close();

        const content = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
        defer allocator.free(content);

        // Split on null bytes
        var file_list = std.ArrayList([]const u8).init(allocator);
        defer file_list.deinit();

        var it = std.mem.splitScalar(u8, content, '\x00');
        while (it.next()) |filename| {
            if (filename.len > 0) {
                try file_list.append(filename);
            }
        }

        files = file_list.items;
    }

    // If no files specified, read from stdin
    if (files.len == 0) {
        const counts = try wcStdin(allocator, options);
        try printCounts(counts, options, null);
        return;
    }

    // Process each file
    for (files) |file_path| {
        const counts = try wcFile(allocator, file_path, options);
        try printCounts(counts, options, file_path);
        total_counts = addCounts(total_counts, counts);
        file_count += 1;
    }

    // Print total if multiple files
    if (file_count > 1) {
        try printCounts(total_counts, options, "total");
    }
}
