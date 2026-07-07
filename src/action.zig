const std = @import("std");
const Schema = @import("schema.zig");
const dl = @import("download.zig");
const command = @import("command.zig");
const config = @import("config.zig");

pub const Command = command.Command;
pub const Mirror = Schema.Index.Mirror;

pub const Folder = enum { config, cache, data, bin };

pub fn getPlatformPath(comptime folder: Folder) []const []const u8 {
    const builtin = @import("builtin");
    return switch (builtin.os.tag) {
        .windows => switch (folder) {
            .config => &.{ "APPDATA", "zigup", "config.zon" },
            .cache => &.{ "LOCALAPPDATA", "zigup", "cache" },
            .data => &.{ "LOCALAPPDATA", "zigup" },
            .bin => &.{ "LOCALAPPDATA", "zigup", "bin" },
        },
        else => switch (folder) {
            .config => &.{ "XDG_CONFIG_HOME", ".config", "zigup", "config.zon" },
            .cache => &.{ "XDG_CACHE_HOME", ".cache", "zigup" },
            .data => &.{ "XDG_DATA_HOME", ".local", "share", "zig" },
            .bin => &.{ "HOME", ".local", "bin" },
        },
    };
}

pub const Context = struct {
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    io: std.Io,
    environMap: *const std.process.Environ.Map,
    pathEnv: []const u8,
    userConfig: config.Config,
    args: []const []const u8,
    sync: bool,

    fn resolvePath(self: Context, comptime folder: Folder) ![]const u8 {
        const parts = getPlatformPath(folder);
        const env_name = parts[0];

        var base_dir: []const u8 = undefined;
        var static_parts: []const []const u8 = undefined;

        if (self.environMap.get(env_name)) |val| {
            base_dir = val;
            static_parts = if (std.mem.startsWith(u8, env_name, "XDG_")) parts[2..] else parts[1..];
        } else {
            if (std.mem.startsWith(u8, env_name, "XDG_")) {
                const home = self.environMap.get("HOME") orelse return error.HomeNotFound;
                base_dir = try std.fs.path.join(self.arena, &.{ home, parts[1] });
                static_parts = parts[2..];
            } else {
                const builtin = @import("builtin");
                if (builtin.os.tag == .windows) {
                    const userprofile = self.environMap.get("USERPROFILE") orelse self.environMap.get("HOME") orelse return error.HomeNotFound;
                    if (std.mem.eql(u8, env_name, "LOCALAPPDATA")) {
                        base_dir = try std.fs.path.join(self.arena, &.{ userprofile, "AppData", "Local" });
                        static_parts = parts[1..];
                    } else if (std.mem.eql(u8, env_name, "APPDATA")) {
                        base_dir = try std.fs.path.join(self.arena, &.{ userprofile, "AppData", "Roaming" });
                        static_parts = parts[1..];
                    } else {
                        return error.EnvironmentVariableNotFound;
                    }
                } else {
                    return error.EnvironmentVariableNotFound;
                }
            }
        }

        if (static_parts.len == 0) return base_dir;

        var list = std.ArrayList([]const u8).empty;
        try list.append(self.arena, base_dir);
        try list.appendSlice(self.arena, static_parts);
        return std.fs.path.join(self.arena, list.items);
    }

    pub fn cacheFile(self: Context, mirror: []const u8) ![]const u8 {
        const base = try self.resolvePath(.cache);
        const filename = try std.fmt.allocPrint(self.arena, "{s}.json", .{mirror});
        return std.fs.path.join(self.arena, &.{ base, filename });
    }

    pub fn dataDir(self: Context) ![]const u8 {
        return self.resolvePath(.data);
    }

    pub fn versionDir(self: Context, ver: []const u8) ![]const u8 {
        return std.fs.path.join(self.arena, &.{ try self.dataDir(), ver });
    }

    pub fn binDir(self: Context) ![]const u8 {
        return self.resolvePath(.bin);
    }

    pub fn configDir(self: Context) ![]const u8 {
        const path = try configPath(self.arena, self.environMap);
        return std.fs.path.dirname(path) orelse path;
    }

    pub fn cacheDir(self: Context) ![]const u8 {
        return self.resolvePath(.cache);
    }
};

