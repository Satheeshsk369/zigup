const std = @import("std");
const adt = @import("adt");
pub const Set = adt.Set(null);
pub const Source = struct {
    tarball: []const u8,
    shasum: []const u8,
    size: usize,
};

pub const Platform = enum {
    @"x86_64-macos",
    @"aarch64-macos",
    @"x86_64-linux",
    @"aarch64-linux",
    @"arm-linux",
    @"riscv64-linux",
    @"powerpc64le-linux",
    @"x86-linux",
    @"loongarch64-linux",
    @"s390x-linux",
    @"x86_64-windows",
    @"aarch64-windows",
    @"x86-windows",
    @"aarch64-freebsd",
    @"arm-freebsd",
    @"powerpc64le-freebsd",
    @"riscv64-freebsd",
    @"x86_64-freebsd",
    @"aarch64-netbsd",
    @"arm-netbsd",
    @"riscv64-netbsd",
    @"x86-netbsd",
    @"x86_64-netbsd",
    @"aarch64-openbsd",
    @"arm-openbsd",
    @"riscv64-openbsd",
    @"x86_64-openbsd",

    const Self = @This();

    pub fn parse(platform: []const u8) ?Platform {
        return std.meta.stringToEnum(Self, platform);
    }

    pub fn toStruct(comptime FieldType: type) type {
        const PlatformUnion = Set.enumToUnion(Self, FieldType);
        return Set.unionToStruct(PlatformUnion);
    }
};

pub const VersionDetail = decl: {
    const Base = struct {
        version: ?[]const u8 = null,
        date: [10]u8,
        docs: ?[]const u8 = null,
        notes: ?[]const u8 = null,
        stdDocs: ?[]const u8 = null,
        src: ?Source = null,
        bootstrap: ?Source = null,
    };
    const PlatformStruct = Platform.toStruct(?Source);
    break :decl Set.join(Base, PlatformStruct);
};

pub const Type = struct {
    parsed: std.json.Parsed(std.json.ArrayHashMap(VersionDetail)),

    pub fn parse(allocator: std.mem.Allocator, json: []const u8) !Type {
        const parsed = try std.json.parseFromSlice(
            std.json.ArrayHashMap(VersionDetail),
            allocator,
            json,
            .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
        );
        return Type{ .parsed = parsed };
    }

    pub fn get(self: Type, version: []const u8, platform: Platform) ?Source {
        const detail = self.parsed.value.map.get(version) orelse return null;
        const target_name = @tagName(platform);
        inline for (std.meta.fields(VersionDetail)) |f| {
            if (std.mem.eql(u8, f.name, target_name)) {
                if (f.type == ?Source) {
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

pub fn diff(target: Type, source: Type, out_buffer: [][]const u8) []const []const u8 {
    var count: usize = 0;
    var it = target.parsed.value.map.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        if (!source.parsed.value.map.contains(key)) {
            if (count < out_buffer.len) {
                out_buffer[count] = key;
                count += 1;
            }
        }
    }
    return out_buffer[0..count];
}
