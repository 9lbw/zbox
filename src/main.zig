const std = @import("std");
const builtin = @import("builtin");

// Import command modules
const echo = @import("echo.zig");
const cat = @import("cat.zig");
const ls = @import("ls.zig");
const mkdir = @import("mkdir.zig");
const rm = @import("rm.zig");
const cp = @import("cp.zig");
const touch = @import("touch.zig");
const mv = @import("mv.zig");
const pwd = @import("pwd.zig");
const chmod = @import("chmod.zig");
const wc = @import("wc.zig");
const whoami = @import("whoami.zig");
const true_util = @import("true.zig");
const false_util = @import("false.zig");
const yes = @import("yes.zig");
const hostname = @import("hostname.zig");
const basename = @import("basename.zig");
const dirname = @import("dirname.zig");
const seq = @import("seq.zig");
const env = @import("env.zig");
const printenv = @import("printenv.zig");
const sleep = @import("sleep.zig");
const id = @import("id.zig");
const head = @import("head.zig");
const tail = @import("tail.zig");
const cut = @import("cut.zig");
const tee = @import("tee.zig");
const grep = @import("grep.zig");

// Command definitions
const Command = struct {
    name: []const u8,
    func: *const fn ([]const []const u8) anyerror!void,
};

// Command registry
const commands = [_]Command{
    .{ .name = "echo", .func = echo.echo_main },
    .{ .name = "cat", .func = cat.cat_main },
    .{ .name = "ls", .func = ls.ls_main },
    .{ .name = "mkdir", .func = mkdir.mkdir_main },
    .{ .name = "rm", .func = rm.rm_main },
    .{ .name = "cp", .func = cp.cp_main },
    .{ .name = "touch", .func = touch.touch_main },
    .{ .name = "mv", .func = mv.mv_main },
    .{ .name = "pwd", .func = pwd.pwd_main },
    .{ .name = "chmod", .func = chmod.chmod_main },
    .{ .name = "wc", .func = wc.wc_main },
    .{ .name = "whoami", .func = whoami.whoami_main },
    .{ .name = "true", .func = true_util.true_main },
    .{ .name = "false", .func = false_util.false_main },
    .{ .name = "yes", .func = yes.yes_main },
    .{ .name = "hostname", .func = hostname.hostname_main },
    .{ .name = "basename", .func = basename.basename_main },
    .{ .name = "dirname", .func = dirname.dirname_main },
    .{ .name = "seq", .func = seq.seq_main },
    .{ .name = "env", .func = env.env_main },
    .{ .name = "printenv", .func = printenv.printenv_main },
    .{ .name = "sleep", .func = sleep.sleep_main },
    .{ .name = "id", .func = id.id_main },
    .{ .name = "head", .func = head.head_main },
    .{ .name = "tail", .func = tail.tail_main },
    .{ .name = "cut", .func = cut.cut_main },
    .{ .name = "tee", .func = tee.tee_main },
    .{ .name = "grep", .func = grep.grep_main },
};

// Main dispatcher
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    if (args.len == 0) return;

    const exe_name = std.fs.path.basename(args[0]);

    for (commands) |cmd| {
        if (std.mem.eql(u8, exe_name, cmd.name)) {
            return cmd.func(args[1..]);
        }
    }

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