pub fn configPath(arena: std.mem.Allocator, environMap: *const std.process.Environ.Map) ![]const u8 {
    const parts = getPlatformPath(.config);
    const env_name = parts[0];
    const env_val = environMap.get(env_name) orelse {
        if (std.mem.startsWith(u8, env_name, "XDG_")) {
            const home = environMap.get("HOME") orelse return error.HomeNotFound;
            const fallback_base = try std.fs.path.join(arena, &.{ home, parts[1] });
            return try std.fs.path.join(arena, &.{ fallback_base, parts[2], parts[3] });
        }
        const builtin = @import("builtin");
        if (builtin.os.tag == .windows) {
            const userprofile = environMap.get("USERPROFILE") orelse environMap.get("HOME") orelse return error.HomeNotFound;
            if (std.mem.eql(u8, env_name, "APPDATA")) {
                const fallback_base = try std.fs.path.join(arena, &.{ userprofile, "AppData", "Roaming" });
                return try std.fs.path.join(arena, &.{ fallback_base, parts[1], parts[2] });
            }
        }
        return error.EnvironmentVariableNotFound;
    };

    const static_parts = if (std.mem.startsWith(u8, env_name, "XDG_")) parts[2..] else parts[1..];
    if (static_parts.len == 0) return env_val;

    var list = std.ArrayList([]const u8).empty;
    try list.append(arena, env_val);
    try list.appendSlice(arena, static_parts);
    return std.fs.path.join(arena, list.items);
}

fn targetKey() []const u8 {
    const builtin = @import("builtin");
    return @tagName(builtin.target.cpu.arch) ++ "-" ++ @tagName(builtin.target.os.tag);
}

fn dirExists(ctx: Context, path: []const u8) bool {
    if (std.Io.Dir.openDirAbsolute(ctx.io, path, .{})) |*d| {
        d.close(ctx.io);
        return true;
    } else |_| return false;
}

fn ensureDir(ctx: Context, path: []const u8) !void {
    std.Io.Dir.createDirAbsolute(ctx.io, path, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

pub fn run(cmd: Command, ctx: Context) !void {
    switch (cmd) {
        .help => runHelp(),
        .version => std.debug.print("zigup version 0.2.0\n", .{}),
        .env => try runEnv(ctx),
        .list => |mirror| try runList(ctx, mirror),
        .install => |ver| try runInstall(ctx, ver),
        .delete => |ver| try runDelete(ctx, ver),
        .default => |ver| try runDefault(ctx, ver),
        .update => try runUpdate(ctx),
    }
}

pub fn parseCommand(args: []const []const u8) ?Command {
    if (args.len < 2) return .help;
    const cmd = args[1];

    if (std.mem.eql(u8, cmd, "help")) return .help;
    if (std.mem.eql(u8, cmd, "version")) return .version;
    if (std.mem.eql(u8, cmd, "env")) return .env;
    if (std.mem.eql(u8, cmd, "update")) return .update;
    if (std.mem.eql(u8, cmd, "list")) {
        if (args.len >= 3) {
            return Command{ .list = args[2] };
        }
        return Command{ .list = "" };
    }

    if (std.mem.eql(u8, cmd, "install")) {
        if (args.len < 3) {
            std.log.err("command 'install' requires a version tag", .{});
            return .help;
        }
        return Command{ .install = args[2] };
    }

    if (std.mem.eql(u8, cmd, "default")) {
        if (args.len < 3) {
            std.log.err("command 'default' requires a version tag", .{});
            return .help;
        }
        return Command{ .default = args[2] };
    }

    if (std.mem.eql(u8, cmd, "delete")) {
        if (args.len < 3) {
            std.log.err("command 'delete' requires a version tag", .{});
            return .help;
        }
        return Command{ .delete = args[2] };
    }

    return null;
}

fn runHelp() void {
    std.debug.print(
        \\Usage:
        \\  zigup <command> [arguments]
        \\
        \\Commands:
        \\
    , .{});

    inline for (command.commands) |entry| {
        const usage = if (entry.argLabel) |lbl| entry.verb ++ " " ++ lbl else entry.verb;
        std.debug.print("  {s:<20} {s}\n", .{ usage, entry.description });
        if (std.mem.eql(u8, entry.verb, "install")) {
            std.debug.print("    --mirror=<name>    Select index mirror configured in config.zon\n", .{});
            std.debug.print("    --url=<url>        Specify custom JSON index URL directly\n", .{});
        }
    }
    std.debug.print("\n", .{});
}

fn runEnv(ctx: Context) !void {
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
        try configPath(ctx.arena, ctx.environMap),
        try ctx.dataDir(),
        try ctx.cacheDir(),
    });
}

