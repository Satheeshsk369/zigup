const std = @import("std");
const Schema = @import("schema.zig");
const dl = @import("download.zig");
const command = @import("command.zig");
const config = @import("config.zig");

pub const Command = command.Command;
pub const Mirror = Schema.Index.Mirror;

pub const Context = struct {
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    io: std.Io,
    home: []const u8,
    pathEnv: []const u8,
    userConfig: config.Config,
    args: []const []const u8,
    sync: bool,

    pub fn zigupDir(self: Context) ![]const u8 {
        return std.fs.path.join(self.arena, &.{ self.home, ".zigup" });
    }

    pub fn versionDir(self: Context, ver: []const u8) ![]const u8 {
        return std.fs.path.join(self.arena, &.{ self.home, ".zigup", ver });
    }

    pub fn binDir(self: Context) ![]const u8 {
        return std.fs.path.join(self.arena, &.{ self.home, ".zigup", "bin" });
    }

    pub fn cacheFile(self: Context, mirror: []const u8) ![]const u8 {
        return std.fs.path.join(self.arena, &.{ self.home, ".zigup", "cache", try std.fmt.allocPrint(self.arena, "{s}.json", .{mirror}) });
    }
};

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
        .version => std.debug.print("zigup version 0.1.0\n", .{}),
        .env => try runEnv(ctx),
        .list => |mirror| try runList(ctx, mirror),
        .install => |ver| try runInstall(ctx, ver),
        .delete => |ver| try runDelete(ctx, ver),
        .default => |ver| try runDefault(ctx, ver),
    }
}

pub fn parseCommand(args: []const []const u8) ?Command {
    if (args.len < 2) return .help;
    const cmd = args[1];

    if (std.mem.eql(u8, cmd, "help")) return .help;
    if (std.mem.eql(u8, cmd, "version")) return .version;
    if (std.mem.eql(u8, cmd, "env")) return .env;

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
    const needle = try ctx.binDir();
    if (std.mem.indexOf(u8, ctx.pathEnv, needle) != null) {
        std.log.info("~/.zigup/bin is in your PATH", .{});
    } else {
        std.log.warn("~/.zigup/bin is NOT in your PATH. Please add it.", .{});
    }
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

    std.log.info("Syncing index from {s} ({s})...", .{ mirror, url });
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
        const zigup_dir_path = try ctx.zigupDir();
        var dir = std.Io.Dir.openDirAbsolute(ctx.io, zigup_dir_path, .{ .iterate = true }) catch |err| {
            std.log.warn("No installed versions found (~/.zigup does not exist): {s}", .{@errorName(err)});
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

    const zigupDir = try ctx.zigupDir();
    const binDir = try ctx.binDir();
    const installDir = try ctx.versionDir(ver);

    try ensureDir(ctx, zigupDir);
    try ensureDir(ctx, binDir);

    if (dirExists(ctx, installDir)) {
        std.log.info("Version {s} is already installed.", .{ver});
        return;
    }

    var split = std.mem.splitBackwardsAny(u8, src.tarball, "/");
    const filename = split.first();

    std.log.info("Downloading {s}...", .{ver});

    var downloader = dl.Downloader.init(&index.client);
    var file = try std.Io.Dir.createFileAbsolute(ctx.io, filename, .{});
    defer file.close(ctx.io);

    const dlResult = try dl.Downloader.downloadToFile(&downloader, src.tarball, file, ctx.io);
    if (dlResult.status != .ok) {
        std.log.err("failed to download tarball. HTTP {s}", .{@tagName(dlResult.status)});
        return;
    }

    std.log.info("Extracting to ~/.zigup/{s}...", .{ver});
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
    std.log.info("Successfully installed {s}.", .{ver});
}

fn runDefault(ctx: Context, ver: []const u8) !void {
    const installDir = try ctx.versionDir(ver);
    if (!dirExists(ctx, installDir)) {
        std.log.err("{s} is not installed. Use 'zigup install {s}' first.", .{ ver, ver });
        return;
    }

    const zigupDir = try ctx.zigupDir();
    const binDir = try ctx.binDir();
    try ensureDir(ctx, binDir);

    const symlinkPath = try std.fs.path.join(ctx.arena, &.{ binDir, "zig" });
    const targetRel = try std.fs.path.join(ctx.arena, &.{ "..", ver, "zig" });

    var zd = std.Io.Dir.openDirAbsolute(ctx.io, zigupDir, .{}) catch return;
    defer zd.close(ctx.io);
    zd.deleteFile(ctx.io, symlinkPath) catch {};
    zd.symLink(ctx.io, targetRel, symlinkPath, .{}) catch |err| {
        std.log.err("failed to create symlink: {s}", .{@errorName(err)});
        return;
    };

    std.log.info("Set {s} as default.", .{ver});
}

fn runDelete(ctx: Context, ver: []const u8) !void {
    const installDir = try ctx.versionDir(ver);
    if (!dirExists(ctx, installDir)) {
        std.log.warn("version {s} is not installed in ~/.zigup/", .{ver});
        return;
    }

    const zigupDir = try ctx.zigupDir();
    var zd = std.Io.Dir.openDirAbsolute(ctx.io, zigupDir, .{}) catch |err| {
        std.log.err("~/.zigup not found: {s}", .{@errorName(err)});
        return;
    };
    defer zd.close(ctx.io);

    zd.deleteTree(ctx.io, ver) catch |err| {
        std.log.err("failed to delete ~/.zigup/{s}: {s}", .{ ver, @errorName(err) });
        return;
    };

    std.log.info("Successfully deleted {s}.", .{ver});
}
