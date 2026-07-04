const std = @import("std");
const color = @import("color.zig");

pub fn print(use_color: bool) void {
    const c_hdr = if (use_color) "\x1b[36m" else "";
    const c_cmd = if (use_color) "\x1b[33m" else "";
    const c_arg = if (use_color) "\x1b[37m" else "";
    const c_rst = if (use_color) "\x1b[0m" else "";
    const c_dim = if (use_color) "\x1b[90m" else "";

    std.debug.print("{s}commands:{s}\n", .{ c_hdr, c_rst });
    std.debug.print("  {s}fetch{s} {s}<index>{s}   {s}download a release{s}\n", .{ c_cmd, c_rst, c_arg, c_rst, c_dim, c_rst });
    std.debug.print("  {s}delete{s} {s}<index>{s}  {s}remove a downloaded release{s}\n", .{ c_cmd, c_rst, c_arg, c_rst, c_dim, c_rst });
    std.debug.print("  {s}help{s}           {s}show this help{s}\n", .{ c_cmd, c_rst, c_dim, c_rst });
    std.debug.print("  {s}q{s}              {s}quit{s}\n", .{ c_cmd, c_rst, c_dim, c_rst });
}
