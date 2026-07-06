const std = @import("std");
const Schema = @import("schema.zig");
const download_mod = @import("download.zig");
const config = @import("config.zig");

pub const Command = config.Command;
pub const Mirror = Schema.Index.Mirror;

pub const Context = struct {
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    io: std.Io,
    home: []const u8,
    path_env: []const u8,

    pub fn zigupDir(self: Context) ![]const u8 {
        return std.fs.path.join(self.arena, &.{ self.home, ".zigup" });
    }

    pub fn versionDir(self: Context, ver: []const u8) ![]const u8 {
        return std.fs.path.join(self.arena, &.{ self.home, ".zigup", ver });
    }

    pub fn binDir(self: Context) ![]const u8 {
        return std.fs.path.join(self.arena, &.{ self.home, ".zigup", "bin" });
    }
};

pub fn parseCommand(args: []const []const u8) ?Command {
    if (args.len < 2) return null;

    var mirror: ?Mirror = null;
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--ziglang")) mirror = .ziglang;
        if (std.mem.eql(u8, arg, "--mach")) mirror = .mach;
    }

    const cmd = args[1];

    if (std.mem.eql(u8, cmd, "help")) return .help;
    if (std.mem.eql(u8, cmd, "version")) return .version;
    if (std.mem.eql(u8, cmd, "env")) return .env;

    if (std.mem.eql(u8, cmd, "list")) {
        return switch (mirror orelse return .list) {
            .ziglang => .show_ziglang,
            .mach => .show_mach,
        };
    }

    if (std.mem.eql(u8, cmd, "install")) {
        if (args.len < 3) return null;
        const tag = args[2];
        return switch (mirror orelse return Command{ .default_ziglang = tag }) {
            .ziglang => Command{ .install_ziglang = tag },
            .mach => Command{ .install_mach = tag },
        };
    }

    if (std.mem.eql(u8, cmd, "delete")) {
        if (args.len < 3) return null;
        const tag = args[2];
        return switch (mirror orelse .ziglang) {
            .ziglang => Command{ .delete_ziglang = tag },
            .mach => Command{ .delete_mach = tag },
        };
    }

    return null;
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

fn fetchIndex(ctx: Context, mirror: Mirror) !struct { index: Schema.Index, schema: Schema.Type } {
    var index = Schema.Index.init(ctx.gpa, ctx.io);
    var http_buf = std.Io.Writer.Allocating.init(ctx.gpa);
    defer http_buf.deinit();

    std.debug.print("Fetching index...\n", .{});
    const status = try index.fetch(mirror, &http_buf);
    if (status != .ok) {
        std.debug.print("Failed to fetch index: {s}\n", .{@tagName(status)});
        index.deinit();
        return error.FetchFailed;
    }

    const schema = try Schema.Type.parse(ctx.gpa, http_buf.written());
    return .{ .index = index, .schema = schema };
}

pub fn run(cmd: Command, ctx: Context) !void {
    switch (cmd) {
        .help => runHelp(),
        .version => std.debug.print("zigup version 0.1.0\n", .{}),
        .env => try runEnv(ctx),
        .list => try runList(ctx),
        .show_ziglang => try runShow(ctx, .ziglang),
        .show_mach => try runShow(ctx, .mach),
        .install_ziglang => |ver| try runInstall(ctx, ver, .ziglang),
        .install_mach => |ver| try runInstall(ctx, ver, .mach),
        .default_ziglang => |ver| try runDefault(ctx, ver),
        .default_mach => |ver| try runDefault(ctx, ver),
        .delete_ziglang => |ver| try runDelete(ctx, ver),
        .delete_mach => |ver| try runDelete(ctx, ver),
    }
}

fn runHelp() void {
    std.debug.print(
        \\zigup - Zig Version Manager
        \\
        \\Commands:
        \\  help              Print this message
        \\  version           Print zigup tool version
        \\  env               Print status of ~/.zigup/bin in your environment PATH
        \\  list              List local installed versions (use --ziglang/--mach for remote)
        \\  install <TAG>     Install version <TAG> (use --ziglang/--mach for remote)
        \\  delete <TAG>      Delete version <TAG>
        \\
        \\
    , .{});
}

fn runEnv(ctx: Context) !void {
    const needle = try ctx.binDir();
    if (std.mem.indexOf(u8, ctx.path_env, needle) != null) {
        std.debug.print("env status: ~/.zigup/bin is in your PATH\n", .{});
    } else {
        std.debug.print("env status: ~/.zigup/bin is NOT in your PATH. Please add it.\n", .{});
    }
}

fn runList(ctx: Context) !void {
    const zigup_dir_path = try ctx.zigupDir();
    var dir = std.Io.Dir.openDirAbsolute(ctx.io, zigup_dir_path, .{ .iterate = true }) catch |err| {
        std.debug.print("No installed versions found (~/.zigup does not exist): {s}\n", .{@errorName(err)});
        return;
    };
    defer dir.close(ctx.io);

    var count: usize = 0;
    var it = dir.iterate();
    while (try it.next(ctx.io)) |entry| {
        if (entry.kind == .directory and
            !std.mem.eql(u8, entry.name, "bin") and
            !std.mem.eql(u8, entry.name, "tmp"))
        {
            std.debug.print(" - {s}\n", .{entry.name});
            count += 1;
        }
    }

    if (count == 0) std.debug.print("No installed versions found in ~/.zigup/\n", .{});
}

