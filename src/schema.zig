const Set = @import("set.zig");

const std = @import("std");

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

    const PlatformUnion = Set.EnumToUnionConst(Platform, ?Source);
    const PlatformStruct = Set.UnionToStruct(PlatformUnion, .{ .assign_null_for_optional = true });

    break :decl Set.Union(Base, PlatformStruct);
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
