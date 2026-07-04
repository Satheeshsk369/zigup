const std = @import("std");
const Schema = @import("schema.zig");
const Client = std.http.Client;

pub const Downloader = struct {
    client: *Client,

    const Self = @This();

    pub fn init(client: *Client) Self {
        return Self{ .client = client };
    }

    pub const Result = struct {
        status: std.http.Status,
        duration: i128,
    };

    pub fn downloadToFile(self: *Self, io: std.Io, url: []const u8, dir: std.Io.Dir) !Result {
        const start = std.Io.Clock.now(.awake, io).nanoseconds;

        var split_it = std.mem.splitBackwardsAny(u8, url, "/");
        const filename = split_it.first();
        var file = try dir.createFile(io, filename, .{});
        defer file.close(io);

        const uri = try std.Uri.parse(url);
        var buf: [65536]u8 = undefined;
        var writer = file.writer(io, &buf);
        const response = try self.client.fetch(.{
            .location = .{ .uri = uri },
            .method = .GET,
            .response_writer = &writer.interface,
        });
        try writer.flush();

        const stop = std.Io.Clock.now(.awake, io).nanoseconds;
        return .{ .status = response.status, .duration = stop - start };
    }
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const builtin = @import("builtin");
    const arch = @tagName(builtin.target.cpu.arch);
    const os = @tagName(builtin.target.os.tag);
    const target_key = arch ++ "-" ++ os;

    var client: Client = .{ .allocator = gpa, .io = init.io };
    defer client.deinit();

    var buffer = std.Io.Writer.Allocating.init(gpa);
    defer buffer.deinit();

    std.log.info("Fetching zig index...", .{});
    const uri = try std.Uri.parse("https://ziglang.org/download/index.json");
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

    const platform = Schema.Platform.parse(target_key) orelse {
        std.log.err("Unsupported target platform: {s}", .{target_key});
        return;
    };

    const target_ver = "0.16.0";
    const src = schema.get(target_ver, platform) orelse {
        std.log.err("No binary found for version {s} and target: {s}", .{ target_ver, target_key });
        return;
    };

    const tarball_url = src.tarball;
    std.log.info("Downloading {s} from {s}", .{ target_ver, tarball_url });

    const dir = std.Io.Dir.cwd();
    var dl = Downloader.init(&client);
    var dl_future = init.io.async(Downloader.downloadToFile, .{ &dl, init.io, tarball_url, dir });
    defer _ = dl_future.cancel(init.io) catch {};
    const result = try dl_future.await(init.io);
    std.log.info("Download completed: {s}", .{@tagName(result.status)});
    std.log.info("Time taken: {d:.3}s", .{@as(f64, @floatFromInt(result.duration)) / 1_000_000_000.0});
}
