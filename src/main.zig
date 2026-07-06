const std = @import("std");
const action = @import("action.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    const home = if (init.environ_map.get("HOME")) |h|
        h
    else if (init.environ_map.get("USERPROFILE")) |h|
        h
    else {
        std.debug.print("error: HOME environment variable not set\n", .{});
        return;
    };

    const ctx = action.Context{
        .gpa = gpa,
        .arena = arena,
        .io = init.io,
        .home = home,
        .path_env = init.environ_map.get("PATH") orelse "",
    };

    const cmd = action.parseCommand(args) orelse {
        if (args.len < 2) {
            std.debug.print("Usage: zigup <command> [options]\nUse 'zigup help' for details.\n", .{});
        } else {
            std.debug.print("Unknown command: {s}\nUse 'zigup help' for usage details.\n", .{args[1]});
        }
        return;
    };

    try action.run(cmd, ctx);
}
