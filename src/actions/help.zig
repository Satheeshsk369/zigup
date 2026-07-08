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
        const usage = if (entry.argLabel) |lbl| entry.verb ++ " " ++ lbl else entry.verb;
        std.debug.print("  {s:<20} {s}\n", .{ usage, entry.description });
        if (std.mem.eql(u8, entry.verb, "install")) {
            std.debug.print("    --mirror=<name>    Select index mirror configured in config.zon\n", .{});
            std.debug.print("    --url=<url>        Specify custom JSON index URL directly\n", .{});
        }
    }
    std.debug.print("\n", .{});
}
