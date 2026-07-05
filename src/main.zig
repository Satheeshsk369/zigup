const std = @import("std");
const builtin = @import("builtin");
const Allocating = std.Io.Writer.Allocating;

const Schema = @import("schema.zig");

fn getTarget() []const u8 {
    const arch = @tagName(builtin.target.cpu.arch);
    const os = @tagName(builtin.target.os.tag);
    return arch ++ "-" ++ os;
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    var index: Schema.Index = .init(gpa, init.io);
    defer index.deinit();

    var ziglang_buf: Allocating = .init(gpa);
    defer ziglang_buf.deinit();
    _ = try index.fetch(.ziglang, &ziglang_buf);
    const ziglang_schema = try Schema.Type.parse(gpa, ziglang_buf.written());
    defer ziglang_schema.deinit();

    var mach_buf: Allocating = .init(gpa);
    defer mach_buf.deinit();
    _ = try index.fetch(.mach, &mach_buf);
    const mach_schema = try Schema.Type.parse(gpa, mach_buf.written());
    defer mach_schema.deinit();

    var buf: [100][]const u8 = undefined;
    const unique_versions = Schema.diff(mach_schema, ziglang_schema, &buf);

    for (unique_versions) |version| {
        std.debug.print(" - {s}\n", .{version});
    }
    std.debug.print("Total unique versions: {d}\n", .{unique_versions.len});
    std.debug.print("----------------------------------------\n\n", .{});
}
