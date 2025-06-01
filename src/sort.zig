const std = @import("std");

pub fn sort_main(args: []const []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    var reverse = false;
    var numeric = false;
    var unique = false;
    var ignore_case = false;
    var output_file: ?[]const u8 = null;
    var field_separator: ?u8 = null;
    var sort_key: ?SortKey = null;
    var file_args: []const []const u8 = &[_][]const u8{};

    // Parse arguments
    var i: usize = 0;
    while (i < args.len) {
        const arg = args[i];

        if (arg.len > 1 and arg[0] == '-') {
            if (std.mem.eql(u8, arg, "--help")) {
                try print_help(stdout);
                return;
            } else if (std.mem.eql(u8, arg, "-r") or std.mem.eql(u8, arg, "--reverse")) {
                reverse = true;
            } else if (std.mem.eql(u8, arg, "-n") or std.mem.eql(u8, arg, "--numeric-sort")) {
                numeric = true;
            } else if (std.mem.eql(u8, arg, "-u") or std.mem.eql(u8, arg, "--unique")) {
                unique = true;
            } else if (std.mem.eql(u8, arg, "-f") or std.mem.eql(u8, arg, "--ignore-case")) {
                ignore_case = true;
            } else if (std.mem.startsWith(u8, arg, "-o")) {
                if (arg.len > 2) {
                    output_file = arg[2..];
                } else if (i + 1 < args.len) {
                    i += 1;
                    output_file = args[i];
                } else {
                    try stderr.print("sort: option requires an argument -- 'o'\n", .{});
                    std.process.exit(1);
                }
            } else if (std.mem.startsWith(u8, arg, "-t")) {
                if (arg.len > 2) {
                    if (arg.len > 3) {
                        try stderr.print("sort: field separator must be a single character\n", .{});
                        std.process.exit(1);
                    }
                    field_separator = arg[2];
                } else if (i + 1 < args.len) {
                    i += 1;
                    if (args[i].len != 1) {
                        try stderr.print("sort: field separator must be a single character\n", .{});
                        std.process.exit(1);
                    }
                    field_separator = args[i][0];
                } else {
                    try stderr.print("sort: option requires an argument -- 't'\n", .{});
                    std.process.exit(1);
                }
            } else if (std.mem.startsWith(u8, arg, "-k")) {
                var key_spec: []const u8 = undefined;
                if (arg.len > 2) {
                    key_spec = arg[2..];
                } else if (i + 1 < args.len) {
                    i += 1;
                    key_spec = args[i];
                } else {
                    try stderr.print("sort: option requires an argument -- 'k'\n", .{});
                    std.process.exit(1);
                }
                sort_key = try parse_sort_key(key_spec);
            } else if (std.mem.startsWith(u8, arg, "-")) {
                // Handle combined flags like -rn, -fu, etc.
                for (arg[1..]) |flag| {
                    switch (flag) {
                        'r' => reverse = true,
                        'n' => numeric = true,
                        'u' => unique = true,
                        'f' => ignore_case = true,
                        else => {
                            try stderr.print("sort: invalid option -- '{c}'\n", .{flag});
                            std.process.exit(1);
                        },
                    }
                }
            } else {
                try stderr.print("sort: invalid option -- '{s}'\n", .{arg});
                std.process.exit(1);
            }
        } else {
            // Remaining arguments are files
            file_args = args[i..];
            break;
        }
        i += 1;
    }

    // Read all lines from input files or stdin
    var lines = std.ArrayList([]const u8).init(allocator);
    defer lines.deinit();

    if (file_args.len == 0) {
        try read_lines_from_file(allocator, null, &lines);
    } else {
        for (file_args) |filename| {
            try read_lines_from_file(allocator, filename, &lines);
        }
    }

    // Create sort context
    const sort_context = SortContext{
        .numeric = numeric,
        .ignore_case = ignore_case,
        .reverse = reverse,
        .field_separator = field_separator,
        .sort_key = sort_key,
    };

    // Sort the lines
    std.mem.sort([]const u8, lines.items, sort_context, compare_lines_less_than);

    // Remove duplicates if unique flag is set
    if (unique) {
        var unique_lines = std.ArrayList([]const u8).init(allocator);
        defer unique_lines.deinit();

        if (lines.items.len > 0) {
            try unique_lines.append(lines.items[0]);

            for (lines.items[1..]) |line| {
                const last_line = unique_lines.items[unique_lines.items.len - 1];
                if (compare_lines(sort_context, last_line, line) != .eq) {
                    try unique_lines.append(line);
                }
            }
        }

        // Transfer ownership properly
        lines.clearAndFree();
        try lines.appendSlice(unique_lines.items);
    }

    // Output the sorted lines
    if (output_file) |fname| {
        const file = try std.fs.cwd().createFile(fname, .{});
        defer file.close();
        const file_writer = file.writer();
        for (lines.items) |line| {
            try file_writer.print("{s}\n", .{line});
        }
    } else {
        for (lines.items) |line| {
            try stdout.print("{s}\n", .{line});
        }
    }
}

