const std = @import("std");
const Client = std.http.Client;
pub const Status = enum {
    missing,
    fetching,
    corrupted,
    downloaded,
    default,
};

pub const Downloader = struct {
    client: *Client,

    pub const Result = struct {
        status: std.http.Status,
        duration: i128,
    };

    pub fn init(client: *Client) Downloader {
        return .{ .client = client };
    }

    pub fn downloadToFile(
        self: *Downloader,
        url: []const u8,
        file: std.Io.File,
        io: std.Io,
        status_out: *Status,
    ) !Result {
        const start = std.Io.Clock.now(.awake, io).nanoseconds;
        const uri = try std.Uri.parse(url);

        var req = try self.client.request(.GET, uri, .{});
        defer req.deinit();
        try req.sendBodiless();

        var redirect_buf: [8192]u8 = undefined;
        var response = try req.receiveHead(&redirect_buf);

        _ = response.head.content_length;

        var transfer_buf: [64]u8 = undefined;
        var decompress: std.http.Decompress = undefined;
        const decompress_buf: []u8 = switch (response.head.content_encoding) {
            .identity => &.{},
            .deflate, .gzip => try self.client.allocator.alloc(u8, std.compress.flate.max_window_len),
            .zstd => try self.client.allocator.alloc(u8, std.compress.zstd.default_window_len),
            .compress => return error.UnsupportedCompressionMethod,
        };
        defer self.client.allocator.free(decompress_buf);

        const body = response.readerDecompressing(&transfer_buf, &decompress, decompress_buf);

        var file_buf: [65536]u8 = undefined;
        var writer = file.writer(io, &file_buf);

        var chunk_buf: [8192]u8 = undefined;
        var downloaded: u64 = 0;

        status_out.* = .fetching;

        while (true) {
            var chunk_writer = std.Io.Writer.fixed(&chunk_buf);
            const n = body.stream(&chunk_writer, std.Io.Limit.limited(chunk_buf.len)) catch |err| switch (err) {
                error.EndOfStream => break,
                else => |e| return e,
            };
            try writer.interface.writeAll(chunk_buf[0..n]);
            downloaded += n;
            _ = std.Io.Clock.now(.awake, io).nanoseconds;
            // no update progress
        }

        try writer.flush();
        // no end progress

        const stop = std.Io.Clock.now(.awake, io).nanoseconds;
        return .{ .status = response.head.status, .duration = stop - start };
    }
};
