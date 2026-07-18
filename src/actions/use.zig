const std = @import("std");
const Schema = @import("../schema.zig");
const dl = @import("../download.zig");
const action = @import("root.zig");
const install = @import("install.zig");

const BuildZon = struct {
    minimum_zig_version: ?[]const u8 = null,
};

/// Read minimum_zig_version from build.zig.zon in the current directory.
fn readProjectVersion(gpa: std.mem.Allocator, io: std.Io) ![]const u8 {
    const cwd = try std.process.currentPathAlloc(io, gpa);
    defer gpa.free(cwd);

    const zon_path = try std.fs.path.join(gpa, &.{ cwd, "build.zig.zon" });
    defer gpa.free(zon_path);

    const file = std.Io.Dir.openFileAbsolute(io, zon_path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            std.log.err("no build.zig.zon found in the current directory ({s})", .{cwd});
            return error.FileNotFound;
        },
        else => return err,
    };
    defer file.close(io);

    const stat = try file.stat(io);
    var f_buf: [65536]u8 = undefined;
    var r = file.reader(io, &f_buf);
    const content = try r.interface.readAlloc(gpa, @intCast(stat.size));
    defer gpa.free(content);

    const content_z = try gpa.dupeZ(u8, content);
    defer gpa.free(content_z);

    const parsed = try std.zon.parse.fromSliceAlloc(BuildZon, gpa, content_z, null, .{
        .ignore_unknown_fields = true,
    });
    defer std.zon.parse.free(gpa, parsed);

    const ver = parsed.minimum_zig_version orelse {
        std.log.err("build.zig.zon does not specify .minimum_zig_version", .{});
        return error.FileNotFound;
    };

    return gpa.dupe(u8, ver);
}

/// Fetch index from a mirror URL, parse it, and return it.
/// Caller owns the returned Schema.Type (call deinit).
fn fetchSchema(
    gpa: std.mem.Allocator,
    io: std.Io,
    environ_map: *const std.process.Environ.Map,
    mirror_name: []const u8,
    mirror_url: []const u8,
    ctx: action.Context,
) !Schema.Type {
    // Try cache first; on miss, fetch live.
    const cache_path = try ctx.cacheFile(mirror_name);
    if (Schema.Type.loadCache(gpa, io, cache_path)) |schema| {
        return schema;
    } else |_| {}

    var index = Schema.Index.init(gpa, io, environ_map);
    defer index.deinit();

    var httpBuf = std.Io.Writer.Allocating.init(gpa);
    defer httpBuf.deinit();

    std.log.info("Fetching index from {s} ({s})", .{ mirror_name, mirror_url });
    if ((try index.fetchUrl(mirror_url, &httpBuf)) != .ok) {
        return error.HttpError;
    }
    Schema.Type.saveCache(gpa, io, cache_path, httpBuf.written()) catch {};
    return Schema.Type.parse(gpa, httpBuf.written());
}

pub fn run(ctx: action.Context) !void {
    const ver = try readProjectVersion(ctx.gpa, ctx.io);
    defer ctx.gpa.free(ver);

    std.log.info("Project requires Zig {s}", .{ver});

    const platform = Schema.Platform.parse(action.targetKey()) orelse {
        std.log.err("unsupported platform: {s}", .{action.targetKey()});
        return;
    };

    // Try every configured mirror in order until one has the version.
    var last_err: ?anyerror = null;
    for (ctx.userConfig.mirrors) |mirror| {
        const schema = fetchSchema(
            ctx.gpa,
            ctx.io,
            ctx.environMap,
            mirror.name,
            mirror.url,
            ctx,
        ) catch |err| {
            std.log.warn("mirror '{s}': failed to load index ({s}), skipping", .{ mirror.name, @errorName(err) });
            last_err = err;
            continue;
        };
        defer schema.deinit();

        const src = schema.get(ver, platform) orelse {
            std.log.warn("mirror '{s}': version {s} not found, skipping", .{ mirror.name, ver });
            last_err = error.FileNotFound;
            continue;
        };

        // Found — delegate to the shared install logic.
        std.log.info("Installing {s} from mirror '{s}'", .{ ver, mirror.name });
        try install.runFromSource(ctx, ver, src);
        return;
    }

    if (last_err) |_| {
        std.log.err("version {s} was not found in any configured mirror", .{ver});
    } else {
        std.log.err("no mirrors configured", .{});
    }
    return error.FileNotFound;
}

test "use action compilation check" {
    _ = run;
}
