const std = @import("std");

const ChmodOptions = struct {
    recursive: bool = false, // -R: change files and directories recursively
    verbose: bool = false, // -v: output a diagnostic for every file processed
    changes: bool = false, // -c: like verbose but report only when a change is made
    quiet: bool = false, // -f, --silent, --quiet: suppress most error messages
    reference: ?[]const u8 = null, // --reference=RFILE: use RFILE's mode instead of MODE
};

const FileMode = struct {
    user: struct {
        read: bool = false,
        write: bool = false,
        execute: bool = false,
    } = .{},
    group: struct {
        read: bool = false,
        write: bool = false,
        execute: bool = false,
    } = .{},
    other: struct {
        read: bool = false,
        write: bool = false,
        execute: bool = false,
    } = .{},

    fn toMode(self: FileMode) u32 {
        var mode: u32 = 0;

        // User permissions
        if (self.user.read) mode |= 0o400;
        if (self.user.write) mode |= 0o200;
        if (self.user.execute) mode |= 0o100;

        // Group permissions
        if (self.group.read) mode |= 0o040;
        if (self.group.write) mode |= 0o020;
        if (self.group.execute) mode |= 0o010;

        // Other permissions
        if (self.other.read) mode |= 0o004;
        if (self.other.write) mode |= 0o002;
        if (self.other.execute) mode |= 0o001;

        return mode;
    }

    fn fromMode(mode: u32) FileMode {
        return FileMode{
            .user = .{
                .read = (mode & 0o400) != 0,
                .write = (mode & 0o200) != 0,
                .execute = (mode & 0o100) != 0,
            },
            .group = .{
                .read = (mode & 0o040) != 0,
                .write = (mode & 0o020) != 0,
                .execute = (mode & 0o010) != 0,
            },
            .other = .{
                .read = (mode & 0o004) != 0,
                .write = (mode & 0o002) != 0,
                .execute = (mode & 0o001) != 0,
            },
        };
    }
};

const ModeChange = union(enum) {
    absolute: u32,
    symbolic: struct {
        who: struct {
            user: bool = false,
            group: bool = false,
            other: bool = false,
            all: bool = false,
        },
        op: enum { set, add, remove },
        perms: struct {
            read: bool = false,
            write: bool = false,
            execute: bool = false,
        },
    },
};

fn parseOptions(args: []const []const u8) !struct { options: ChmodOptions, mode_str: ?[]const u8, files: []const []const u8 } {
    var options = ChmodOptions{};
    var i: usize = 0;
    var mode_str: ?[]const u8 = null;

    // Parse flags
    while (i < args.len and args[i][0] == '-' and args[i].len > 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-R") or std.mem.eql(u8, arg, "--recursive")) {
            options.recursive = true;
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose")) {
            options.verbose = true;
        } else if (std.mem.eql(u8, arg, "-c") or std.mem.eql(u8, arg, "--changes")) {
            options.changes = true;
        } else if (std.mem.eql(u8, arg, "-f") or std.mem.eql(u8, arg, "--silent") or std.mem.eql(u8, arg, "--quiet")) {
            options.quiet = true;
        } else if (std.mem.startsWith(u8, arg, "--reference=")) {
            options.reference = arg[12..];
        } else if (std.mem.eql(u8, arg, "--")) {
            i += 1;
            break;
        } else {
            // Handle combined flags
            if (arg.len > 1 and arg[1] != '-') {
                for (arg[1..]) |flag| {
                    switch (flag) {
                        'R' => options.recursive = true,
                        'v' => options.verbose = true,
                        'c' => options.changes = true,
                        'f' => options.quiet = true,
                        else => {
                            const stderr = std.io.getStdErr().writer();
                            try stderr.print("chmod: unknown option: -{c}\n", .{flag});
                            std.process.exit(1);
                        },
                    }
                }
            } else {
                const stderr = std.io.getStdErr().writer();
                try stderr.print("chmod: unknown option: {s}\n", .{arg});
                std.process.exit(1);
            }
        }
        i += 1;
    }

    // Get mode string (unless using --reference)
    if (options.reference == null) {
        if (i >= args.len) {
            const stderr = std.io.getStdErr().writer();
            try stderr.writeAll("chmod: missing operand\n");
            std.process.exit(1);
        }
        mode_str = args[i];
        i += 1;
    }

    // Get file arguments
    if (i >= args.len) {
        const stderr = std.io.getStdErr().writer();
        if (options.reference != null) {
            try stderr.writeAll("chmod: missing operand after reference file\n");
        } else {
            try stderr.writeAll("chmod: missing operand after mode\n");
        }
        std.process.exit(1);
    }

    return .{ .options = options, .mode_str = mode_str, .files = args[i..] };
}

