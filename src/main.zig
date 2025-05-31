const std = @import("std");
const builtin = @import("builtin");

// Command definitions
const Command = struct {
    name: []const u8,
    func: *const fn ([]const []const u8) anyerror!void,
};

// Echo implementation
fn echo_main(args: []const []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    for (args, 0..) |arg, i| {
        if (i > 0) try stdout.writeAll(" ");
        try stdout.writeAll(arg);
    }
    try stdout.writeAll("\n");
}

// Shared stream copier
fn cat_stream(reader: anytype, writer: anytype) !void {
    var buffer: [4096]u8 = undefined;
    while (true) {
        const bytes_read = try reader.read(&buffer);
        if (bytes_read == 0) break;
        try writer.writeAll(buffer[0..bytes_read]);
    }
}

// Cat implementation
fn cat_main(args: []const []const u8) !void {
    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();
    const stderr = std.io.getStdErr().writer();

    if (args.len == 0) {
        try cat_stream(stdin.reader(), stdout.writer());
        return;
    }

    for (args) |file| {
        if (std.mem.eql(u8, file, "-")) {
            cat_stream(stdin.reader(), stdout.writer()) catch |err| {
                if (err == error.BrokenPipe) return;
                try stderr.print("cat: stdin: {s}\n", .{@errorName(err)});
            };
        } else {
            const f = std.fs.cwd().openFile(file, .{}) catch |err| {
                try stderr.print("cat: {s}: {s}\n", .{ file, @errorName(err) });
                continue;
            };
            defer f.close();

            cat_stream(f.reader(), stdout.writer()) catch |err| {
                if (err == error.BrokenPipe) return;
                try stderr.print("cat: {s}: {s}\n", .{ file, @errorName(err) });
            };
        }
    }
}

// ls implementation
fn ls_main(args: []const []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();
    const cwd = std.fs.cwd();

    // Handle no arguments (current directory)
    if (args.len == 0) {
        try listDirectory(cwd, ".", stdout, stderr);
        return;
    }

    // Handle each argument
    for (args) |path| {
        try listDirectory(cwd, path, stdout, stderr);
    }
}

fn listDirectory(cwd: std.fs.Dir, path: []const u8, writer: anytype, stderr_writer: anytype) !void {
    var dir = cwd.openDir(path, .{ .iterate = true }) catch |err| {
        // Handle file instead of directory
        if (err == error.NotDir) {
            try writer.print("{s}\n", .{path});
            return;
        }
        try stderr_writer.print("ls: {s}: {s}\n", .{ path, @errorName(err) });
        return;
    };
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        try writer.print("{s}\n", .{entry.name});
    }
}

fn mkdir_main(args: []const []const u8) !void {
    const stderr = std.io.getStdErr().writer();
    var parents = false;
    var i: usize = 0;

    // Parse options (-p/--parents)
    while (i < args.len and args[i][0] == '-') {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-p") or std.mem.eql(u8, arg, "--parents")) {
            parents = true;
        } else {
            try stderr.print("mkdir: unknown option: {s}\n", .{arg});
            std.process.exit(1);
        }
        i += 1;
    }

    // Validate directory arguments
    const dirs = args[i..];
    if (dirs.len == 0) {
        try stderr.writeAll("mkdir: missing operand\n");
        std.process.exit(1);
    }

    const cwd = std.fs.cwd();
    for (dirs) |dir| {
        if (parents) {
            // Create parent directories if needed
            cwd.makePath(dir) catch |err| {
                try stderr.print("mkdir: cannot create directory '{s}': {s}\n", .{ dir, @errorName(err) });
            };
        } else {
            // Create single directory (fails if parents don't exist)
            cwd.makeDir(dir) catch |err| {
                try stderr.print("mkdir: cannot create directory '{s}': {s}\n", .{ dir, @errorName(err) });
            };
        }
    }
}

// Command registry
const commands = [_]Command{
    .{ .name = "echo", .func = echo_main },
    .{ .name = "cat", .func = cat_main },
    .{ .name = "ls", .func = ls_main },
    .{ .name = "mkdir", .func = mkdir_main },
};

// Main dispatcher
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    if (args.len == 0) return;

    const exe_name = std.fs.path.basename(args[0]);

    // Case 1: Called directly as a utility (e.g., via symlink)
    for (commands) |cmd| {
        if (std.mem.eql(u8, exe_name, cmd.name)) {
            return cmd.func(args[1..]);
        }
    }

    // Case 2: Called with command argument (e.g., ./coreutils echo)
    if (args.len < 2) {
        try print_usage(exe_name);
        std.process.exit(1);
    }

    const command_name = args[1];
    for (commands) |cmd| {
        if (std.mem.eql(u8, command_name, cmd.name)) {
            return cmd.func(args[2..]);
        }
    }

    try print_usage(exe_name);
    std.process.exit(1);
}

// Usage printer
fn print_usage(exe_name: []const u8) !void {
    const stderr = std.io.getStdErr().writer();
    try stderr.print("Usage: {s} <command> [args]\n\nAvailable commands:\n", .{exe_name});
    for (commands) |cmd| {
        try stderr.print("  {s}\n", .{cmd.name});
    }
}

// Basic test
test "multi-call binary" {
    try std.testing.expect(true);
}
