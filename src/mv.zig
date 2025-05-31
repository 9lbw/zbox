const std = @import("std");

const MvOptions = struct {
    force: bool = false, // -f: force overwrite without prompting
    interactive: bool = false, // -i: prompt before overwrite
    no_clobber: bool = false, // -n: do not overwrite existing files
    verbose: bool = false, // -v: verbose output
};

fn parseOptions(args: []const []const u8) !struct { options: MvOptions, files: []const []const u8 } {
    var options = MvOptions{};
    var i: usize = 0;

    // Parse flags
    while (i < args.len and args[i][0] == '-') {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-f") or std.mem.eql(u8, arg, "--force")) {
            options.force = true;
        } else if (std.mem.eql(u8, arg, "-i") or std.mem.eql(u8, arg, "--interactive")) {
            options.interactive = true;
        } else if (std.mem.eql(u8, arg, "-n") or std.mem.eql(u8, arg, "--no-clobber")) {
            options.no_clobber = true;
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose")) {
            options.verbose = true;
        } else if (std.mem.eql(u8, arg, "--")) {
            i += 1;
            break;
        } else {
            // Handle combined flags like -fv, -iv, etc.
            if (arg.len > 1 and arg[1] != '-') {
                for (arg[1..]) |flag| {
                    switch (flag) {
                        'f' => options.force = true,
                        'i' => options.interactive = true,
                        'n' => options.no_clobber = true,
                        'v' => options.verbose = true,
                        else => {
                            const stderr = std.io.getStdErr().writer();
                            try stderr.print("mv: unknown option: -{c}\n", .{flag});
                            std.process.exit(1);
                        },
                    }
                }
            } else {
                const stderr = std.io.getStdErr().writer();
                try stderr.print("mv: unknown option: {s}\n", .{arg});
                std.process.exit(1);
            }
        }
        i += 1;
    }

    return .{ .options = options, .files = args[i..] };
}

fn isDirectory(path: []const u8) bool {
    const cwd = std.fs.cwd();
    const stat = cwd.statFile(path) catch return false;
    return stat.kind == .directory;
}

fn promptOverwrite(dest_path: []const u8) !bool {
    const stderr = std.io.getStdErr().writer();
    const stdin = std.io.getStdIn().reader();

    try stderr.print("mv: overwrite '{s}'? ", .{dest_path});

    var buffer: [256]u8 = undefined;
    if (try stdin.readUntilDelimiterOrEof(buffer[0..], '\n')) |input| {
        const trimmed = std.mem.trim(u8, input, " \t\r\n");
        return std.mem.eql(u8, trimmed, "y") or std.mem.eql(u8, trimmed, "Y") or
            std.mem.eql(u8, trimmed, "yes") or std.mem.eql(u8, trimmed, "YES");
    }
    return false;
}

fn copyFile(src_path: []const u8, dest_path: []const u8) !void {
    const cwd = std.fs.cwd();

    // Open source file
    const src_file = try cwd.openFile(src_path, .{});
    defer src_file.close();

    // Create destination file
    const dest_file = try cwd.createFile(dest_path, .{});
    defer dest_file.close();

    // Copy file contents
    var buffer: [8192]u8 = undefined;
    while (true) {
        const bytes_read = try src_file.read(&buffer);
        if (bytes_read == 0) break;
        try dest_file.writeAll(buffer[0..bytes_read]);
    }

    // Copy file permissions
    const src_stat = try src_file.stat();
    try dest_file.chmod(src_stat.mode);
}

fn copyDirectory(allocator: std.mem.Allocator, src_path: []const u8, dest_path: []const u8) !void {
    const cwd = std.fs.cwd();

    // Create destination directory
    try cwd.makeDir(dest_path);

    // Open source directory
    var src_dir = try cwd.openDir(src_path, .{ .iterate = true });
    defer src_dir.close();

    // Copy all contents recursively
    var iter = src_dir.iterate();
    while (try iter.next()) |entry| {
        const src_entry_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ src_path, entry.name });
        defer allocator.free(src_entry_path);

        const dest_entry_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dest_path, entry.name });
        defer allocator.free(dest_entry_path);

        switch (entry.kind) {
            .file, .sym_link => {
                try copyFile(src_entry_path, dest_entry_path);
            },
            .directory => {
                try copyDirectory(allocator, src_entry_path, dest_entry_path);
            },
            else => {
                // Skip other file types
            },
        }
    }
}

