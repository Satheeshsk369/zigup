const std = @import("std");
const StructField = std.builtin.Type.StructField;

pub const Op = enum {
    Union,
    Intersection,
    Difference,
};

pub const Options = struct {
    assign_null_for_optional: bool = false,
};

fn contains(fields: []const StructField, name: []const u8) bool {
    @setEvalBranchQuota(@max(1000, fields.len * 10));
    for (fields) |f| {
        if (std.mem.eql(u8, f.name, name)) return true;
    }
    return false;
}

fn count(comptime op: Op, comptime a: []const StructField, comptime b: []const StructField) usize {
    @setEvalBranchQuota(@max(1000, a.len * b.len * 5));
    switch (op) {
        .Union => {
            var c = a.len;
            for (b) |field_b| {
                if (!contains(a, field_b.name)) {
                    c += 1;
                }
            }
            return c;
        },
        .Intersection => {
            var c = 0;
            for (a) |field_a| {
                if (contains(b, field_a.name)) {
                    c += 1;
                }
            }
            return c;
        },
        .Difference => {
            var c = 0;
            for (a) |field_a| {
                if (!contains(b, field_a.name)) {
                    c += 1;
                }
            }
            return c;
        },
    }
}

pub fn Union(comptime A: type, comptime B: type) type {
    comptime {
        const fields_a = std.meta.fields(A);
        const fields_b = std.meta.fields(B);
        const union_size = count(.Union, fields_a, fields_b);

        @setEvalBranchQuota(@max(1000, fields_a.len * fields_b.len * 10));
        var merged: [union_size]StructField = undefined;
        @memcpy(merged[0..fields_a.len], fields_a);

        var index = fields_a.len;
        for (fields_b) |field_b| {
            if (!contains(fields_a, field_b.name)) {
                merged[index] = field_b;
                index += 1;
            }
        }

        return Struct(&merged);
    }
}

pub fn Intersection(comptime A: type, comptime B: type) type {
    comptime {
        const fields_a = std.meta.fields(A);
        const fields_b = std.meta.fields(B);
        const intersect_size = count(.Intersection, fields_a, fields_b);

        @setEvalBranchQuota(@max(1000, fields_a.len * fields_b.len * 10));
        var merged: [intersect_size]StructField = undefined;
        var index = 0;
        for (fields_a) |field_a| {
            if (contains(fields_b, field_a.name)) {
                merged[index] = field_a;
                index += 1;
            }
        }

        return Struct(&merged);
    }
}

pub fn Difference(comptime A: type, comptime B: type) type {
    comptime {
        const fields_a = std.meta.fields(A);
        const fields_b = std.meta.fields(B);
        const diff_size = count(.Difference, fields_a, fields_b);

        @setEvalBranchQuota(@max(1000, fields_a.len * fields_b.len * 10));
        var merged: [diff_size]StructField = undefined;
        var index = 0;
        for (fields_a) |field_a| {
            if (!contains(fields_b, field_a.name)) {
                merged[index] = field_a;
                index += 1;
            }
        }

        return Struct(&merged);
    }
}

pub fn UnionToStruct(comptime U: type, comptime opt: Options) type {
    comptime {
        const info = @typeInfo(U);
        if (info != .@"union") {
            @compileError("UnionToStruct expects a union type, got: " ++ @typeName(U));
        }

        var struct_fields: [info.@"union".fields.len]StructField = undefined;
        for (info.@"union".fields, 0..) |f, i| {
            const is_optional = @typeInfo(f.type) == .optional;
            const default_val = if (opt.assign_null_for_optional and is_optional) &@as(f.type, null) else null;
            struct_fields[i] = .{
                .name = f.name,
                .type = f.type,
                .default_value_ptr = @ptrCast(default_val),
                .is_comptime = false,
                .alignment = @alignOf(f.type),
            };
        }

        return Struct(&struct_fields);
    }
}

pub fn StructToUnion(comptime S: type) type {
    comptime {
        const fields = std.meta.fields(S);
        var names: [fields.len][:0]const u8 = undefined;
        var values: [fields.len]comptime_int = undefined;
        for (fields, 0..) |f, i| {
            names[i] = f.name;
            values[i] = i;
        }

        const Tag = @Enum(u16, .auto, &names, &values);
        var types: [fields.len]type = undefined;
        var attrs: [fields.len]std.builtin.Type.UnionField.Attributes = undefined;
        for (fields, 0..) |f, i| {
            types[i] = f.type;
            attrs[i] = .{ .@"align" = f.alignment };
        }

        return @Union(.auto, Tag, &names, &types, &attrs);
    }
}

pub fn EnumToUnion(comptime E: type, comptime T: anytype) type {
    comptime {
        const info = @typeInfo(E);
        if (info != .@"enum") {
            @compileError("EnumToUnion expects an enum type, got: " ++ @typeName(E));
        }
        if (info.@"enum".fields.len != T.len) {
            @compileError("EnumToUnion requires payload type count to match enum tag count");
        }

        var names: [T.len][:0]const u8 = undefined;
        var types: [T.len]type = undefined;
        var attrs: [T.len]std.builtin.Type.UnionField.Attributes = undefined;
        for (info.@"enum".fields, 0..) |f, i| {
            names[i] = f.name;
            types[i] = T[i];
            attrs[i] = .{ .@"align" = @alignOf(type) };
        }

        return @Union(.auto, E, &names, &types, &attrs);
    }
}

pub fn EnumToUnionConst(comptime E: type, comptime T: type) type {
    comptime {
        const info = @typeInfo(E);
        if (info != .@"enum") {
            @compileError("EnumToUnionConst expects an enum type, got: " ++ @typeName(E));
        }

        var types: [info.@"enum".fields.len]type = undefined;
        for (0..info.@"enum".fields.len) |i| {
            types[i] = T;
        }

        return EnumToUnion(E, &types);
    }
}

pub fn UnionToEnum(comptime U: type) type {
    comptime {
        const info = @typeInfo(U);
        if (info != .@"union") {
            @compileError("UnionToEnum expects a union type, got: " ++ @typeName(U));
        }

        const tag_type = info.@"union".tag_type orelse @compileError("UnionToEnum expects a tagged union");
        return tag_type;
    }
}

fn Struct(comptime fields: []const StructField) type {
    comptime {
        @setEvalBranchQuota(@max(2000, fields.len * 20));
        var names: [fields.len][:0]const u8 = undefined;
        var types: [fields.len]type = undefined;
        var attrs: [fields.len]std.builtin.Type.StructField.Attributes = undefined;

        for (fields, 0..) |f, i| {
            names[i] = f.name;
            types[i] = f.type;
            attrs[i] = .{
                .@"align" = f.alignment,
                .default_value_ptr = f.default_value_ptr,
            };
        }

        return @Struct(.auto, null, &names, &types, &attrs);
    }
}
