const std = @import("std");
const Schema = @import("schema.zig");
const Client = std.http.Client;
const Progress = @import("ui/progress.zig").Progress;

pub const Downloader = struct {
    client: *Client,

    pub fn init(client: *Client) Downloader {
        return .{ .client = client };
    }

    pub fn downloadToFile(
        self: *Downloader,
        url: []const u8,
        file: std.Io.File,
        io: std.Io,
        progress: *Progress,
    ) !std.http.Status {
        const uri = try std.Uri.parse(url);

        var redirect_buf: [4096]u8 = undefined;
        var req = try self.client.request(.GET, uri, .{});
        try req.sendBodiless();
        var response = try req.receiveHead(&redirect_buf);

        const total_size = response.head.content_length;

        var transfer_buf: [65536]u8 = undefined;
        const body = response.reader(&transfer_buf);

        var file_buf: [65536]u8 = undefined;
        var writer = file.writer(io, &file_buf);

        var chunk_buf: [8192]u8 = undefined;
        var downloaded: u64 = 0;
        const start_ns: u64 = @intCast(@max(0, std.Io.Clock.now(.awake, io).nanoseconds));

        progress.begin();

        while (true) {
            var chunk_writer = std.Io.Writer.fixed(&chunk_buf);
            const n = body.stream(&chunk_writer, std.Io.Limit.limited(chunk_buf.len)) catch break;
            if (n == 0) break;
            try writer.interface.writeAll(chunk_buf[0..n]);
            downloaded += n;
            const now_ns: u64 = @intCast(@max(0, std.Io.Clock.now(.awake, io).nanoseconds));
            progress.update(downloaded, total_size, now_ns -| start_ns);
        }

        try writer.flush();
        progress.end();

        return response.head.status;
    }
};
