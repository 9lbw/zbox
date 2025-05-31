const std = @import("std");

const CpOptions = struct {
    recursive: bool = false,
    force: bool = false,
    preserve: bool = false,
    verbose: bool = false,
};

fn parseOptions(args: []const []const u8) !struct { options: CpOptions, files: []const []const u8 } {
    var options = CpOptions{};
    var i: usize = 0;

    // Parse flags
    while (i < args.len and args[i][0] == '-') {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-r") or std.mem.eql(u8, arg, "--recursive")) {
            options.recursive = true;
        } else if (std.mem.eql(u8, arg, "-f") or std.mem.eql(u8, arg, "--force")) {
            options.force = true;
        } else if (std.mem.eql(u8, arg, "-p") or std.mem.eql(u8, arg, "--preserve")) {
            options.preserve = true;
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose")) {
            options.verbose = true;
        } else if (std.mem.eql(u8, arg, "--")) {
            i += 1;
            break;
        } else {
            // Handle combined flags like -rf, -rv, etc.
            if (arg.len > 1 and arg[1] != '-') {
                for (arg[1..]) |flag| {
                    switch (flag) {
                        'r' => options.recursive = true,
                        'f' => options.force = true,
                        'p' => options.preserve = true,
                        'v' => options.verbose = true,
                        else => {
                            const stderr = std.io.getStdErr().writer();
                            try stderr.print("cp: unknown option: -{c}\n", .{flag});
                            std.process.exit(1);
                        },
                    }
                }
            } else {
                const stderr = std.io.getStdErr().writer();
                try stderr.print("cp: unknown option: {s}\n", .{arg});
                std.process.exit(1);
            }
        }
        i += 1;
    }

    return .{ .options = options, .files = args[i..] };
}

fn copyFile(src_path: []const u8, dest_path: []const u8, options: CpOptions) !void {
    const cwd = std.fs.cwd();
    const stderr = std.io.getStdErr().writer();

    // Open source file
    const src_file = cwd.openFile(src_path, .{}) catch |err| {
        if (!options.force) {
            try stderr.print("cp: cannot open '{s}': {s}\n", .{ src_path, @errorName(err) });
        }
        return;
    };
    defer src_file.close();

    // Check if destination exists and handle accordingly
    if (cwd.access(dest_path, .{})) {
        if (!options.force) {
            // TODO: In a real implementation, we might prompt the user here
            // For now, we'll just overwrite
        }
    } else |_| {
        // Destination doesn't exist, which is fine
    }

    // Create destination file
    const dest_file = cwd.createFile(dest_path, .{}) catch |err| {
        if (!options.force) {
            try stderr.print("cp: cannot create '{s}': {s}\n", .{ dest_path, @errorName(err) });
        }
        return;
    };
    defer dest_file.close();

    // Copy file contents
    var buffer: [8192]u8 = undefined;
    while (true) {
        const bytes_read = src_file.read(&buffer) catch |err| {
            if (!options.force) {
                try stderr.print("cp: error reading '{s}': {s}\n", .{ src_path, @errorName(err) });
            }
            return;
        };
        if (bytes_read == 0) break;

        dest_file.writeAll(buffer[0..bytes_read]) catch |err| {
            if (!options.force) {
                try stderr.print("cp: error writing '{s}': {s}\n", .{ dest_path, @errorName(err) });
            }
            return;
        };
    }

    // Copy metadata if preserve flag is set
    if (options.preserve) {
        const src_stat = src_file.stat() catch |err| {
            if (!options.force) {
                try stderr.print("cp: cannot stat '{s}': {s}\n", .{ src_path, @errorName(err) });
            }
            return;
        };

        dest_file.chmod(src_stat.mode) catch |err| {
            if (!options.force) {
                try stderr.print("cp: cannot set permissions for '{s}': {s}\n", .{ dest_path, @errorName(err) });
            }
        };
    }

    if (options.verbose) {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("'{s}' -> '{s}'\n", .{ src_path, dest_path });
    }
}

