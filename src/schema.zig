const std = @import("std");

pub const Source = struct {
    tarball: []const u8,
    shasum: []const u8,
    size: usize,
};

pub const VersionDetail = struct {
    version: ?[]const u8 = null,
    date: [10]u8,
    docs: ?[]const u8 = null,
    notes: ?[]const u8 = null,
    stdDocs: ?[]const u8 = null,
    src: ?Source = null,
    bootstrap: ?Source = null,
    @"x86_64-macos": ?Source = null,
    @"aarch64-macos": ?Source = null,
    @"x86_64-linux": ?Source = null,
    @"aarch64-linux": ?Source = null,
    @"arm-linux": ?Source = null,
    @"riscv64-linux": ?Source = null,
    @"powerpc64le-linux": ?Source = null,
    @"x86-linux": ?Source = null,
    @"loongarch64-linux": ?Source = null,
    @"s390x-linux": ?Source = null,
    @"x86_64-windows": ?Source = null,
    @"aarch64-windows": ?Source = null,
    @"x86-windows": ?Source = null,
    @"aarch64-freebsd": ?Source = null,
    @"arm-freebsd": ?Source = null,
    @"powerpc64le-freebsd": ?Source = null,
    @"riscv64-freebsd": ?Source = null,
    @"x86_64-freebsd": ?Source = null,
    @"aarch64-netbsd": ?Source = null,
    @"arm-netbsd": ?Source = null,
    @"riscv64-netbsd": ?Source = null,
    @"x86-netbsd": ?Source = null,
    @"x86_64-netbsd": ?Source = null,
    @"aarch64-openbsd": ?Source = null,
    @"arm-openbsd": ?Source = null,
    @"riscv64-openbsd": ?Source = null,
    @"x86_64-openbsd": ?Source = null,
};

pub const Type = struct {
    parsed: std.json.Parsed(std.json.ArrayHashMap(VersionDetail)),

    pub fn parse(allocator: std.mem.Allocator, json: []const u8) !Type {
        const parsed = try std.json.parseFromSlice(
            std.json.ArrayHashMap(VersionDetail),
            allocator,
            json,
            .{ .ignore_unknown_fields = true },
        );
        return Type{ .parsed = parsed };
    }

    pub fn get(self: Type, version: []const u8, target_key: []const u8) ?Source {
        const detail = self.parsed.value.map.get(version) orelse return null;
        inline for (std.meta.fields(VersionDetail)) |f| {
            if (f.type == ?Source) {
                if (std.mem.eql(u8, f.name, target_key)) {
                    return @field(detail, f.name);
                }
            }
        }
        return null;
    }

    pub fn deinit(self: Type) void {
        self.parsed.deinit();
    }
};
