const std = @import("std");
const action = @import("root.zig");

pub fn run(ctx: action.Context, ver: []const u8) !void {
    const installDir = try ctx.versionDir(ver);
    if (!action.dirExists(ctx, installDir)) return error.FileNotFound;

    const binDir = try ctx.binDir();
    try action.ensureDir(ctx.io, binDir);

    const builtin = @import("builtin");
    if (comptime builtin.os.tag == .windows) {
        const src_exe = try std.fs.path.join(ctx.arena, &.{ installDir, "zig.exe" });
        const dst_exe = try std.fs.path.join(ctx.arena, &.{ binDir, "zig.exe" });

        var src_file = try std.Io.Dir.openFileAbsolute(ctx.io, src_exe, .{});
        defer src_file.close(ctx.io);

        var dst_file = try std.Io.Dir.createFileAbsolute(ctx.io, dst_exe, .{});
        defer dst_file.close(ctx.io);

        var f_buf: [65536]u8 = undefined;
        var r = src_file.reader(ctx.io, &f_buf);
        var w = dst_file.writer(ctx.io, &f_buf);

        var chunk: [65536]u8 = undefined;
        while (true) {
            const n = try r.interface.readSliceShort(&chunk);
            if (n == 0) break;
            try w.interface.writeAll(chunk[0..n]);
        }
        try w.flush();
    } else {
        const symlinkPath = try std.fs.path.join(ctx.arena, &.{ binDir, "zig" });
        const targetRel = try std.fmt.allocPrint(ctx.arena, "../share/zig/{s}/zig", .{ver});

        var bd = try std.Io.Dir.openDirAbsolute(ctx.io, binDir, .{});
        defer bd.close(ctx.io);

        bd.deleteFile(ctx.io, symlinkPath) catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };
        try bd.symLink(ctx.io, targetRel, "zig", .{});
    }

    std.log.info("Set {s} as default.", .{ver});
}
test "default action fails on nonexistent version" {
    var env_map = std.process.Environ.Map.init(std.testing.allocator);
    defer env_map.deinit();
    try env_map.put("HOME", "/tmp/zigup-default-home");

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

    // Version not installed — expect FileNotFound, no panic
    try std.testing.expectError(error.FileNotFound, run(ctx, "0.0.0-nonexistent"));
}
