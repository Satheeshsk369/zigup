const std = @import("std");
const action = @import("root.zig");

pub fn run(ctx: action.Context) !void {
    std.debug.print(
        \\.{{
        \\    .ZIGUP = "{s}",
        \\    .BIN = "{s}",
        \\    .CONFIG = "{s}",
        \\    .DATA = "{s}",
        \\    .CACHE = "{s}",
        \\}}
        \\
    , .{
        std.process.executablePathAlloc(ctx.io, ctx.arena) catch "zigup",
        try ctx.binDir(),
        try action.configPath(ctx.arena, ctx.environMap),
        try ctx.dataDir(),
        try ctx.cacheDir(),
    });
}
