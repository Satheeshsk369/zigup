const std = @import("std");
const action = @import("action.zig");
const config = @import("config.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var sync = false;
    var filtered_args = std.ArrayList([]const u8).empty;
    defer filtered_args.deinit(arena);
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "-S")) {
            sync = true;
        } else {
            try filtered_args.append(arena, arg);
        }
    }
    const final_args = filtered_args.items;

    const home = if (init.environ_map.get("HOME")) |h|
        h
    else if (init.environ_map.get("USERPROFILE")) |h|
        h
    else {
        std.debug.print("error: HOME environment variable not set\n", .{});
        return;
    };

    const config_zon_path = try std.fs.path.join(arena, &.{ home, ".zigup", "config.zon" });
    const config_val = try config.Config.loadOrInit(arena, init.io, config_zon_path);

    const ctx = action.Context{
        .gpa = gpa,
        .arena = arena,
        .io = init.io,
        .home = home,
        .pathEnv = init.environ_map.get("PATH") orelse "",
        .userConfig = config_val,
        .args = final_args,
        .sync = sync,
    };

    const cmd = action.parseCommand(final_args) orelse {
        std.debug.print("Unknown command: {s}\nUse 'zigup help' for usage details.\n", .{final_args[1]});
        return;
    };

    try action.run(cmd, ctx);
}
