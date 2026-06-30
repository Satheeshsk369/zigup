const std = @import("std");
const builtin = @import("builtin");
const IndexMod = @import("index.zig");
const Allocating = std.Io.Writer.Allocating;

const Schema = @import("schema.zig");
const Mirror = IndexMod.Mirror;

fn getTarget() []const u8 {
    const arch = @tagName(builtin.target.cpu.arch);
    const os = @tagName(builtin.target.os.tag);
    return arch ++ "-" ++ os;
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    var index: IndexMod.Index = .init(gpa, init.io);
    defer index.deinit();

    var buffer: Allocating = .init(gpa);
    defer buffer.deinit();

    const ind1 = try index.fetch(Mirror[1], &buffer);
    const json = buffer.written();
    if (ind1 == .ok) std.log.info("Status: {s}", .{@tagName(ind1)});

    const schema = try Schema.Type.parse(gpa, json);
    defer schema.deinit();

    var it = schema.parsed.value.map.iterator();
    while (it.next()) |entry| {
        std.debug.print("Version: {s}, Date: {s}\n", .{ entry.key_ptr.*, entry.value_ptr.date });
    }
}
