const std = @import("std");
const Schema = @import("schema.zig");
const Client = std.http.Client;
const Downloader = @import("download.zig").Downloader;
const Index = @import("index.zig").Index;
const Mirror = @import("index.zig").Mirror;

fn getTargetKey() []const u8 {
    const builtin = @import("builtin");
    const arch = @tagName(builtin.target.cpu.arch);
    const os = @tagName(builtin.target.os.tag);
    return arch ++ "-" ++ os;
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var use_mach = false;
    var it_args = try std.process.Args.Iterator.initAllocator(init.minimal.args, gpa);
    defer it_args.deinit();
    while (it_args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--mach")) {
            use_mach = true;
        }
    }

    var client: Client = .{ .allocator = gpa, .io = io };
    defer client.deinit();

    var buffer = std.Io.Writer.Allocating.init(gpa);
    defer buffer.deinit();

    const mirror_url = if (use_mach) Mirror[1] else Mirror[0];
    std.log.info("Fetching index from {s}...", .{mirror_url});

    const uri = try std.Uri.parse(mirror_url);
    const index_response = try client.fetch(.{
        .location = .{ .uri = uri },
        .method = .GET,
        .response_writer = &buffer.writer,
    });

    if (index_response.status != .ok) {
        std.log.err("Failed to fetch index: {s}", .{@tagName(index_response.status)});
        return;
    }

    const schema = try Schema.Type.parse(gpa, buffer.written());
    defer schema.deinit();

    const VersionItem = struct {
        key: []const u8,
        date: []const u8,
    };

    var versions = std.ArrayList(VersionItem).empty;
    defer versions.deinit(gpa);
    var it = schema.parsed.value.map.iterator();
    if (use_mach) {
        var official_buf = std.Io.Writer.Allocating.init(gpa);
        defer official_buf.deinit();
        const official_uri = try std.Uri.parse(Mirror[0]);
        const official_response = try client.fetch(.{
            .location = .{ .uri = official_uri },
            .method = .GET,
            .response_writer = &official_buf.writer,
        });
        if (official_response.status == .ok) {
            const official_schema = try Schema.Type.parse(gpa, official_buf.written());
            defer official_schema.deinit();

            var buf_keys: [200][]const u8 = undefined;
            const diff_keys = Schema.diff(schema, official_schema, &buf_keys);
            for (diff_keys) |key| {
                if (schema.parsed.value.map.get(key)) |detail| {
                    try versions.append(gpa, .{ .key = key, .date = &detail.date });
                }
            }
        }
    } else {
        while (it.next()) |entry| {
            try versions.append(gpa, .{ .key = entry.key_ptr.*, .date = &entry.value_ptr.date });
        }
    }

    if (versions.items.len == 0) {
        std.log.info("No matching versions found.", .{});
        return;
    }

    std.mem.sort(VersionItem, versions.items, {}, struct {
        fn lessThan(_: void, lhs: VersionItem, rhs: VersionItem) bool {
            const date_order = std.mem.order(u8, lhs.date, rhs.date);
            if (date_order != .eq) {
                return date_order == .gt;
            }
            return std.mem.order(u8, lhs.key, rhs.key) == .gt;
        }
    }.lessThan);
    var stdin_buf: [128]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().reader(io, &stdin_buf);
    var stdin_interface = &stdin_reader.interface;

    while (true) {
        std.debug.print("\n=== Zigup Release Selector ===\n", .{});
        for (versions.items, 0..) |item, idx| {
            std.debug.print(" [{d}] {s} (Date: {s})\n", .{ idx, item.key, item.date });
        }
        std.debug.print("\nOptions: [number] to select, [q]uit: ", .{});
        const line = (try stdin_interface.takeDelimiter('\n')) orelse break;
        const trimmed = std.mem.trim(u8, line, " \r\n");
        if (std.mem.eql(u8, trimmed, "q")) {
            break;
        } else {
            const selected_idx = std.fmt.parseInt(usize, trimmed, 10) catch {
                std.debug.print("Invalid command or index.\n", .{});
                continue;
            };

            if (selected_idx >= versions.items.len) {
                std.debug.print("Index out of bounds.\n", .{});
                continue;
            }

            const target_ver = versions.items[selected_idx].key;
            const target_key = getTargetKey();
            const platform = Schema.Platform.parse(target_key) orelse {
                std.log.err("Unsupported target platform: {s}", .{target_key});
                return;
            };

            const src = schema.get(target_ver, platform) orelse {
                std.log.err("No binary found for version {s} and target: {s}", .{ target_ver, target_key });
                continue;
            };

            const tarball_url = src.tarball;
            std.log.info("Downloading {s} from {s}...", .{ target_ver, tarball_url });

            var split_it = std.mem.splitBackwardsAny(u8, tarball_url, "/");
            const filename = split_it.first();
            var dir = std.Io.Dir.cwd();
            var file = try dir.createFile(io, filename, .{});
            defer file.close(io);

            const start_time = std.Io.Clock.now(.awake, io);
            var dl = Downloader.init(&client);
            const dl_status = try dl.downloadToFile(tarball_url, file, io);
            const stop_time = std.Io.Clock.now(.awake, io);
            const duration = start_time.durationTo(stop_time).nanoseconds;

            std.log.info("Download status: {s}", .{@tagName(dl_status)});
            std.log.info("Time elapsed: {d:.3}s", .{@as(f64, @floatFromInt(duration)) / 1_000_000_000.0});
            break;
        }
    }
}
