const std = @import("std");
const action = @import("root.zig");

pub fn run(ctx: action.Context, ver: []const u8) !void {
    const installDir = try ctx.versionDir(ver);
    if (!action.dirExists(ctx, installDir)) {
        std.log.warn("version {s} is not installed", .{ver});
        return;
    }

    const data_dir = try ctx.dataDir();
    var zd = std.Io.Dir.openDirAbsolute(ctx.io, data_dir, .{}) catch |err| {
        std.log.err("data directory not found: {s}", .{@errorName(err)});
        return;
    };
    defer zd.close(ctx.io);

    zd.deleteTree(ctx.io, ver) catch |err| {
        std.log.err("failed to delete version '{s}': {s}", .{ ver, @errorName(err) });
        return;
    };

    std.log.info("Successfully deleted {s}.", .{ver});
}
