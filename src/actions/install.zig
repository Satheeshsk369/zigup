const std = @import("std");
const Schema = @import("../schema.zig");
const dl = @import("../download.zig");
const action = @import("root.zig");

fn syncMirror(ctx: action.Context, mirror: []const u8) !void {
    const url = ctx.userConfig.getMirrorUrl(mirror) orelse {
        std.log.err("mirror '{s}' not defined in config.zon", .{mirror});
        return;
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

pub fn run(ctx: action.Context, ver: []const u8) !void {
    var mirror_opt: ?[]const u8 = null;
    var url_opt: ?[]const u8 = null;

    for (ctx.args) |arg| {
        if (std.mem.startsWith(u8, arg, "--mirror=")) {
            mirror_opt = arg["--mirror=".len..];
        } else if (std.mem.startsWith(u8, arg, "--url=")) {
            url_opt = arg["--url=".len..];
        }
    }

    if (mirror_opt != null and url_opt != null) {
        std.log.err("cannot specify both --mirror and --url", .{});
        return;
    }

    const mirror_name = mirror_opt orelse ctx.userConfig.defaultMirror;

    if (ctx.sync and url_opt == null) {
        try syncMirror(ctx, mirror_name);
    }

    var index = Schema.Index.init(ctx.gpa, ctx.io);
    defer index.deinit();

    const schema = blk: {
        if (url_opt) |u| {
            var httpBuf = std.Io.Writer.Allocating.init(ctx.gpa);
            defer httpBuf.deinit();
            std.log.info("Fetching index from {s}...", .{u});
            if ((try index.fetchUrl(u, &httpBuf)) != .ok) {
                std.log.err("failed to fetch index", .{});
                return;
            }
            break :blk try Schema.Type.parse(ctx.gpa, httpBuf.written());
        } else {
            const cache_path = try ctx.cacheFile(mirror_name);
            break :blk Schema.Type.loadCache(ctx.gpa, ctx.io, cache_path) catch |err| {
                if (ctx.userConfig.getMirrorUrl(mirror_name)) |url| {
                    var httpBuf = std.Io.Writer.Allocating.init(ctx.gpa);
                    defer httpBuf.deinit();
                    std.log.warn("Cache not found for '{s}'. Fetching from {s}...", .{ mirror_name, url });
                    if ((try index.fetchUrl(url, &httpBuf)) == .ok) {
                        try Schema.Type.saveCache(ctx.gpa, ctx.io, cache_path, httpBuf.written());
                        break :blk try Schema.Type.parse(ctx.gpa, httpBuf.written());
                    }
                }
                std.log.err("failed to load cached index for mirror '{s}': {s}\nUse -S flag (e.g. 'zigup -S install {s}') to sync the cache.", .{ mirror_name, @errorName(err), ver });
                return;
            };
        }
    };
    defer schema.deinit();

    const platform = Schema.Platform.parse(action.targetKey()) orelse {
        std.log.err("unsupported platform: {s}", .{action.targetKey()});
        return;
    };

    const src = schema.get(ver, platform) orelse {
        std.log.err("no binary found for version {s} on {s}", .{ ver, action.targetKey() });
        return;
    };

    const dataDir = try ctx.dataDir();
    const binDir = try ctx.binDir();
    const installDir = try ctx.versionDir(ver);

    try action.ensureDir(ctx.io, dataDir);
    try action.ensureDir(ctx.io, binDir);

    if (action.dirExists(ctx, installDir)) {
        std.log.info("Version {s} is already installed.", .{ver});
        return;
    }

    var split = std.mem.splitBackwardsAny(u8, src.tarball, "/");
    const filename = split.first();

    std.log.info("Downloading {s}", .{ver});

    var downloader = dl.Downloader.init(&index.client);
    const cwd = try std.process.currentPathAlloc(ctx.io, ctx.arena);
    const download_path = try std.fs.path.join(ctx.arena, &.{ cwd, filename });
    var file = try std.Io.Dir.createFileAbsolute(ctx.io, download_path, .{});
    defer file.close(ctx.io);

    const dlResult = dl.Downloader.downloadToFile(&downloader, src.tarball, src.shasum, src.size, file, ctx.io) catch |err| {
        if (err == error.ShasumMismatch) {
            std.log.err("SHA-256 shasum mismatch! The downloaded file is corrupted or tampered with.", .{});
        } else {
            std.log.err("failed to download tarball: {s}", .{@errorName(err)});
        }
        return;
    };
    if (dlResult.status != .ok) {
        std.log.err("failed to download tarball. HTTP {s}", .{@tagName(dlResult.status)});
        return;
    }
    const dl_secs = @as(f64, @floatFromInt(dlResult.duration)) / 1_000_000_000.0;

    std.log.info("Verified SHA-256 shasum: {s}", .{src.shasum});
    try action.ensureDir(ctx.io, installDir);
    const is_zip = std.mem.endsWith(u8, filename, ".zip");

    var archive_file = try std.Io.Dir.openFileAbsolute(ctx.io, download_path, .{});
    defer archive_file.close(ctx.io);

    var dest_dir = try std.Io.Dir.openDirAbsolute(ctx.io, installDir, .{});
    defer dest_dir.close(ctx.io);

    var f_buf: [65536]u8 = undefined;
    var file_reader = archive_file.reader(ctx.io, &f_buf);
    if (is_zip) {
        action.extractZipStrip(ctx.io, dest_dir, &file_reader) catch |err| {
            std.log.err("failed to extract zip natively: {s}", .{@errorName(err)});
            return;
        };
    } else {
        const decompress_buf = try ctx.gpa.alloc(u8, 65536);
        var xz_stream = try std.compress.xz.Decompress.init(&file_reader.interface, ctx.gpa, decompress_buf);
        defer xz_stream.deinit();

        std.tar.extract(ctx.io, dest_dir, &xz_stream.reader, .{
            .strip_components = 1,
        }) catch |err| {
            std.log.err("failed to extract tarball natively: {s}", .{@errorName(err)});
            return;
        };
    }

    std.Io.Dir.deleteFile(std.Io.Dir.cwd(), ctx.io, download_path) catch {};
    std.log.info("Successfully installed {s} in {d:.2}s.", .{ ver, dl_secs });
}

test "install action structures compilation check" {
    // Assert type structure compiles
    _ = run;
}
