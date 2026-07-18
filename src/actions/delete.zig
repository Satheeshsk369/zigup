const std = @import("std");
const action = @import("root.zig");

pub fn run(ctx: action.Context, ver: []const u8) !void {
    const installDir = try ctx.versionDir(ver);
    if (!action.dirExists(ctx, installDir)) return error.FileNotFound;

    const data_dir = try ctx.dataDir();
    var zd = try std.Io.Dir.openDirAbsolute(ctx.io, data_dir, .{});
    defer zd.close(ctx.io);

    try zd.deleteTree(ctx.io, ver);

    std.log.info("Successfully deleted {s}.", .{ver});
}
