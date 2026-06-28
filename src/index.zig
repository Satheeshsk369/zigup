const std = @import("std");
const Client = std.http.Client;
const Allocating = std.Io.Writer.Allocating;

pub const Mirror = [_][]const u8{
    "https://ziglang.org/download/index.json",
    "https://pkg.hexops.org/zig/index.json",
};

pub const Index = struct {
    client: Client,

    const Self = @This();

    pub fn init(gpa: std.mem.Allocator, io: std.Io) Self {
        return Self{ .client = .{ .allocator = gpa, .io = io } };
    }

    pub fn fetch(self: *Self, url: []const u8, body: *Allocating) !std.http.Status {
        const uri = try std.Uri.parse(url);
        const response = try self.client.fetch(.{
            .location = .{ .uri = uri },
            .method = .GET,
            .response_writer = &body.writer,
        });
        return response.status;
    }

    pub fn deinit(self: *Self) void {
        self.client.deinit();
    }
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    var index: Index = .init(gpa, init.io);
    defer index.deinit();

    var ziglang: Allocating = .init(gpa);
    defer ziglang.deinit();

    const index01 = try index.fetch(Mirror[0], &ziglang);
    if (index01 == .ok) std.debug.print("{s}", .{ziglang.written()});

    var mach: Allocating = .init(gpa);
    defer mach.deinit();

    const index02 = try index.fetch(Mirror[1], &mach);
    if (index02 == .ok) std.debug.print("{s}", .{mach.written()});
}
