const std = @import("std");
const color = @import("color.zig");
const out = @import("out.zig");

fn visibleLen(s: []const u8) usize {
    var len: usize = 0;
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '\x1b' and i + 1 < s.len and s[i + 1] == '[') {
            i += 2;
            while (i < s.len and s[i] != 'm') : (i += 1) {}
            if (i < s.len) i += 1;
        } else {
            len += 1;
            i += 1;
        }
    }
    return len;
}

pub const Alignment = enum {
    left,
    center,
    right,
};

pub const BorderStyle = enum {
    ascii,
    unicode_single,
    unicode_double,
};

pub const Config = struct {
    padding_left: usize = 2,
    padding_right: usize = 2,
    border_style: BorderStyle = .ascii,
};

fn getAlign(comptime field_name: []const u8, comptime T: type) Alignment {
    if (std.mem.eql(u8, field_name, "index")) return .center;
    if (std.mem.eql(u8, field_name, "status")) return .center;
    return switch (@typeInfo(T)) {
        .int, .comptime_int, .float, .comptime_float => .right,
        else => .left,
    };
}

pub fn print(allocator: std.mem.Allocator, io: std.Io, comptime T: type, slice: []const T) !void {
    try printConfig(allocator, io, T, slice, .{});
}

pub fn printMeasured(
    allocator: std.mem.Allocator,
    io: std.Io,
    comptime T: type,
    slice: []const T,
) ![std.meta.fields(T).len]usize {
    const fields = std.meta.fields(T);
    var col_widths: [fields.len]usize = undefined;
    inline for (fields, 0..) |field, ci| col_widths[ci] = field.name.len;
    var buf2: [256]u8 = undefined;
    for (slice) |row| {
        inline for (fields, 0..) |field, ci| {
            const val = @field(row, field.name);
            const slen: usize = blk: {
                if (@typeInfo(field.type) == .pointer) {
                    const p = @typeInfo(field.type).pointer;
                    if (p.size == .slice and p.child == u8) break :blk visibleLen(val);
                }
                const text = std.fmt.bufPrint(&buf2, "{}", .{val}) catch "";
                break :blk text.len;
            };
            col_widths[ci] = @max(col_widths[ci], slen);
        }
    }
    try printConfig(allocator, io, T, slice, .{});
    return col_widths;
}

