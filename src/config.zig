const std = @import("std");
const adt = @import("adt");

pub const Set = adt.Set(null);

pub const TypeA = enum {
    help,
    version,
    env,
};

pub const TypeB = enum {
    install,
    list,
    delete,
};

pub const TypeC = enum {
    ziglang,
    mach,
    local,
};

// Type D => Cartesian product of B and C (struct type containing combinations as fields)
pub const TypeD = Set.cartesianProduct(TypeB, TypeC);

// Transform Type A enum to union then to struct
pub const TypeAStruct = Set.unionToStruct(Set.enumToUnion(TypeA, void));

// Joint representation of A and D (struct type)
pub const AppStateLayout = Set.join(TypeAStruct, TypeD);

// UniverseEnum (Type E) is the enum generated from the keys of AppStateLayout
pub const UniverseEnum = enum {
    help,
    version,
    env,
    install_ziglang,
    install_mach,
    install_local,
    list_ziglang,
    list_mach,
    list_local,
    delete_ziglang,
    delete_mach,
    delete_local,
};

pub const Command = union(UniverseEnum) {
    help: void,
    version: void,
    env: void,

    install_ziglang: []const u8,
    install_mach: []const u8,
    install_local: []const u8,
    list_ziglang: void,
    list_mach: void,
    list_local: void,
    delete_ziglang: []const u8,
    delete_mach: []const u8,
    delete_local: []const u8,
};
