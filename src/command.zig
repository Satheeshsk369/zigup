const std = @import("std");
const adt = @import("adt");

pub const Set = adt.Set(null);

pub const A = enum(u2) {
    help,
    version,
    env,

    pub const argCount = 0;
    pub const PayloadType: type = void;
    pub const argLabel: ?[]const u8 = null;

    pub fn info(self: @This()) []const u8 {
        return switch (self) {
            .help => "Print this message",
            .version => "Print zigup tool version",
            .env => "Print status of ~/.zigup/bin in your PATH",
        };
    }
};

pub const C = enum(u2) {
    install,
    delete,
    default,
    list,

    pub const argCount = 1;
    pub const PayloadType: type = []const u8;
    pub const argLabel: ?[]const u8 = "<TAG>";

    pub fn info(self: @This()) []const u8 {
        return switch (self) {
            .install => "Download and install a version",
            .delete => "Delete an installed version",
            .default => "Set an installed version as the active default",
            .list => "List remote versions from cached index",
        };
    }
};

pub const A1 = Set.enumToUnion(A, A.PayloadType);
pub const C1 = Set.enumToUnion(C, C.PayloadType);

pub const Command = Set.join(A1, C1);

pub const Entry = struct { verb: []const u8, argLabel: ?[]const u8, description: []const u8 };

fn appendEntries(comptime T: type, comptime out: []Entry, comptime start: usize) usize {
    var i = start;
    for (@typeInfo(T).@"enum".fields) |f| {
        const v: T = @enumFromInt(f.value);
        const label = if (std.mem.eql(u8, f.name, "list")) "<MIRROR>" else T.argLabel;
        out[i] = .{ .verb = f.name, .argLabel = label, .description = v.info() };
        i += 1;
    }
    return i;
}

pub const commands: []const Entry = blk: {
    const n = @typeInfo(A).@"enum".fields.len +
        @typeInfo(C).@"enum".fields.len;
    var out: [n]Entry = undefined;
    var i: usize = 0;
    i = appendEntries(A, &out, i);
    i = appendEntries(C, &out, i);
    const frozen = out;
    break :blk &frozen;
};
