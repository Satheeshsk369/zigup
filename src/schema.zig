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

pub const Schema = std.json.ArrayHashMap(VersionDetail);