fn copyDirectory(allocator: std.mem.Allocator, src_path: []const u8, dest_path: []const u8, options: CpOptions) !void {
    const cwd = std.fs.cwd();
    const stderr = std.io.getStdErr().writer();

    // Create destination directory
    cwd.makeDir(dest_path) catch |err| switch (err) {
        error.PathAlreadyExists => {
            // Directory already exists, check if it's actually a directory
            const stat = cwd.statFile(dest_path) catch |stat_err| {
                if (!options.force) {
                    try stderr.print("cp: cannot stat '{s}': {s}\n", .{ dest_path, @errorName(stat_err) });
                }
                return;
            };
            if (stat.kind != .directory) {
                if (!options.force) {
                    try stderr.print("cp: '{s}' exists and is not a directory\n", .{dest_path});
                }
                return;
            }
        },
        else => {
            if (!options.force) {
                try stderr.print("cp: cannot create directory '{s}': {s}\n", .{ dest_path, @errorName(err) });
            }
            return;
        },
    };

    // Open source directory
    var src_dir = cwd.openDir(src_path, .{ .iterate = true }) catch |err| {
        if (!options.force) {
            try stderr.print("cp: cannot open directory '{s}': {s}\n", .{ src_path, @errorName(err) });
        }
        return;
    };
    defer src_dir.close();

    // Iterate through source directory
    var iter = src_dir.iterate();
    while (try iter.next()) |entry| {
        const src_entry_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ src_path, entry.name });
        defer allocator.free(src_entry_path);

        const dest_entry_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dest_path, entry.name });
        defer allocator.free(dest_entry_path);

        switch (entry.kind) {
            .file, .sym_link => {
                try copyFile(src_entry_path, dest_entry_path, options);
            },
            .directory => {
                if (options.recursive) {
                    try copyDirectory(allocator, src_entry_path, dest_entry_path, options);
                } else {
                    if (!options.force) {
                        try stderr.print("cp: omitting directory '{s}'\n", .{src_entry_path});
                    }
                }
            },
            else => {
                if (!options.force) {
                    try stderr.print("cp: skipping '{s}': unsupported file type\n", .{src_entry_path});
                }
            },
        }
    }

    if (options.verbose) {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("'{s}' -> '{s}'\n", .{ src_path, dest_path });
    }
}

fn isDirectory(path: []const u8) bool {
    const cwd = std.fs.cwd();
    const stat = cwd.statFile(path) catch return false;
    return stat.kind == .directory;
}

pub fn cp_main(args: []const []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const parsed = try parseOptions(args);
    const options = parsed.options;
    const files = parsed.files;

    if (files.len < 2) {
        const stderr = std.io.getStdErr().writer();
        try stderr.writeAll("cp: missing file operand\n");
        std.process.exit(1);
    }

    const dest = files[files.len - 1];
    const sources = files[0 .. files.len - 1];

    // Check if destination is a directory
    const dest_is_dir = isDirectory(dest);

    if (sources.len > 1 and !dest_is_dir) {
        const stderr = std.io.getStdErr().writer();
        try stderr.print("cp: target '{s}' is not a directory\n", .{dest});
        std.process.exit(1);
    }

    for (sources) |src| {
        const cwd = std.fs.cwd();
        const src_stat = cwd.statFile(src) catch |err| {
            if (!options.force) {
                const stderr = std.io.getStdErr().writer();
                try stderr.print("cp: cannot stat '{s}': {s}\n", .{ src, @errorName(err) });
            }
            continue;
        };

        const final_dest = if (dest_is_dir) blk: {
            const basename = std.fs.path.basename(src);
            break :blk try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dest, basename });
        } else dest;

        switch (src_stat.kind) {
            .file, .sym_link => {
                try copyFile(src, final_dest, options);
            },
            .directory => {
                if (!options.recursive) {
                    if (!options.force) {
                        const stderr = std.io.getStdErr().writer();
                        try stderr.print("cp: omitting directory '{s}'\n", .{src});
                    }
                    continue;
                }
                try copyDirectory(allocator, src, final_dest, options);
            },
            else => {
                if (!options.force) {
                    const stderr = std.io.getStdErr().writer();
                    try stderr.print("cp: skipping '{s}': unsupported file type\n", .{src});
                }
            },
        }
    }
}
