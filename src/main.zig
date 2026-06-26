const std = @import("std");
const builtin = @import("builtin");

fn getTarget() []const u8 {
    const arch = @tagName(builtin.target.cpu.arch);
    const os = @tagName(builtin.target.os.tag);
    return arch ++ "-" ++ os;
}

pub fn main(init: std.process.Init) !void {
    _ = init;
    std.debug.print("{s}", .{getTarget()});
}
