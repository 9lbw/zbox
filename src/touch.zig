const std = @import("std");

const TouchOptions = struct {
    access_only: bool = false, // -a: change only access time
    modify_only: bool = false, // -m: change only modification time
    no_create: bool = false, // -c: do not create files
    reference: ?[]const u8 = null, // -r: use reference file's time
    time_str: ?[]const u8 = null, // -t: use specified time
};

fn parseOptions(args: []const []const u8) !struct { options: TouchOptions, files: []const []const u8 } {
    var options = TouchOptions{};
    var i: usize = 0;

    // Parse flags
    while (i < args.len and args[i][0] == '-') {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-a") or std.mem.eql(u8, arg, "--time=atime") or std.mem.eql(u8, arg, "--time=access")) {
            options.access_only = true;
        } else if (std.mem.eql(u8, arg, "-m") or std.mem.eql(u8, arg, "--time=mtime") or std.mem.eql(u8, arg, "--time=modify")) {
            options.modify_only = true;
        } else if (std.mem.eql(u8, arg, "-c") or std.mem.eql(u8, arg, "--no-create")) {
            options.no_create = true;
        } else if (std.mem.eql(u8, arg, "-r") or std.mem.eql(u8, arg, "--reference")) {
            i += 1;
            if (i >= args.len) {
                const stderr = std.io.getStdErr().writer();
                try stderr.print("touch: option requires an argument -- 'r'\n", .{});
                std.process.exit(1);
            }
            options.reference = args[i];
        } else if (std.mem.eql(u8, arg, "-t")) {
            i += 1;
            if (i >= args.len) {
                const stderr = std.io.getStdErr().writer();
                try stderr.print("touch: option requires an argument -- 't'\n", .{});
                std.process.exit(1);
            }
            options.time_str = args[i];
        } else if (std.mem.eql(u8, arg, "--")) {
            i += 1;
            break;
        } else {
            // Handle combined flags like -am, -cm, etc.
            if (arg.len > 1 and arg[1] != '-') {
                for (arg[1..]) |flag| {
                    switch (flag) {
                        'a' => options.access_only = true,
                        'm' => options.modify_only = true,
                        'c' => options.no_create = true,
                        else => {
                            const stderr = std.io.getStdErr().writer();
                            try stderr.print("touch: unknown option: -{c}\n", .{flag});
                            std.process.exit(1);
                        },
                    }
                }
            } else {
                const stderr = std.io.getStdErr().writer();
                try stderr.print("touch: unknown option: {s}\n", .{arg});
                std.process.exit(1);
            }
        }
        i += 1;
    }

    return .{ .options = options, .files = args[i..] };
}

fn getCurrentTime() i64 {
    return std.time.timestamp();
}

fn getFileTime(file_path: []const u8) !struct { atime: i64, mtime: i64 } {
    const cwd = std.fs.cwd();
    const stat = try cwd.statFile(file_path);
    return .{ .atime = @intCast(@divTrunc(stat.atime, std.time.ns_per_s)), .mtime = @intCast(@divTrunc(stat.mtime, std.time.ns_per_s)) };
}

fn parseTimeString(time_str: []const u8) !i64 {
    // Parse time in format [[CC]YY]MMDDhhmm[.ss]
    // For simplicity, we'll support basic YYYYMMDDHHMM format
    if (time_str.len < 8) {
        return error.InvalidTimeFormat;
    }

    // Extract components
    const year_str = if (time_str.len >= 12) time_str[0..4] else "2024"; // Default year
    const month_str = time_str[time_str.len - 8 .. time_str.len - 6];
    const day_str = time_str[time_str.len - 6 .. time_str.len - 4];
    const hour_str = time_str[time_str.len - 4 .. time_str.len - 2];
    const min_str = time_str[time_str.len - 2 ..];

    const year = try std.fmt.parseInt(u16, year_str, 10);
    const month = try std.fmt.parseInt(u8, month_str, 10);
    const day = try std.fmt.parseInt(u8, day_str, 10);
    const hour = try std.fmt.parseInt(u8, hour_str, 10);
    const min = try std.fmt.parseInt(u8, min_str, 10);

    // Basic validation
    if (month < 1 or month > 12 or day < 1 or day > 31 or hour > 23 or min > 59) {
        return error.InvalidTimeFormat;
    }

    // Convert to timestamp (simplified - doesn't handle all edge cases)
    const days_since_epoch = @as(i64, (year - 1970)) * 365 + @as(i64, (month - 1)) * 30 + @as(i64, day - 1);
    const seconds = days_since_epoch * 24 * 60 * 60 + @as(i64, hour) * 60 * 60 + @as(i64, min) * 60;

    return seconds;
}

