const std = @import("std");

pub const Config = struct {
    pub const MirrorEntry = struct {
        name: []const u8,
        url: []const u8,
    };

    mirrors: []const MirrorEntry,
    defaultMirror: []const u8,

    pub const default_zon =
        \\.{
        \\    .mirrors = .{
        \\        .{ .name = "ziglang", .url = "https://ziglang.org/download/index.json" },
        \\        .{ .name = "mach", .url = "https://pkg.hexops.org/zig/index.json" },
        \\    },
        \\    .defaultMirror = "ziglang",
        \\}
    ;

    pub fn getMirrorUrl(self: Config, name: []const u8) ?[]const u8 {
        for (self.mirrors) |m| {
            if (std.mem.eql(u8, m.name, name)) return m.url;
        }
        return null;
    }

    pub fn loadOrInit(gpa: std.mem.Allocator, io: std.Io, path: []const u8) !Config {
        const file = std.Io.Dir.openFileAbsolute(io, path, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                if (std.fs.path.dirname(path)) |dir_path| {
                    var parts = std.mem.tokenizeAny(u8, dir_path, "/\\");
                    var buffer = std.ArrayList(u8).empty;
                    defer buffer.deinit(gpa);

                    const builtin = @import("builtin");
                    const is_windows = builtin.os.tag == .windows;

                    if (!is_windows and dir_path.len > 0 and dir_path[0] == '/') {
                        try buffer.append(gpa, '/');
                    }

                    while (parts.next()) |part| {
                        if (buffer.items.len > 0 and buffer.items[buffer.items.len - 1] != '/' and buffer.items[buffer.items.len - 1] != '\\') {
                            const sep: u8 = if (is_windows) '\\' else '/';
                            try buffer.append(gpa, sep);
                        }
                        try buffer.appendSlice(gpa, part);
                        std.Io.Dir.createDirAbsolute(io, buffer.items, .default_dir) catch |e| switch (e) {
                            error.PathAlreadyExists => {},
                            else => return e,
                        };
                    }
                }
                var f = try std.Io.Dir.createFileAbsolute(io, path, .{});
                defer f.close(io);
                var writer = f.writer(io, &.{});
                try writer.interface.writeAll(default_zon);

                // For the default case, parse default_zon
                const default_zon_z = try gpa.dupeZ(u8, default_zon);
                defer gpa.free(default_zon_z);
                return try std.zon.parse.fromSliceAlloc(Config, gpa, default_zon_z, null, .{});
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

        var diag = std.zon.parse.Diagnostics{};
        defer diag.deinit(gpa);

        return std.zon.parse.fromSliceAlloc(Config, gpa, content_z, &diag, .{
            .ignore_unknown_fields = true,
        }) catch |e| {
            var http_buf = std.Io.Writer.Allocating.init(gpa);
            defer http_buf.deinit();
            diag.format(&http_buf.writer) catch {};
            std.debug.print("ZON Parse error:\n{s}\n", .{http_buf.written()});
            return e;
        };
    }
};