fn syncMirror(ctx: Context, mirror: []const u8) !void {
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
    try Schema.Type.saveCache(ctx.io, cache_path, httpBuf.written());
}

fn runList(ctx: Context, mirror_arg: []const u8) !void {
    const mirror = if (mirror_arg.len > 0) mirror_arg else null;
    if (mirror) |m| {
        if (ctx.sync) {
            try syncMirror(ctx, m);
        }

        const cache_path = try ctx.cacheFile(m);
        const schema = Schema.Type.loadCache(ctx.gpa, ctx.io, cache_path) catch |err| {
            std.log.err("failed to load cached index for mirror '{s}': {s}\nUse -S flag (e.g. 'zigup list {s} -S') to sync the cache.", .{ m, @errorName(err), m });
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
            std.debug.print(" - {s} ({s})\n", .{ item.key, item.date });
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
                std.debug.print(" - {s}\n", .{entry.name});
                count += 1;
            }
        }

        if (count == 0) std.log.info("No installed versions found in ~/.zigup/", .{});
    }
}

fn runInstall(ctx: Context, ver: []const u8) !void {
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
                        try Schema.Type.saveCache(ctx.io, cache_path, httpBuf.written());
                        break :blk try Schema.Type.parse(ctx.gpa, httpBuf.written());
                    }
                }
                std.log.err("failed to load cached index for mirror '{s}': {s}\nUse -S flag (e.g. 'zigup install {s} -S') to sync the cache.", .{ mirror_name, @errorName(err), ver });
                return;
            };
        }
    };
    defer schema.deinit();

    const platform = Schema.Platform.parse(targetKey()) orelse {
        std.log.err("unsupported platform: {s}", .{targetKey()});
        return;
    };

    const src = schema.get(ver, platform) orelse {
        std.log.err("no binary found for version {s} on {s}", .{ ver, targetKey() });
        return;
    };

    const dataDir = try ctx.dataDir();
    const binDir = try ctx.binDir();
    const installDir = try ctx.versionDir(ver);

    try ensureDir(ctx, dataDir);
    try ensureDir(ctx, binDir);

    if (dirExists(ctx, installDir)) {
        std.log.info("Version {s} is already installed.", .{ver});
        return;
    }

    var split = std.mem.splitBackwardsAny(u8, src.tarball, "/");
    const filename = split.first();

    std.log.info("Downloading {s}", .{ver});

    var downloader = dl.Downloader.init(&index.client);
    var file = try std.Io.Dir.createFileAbsolute(ctx.io, filename, .{});
    defer file.close(ctx.io);

    const dlResult = dl.Downloader.downloadToFile(&downloader, src.tarball, src.shasum, file, ctx.io) catch |err| {
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
    std.log.info("Extracting to {s}", .{installDir});
    try std.Io.Dir.createDirAbsolute(ctx.io, installDir, .default_dir);

    var child = std.process.spawn(ctx.io, .{
        .argv = &.{ "tar", "-xf", filename, "-C", installDir, "--strip-components=1" },
    }) catch |err| {
        std.log.err("failed to spawn tar: {s}", .{@errorName(err)});
        return;
    };
    const term = child.wait(ctx.io) catch |err| {
        std.log.err("failed to wait for tar: {s}", .{@errorName(err)});
        return;
    };
    switch (term) {
        .exited => |code| if (code != 0) {
            std.log.err("tar failed with exit code {d}", .{code});
            return;
        },
        else => {
            std.log.err("tar terminated abnormally", .{});
            return;
        },
    }

    std.Io.Dir.deleteFile(std.Io.Dir.cwd(), ctx.io, filename) catch {};
    std.log.info("Successfully installed {s} in {d:.2}s.", .{ ver, dl_secs });
}

fn runDefault(ctx: Context, ver: []const u8) !void {
    const installDir = try ctx.versionDir(ver);
    if (!dirExists(ctx, installDir)) {
        std.log.err("{s} is not installed. Use 'zigup install {s}' first.", .{ ver, ver });
        return;
    }

    const binDir = try ctx.binDir();
    try ensureDir(ctx, binDir);

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

        var bd = std.Io.Dir.openDirAbsolute(ctx.io, binDir, .{}) catch return;
        defer bd.close(ctx.io);

        bd.deleteFile(ctx.io, symlinkPath) catch {};
        bd.symLink(ctx.io, targetRel, "zig", .{}) catch |err| {
            std.log.err("failed to create symlink: {s}", .{@errorName(err)});
            return;
        };
    }

    std.log.info("Set {s} as default.", .{ver});
}

