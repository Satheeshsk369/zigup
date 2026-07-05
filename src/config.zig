const std = @import("std");
const adt = @import("adt");

pub const Set = adt.Set(null);

pub const NoArgOptions = enum(u2) { help, version, env, list };
pub const Mirror = enum(u1) { ziglang, mach };
pub const OpArg1 = enum(u2) { install, delete, default };
pub const OpNoArg = enum(u1) { show };

pub const OpArg1Indexed = Set.cartesianProduct(OpArg1, Mirror, .{ .separator = "_" });
pub const OpNoArgIndexed = Set.cartesianProduct(OpNoArg, Mirror, .{ .separator = "_" });

pub const VoidType = Set.enumToUnion(NoArgOptions, void);
pub const OpArg1Type = Set.enumToUnion(OpArg1Indexed, []const u8);
pub const OpNoArgType = Set.enumToUnion(OpNoArgIndexed, void);

pub const Command = Set.join(Set.join(VoidType, OpArg1Type), OpNoArgType);
