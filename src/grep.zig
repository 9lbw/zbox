const std = @import("std");

pub fn grep_main(args: []const []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    var pattern: ?[]const u8 = null;
    var case_insensitive = false;
    var show_line_numbers = false;
    var invert_match = false;
    var recursive = false;
    var show_filenames = false;
    var count_only = false;
    var quiet = false;
    var file_args: []const []const u8 = &[_][]const u8{};

    // Parse arguments
    var i: usize = 0;
    while (i < args.len) {
        const arg = args[i];

        if (arg.len > 1 and arg[0] == '-') {
            if (std.mem.eql(u8, arg, "--help")) {
                try print_help(stdout);
                return;
            } else if (std.mem.eql(u8, arg, "-i") or std.mem.eql(u8, arg, "--ignore-case")) {
                case_insensitive = true;
            } else if (std.mem.eql(u8, arg, "-n") or std.mem.eql(u8, arg, "--line-number")) {
                show_line_numbers = true;
            } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--invert-match")) {
                invert_match = true;
            } else if (std.mem.eql(u8, arg, "-r") or std.mem.eql(u8, arg, "--recursive")) {
                recursive = true;
            } else if (std.mem.eql(u8, arg, "-H") or std.mem.eql(u8, arg, "--with-filename")) {
                show_filenames = true;
            } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--no-filename")) {
                show_filenames = false;
            } else if (std.mem.eql(u8, arg, "-c") or std.mem.eql(u8, arg, "--count")) {
                count_only = true;
            } else if (std.mem.eql(u8, arg, "-q") or std.mem.eql(u8, arg, "--quiet")) {
                quiet = true;
            } else if (std.mem.startsWith(u8, arg, "-")) {
                // Handle combined flags like -in, -nv, etc.
                for (arg[1..]) |flag| {
                    switch (flag) {
                        'i' => case_insensitive = true,
                        'n' => show_line_numbers = true,
                        'v' => invert_match = true,
                        'r' => recursive = true,
                        'H' => show_filenames = true,
                        'h' => show_filenames = false,
                        'c' => count_only = true,
                        'q' => quiet = true,
                        else => {
                            try stderr.print("grep: invalid option -- '{c}'\n", .{flag});
                            std.process.exit(1);
                        },
                    }
                }
            } else {
                try stderr.print("grep: invalid option -- '{s}'\n", .{arg});
                std.process.exit(1);
            }
        } else {
            // First non-option argument is the pattern
            if (pattern == null) {
                pattern = arg;
            } else {
                // Remaining arguments are files
                file_args = args[i..];
                break;
            }
        }
        i += 1;
    }

    if (pattern == null) {
        try stderr.print("grep: missing pattern\n", .{});
        try stderr.print("Usage: grep [OPTION]... PATTERN [FILE]...\n", .{});
        try stderr.print("Try 'grep --help' for more information.\n", .{});
        std.process.exit(1);
    }

    const search_pattern = pattern.?;

    // If no files specified, read from stdin
    if (file_args.len == 0) {
        const result = try grep_file(allocator, null, search_pattern, case_insensitive, show_line_numbers, invert_match, show_filenames, count_only, quiet);
        if (quiet and result > 0) std.process.exit(0);
        if (quiet and result == 0) std.process.exit(1);
        return;
    }

    // Determine if we should show filenames (default is yes if multiple files)
    const should_show_filenames = show_filenames or (file_args.len > 1);
    var total_matches: usize = 0;
    var any_matches = false;

    // Process each file
    for (file_args) |filename| {
        if (recursive and is_directory(filename)) {
            const matches = try grep_directory(allocator, filename, search_pattern, case_insensitive, show_line_numbers, invert_match, should_show_filenames, count_only, quiet);
            total_matches += matches;
            if (matches > 0) any_matches = true;
        } else {
            const matches = try grep_file(allocator, filename, search_pattern, case_insensitive, show_line_numbers, invert_match, should_show_filenames, count_only, quiet);
            total_matches += matches;
            if (matches > 0) any_matches = true;
        }
    }

    // Set exit code based on whether we found matches
    if (quiet) {
        std.process.exit(if (any_matches) 0 else 1);
    }
}

fn print_help(writer: anytype) !void {
    try writer.print("Usage: grep [OPTION]... PATTERN [FILE]...\n", .{});
    try writer.print("Search for PATTERN in each FILE.\n", .{});
    try writer.print("Example: grep -i 'hello world' menu.h main.c\n", .{});
    try writer.print("\n", .{});
    try writer.print("Pattern selection and interpretation:\n", .{});
    try writer.print("  -i, --ignore-case         ignore case distinctions\n", .{});
    try writer.print("\n", .{});
    try writer.print("Miscellaneous:\n", .{});
    try writer.print("  -v, --invert-match        select non-matching lines\n", .{});
    try writer.print("  -n, --line-number         print line number with output lines\n", .{});
    try writer.print("  -H, --with-filename       print the file name for each match\n", .{});
    try writer.print("  -h, --no-filename         suppress the file name prefix on output\n", .{});
    try writer.print("  -c, --count               print only a count of matching lines per FILE\n", .{});
    try writer.print("  -q, --quiet               suppress all normal output\n", .{});
    try writer.print("  -r, --recursive           read all files under each directory, recursively\n", .{});
    try writer.print("      --help                display this help and exit\n", .{});
    try writer.print("\n", .{});
    try writer.print("With no FILE, or when FILE is -, read standard input.\n", .{});
}

