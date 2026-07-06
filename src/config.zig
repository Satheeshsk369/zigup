const std = @import("std");
const adt = @import("adt");

pub const Set = adt.Set(null);

pub fn Option(comptime n: usize) type {
    return struct {
        pub const argCount = n;
        pub const PayloadType: type = if (n == 0) void else []const u8;
        pub const argLabel: ?[]const u8 = if (n == 0) null else "<TAG>";
    };
}

pub const A = enum(u2) {
    help,
    version,
    env,
    list,

    pub const argCount = 0;
    pub const PayloadType: type = void;
    pub const argLabel: ?[]const u8 = null;

    pub fn info(self: @This()) []const u8 {
        return switch (self) {
            .help => "Print this message",
            .version => "Print zigup tool version",
            .env => "Print status of ~/.zigup/bin in your PATH",
            .list => "List local installs (--ziglang/--mach for remote)",
        };
    }
};

pub const B = enum(u1) { ziglang, mach };

pub const C = enum(u1) {
    install,
    delete,

    pub const argCount = 1;
    pub const PayloadType: type = []const u8;
    pub const argLabel: ?[]const u8 = "<TAG>";

    pub fn info(self: @This()) []const u8 {
        return switch (self) {
            .install => "Download and install a version (--ziglang/--mach)",
            .delete => "Delete an installed version",
        };
    }
};

pub const D = enum(u1) {
    default,

    pub const argCount = 1;
    pub const PayloadType: type = []const u8;
    pub const argLabel: ?[]const u8 = "<TAG>";

    pub fn info(self: @This()) []const u8 {
        return switch (self) {
            .default => "Set an installed version as the active default",
        };
    }
};

pub const E = enum(u1) { show };

pub const CB = Set.cartesianProduct(C, B, .{ .separator = "_" });
pub const EB = Set.cartesianProduct(E, B, .{ .separator = "_" });

pub const A1 = Set.enumToUnion(A, A.PayloadType);
pub const CB1 = Set.enumToUnion(CB, C.PayloadType);
pub const D1 = Set.enumToUnion(D, D.PayloadType);
pub const EB1 = Set.enumToUnion(EB, void);

pub const Command = Set.join(
    Set.join(A1, CB1),
    Set.join(D1, EB1),
);

pub const Entry = struct { verb: []const u8, argLabel: ?[]const u8, description: []const u8 };

fn appendEntries(comptime T: type, comptime out: []Entry, comptime start: usize) usize {
    var i = start;
    for (@typeInfo(T).@"enum".fields) |f| {
        const v: T = @enumFromInt(f.value);
        out[i] = .{ .verb = f.name, .argLabel = T.argLabel, .description = v.info() };
        i += 1;
    }
    return i;
}

pub const commands: []const Entry = blk: {
    const n = @typeInfo(A).@"enum".fields.len +
        @typeInfo(D).@"enum".fields.len +
        @typeInfo(C).@"enum".fields.len;
    var out: [n]Entry = undefined;
    var i: usize = 0;
    i = appendEntries(A, &out, i);
    i = appendEntries(D, &out, i);
    i = appendEntries(C, &out, i);
    const frozen = out;
    break :blk &frozen;
};
