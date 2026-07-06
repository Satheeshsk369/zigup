const std = @import("std");
const action = @import("action.zig");
const config = @import("config.zig");

pub fn main(init: std.process.Init) !void {
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
