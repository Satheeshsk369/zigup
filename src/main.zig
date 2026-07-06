const std = @import("std");
const action = @import("action.zig");
const config = @import("config.zig");

var global_io: std.Io = undefined;

pub const std_options: std.Options = .{
    .logFn = logFn,
};

pub fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.default),
    comptime format: []const u8,
    args: anytype,
) void {
    const stderr = std.Io.File.stderr();

    // If format starts with \r (progress carriage return), print directly and don't append a newline or prefixes
    if (format.len > 0 and format[0] == '\r') {
        var buf: [1024]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, format, args) catch return;
        stderr.writeStreamingAll(global_io, msg) catch {};
        return;
    }

    const prefix = if (scope == .default) "" else "(" ++ @tagName(scope) ++ "): ";
    const level_txt = switch (message_level) {
        .err => "error: ",
        .warn => "warning: ",
        .info => "info: ",
        .debug => "debug: ",
    };

    var buf: [2048]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, level_txt ++ prefix ++ format, args) catch return;
    stderr.writeStreamingAll(global_io, msg) catch {};

    if (format.len == 0 or format[format.len - 1] != '\n') {
        stderr.writeStreamingAll(global_io, "\n") catch {};
    }
}

pub fn main(init: std.process.Init) !void {
    global_io = init.io;
    const gpa = init.gpa;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var sync = false;
    var final_args = args;
    if (args.len >= 2 and std.mem.eql(u8, args[1], "-S")) {
        sync = true;
        var list = std.ArrayList([:0]const u8).empty;
        try list.append(arena, args[0]);
        try list.appendSlice(arena, args[2..]);
        final_args = list.items;
    }

    const config_zon_path = try action.configPath(arena, init.environ_map);
    const config_val = try config.Config.loadOrInit(arena, init.io, config_zon_path);

    const ctx = action.Context{
        .gpa = gpa,
        .arena = arena,
        .io = init.io,
        .environMap = init.environ_map,
        .pathEnv = init.environ_map.get("PATH") orelse "",
        .userConfig = config_val,
        .args = final_args,
        .sync = sync,
    };

    const cmd = action.parseCommand(final_args) orelse {
        std.log.err("Unknown command: {s}.\nUse 'zigup help' for usage details.", .{final_args[1]});
        return;
    };

    try action.run(cmd, ctx);
}