fn touchFile(file_path: []const u8, options: TouchOptions) !void {
    const cwd = std.fs.cwd();
    const stderr = std.io.getStdErr().writer();

    // Check if file exists
    const file_exists = blk: {
        cwd.access(file_path, .{}) catch |err| switch (err) {
            error.FileNotFound => break :blk false,
            else => {
                try stderr.print("touch: cannot access '{s}': {s}\n", .{ file_path, @errorName(err) });
                return;
            },
        };
        break :blk true;
    };

    // Create file if it doesn't exist and -c is not specified
    if (!file_exists) {
        if (options.no_create) {
            return; // Skip if -c is specified and file doesn't exist
        }

        // Create empty file
        const file = cwd.createFile(file_path, .{}) catch |err| {
            try stderr.print("touch: cannot create '{s}': {s}\n", .{ file_path, @errorName(err) });
            return;
        };
        file.close();
    }

    // Determine the time to set
    var new_atime: i64 = undefined;
    var new_mtime: i64 = undefined;

    if (options.reference) |ref_path| {
        // Use reference file's time
        const ref_times = getFileTime(ref_path) catch |err| {
            try stderr.print("touch: cannot get time from reference file '{s}': {s}\n", .{ ref_path, @errorName(err) });
            return;
        };
        new_atime = ref_times.atime;
        new_mtime = ref_times.mtime;
    } else if (options.time_str) |time_str| {
        // Use specified time
        const parsed_time = parseTimeString(time_str) catch |err| {
            try stderr.print("touch: invalid time format '{s}': {s}\n", .{ time_str, @errorName(err) });
            return;
        };
        new_atime = parsed_time;
        new_mtime = parsed_time;
    } else {
        // Use current time
        const current_time = getCurrentTime();
        new_atime = current_time;
        new_mtime = current_time;
    }

    // If file already existed, get current times to preserve what we're not changing
    if (file_exists) {
        const current_times = getFileTime(file_path) catch |err| {
            try stderr.print("touch: cannot get current time for '{s}': {s}\n", .{ file_path, @errorName(err) });
            return;
        };

        if (options.access_only) {
            new_mtime = current_times.mtime; // Preserve modification time
        } else if (options.modify_only) {
            new_atime = current_times.atime; // Preserve access time
        }
    }

    // Update file times
    const file = cwd.openFile(file_path, .{ .mode = .read_write }) catch |err| {
        try stderr.print("touch: cannot open '{s}' for time update: {s}\n", .{ file_path, @errorName(err) });
        return;
    };
    defer file.close();

    file.updateTimes(
        @as(i128, new_atime) * std.time.ns_per_s,
        @as(i128, new_mtime) * std.time.ns_per_s,
    ) catch |err| {
        try stderr.print("touch: cannot update times for '{s}': {s}\n", .{ file_path, @errorName(err) });
        return;
    };
}

pub fn touch_main(args: []const []const u8) !void {
    const parsed = try parseOptions(args);
    const options = parsed.options;
    const files = parsed.files;

    if (files.len == 0) {
        const stderr = std.io.getStdErr().writer();
        try stderr.writeAll("touch: missing file operand\n");
        std.process.exit(1);
    }

    // Validate conflicting options
    if (options.access_only and options.modify_only) {
        const stderr = std.io.getStdErr().writer();
        try stderr.writeAll("touch: cannot specify both -a and -m\n");
        std.process.exit(1);
    }

    for (files) |file_path| {
        try touchFile(file_path, options);
    }
}