fn runDelete(ctx: Context, ver: []const u8) !void {
    const installDir = try ctx.versionDir(ver);
    if (!dirExists(ctx, installDir)) {
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

fn runUpdate(ctx: Context) !void {
    const builtin = @import("builtin");
    const suffix = if (builtin.os.tag == .windows) ".exe" else "";
    const expected_asset_name = try std.fmt.allocPrint(ctx.arena, "zigup-{s}{s}", .{ targetKey(), suffix });

    var client = std.http.Client{ .allocator = ctx.gpa, .io = ctx.io };
    defer client.deinit();

    const extra_headers = &[_]std.http.Header{
        .{ .name = "User-Agent", .value = "zigup-client" },
    };

    var httpBuf = std.Io.Writer.Allocating.init(ctx.gpa);
    defer httpBuf.deinit();

    const uri = try std.Uri.parse("https://api.github.com/repos/Satheeshsk369/zigup/releases/latest");
    std.log.info("Checking for updates from GitHub", .{});
    const resp = try client.fetch(.{
        .location = .{ .uri = uri },
        .method = .GET,
        .extra_headers = extra_headers,
        .response_writer = &httpBuf.writer,
    });

    if (resp.status != .ok) {
        std.log.err("failed to check for updates: HTTP {s}", .{@tagName(resp.status)});
        return;
    }

    const GitHubRelease = struct {
        tag_name: []const u8,
        assets: []const struct {
            name: []const u8,
            browser_download_url: []const u8,
        },
    };

    const release_parsed = std.json.parseFromSlice(
        GitHubRelease,
        ctx.arena,
        httpBuf.written(),
        .{ .ignore_unknown_fields = true },
    ) catch |err| {
        std.log.err("failed to parse release metadata: {s}", .{@errorName(err)});
        return;
    };
    defer release_parsed.deinit();

    const release = release_parsed.value;

    const current_ver = "v0.1.0";
    if (std.mem.eql(u8, release.tag_name, current_ver)) {
        std.log.info("zigup is already up to date ({s}).", .{current_ver});
        return;
    }

    var download_url: ?[]const u8 = null;
    for (release.assets) |asset| {
        if (std.mem.eql(u8, asset.name, expected_asset_name)) {
            download_url = asset.browser_download_url;
            break;
        }
    }

    const url = download_url orelse {
        std.log.err("no compatible binary asset found for {s} in release {s}", .{ expected_asset_name, release.tag_name });
        return;
    };

    const bin_dir = try ctx.binDir();
    const temp_exe_path = try std.fs.path.join(ctx.arena, &.{ bin_dir, "zigup.tmp" });

    std.log.info("Downloading new binary from {s}...", .{url});

    var dl_client = std.http.Client{ .allocator = ctx.gpa, .io = ctx.io };
    defer dl_client.deinit();
    var downloader = dl.Downloader.init(&dl_client);

    var file = try std.Io.Dir.createFileAbsolute(ctx.io, temp_exe_path, .{});
    defer file.close(ctx.io);

    const dlResult = try dl.Downloader.downloadToFile(&downloader, url, null, file, ctx.io);
    if (dlResult.status != .ok) {
        std.log.err("failed to download update: HTTP {s}", .{@tagName(dlResult.status)});
        return;
    }
    const dl_secs = @as(f64, @floatFromInt(dlResult.duration)) / 1_000_000_000.0;

    if (comptime builtin.os.tag != .windows) {
        const fd = file.handle;
        const rc = std.posix.system.fchmod(fd, 0o755);
        if (rc != 0) {
            std.log.err("failed to set executable permission: rc {d}", .{rc});
            return;
        }
    }

    var bd = std.Io.Dir.openDirAbsolute(ctx.io, bin_dir, .{}) catch return;
    defer bd.close(ctx.io);

    bd.deleteFile(ctx.io, "zigup") catch {};
    bd.rename("zigup.tmp", bd, "zigup", ctx.io) catch |err| {
        std.log.err("failed to replace zigup binary: {s}", .{@errorName(err)});
        return;
    };

    std.log.info("Successfully updated zigup to {s} in {d:.2}s.", .{ release.tag_name, dl_secs });
}
