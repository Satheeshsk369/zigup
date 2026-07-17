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
    const parsed = try std.zon.parse.fromSliceAlloc(@import("../config.zig").Config, std.testing.allocator, config_zon, null, .{});
    defer std.zon.parse.free(std.testing.allocator, parsed);

    var arena_alloc = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_alloc.deinit();

    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();

    const ctx = action.Context{
        .gpa = std.testing.allocator,
        .arena = arena_alloc.allocator(),
        .io = threaded.io(),
        .environMap = &env_map,
        .pathEnv = "/usr/bin:/bin",
        .userConfig = parsed,
        .args = &.{},
        .sync = false,
    };

    try std.testing.expectError(error.FileNotFound, run(ctx, "0.0.0-nonexistent"));
}
