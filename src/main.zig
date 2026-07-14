const std = @import("std");
const action = @import("actions/root.zig");
const config = @import("config.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const arena = init.arena.allocator();
    var args = init.minimal.args.iterate();

    var sync = false;
    var list = std.ArrayList([:0]const u8).empty;

    if (args.next()) |first| try list.append(arena, first);
    if (args.next()) |second| {
        if (std.mem.eql(u8, second, "-S")) {
            sync = true;
        } else {
            try list.append(arena, second);
        }
    }

    while (args.next()) |rest| try list.append(arena, rest);
    const argslist = list.items;

    const config_zon_path = try action.configPath(arena, init.environ_map);
    const config_val = try config.Config.loadOrInit(arena, init.io, config_zon_path);

    const ctx = action.Context{
        .gpa = gpa,
        .arena = arena,
        .io = init.io,
        .environMap = init.environ_map,
        .pathEnv = init.environ_map.get("PATH") orelse "",
        .userConfig = config_val,
        .args = argslist,
        .sync = sync,
    };

    const cmd = action.parseCommand(argslist) orelse {
        std.log.err("Unknown command: {s}.\nUse 'zigup help' for usage details.", .{argslist[1]});
        return;
    };

    try action.run(cmd, ctx);
}