fn parseOctalMode(mode_str: []const u8) !u32 {
    if (mode_str.len == 0 or mode_str.len > 4) {
        return error.InvalidMode;
    }

    var mode: u32 = 0;
    for (mode_str) |c| {
        if (c < '0' or c > '7') {
            return error.InvalidMode;
        }
        mode = mode * 8 + (c - '0');
    }

    return mode;
}

fn parseSymbolicMode(mode_str: []const u8, current_mode: u32) !u32 {
    var result_mode = current_mode;
    var i: usize = 0;

    while (i < mode_str.len) {
        // Parse who (u, g, o, a)
        var who = struct {
            user: bool = false,
            group: bool = false,
            other: bool = false,
            all: bool = false,
        }{};

        var found_who = false;
        while (i < mode_str.len) {
            switch (mode_str[i]) {
                'u' => {
                    who.user = true;
                    found_who = true;
                },
                'g' => {
                    who.group = true;
                    found_who = true;
                },
                'o' => {
                    who.other = true;
                    found_who = true;
                },
                'a' => {
                    who.all = true;
                    found_who = true;
                },
                else => break,
            }
            i += 1;
        }

        // If no who specified, default to all
        if (!found_who) {
            who.all = true;
        }

        // Parse operator (+, -, =)
        if (i >= mode_str.len) return error.InvalidMode;
        const op = mode_str[i];
        if (op != '+' and op != '-' and op != '=') {
            return error.InvalidMode;
        }
        i += 1;

        // Parse permissions (r, w, x)
        var perms = struct {
            read: bool = false,
            write: bool = false,
            execute: bool = false,
        }{};

        while (i < mode_str.len and mode_str[i] != ',' and mode_str[i] != '+' and mode_str[i] != '-' and mode_str[i] != '=') {
            switch (mode_str[i]) {
                'r' => perms.read = true,
                'w' => perms.write = true,
                'x' => perms.execute = true,
                else => return error.InvalidMode,
            }
            i += 1;
        }

        // Apply changes
        var mask: u32 = 0;
        if (who.user or who.all) {
            if (perms.read) mask |= 0o400;
            if (perms.write) mask |= 0o200;
            if (perms.execute) mask |= 0o100;
        }
        if (who.group or who.all) {
            if (perms.read) mask |= 0o040;
            if (perms.write) mask |= 0o020;
            if (perms.execute) mask |= 0o010;
        }
        if (who.other or who.all) {
            if (perms.read) mask |= 0o004;
            if (perms.write) mask |= 0o002;
            if (perms.execute) mask |= 0o001;
        }

        switch (op) {
            '=' => {
                // Clear and set
                var clear_mask: u32 = 0;
                if (who.user or who.all) clear_mask |= 0o700;
                if (who.group or who.all) clear_mask |= 0o070;
                if (who.other or who.all) clear_mask |= 0o007;
                result_mode = (result_mode & ~clear_mask) | mask;
            },
            '+' => result_mode |= mask,
            '-' => result_mode &= ~mask,
            else => unreachable,
        }

        // Skip comma if present
        if (i < mode_str.len and mode_str[i] == ',') {
            i += 1;
        }
    }

    return result_mode;
}

