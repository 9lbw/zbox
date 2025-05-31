const std = @import("std");

// Shared stream copier
fn cat_stream(reader: anytype, writer: anytype) !void {
    var buffer: [4096]u8 = undefined;
    while (true) {
        const bytes_read = try reader.read(&buffer);
        if (bytes_read == 0) break;
        try writer.writeAll(buffer[0..bytes_read]);
    }
}

pub fn cat_main(args: []const []const u8) !void {
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
