const std = @import("std");
const command = @import("../command.zig");

pub fn run() void {
    std.debug.print(
        \\Usage:
        \\  zigup <command> [arguments]
        \\
        \\Commands:
        \\
    , .{});

    inline for (command.commands) |entry| {
        const alias = comptime blk: {
            if (std.mem.eql(u8, entry.verb, "help")) break :blk "-h help";
            if (std.mem.eql(u8, entry.verb, "version")) break :blk "-v version";
            if (std.mem.eql(u8, entry.verb, "env")) break :blk "-e env";
            if (std.mem.eql(u8, entry.verb, "install")) break :blk "-i install";
            if (std.mem.eql(u8, entry.verb, "delete")) break :blk "-d delete";
            if (std.mem.eql(u8, entry.verb, "list")) break :blk "-l list";
            break :blk entry.verb;
        };
        const usage = if (entry.argLabel) |lbl| alias ++ " " ++ lbl else alias;
        std.debug.print("  {s:<20} {s}\n", .{ usage, entry.description });
        if (std.mem.eql(u8, entry.verb, "install")) {
            std.debug.print("    --mirror=<name>    Select index mirror configured in config.zon\n", .{});
            std.debug.print("    --url=<url>        Specify custom JSON index URL directly\n", .{});
        }
    }
    std.debug.print("\n", .{});
}
