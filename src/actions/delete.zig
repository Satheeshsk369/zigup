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

test "delete action directory check" {
    var env_map = std.process.Environ.Map.init(std.testing.allocator);
    defer env_map.deinit();
    try env_map.put("HOME", "/tmp/zigup-delete-home");

    const config_zon =
        \\.{
        \\    .mirrors = .{},
        \\    .defaultMirror = "ziglang",
        \\}
    ;
    var parsed = try std.zon.parse.fromSliceAlloc(@import("../config.zig").Config, std.testing.allocator, config_zon, null, .{});
    defer parsed.deinit(std.testing.allocator);

    const ctx = action.Context{
        .gpa = std.testing.allocator,
        .arena = std.testing.allocator,
        .io = undefined,
        .environMap = &env_map,
        .pathEnv = "/usr/bin:/bin",
        .userConfig = parsed.value,
        .args = &.{},
        .sync = false,
    };

    // Assert that attempting to delete a non-installed version handles it cleanly
    // (it should warn and return, not crash or assert fail)
    try run(ctx, "0.0.0-nonexistent");
}