pub fn printConfig(allocator: std.mem.Allocator, io: std.Io, comptime T: type, slice: []const T, config: Config) !void {
    const fields = std.meta.fields(T);
    var col_widths: [fields.len]usize = undefined;

    inline for (fields, 0..) |field, col_idx| {
        col_widths[col_idx] = field.name.len;
    }

    var buf: [256]u8 = undefined;
    for (slice) |row| {
        inline for (fields, 0..) |field, col_idx| {
            const val = @field(row, field.name);
            const str_len = blk: {
                if (@typeInfo(field.type) == .pointer) {
                    const p = @typeInfo(field.type).pointer;
                    if (p.size == .slice and p.child == u8) {
                        break :blk visibleLen(val);
                    }
                }
                const text = std.fmt.bufPrint(&buf, "{}", .{val}) catch "";
                break :blk text.len;
            };
            col_widths[col_idx] = @max(col_widths[col_idx], str_len);
        }
    }

    const stdout = std.Io.File.stdout();
    const use_color = color.isTerminal(stdout, io);

    const c_border = if (use_color) color.gray else "";
    const c_header = if (use_color) color.cyan else "";
    const c_reset = if (use_color) color.reset else "";
    const c_val = if (use_color) color.white else "";
    const c_idx = if (use_color) color.yellow else "";

    const BorderSet = struct {
        top_left: []const u8,
        top_mid: []const u8,
        top_right: []const u8,
        mid_left: []const u8,
        mid_mid: []const u8,
        mid_right: []const u8,
        bot_left: []const u8,
        bot_mid: []const u8,
        bot_right: []const u8,
        horiz: []const u8,
        vert: []const u8,
    };

    const b = switch (config.border_style) {
        .ascii => BorderSet{
            .top_left = "+",
            .top_mid = "+",
            .top_right = "+",
            .mid_left = "+",
            .mid_mid = "+",
            .mid_right = "+",
            .bot_left = "+",
            .bot_mid = "+",
            .bot_right = "+",
            .horiz = "-",
            .vert = "|",
        },
        .unicode_single => BorderSet{
            .top_left = "┌",
            .top_mid = "┬",
            .top_right = "┐",
            .mid_left = "├",
            .mid_mid = "┼",
            .mid_right = "┤",
            .bot_left = "└",
            .bot_mid = "┴",
            .bot_right = "┘",
            .horiz = "─",
            .vert = "│",
        },
        .unicode_double => BorderSet{
            .top_left = "╔",
            .top_mid = "╦",
            .top_right = "╗",
            .mid_left = "╠",
            .mid_mid = "╬",
            .mid_right = "╣",
            .bot_left = "╚",
            .bot_mid = "╩",
            .bot_right = "╝",
            .horiz = "═",
            .vert = "║",
        },
    };

    const printLine = struct {
        fn run(widths: []const usize, cfg: Config, left: []const u8, mid: []const u8, right: []const u8, horiz: []const u8, color_prefix: []const u8) void {
            out.print("{s}{s}", .{ color_prefix, left });
            for (widths, 0..) |w, col_idx| {
                var i: usize = 0;
                while (i < w + cfg.padding_left + cfg.padding_right) : (i += 1) {
                    out.print("{s}", .{horiz});
                }
                if (col_idx < widths.len - 1) {
                    out.print("{s}", .{mid});
                } else {
                    out.print("{s}\n", .{right});
                }
            }
        }
    }.run;

    const printSpaces = struct {
        fn run(n: usize) void {
            var i: usize = 0;
            while (i < n) : (i += 1) {
                out.print(" ", .{});
            }
        }
    }.run;

    printLine(&col_widths, config, b.top_left, b.top_mid, b.top_right, b.horiz, c_border);

    out.print("{s}{s}{s}", .{ c_border, b.vert, c_reset });
    inline for (fields, 0..) |field, col_idx| {
        const w = col_widths[col_idx];
        const total_spaces = w - field.name.len;
        const left_spaces = total_spaces / 2;
        const right_spaces = total_spaces - left_spaces;
        printSpaces(config.padding_left + left_spaces);
        out.print("{s}{s}{s}", .{ c_header, field.name, c_reset });
        printSpaces(config.padding_right + right_spaces);
        out.print("{s}{s}{s}", .{ c_border, b.vert, c_reset });
    }
    out.print("\n", .{});

    printLine(&col_widths, config, b.mid_left, b.mid_mid, b.mid_right, b.horiz, c_border);

    for (slice) |row| {
        out.print("{s}{s}{s}", .{ c_border, b.vert, c_reset });
        inline for (fields, 0..) |field, col_idx| {
            const w = col_widths[col_idx];
            const val = @field(row, field.name);
            const str = switch (@typeInfo(field.type)) {
                .pointer => |p| if (p.size == .slice and p.child == u8) val else try std.fmt.allocPrint(allocator, "{}", .{val}),
                .int, .comptime_int => try std.fmt.allocPrint(allocator, "{d}", .{val}),
                else => try std.fmt.allocPrint(allocator, "{}", .{val}),
            };
            defer {
                if (@typeInfo(field.type) != .pointer or (@typeInfo(field.type) == .pointer and @typeInfo(field.type).pointer.child != u8)) {
                    allocator.free(str);
                }
            }

            const current_color = if (std.mem.eql(u8, field.name, "index")) c_idx else c_val;
            const alignment = getAlign(field.name, field.type);

            const total_spaces = w - visibleLen(str);
            switch (alignment) {
                .left => {
                    printSpaces(config.padding_left);
                    out.print("{s}{s}{s}", .{ current_color, str, c_reset });
                    printSpaces(total_spaces + config.padding_right);
                },
                .right => {
                    printSpaces(config.padding_left + total_spaces);
                    out.print("{s}{s}{s}", .{ current_color, str, c_reset });
                    printSpaces(config.padding_right);
                },
                .center => {
                    const left_spaces = total_spaces / 2;
                    const right_spaces = total_spaces - left_spaces;
                    printSpaces(config.padding_left + left_spaces);
                    out.print("{s}{s}{s}", .{ current_color, str, c_reset });
                    printSpaces(config.padding_right + right_spaces);
                },
            }
            out.print("{s}{s}{s}", .{ c_border, b.vert, c_reset });
        }
        out.print("\n", .{});
    }

    printLine(&col_widths, config, b.bot_left, b.bot_mid, b.bot_right, b.horiz, c_border);
    out.print("{s}", .{c_reset});
}