fn runShow(ctx: Context, mirror: Mirror) !void {
    const VersionItem = struct { key: []const u8, date: []const u8 };

    var result = try fetchIndex(ctx, mirror);
    defer result.index.deinit();
    defer result.schema.deinit();

    var versions = std.ArrayList(VersionItem).empty;
    defer versions.deinit(ctx.gpa);

    if (mirror == .mach) {
        var official_buf = std.Io.Writer.Allocating.init(ctx.gpa);
        defer official_buf.deinit();
        var official_index = Schema.Index.init(ctx.gpa, ctx.io);
        defer official_index.deinit();
        if ((try official_index.fetch(.ziglang, &official_buf)) == .ok) {
            const official = try Schema.Type.parse(ctx.gpa, official_buf.written());
            defer official.deinit();
            var buf_keys: [200][]const u8 = undefined;
            for (Schema.diff(result.schema, official, &buf_keys)) |key| {
                if (result.schema.parsed.value.map.get(key)) |detail| {
                    try versions.append(ctx.gpa, .{ .key = key, .date = &detail.date });
                }
            }
        }
    } else {
        var it = result.schema.parsed.value.map.iterator();
        while (it.next()) |entry| {
            try versions.append(ctx.gpa, .{ .key = entry.key_ptr.*, .date = &entry.value_ptr.date });
        }
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
}

fn runInstall(ctx: Context, ver: []const u8, mirror: Mirror) !void {
    var result = try fetchIndex(ctx, mirror);
    defer result.index.deinit();
    defer result.schema.deinit();

    const platform = Schema.Platform.parse(targetKey()) orelse {
        std.debug.print("error: unsupported platform: {s}\n", .{targetKey()});
        return;
    };

    const src = result.schema.get(ver, platform) orelse {
        std.debug.print("error: no binary found for version {s} on {s}\n", .{ ver, targetKey() });
        return;
    };

    const zigup_dir = try ctx.zigupDir();
    const bin_dir = try ctx.binDir();
    const install_dir = try ctx.versionDir(ver);

    try ensureDir(ctx, zigup_dir);
    try ensureDir(ctx, bin_dir);

    if (dirExists(ctx, install_dir)) {
        std.debug.print("Version {s} is already installed.\n", .{ver});
        return;
    }

    var split = std.mem.splitBackwardsAny(u8, src.tarball, "/");
    const filename = split.first();

    std.debug.print("Downloading {s}...\n", .{ver});

    var dl = download_mod.Downloader.init(&result.index.client);
    var file = try std.Io.Dir.createFileAbsolute(ctx.io, filename, .{});
    defer file.close(ctx.io);

    const dl_result = try download_mod.Downloader.downloadToFile(&dl, src.tarball, file, ctx.io);
    if (dl_result.status != .ok) {
        std.debug.print("error: failed to download tarball. HTTP {s}\n", .{@tagName(dl_result.status)});
        return;
    }

    std.debug.print("Extracting to ~/.zigup/{s}...\n", .{ver});
    try std.Io.Dir.createDirAbsolute(ctx.io, install_dir, .default_dir);

    var child = std.process.spawn(ctx.io, .{
        .argv = &.{ "tar", "-xf", filename, "-C", install_dir, "--strip-components=1" },
    }) catch |err| {
        std.debug.print("error: failed to spawn tar: {s}\n", .{@errorName(err)});
        return;
    };
    const term = child.wait(ctx.io) catch |err| {
        std.debug.print("error: failed to wait for tar: {s}\n", .{@errorName(err)});
        return;
    };
    switch (term) {
        .exited => |code| if (code != 0) {
            std.debug.print("error: tar failed with exit code {d}\n", .{code});
            return;
        },
        else => {
            std.debug.print("error: tar terminated abnormally\n", .{});
            return;
        },
    }

    std.Io.Dir.deleteFile(std.Io.Dir.cwd(), ctx.io, filename) catch {};
    std.debug.print("Successfully installed {s}.\n", .{ver});
}

fn runDefault(ctx: Context, ver: []const u8) !void {
    const install_dir = try ctx.versionDir(ver);
    if (!dirExists(ctx, install_dir)) {
        std.debug.print("error: {s} is not installed. Use 'zigup install {s} --ziglang' first.\n", .{ ver, ver });
        return;
    }

    const zigup_dir = try ctx.zigupDir();
    const bin_dir = try ctx.binDir();
    try ensureDir(ctx, bin_dir);

    const symlink_path = try std.fs.path.join(ctx.arena, &.{ bin_dir, "zig" });
    const target_rel = try std.fs.path.join(ctx.arena, &.{ "..", ver, "zig" });

    var zd = std.Io.Dir.openDirAbsolute(ctx.io, zigup_dir, .{}) catch return;
    defer zd.close(ctx.io);
    zd.deleteFile(ctx.io, symlink_path) catch {};
    zd.symLink(ctx.io, target_rel, symlink_path, .{}) catch |err| {
        std.debug.print("error: failed to create symlink: {s}\n", .{@errorName(err)});
        return;
    };

    std.debug.print("Set {s} as default.\n", .{ver});
}

fn runDelete(ctx: Context, ver: []const u8) !void {
    const zigup_dir = try ctx.zigupDir();
    var zd = std.Io.Dir.openDirAbsolute(ctx.io, zigup_dir, .{}) catch |err| {
        std.debug.print("error: ~/.zigup not found: {s}\n", .{@errorName(err)});
        return;
    };
    defer zd.close(ctx.io);

    zd.deleteTree(ctx.io, ver) catch |err| {
        std.debug.print("error: failed to delete ~/.zigup/{s}: {s}\n", .{ ver, @errorName(err) });
        return;
    };

    std.debug.print("Successfully deleted {s}.\n", .{ver});
}