const SortKey = struct {
    field_start: usize,
    field_end: ?usize,
    char_start: usize,
    char_end: ?usize,
};

const SortContext = struct {
    numeric: bool,
    ignore_case: bool,
    reverse: bool,
    field_separator: ?u8,
    sort_key: ?SortKey,
};

fn print_help(writer: anytype) !void {
    try writer.print("Usage: sort [OPTION]... [FILE]...\n", .{});
    try writer.print("Write sorted concatenation of all FILE(s) to standard output.\n", .{});
    try writer.print("\n", .{});
    try writer.print("Ordering options:\n", .{});
    try writer.print("  -f, --ignore-case         fold lower case to upper case characters\n", .{});
    try writer.print("  -n, --numeric-sort        compare according to string numerical value\n", .{});
    try writer.print("  -r, --reverse             reverse the result of comparisons\n", .{});
    try writer.print("\n", .{});
    try writer.print("Other options:\n", .{});
    try writer.print("  -k, --key=KEYDEF          sort via a key; KEYDEF gives location and type\n", .{});
    try writer.print("  -o, --output=FILE         write result to FILE instead of standard output\n", .{});
    try writer.print("  -t, --field-separator=SEP use SEP instead of non-blank to blank transition\n", .{});
    try writer.print("  -u, --unique              with -c, check for strict ordering;\n", .{});
    try writer.print("                            without -c, output only the first of an equal run\n", .{});
    try writer.print("      --help                display this help and exit\n", .{});
    try writer.print("\n", .{});
    try writer.print("KEYDEF is F[.C][OPTS][,F[.C][OPTS]] for start and stop position, where F is a\n", .{});
    try writer.print("field number and C a character position in the field; both are origin 1.\n", .{});
    try writer.print("If neither -t nor -b is in effect, characters in a field are counted from the\n", .{});
    try writer.print("beginning of the whitespace-separated field.\n", .{});
}

fn read_lines_from_file(allocator: std.mem.Allocator, filename: ?[]const u8, lines: *std.ArrayList([]const u8)) !void {
    const stderr = std.io.getStdErr().writer();

    var file: std.fs.File = undefined;
    var should_close = false;

    if (filename) |fname| {
        file = std.fs.cwd().openFile(fname, .{}) catch |err| {
            try stderr.print("sort: {s}: {s}\n", .{ fname, @errorName(err) });
            std.process.exit(1);
        };
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
        try lines.append(line);
    }
}

fn parse_sort_key(key_spec: []const u8) !SortKey {
    // Simple key parsing: field[.char]
    // For now, we'll implement basic field specification

    var field_start: usize = 1;
    var field_end: ?usize = null;
    var char_start: usize = 1;
    var char_end: ?usize = null;

    // Look for comma to separate start and end specifications
    if (std.mem.indexOf(u8, key_spec, ",")) |comma_pos| {
        // Parse start field
        const start_spec = key_spec[0..comma_pos];
        const end_spec = key_spec[comma_pos + 1 ..];

        field_start = try parse_field_spec(start_spec, &char_start);
        var temp_char_end: usize = 1;
        field_end = try parse_field_spec(end_spec, &temp_char_end);
        char_end = temp_char_end;
    } else {
        // Only start field specified
        field_start = try parse_field_spec(key_spec, &char_start);
    }

    return SortKey{
        .field_start = field_start,
        .field_end = field_end,
        .char_start = char_start,
        .char_end = char_end,
    };
}

