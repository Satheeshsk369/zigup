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

test "env action directories resolve" {
    var env_map = std.process.Environ.Map.init(std.testing.allocator);
    defer env_map.deinit();

    // Set temporary home environment for directory resolution test
    try env_map.put("HOME", "/tmp/zigup-test-home");
    try env_map.put("PATH", "/usr/bin:/bin");

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

    const bin_dir = try ctx.binDir();
    const data_dir = try ctx.dataDir();

    const builtin = @import("builtin");
    if (builtin.os.tag != .windows) {
        try std.testing.expectEqualStrings("/tmp/zigup-test-home/.local/bin", bin_dir);
        try std.testing.expectEqualStrings("/tmp/zigup-test-home/.local/share/zig", data_dir);
    }
}
