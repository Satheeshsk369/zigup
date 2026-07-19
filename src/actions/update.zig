const std = @import("std");
const dl = @import("../download.zig");
const action = @import("root.zig");

pub fn run(ctx: action.Context) !void {
    const builtin = @import("builtin");
    const suffix = if (builtin.os.tag == .windows) ".exe" else "";
    const expected_asset_name = try std.fmt.allocPrint(ctx.arena, "zigup-{s}{s}", .{ action.targetKey(), suffix });

    var client = std.http.Client{ .allocator = ctx.gpa, .io = ctx.io };
    client.initDefaultProxies(ctx.gpa, ctx.environMap) catch {};
    defer client.deinit();
    const extra_headers = &[_]std.http.Header{
        .{ .name = "User-Agent", .value = "zigup-client" },
    };

    var httpBuf = std.Io.Writer.Allocating.init(ctx.gpa);
    defer httpBuf.deinit();

    const uri = try std.Uri.parse("https://api.github.com/repos/Satheeshsk369/zigup/releases");
    std.log.info("Checking for updates from GitHub", .{});
    const resp = try client.fetch(.{
        .location = .{ .uri = uri },
        .method = .GET,
        .extra_headers = extra_headers,
        .response_writer = &httpBuf.writer,
    });

    if (resp.status != .ok) {
        std.log.err("failed to check for updates: HTTP {s}", .{@tagName(resp.status)});
        return error.HttpError;
    }

    const GitHubRelease = struct {
        tag_name: []const u8,
        assets: []const struct {
            name: []const u8,
            browser_download_url: []const u8,
        },
    };

    const releases_parsed = std.json.parseFromSlice(
        []GitHubRelease,
        ctx.arena,
        httpBuf.written(),
        .{ .ignore_unknown_fields = true },
    ) catch |err| {
        std.log.err("failed to parse release metadata: {s}", .{@errorName(err)});
        return;
    };
    defer releases_parsed.deinit();

    const releases = releases_parsed.value;
    if (releases.len == 0) {
        std.log.info("No releases found.", .{});
        return;
    }

    const current_ver = @import("options").version;
    var target_release: ?GitHubRelease = null;
    var download_url: ?[]const u8 = null;

    // Find the latest release that actually has the asset matching expected_asset_name
    for (releases) |rel| {
        for (rel.assets) |asset| {
            if (std.mem.eql(u8, asset.name, expected_asset_name)) {
                target_release = rel;
                download_url = asset.browser_download_url;
                break;
            }
        }
        if (target_release != null) break;
    }

    const release = target_release orelse {
        std.log.err("no compatible binary asset found for {s} in any release", .{expected_asset_name});
        return error.HttpError;
    };
    var release_tag = release.tag_name;
    if (std.mem.startsWith(u8, release_tag, "v")) {
        release_tag = release_tag[1..];
    }

    const parsed_current = std.SemanticVersion.parse(current_ver) catch std.SemanticVersion{ .major = 0, .minor = 0, .patch = 0 };
    const parsed_release = std.SemanticVersion.parse(release_tag) catch std.SemanticVersion{ .major = 0, .minor = 0, .patch = 0 };

    if (parsed_release.order(parsed_current) == .eq) {
        std.log.info("zigup is already up to date ({s}).", .{current_ver});
        return;
    }
    const url = download_url.?;

    const bin_dir = try ctx.binDir();
    const temp_exe_path = try std.fs.path.join(ctx.arena, &.{ bin_dir, "zigup.tmp" });

    std.log.info("Downloading new binary from {s}", .{url});

    var dl_client = std.http.Client{ .allocator = ctx.gpa, .io = ctx.io };
    dl_client.initDefaultProxies(ctx.gpa, ctx.environMap) catch {};
    defer dl_client.deinit();
    var downloader = dl.Downloader.init(&dl_client);

    var file = try std.Io.Dir.createFileAbsolute(ctx.io, temp_exe_path, .{});
    var success = false;
    defer {
        file.close(ctx.io);
        if (!success) {
            std.Io.Dir.deleteFile(std.Io.Dir.cwd(), ctx.io, temp_exe_path) catch {};
        }
    }

    const dlResult = try dl.Downloader.downloadToFile(&downloader, url, null, file, ctx.io);
    if (dlResult.status != .ok) {
        std.log.err("failed to download update: HTTP {s}", .{@tagName(dlResult.status)});
        return error.HttpError;
    }
    const dl_secs = @as(f64, @floatFromInt(dlResult.duration)) / 1_000_000_000.0;

    if (comptime builtin.os.tag != .windows) {
        const fd = file.handle;
        const rc = std.posix.system.fchmod(fd, 0o755);
        if (rc != 0) {
            std.log.err("failed to set executable permission: rc {d}", .{rc});
            return error.AccessDenied;
        }
    }

    var bd = try std.Io.Dir.openDirAbsolute(ctx.io, bin_dir, .{});
    defer bd.close(ctx.io);

    bd.deleteFile(ctx.io, "zigup") catch {};
    success = true;
    bd.rename("zigup.tmp", bd, "zigup", ctx.io) catch |err| {
        std.log.err("failed to replace zigup binary: {s}", .{@errorName(err)});
        return err;
    };

    std.log.info("Successfully updated zigup in {d:.2}s.", .{dl_secs});
}
