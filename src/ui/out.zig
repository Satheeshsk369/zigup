const std = @import("std");

var global_io: ?std.Io = null;

pub fn init(io: std.Io) void {
    global_io = io;
}

pub fn print(comptime fmt: []const u8, args: anytype) void {
    const io = global_io orelse return;
    const file = std.Io.File.stdout();
    var stream_buf: [1024]u8 = undefined;
    var writer = file.writer(io, &stream_buf);
    writer.interface.print(fmt, args) catch {};
    _ = writer.interface.flush() catch {};
}

pub fn flush() void {}