fn parseMode(mode_str: []const u8, current_mode: u32) !u32 {
    // Try octal first
    if (parseOctalMode(mode_str)) |mode| {
        return mode;
    } else |_| {
        // Try symbolic
        return parseSymbolicMode(mode_str, current_mode);
    }
}

fn getReferenceMode(ref_file: []const u8) !u32 {
    const file = std.fs.cwd().openFile(ref_file, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            const stderr = std.io.getStdErr().writer();
            try stderr.print("chmod: cannot access '{s}': No such file or directory\n", .{ref_file});
            std.process.exit(1);
        },
        else => return err,
    };
    defer file.close();

    const stat = try file.stat();
    return @intCast(stat.mode & 0o777);
}

fn chmodFile(path: []const u8, new_mode: u32, options: ChmodOptions) !void {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            if (!options.quiet) {
                const stderr = std.io.getStdErr().writer();
                try stderr.print("chmod: cannot access '{s}': No such file or directory\n", .{path});
            }
            return;
        },
        error.AccessDenied => {
            if (!options.quiet) {
                const stderr = std.io.getStdErr().writer();
                try stderr.print("chmod: changing permissions of '{s}': Operation not permitted\n", .{path});
            }
            return;
        },
        else => return err,
    };
    defer file.close();

    // Get current mode
    const stat = try file.stat();
    const old_mode = @as(u32, @intCast(stat.mode & 0o777));

    // Set new mode
    try file.chmod(new_mode);

    // Output if requested
    if (options.verbose or (options.changes and old_mode != new_mode)) {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("mode of '{s}' changed from {o:0>3} to {o:0>3}\n", .{ path, old_mode, new_mode });
    }
}

fn chmodRecursive(allocator: std.mem.Allocator, dir_path: []const u8, new_mode: u32, options: ChmodOptions) !void {
    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => {
            if (!options.quiet) {
                const stderr = std.io.getStdErr().writer();
                try stderr.print("chmod: cannot access '{s}': No such file or directory\n", .{dir_path});
            }
            return;
        },
        error.AccessDenied => {
            if (!options.quiet) {
                const stderr = std.io.getStdErr().writer();
                try stderr.print("chmod: cannot access '{s}': Permission denied\n", .{dir_path});
            }
            return;
        },
        error.NotDir => {
            // It's a file, not a directory
            return chmodFile(dir_path, new_mode, options);
        },
        else => return err,
    };
    defer dir.close();

    // Change permissions of the directory itself
    try chmodFile(dir_path, new_mode, options);

    // Iterate through directory contents
    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ dir_path, entry.name });
        defer allocator.free(full_path);

        if (entry.kind == .directory) {
            try chmodRecursive(allocator, full_path, new_mode, options);
        } else {
            try chmodFile(full_path, new_mode, options);
        }
    }
}

pub fn chmod_main(args: []const []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const parsed = try parseOptions(args);
    const options = parsed.options;
    const mode_str = parsed.mode_str;
    const files = parsed.files;

    // Determine the mode to set
    var target_mode: u32 = undefined;

    if (options.reference) |ref_file| {
        target_mode = try getReferenceMode(ref_file);
    } else if (mode_str) |mode| {
        // For now, use a default mode for symbolic parsing
        target_mode = parseMode(mode, 0o644) catch |err| switch (err) {
            error.InvalidMode => {
                const stderr = std.io.getStdErr().writer();
                try stderr.print("chmod: invalid mode: '{s}'\n", .{mode});
                std.process.exit(1);
            },
            else => return err,
        };
    } else {
        const stderr = std.io.getStdErr().writer();
        try stderr.writeAll("chmod: missing mode specification\n");
        std.process.exit(1);
    }

    // Process each file
    for (files) |file_path| {
        if (options.recursive) {
            try chmodRecursive(allocator, file_path, target_mode, options);
        } else {
            try chmodFile(file_path, target_mode, options);
        }
    }
}
