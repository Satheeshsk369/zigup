const std = @import("std");
const Schema = @import("../schema.zig");
const action = @import("root.zig");

fn syncMirror(ctx: action.Context, mirror: []const u8) !void {
    const url = ctx.userConfig.getMirrorUrl(mirror) orelse {
        return error.MirrorNotFound;
    };

    var index = Schema.Index.init(ctx.gpa, ctx.io);
    defer index.deinit();

    var httpBuf = std.Io.Writer.Allocating.init(ctx.gpa);
    defer httpBuf.deinit();

    std.log.info("Syncing index from {s} ({s})", .{ mirror, url });
    if ((try index.fetchUrl(url, &httpBuf)) != .ok) {
        std.log.err("failed to fetch index", .{});
        return;
    }

    const cache_path = try ctx.cacheFile(mirror);
    try Schema.Type.saveCache(ctx.gpa, ctx.io, cache_path, httpBuf.written());
}

pub fn run(ctx: action.Context, mirror_arg: []const u8) !void {
    const mirror = if (mirror_arg.len > 0) mirror_arg else null;
    if (mirror) |m| {
        if (ctx.sync) {
            try syncMirror(ctx, m);
        }

        const cache_path = try ctx.cacheFile(m);
        const schema = Schema.Type.loadCache(ctx.gpa, ctx.io, cache_path) catch |err| {
            std.log.err("failed to load cached index for mirror '{s}': {s}\nUse -S flag (e.g. 'zigup -S list {s}') to sync the cache.", .{ m, @errorName(err), m });
            return;
        };
        defer schema.deinit();

        const VersionItem = struct { key: []const u8, date: []const u8 };
        var versions = std.ArrayList(VersionItem).empty;
        defer versions.deinit(ctx.gpa);

        var it = schema.parsed.value.map.iterator();
        while (it.next()) |entry| {
            try versions.append(ctx.gpa, .{ .key = entry.key_ptr.*, .date = &entry.value_ptr.date });
        }

        std.mem.sort(VersionItem, versions.items, {}, struct {
            fn lt(_: void, a: VersionItem, b: VersionItem) bool {
                const ord = std.mem.order(u8, a.date, b.date);
                if (ord != .eq) return ord == .gt;
                return std.mem.order(u8, a.key, b.key) == .gt;
            }
        }.lt);

        for (versions.items) |item| {
            std.debug.print("{s} ({s})\n", .{ item.key, item.date });
        }
    } else {
        const data_dir = try ctx.dataDir();
        var dir = std.Io.Dir.openDirAbsolute(ctx.io, data_dir, .{ .iterate = true }) catch |err| {
            std.log.warn("No installed versions found: {s}", .{@errorName(err)});
            return;
        };
        defer dir.close(ctx.io);

        var count: usize = 0;
        var it = dir.iterate();
        while (try it.next(ctx.io)) |entry| {
            if (entry.kind == .directory and
                !std.mem.eql(u8, entry.name, "bin") and
                !std.mem.eql(u8, entry.name, "cache") and
                !std.mem.eql(u8, entry.name, "tmp"))
            {
                std.debug.print("{s}\n", .{entry.name});
                count += 1;
            }
        }

        if (count == 0) std.log.info("No installed versions found in {s}", .{data_dir});
    }
}

test "list action mock execution" {
    var env_map = std.process.Environ.Map.init(std.testing.allocator);
    defer env_map.deinit();
    try env_map.put("HOME", "/tmp/zigup-list-home");

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

    // Assert that listing local installations handles a nonexistent data folder cleanly
    try run(ctx, "");
}
