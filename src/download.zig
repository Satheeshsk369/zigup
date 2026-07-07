const std = @import("std");
const Client = std.http.Client;

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
        shasum: ?[]const u8,
        size: ?u64,
        file: std.Io.File,
        io: std.Io,
    ) !Result {
        const Sha256 = std.crypto.hash.sha2.Sha256;
        var hasher = Sha256.init(.{});
        const start = std.Io.Clock.now(.awake, io).nanoseconds;
        const uri = try std.Uri.parse(url);

        var req = try self.client.request(.GET, uri, .{});
        defer req.deinit();
        try req.sendBodiless();

        var redirect_buf: [8192]u8 = undefined;
        var response = try req.receiveHead(&redirect_buf);

        const content_length = response.head.content_length orelse size;
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
        var last_update: i128 = 0;

        while (true) {
            var chunk_writer = std.Io.Writer.fixed(&chunk_buf);
            const n = body.stream(&chunk_writer, std.Io.Limit.limited(chunk_buf.len)) catch |err| switch (err) {
                error.EndOfStream => break,
                else => |e| return e,
            };
            try writer.interface.writeAll(chunk_buf[0..n]);
            if (shasum != null) {
                hasher.update(chunk_buf[0..n]);
            }
            downloaded += n;
            const now = std.Io.Clock.now(.awake, io).nanoseconds;
            if (now - last_update > 100_000_000) {
                last_update = now;
                if (content_length) |total| {
                    const pct = (@as(f64, @floatFromInt(downloaded)) / @as(f64, @floatFromInt(total))) * 100.0;
                    std.log.info("\rDownloading... {d:.1}% ({d} / {d} bytes)", .{ pct, downloaded, total });
                } else {
                    std.log.info("\rDownloading... {d} bytes", .{downloaded});
                }
            }
        }
        if (content_length) |total| {
            std.log.info("\rDownloading... 100.0% ({d} / {d} bytes)\n", .{ total, total });
        } else {
            std.log.info("\rDownloading... {d} bytes\n", .{downloaded});
        }

        try writer.flush();

        if (shasum) |expected| {
            var digest: [Sha256.digest_length]u8 = undefined;
            hasher.final(&digest);
            var actual_hex: [Sha256.digest_length * 2]u8 = undefined;
            const hex = std.fmt.bytesToHex(digest, .lower);
            @memcpy(actual_hex[0..], hex[0..]);
            if (!std.mem.eql(u8, expected, &actual_hex)) {
                return error.ShasumMismatch;
            }
        }

        const stop = std.Io.Clock.now(.awake, io).nanoseconds;
        return .{ .status = response.head.status, .duration = stop - start };
    }
};
