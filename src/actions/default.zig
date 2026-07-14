const std = @import("std");
const action = @import("root.zig");

pub fn run(ctx: action.Context, ver: []const u8) !void {
    const installDir = try ctx.versionDir(ver);
    if (!action.dirExists(ctx, installDir)) {
        std.log.err("{s} is not installed. Use 'zigup install {s}' first.", .{ ver, ver });
        return;
    }

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

    // Assert that attempting to set a non-installed version as default returns cleanly with error message instead of panicking
    try run(ctx, "0.0.0-nonexistent");
}
