const std = @import("std");

const RmOptions = struct {
    recursive: bool = false,
    force: bool = false,
};

fn parseOptions(args: []const []const u8) !struct { options: RmOptions, files: []const []const u8 } {
    var options = RmOptions{};
    var i: usize = 0;

    // Parse flags
    while (i < args.len and args[i][0] == '-') {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-r") or std.mem.eql(u8, arg, "--recursive")) {
            options.recursive = true;
        } else if (std.mem.eql(u8, arg, "-f") or std.mem.eql(u8, arg, "--force")) {
            options.force = true;
        } else if (std.mem.eql(u8, arg, "-rf") or std.mem.eql(u8, arg, "-fr")) {
            options.recursive = true;
            options.force = true;
        } else if (std.mem.eql(u8, arg, "--")) {
            i += 1;
            break;
        } else {
            const stderr = std.io.getStdErr().writer();
            try stderr.print("rm: unknown option: {s}\n", .{arg});
            std.process.exit(1);
        }
        i += 1;
    }

    return .{ .options = options, .files = args[i..] };
}

fn removeFileOrDir(path: []const u8, options: RmOptions) !void {
    const cwd = std.fs.cwd();
    const stderr = std.io.getStdErr().writer();

    // Check if path exists
    const stat = cwd.statFile(path) catch |err| switch (err) {
        error.FileNotFound => {
            if (!options.force) {
                try stderr.print("rm: cannot remove '{s}': No such file or directory\n", .{path});
            }
            return;
        },
        else => {
            if (!options.force) {
                try stderr.print("rm: cannot remove '{s}': {s}\n", .{ path, @errorName(err) });
            }
            return;
        },
    };

    switch (stat.kind) {
        .file, .sym_link => {
            cwd.deleteFile(path) catch |err| {
                if (!options.force) {
                    try stderr.print("rm: cannot remove '{s}': {s}\n", .{ path, @errorName(err) });
                }
            };
        },
        .directory => {
            if (!options.recursive) {
                try stderr.print("rm: cannot remove '{s}': Is a directory\n", .{path});
                return;
            }

            removeDirectoryRecursive(cwd, path, options) catch |err| {
                if (!options.force) {
                    try stderr.print("rm: cannot remove '{s}': {s}\n", .{ path, @errorName(err) });
                }
            };
        },
        else => {
            if (!options.force) {
                try stderr.print("rm: cannot remove '{s}': unsupported file type\n", .{path});
            }
        },
    }
}

fn removeDirectoryRecursive(cwd: std.fs.Dir, path: []const u8, options: RmOptions) !void {
    var dir = cwd.openDir(path, .{ .iterate = true }) catch |err| {
        if (options.force and err == error.FileNotFound) return;
        return err;
    };
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        switch (entry.kind) {
            .file, .sym_link => {
                dir.deleteFile(entry.name) catch |err| {
                    if (!options.force) {
                        const stderr = std.io.getStdErr().writer();
                        try stderr.print("rm: cannot remove '{s}/{s}': {s}\n", .{ path, entry.name, @errorName(err) });
                    }
                };
            },
            .directory => {
                // Remove subdirectory recursively
                dir.deleteTree(entry.name) catch |err| {
                    if (!options.force) {
                        const stderr = std.io.getStdErr().writer();
                        try stderr.print("rm: cannot remove directory '{s}/{s}': {s}\n", .{ path, entry.name, @errorName(err) });
                    }
                };
            },
            else => {
                // Skip other file types
                if (!options.force) {
                    const stderr = std.io.getStdErr().writer();
                    try stderr.print("rm: skipping '{s}/{s}': unsupported file type\n", .{ path, entry.name });
                }
            },
        }
    }

    // Remove the directory itself
    cwd.deleteDir(path) catch |err| {
        if (!options.force) {
            const stderr = std.io.getStdErr().writer();
            try stderr.print("rm: cannot remove directory '{s}': {s}\n", .{ path, @errorName(err) });
        }
    };
}

pub fn rm_main(args: []const []const u8) !void {
    const parsed = try parseOptions(args);
    const options = parsed.options;
    const files = parsed.files;

    if (files.len == 0) {
        const stderr = std.io.getStdErr().writer();
        try stderr.writeAll("rm: missing operand\n");
        std.process.exit(1);
    }

    for (files) |file| {
        try removeFileOrDir(file, options);
    }
}