fn parse_field_spec(spec: []const u8, char_pos: *usize) !usize {
    if (std.mem.indexOf(u8, spec, ".")) |dot_pos| {
        const field_str = spec[0..dot_pos];
        const char_str = spec[dot_pos + 1 ..];

        const field = try std.fmt.parseInt(usize, field_str, 10);
        char_pos.* = try std.fmt.parseInt(usize, char_str, 10);

        return field;
    } else {
        return try std.fmt.parseInt(usize, spec, 10);
    }
}

fn compare_lines_less_than(context: SortContext, a: []const u8, b: []const u8) bool {
    return compare_lines(context, a, b) == .lt;
}

fn compare_lines(context: SortContext, a: []const u8, b: []const u8) std.math.Order {
    var line_a = a;
    var line_b = b;

    // Extract key fields if specified
    if (context.sort_key) |key| {
        line_a = extract_sort_key(a, key, context.field_separator);
        line_b = extract_sort_key(b, key, context.field_separator);
    }

    var result: std.math.Order = undefined;

    if (context.numeric) {
        result = compare_numeric(line_a, line_b);
    } else if (context.ignore_case) {
        result = compare_ignore_case(line_a, line_b);
    } else {
        result = std.mem.order(u8, line_a, line_b);
    }

    if (context.reverse) {
        result = switch (result) {
            .lt => .gt,
            .gt => .lt,
            .eq => .eq,
        };
    }

    return result;
}

fn extract_sort_key(line: []const u8, key: SortKey, field_separator: ?u8) []const u8 {
    const separator = field_separator orelse ' ';

    // Split line into fields
    var field_iter = std.mem.splitScalar(u8, line, separator);
    var field_count: usize = 1;

    // Find the start field
    while (field_iter.next()) |field| {
        if (field_count == key.field_start) {
            // Extract character range within the field
            const start_char = if (key.char_start > 1) key.char_start - 1 else 0;
            const end_char = if (key.char_end) |end| @min(end, field.len) else field.len;

            if (start_char >= field.len) return "";
            return field[start_char..end_char];
        }
        field_count += 1;
    }

    return "";
}

fn compare_numeric(a: []const u8, b: []const u8) std.math.Order {
    // Extract numeric values from the beginning of each string
    const num_a = parse_number(a);
    const num_b = parse_number(b);

    return std.math.order(num_a, num_b);
}

fn parse_number(str: []const u8) f64 {
    // Skip leading whitespace
    var start: usize = 0;
    while (start < str.len and std.ascii.isWhitespace(str[start])) {
        start += 1;
    }

    if (start >= str.len) return 0.0;

    // Find end of number
    var end = start;
    var has_dot = false;

    // Handle optional negative sign
    if (str[end] == '-' or str[end] == '+') {
        end += 1;
    }

    while (end < str.len) {
        const c = str[end];
        if (std.ascii.isDigit(c)) {
            end += 1;
        } else if (c == '.' and !has_dot) {
            has_dot = true;
            end += 1;
        } else {
            break;
        }
    }

    if (end == start or (end == start + 1 and (str[start] == '-' or str[start] == '+'))) {
        return 0.0;
    }

    return std.fmt.parseFloat(f64, str[start..end]) catch 0.0;
}

fn compare_ignore_case(a: []const u8, b: []const u8) std.math.Order {
    const min_len = @min(a.len, b.len);

    for (0..min_len) |i| {
        const char_a = std.ascii.toLower(a[i]);
        const char_b = std.ascii.toLower(b[i]);

        if (char_a < char_b) return .lt;
        if (char_a > char_b) return .gt;
    }

    return std.math.order(a.len, b.len);
}
