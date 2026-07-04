const std = @import("std");
const Schema = @import("schema.zig");
const Downloader = @import("download.zig").Downloader;
const Index = @import("index.zig").Index;
const Mirror = @import("index.zig").Mirror;
const Table = @import("ui/table.zig");
const TableBuffer = @import("ui/buffer.zig").TableBuffer;
const ReplBuffer = @import("ui/buffer.zig").ReplBuffer;
const State = @import("ui/state.zig").State;
const Status = @import("ui/state.zig").Status;
const Progress = @import("ui/progress.zig").Progress;
const Help = @import("ui/help.zig");

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
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--mach")) use_mach = true;
    }

    var index = Index.init(gpa, io);
    defer index.deinit();

    var http_buf = std.Io.Writer.Allocating.init(gpa);
    defer http_buf.deinit();

    const mirror_url = if (use_mach) Mirror[1] else Mirror[0];
    const use_color = @import("ui/color.zig").isTerminal(std.Io.File.stdout(), io);
    const c_url = if (use_color) "\x1b[33m" else "";
    const c_rst = if (use_color) "\x1b[0m" else "";

    std.debug.print("info: Fetching index from {s}{s}{s}\n", .{ c_url, mirror_url, c_rst });

    const index_response = try index.fetch(mirror_url, &http_buf);
    if (index_response != .ok) {
        std.log.err("Failed to fetch index: {s}", .{@tagName(index_response)});
        return;
    }

    const schema = try Schema.Type.parse(gpa, http_buf.written());
    defer schema.deinit();

    const VersionItem = struct {
        key: []const u8,
        date: []const u8,
    };

    var versions = std.ArrayList(VersionItem).empty;
    defer versions.deinit(gpa);

    if (use_mach) {
        var official_buf = std.Io.Writer.Allocating.init(gpa);
        defer official_buf.deinit();
        if ((try index.fetch(Mirror[0], &official_buf)) == .ok) {
            const official_schema = try Schema.Type.parse(gpa, official_buf.written());
            defer official_schema.deinit();
            var buf_keys: [200][]const u8 = undefined;
            for (Schema.diff(schema, official_schema, &buf_keys)) |key| {
                if (schema.parsed.value.map.get(key)) |detail| {
                    try versions.append(gpa, .{ .key = key, .date = &detail.date });
                }
            }
        }
    } else {
        var it = schema.parsed.value.map.iterator();
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
            if (date_order != .eq) return date_order == .gt;
            return std.mem.order(u8, lhs.key, rhs.key) == .gt;
        }
    }.lessThan);

    var state = try State.init(gpa, versions.items.len);
    defer state.deinit();

    const TableItem = struct {
        index: usize,
        version: []const u8,
        date: []const u8,
        status: []const u8,
    };

    var table_items = try std.ArrayList(TableItem).initCapacity(gpa, versions.items.len);
    defer table_items.deinit(gpa);

    var cwd = std.Io.Dir.cwd();
    for (versions.items, 0..) |item, idx| {
        const platform = Schema.Platform.parse(getTargetKey()) orelse continue;
        const src = schema.get(item.key, platform) orelse continue;
        var split_it = std.mem.splitBackwardsAny(u8, src.tarball, "/");
        const filename = split_it.first();
        const file_status: Status = if (cwd.openFile(io, filename, .{})) |f| blk: {
            f.close(io);
            break :blk .downloaded;
        } else |_| .missing;
        state.set(idx, file_status);
        table_items.appendAssumeCapacity(.{
            .index = idx,
            .version = item.key,
            .date = item.date,
            .status = file_status.toString(use_color),
        });
    }

    const col_widths = try Table.printMeasured(gpa, io, TableItem, table_items.items);

    const tbl = TableBuffer.init(col_widths, table_items.items.len);
    const repl = ReplBuffer.init();

    var stdin_buf: [128]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().reader(io, &stdin_buf);
    var stdin_iface = &stdin_reader.interface;

    repl.log("{s}", .{Help.print(use_color)});
    std.debug.print("\n> ", .{});

    while (true) {
        const line = (try stdin_iface.takeDelimiter('\n')) orelse break;
        const trimmed = std.mem.trim(u8, line, " \r\n");

        if (std.mem.eql(u8, trimmed, "q")) break;

        if (std.mem.eql(u8, trimmed, "help") or trimmed.len == 0) {
            repl.log("{s}", .{Help.print(use_color)});
            std.debug.print("\n> ", .{});
            continue;
        }

        const sp = std.mem.indexOfScalar(u8, trimmed, ' ');
        if (sp == null) {
            repl.log("unknown: {s}  |  {s}", .{ trimmed, Help.print(use_color) });
            std.debug.print("\n> ", .{});
            continue;
        }

        const cmd = trimmed[0..sp.?];
        const num_str = std.mem.trim(u8, trimmed[sp.? + 1 ..], " ");
        const selected_idx = std.fmt.parseInt(usize, num_str, 10) catch {
            repl.log("usage: {s} <index>", .{cmd});
            std.debug.print("\n> ", .{});
            continue;
        };

        if (selected_idx >= versions.items.len) {
            repl.log("index out of range (0-{d})", .{versions.items.len - 1});
            std.debug.print("\n> ", .{});
            continue;
        }

        const target_ver = versions.items[selected_idx].key;
        const platform = Schema.Platform.parse(getTargetKey()) orelse {
            repl.log("error: unsupported platform: {s}", .{getTargetKey()});
            std.debug.print("\n> ", .{});
            return;
        };
        const src = schema.get(target_ver, platform) orelse {
            repl.log("error: no binary for {s} on {s}", .{ target_ver, getTargetKey() });
            std.debug.print("\n> ", .{});
            continue;
        };
        var split_it = std.mem.splitBackwardsAny(u8, src.tarball, "/");
        const filename = split_it.first();

        if (std.mem.eql(u8, cmd, "fetch")) {
            state.set(selected_idx, .fetching);
            tbl.patch(selected_idx, Status.fetching.toString(use_color));
            repl.log("fetching {s}...", .{target_ver});
            var prog = Progress.init(use_color);
            var dl = Downloader.init(&index.client);
            const dir = std.Io.Dir.cwd();
            var file = try dir.createFile(io, filename, .{});
            defer file.close(io);
            var dl_future = io.async(Downloader.downloadToFile, .{ &dl, src.tarball, file, io, &prog });
            defer _ = dl_future.cancel(io) catch {};
            const result: Downloader.Result = try dl_future.await(io);

            const final: Status = if (result.status == .ok) .downloaded else .missing;
            state.set(selected_idx, final);
            tbl.patch(selected_idx, final.toString(use_color));
            repl.log("{s} {s} in {d:.3}s", .{
                target_ver,
                if (result.status == .ok) "done" else "failed",
                @as(f64, @floatFromInt(result.duration)) / 1_000_000_000.0,
            });
            std.debug.print("\n> ", .{});
        } else if (std.mem.eql(u8, cmd, "delete")) {
            cwd.deleteFile(io, filename) catch |err| {
                repl.log("error: {s}", .{@errorName(err)});
                std.debug.print("\n> ", .{});
                continue;
            };
            state.set(selected_idx, .missing);
            tbl.patch(selected_idx, Status.missing.toString(use_color));
            repl.log("deleted {s}", .{filename});
            std.debug.print("\n> ", .{});
        } else {
            repl.log("unknown: {s}  |  {s}", .{ cmd, Help.print(use_color) });
            std.debug.print("\n> ", .{});
        }
    }
}