fn grep_file(allocator: std.mem.Allocator, filename: ?[]const u8, pattern: []const u8, case_insensitive: bool, show_line_numbers: bool, invert_match: bool, show_filenames: bool, count_only: bool, quiet: bool) !usize {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    var file: std.fs.File = undefined;
    var should_close = false;

    if (filename) |fname| {
        file = std.fs.cwd().openFile(fname, .{}) catch |err| {
            if (!quiet) {
                try stderr.print("grep: {s}: {s}\n", .{ fname, @errorName(err) });
            }
            return 0;
        };
        should_close = true;

        // Skip binary files when doing recursive search
        if (is_binary_file(file)) {
            return 0;
        }
    } else {
        file = std.io.getStdIn();
    }
    defer if (should_close) file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var reader = buf_reader.reader();

    var line_number: usize = 1;
    var match_count: usize = 0;

    // Convert pattern to lowercase if case insensitive
    var pattern_lower: []u8 = &[_]u8{};
    if (case_insensitive) {
        pattern_lower = try allocator.alloc(u8, pattern.len);
        for (pattern, 0..) |c, idx| {
            pattern_lower[idx] = std.ascii.toLower(c);
        }
    }
    defer if (case_insensitive) allocator.free(pattern_lower);

    while (true) {
        const line = reader.readUntilDelimiterAlloc(allocator, '\n', 8192) catch |err| switch (err) {
            error.EndOfStream => break,
            error.StreamTooLong => {
                // Skip this line if it's too long (likely a binary file)
                _ = reader.skipUntilDelimiterOrEof('\n') catch {};
                continue;
            },
            else => return err,
        };
        defer allocator.free(line);

        var matches = false;
        if (case_insensitive) {
            // Convert line to lowercase for comparison
            var line_lower = try allocator.alloc(u8, line.len);
            defer allocator.free(line_lower);
            for (line, 0..) |c, idx| {
                line_lower[idx] = std.ascii.toLower(c);
            }
            matches = std.mem.indexOf(u8, line_lower, pattern_lower) != null;
        } else {
            matches = std.mem.indexOf(u8, line, pattern) != null;
        }

        // Apply invert match logic
        if (invert_match) {
            matches = !matches;
        }

        if (matches) {
            match_count += 1;

            if (quiet) {
                // In quiet mode, we can return early on first match
                return match_count;
            }

            if (!count_only) {
                // Print filename if needed
                if (show_filenames and filename != null) {
                    try stdout.print("{s}:", .{filename.?});
                }

                // Print line number if needed
                if (show_line_numbers) {
                    try stdout.print("{d}:", .{line_number});
                }

                try stdout.print("{s}\n", .{line});
            }
        }

        line_number += 1;
    }

    // Print count if requested
    if (count_only and !quiet) {
        if (show_filenames and filename != null) {
            try stdout.print("{s}:", .{filename.?});
        }
        try stdout.print("{d}\n", .{match_count});
    }

    return match_count;
}

fn grep_directory(allocator: std.mem.Allocator, dir_path: []const u8, pattern: []const u8, case_insensitive: bool, show_line_numbers: bool, invert_match: bool, show_filenames: bool, count_only: bool, quiet: bool) !usize {
    var total_matches: usize = 0;

    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
        const stderr = std.io.getStdErr().writer();
        if (!quiet) {
            try stderr.print("grep: {s}: {s}\n", .{ dir_path, @errorName(err) });
        }
        return 0;
    };
    defer dir.close();

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ dir_path, entry.name });
        defer allocator.free(full_path);

        switch (entry.kind) {
            .file => {
                const matches = try grep_file(allocator, full_path, pattern, case_insensitive, show_line_numbers, invert_match, show_filenames, count_only, quiet);
                total_matches += matches;
            },
            .directory => {
                // Skip hidden directories
                if (entry.name[0] != '.') {
                    const matches = try grep_directory(allocator, full_path, pattern, case_insensitive, show_line_numbers, invert_match, show_filenames, count_only, quiet);
                    total_matches += matches;
                }
            },
            else => {}, // Skip other file types
        }
    }

    return total_matches;
}

fn is_directory(path: []const u8) bool {
    const stat = std.fs.cwd().statFile(path) catch return false;
    return stat.kind == .directory;
}

fn is_binary_file(file: std.fs.File) bool {
    // Read first 512 bytes to check for binary content
    var buffer: [512]u8 = undefined;
    const bytes_read = file.readAll(&buffer) catch return false;

    // Reset file position
    file.seekTo(0) catch {};

    // Check for null bytes which typically indicate binary content
    for (buffer[0..bytes_read]) |byte| {
        if (byte == 0) return true;
    }

    return false;
}