fn removeFile(path: []const u8) !void {
    const cwd = std.fs.cwd();
    try cwd.deleteFile(path);
}

fn removeDirectory(path: []const u8) !void {
    const cwd = std.fs.cwd();
    try cwd.deleteTree(path);
}

fn moveFile(allocator: std.mem.Allocator, src_path: []const u8, dest_path: []const u8, options: MvOptions) !void {
    const cwd = std.fs.cwd();
    const stderr = std.io.getStdErr().writer();
    const stdout = std.io.getStdOut().writer();

    // Check if source exists
    const src_stat = cwd.statFile(src_path) catch |err| {
        try stderr.print("mv: cannot stat '{s}': {s}\n", .{ src_path, @errorName(err) });
        return;
    };

    // Check if destination exists
    const dest_exists = blk: {
        cwd.access(dest_path, .{}) catch |err| switch (err) {
            error.FileNotFound => break :blk false,
            else => {
                try stderr.print("mv: cannot access '{s}': {s}\n", .{ dest_path, @errorName(err) });
                return;
            },
        };
        break :blk true;
    };

    // Handle existing destination
    if (dest_exists) {
        if (options.no_clobber) {
            // Don't overwrite if -n is specified
            return;
        }

        if (options.interactive and !options.force) {
            if (!(try promptOverwrite(dest_path))) {
                return;
            }
        }
    }

    // Try atomic rename first (works if source and dest are on same filesystem)
    cwd.rename(src_path, dest_path) catch |err| switch (err) {
        error.RenameAcrossMountPoints => {
            // Cross-filesystem move: copy then delete
            switch (src_stat.kind) {
                .file, .sym_link => {
                    copyFile(src_path, dest_path) catch |copy_err| {
                        try stderr.print("mv: cannot copy '{s}' to '{s}': {s}\n", .{ src_path, dest_path, @errorName(copy_err) });
                        return;
                    };
                    removeFile(src_path) catch |rm_err| {
                        try stderr.print("mv: cannot remove '{s}': {s}\n", .{ src_path, @errorName(rm_err) });
                        return;
                    };
                },
                .directory => {
                    copyDirectory(allocator, src_path, dest_path) catch |copy_err| {
                        try stderr.print("mv: cannot copy directory '{s}' to '{s}': {s}\n", .{ src_path, dest_path, @errorName(copy_err) });
                        return;
                    };
                    removeDirectory(src_path) catch |rm_err| {
                        try stderr.print("mv: cannot remove directory '{s}': {s}\n", .{ src_path, @errorName(rm_err) });
                        return;
                    };
                },
                else => {
                    try stderr.print("mv: cannot move '{s}': unsupported file type\n", .{src_path});
                    return;
                },
            }
        },
        else => {
            try stderr.print("mv: cannot move '{s}' to '{s}': {s}\n", .{ src_path, dest_path, @errorName(err) });
            return;
        },
    };

    if (options.verbose) {
        try stdout.print("'{s}' -> '{s}'\n", .{ src_path, dest_path });
    }
}

pub fn mv_main(args: []const []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const parsed = try parseOptions(args);
    const options = parsed.options;
    const files = parsed.files;

    if (files.len < 2) {
        const stderr = std.io.getStdErr().writer();
        try stderr.writeAll("mv: missing file operand\n");
        std.process.exit(1);
    }

    // Validate conflicting options
    if (options.force and options.interactive) {
        // In real mv, -f overrides -i, but we'll allow both for compatibility
    }
    if (options.no_clobber and (options.force or options.interactive)) {
        // -n overrides both -f and -i
    }

    const dest = files[files.len - 1];
    const sources = files[0 .. files.len - 1];

    // Check if destination is a directory
    const dest_is_dir = isDirectory(dest);

    if (sources.len > 1 and !dest_is_dir) {
        const stderr = std.io.getStdErr().writer();
        try stderr.print("mv: target '{s}' is not a directory\n", .{dest});
        std.process.exit(1);
    }

    for (sources) |src| {
        const final_dest = if (dest_is_dir) blk: {
            const basename = std.fs.path.basename(src);
            break :blk try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dest, basename });
        } else dest;

        try moveFile(allocator, src, final_dest, options);
    }
}
