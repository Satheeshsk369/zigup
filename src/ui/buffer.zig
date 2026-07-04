const std = @import("std");

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

pub const TableBuffer = struct {
    status_col: usize,
    status_width: usize,
    n_rows: usize,

    const padding_left: usize = 2;
    const padding_right: usize = 2;
    const vert_width: usize = 1;

    pub fn init(col_widths: [4]usize, n_rows: usize) TableBuffer {
        var col: usize = vert_width;
        for (0..3) |ci| col += padding_left + col_widths[ci] + padding_right + vert_width;
        col += vert_width + padding_left;
        return .{
            .status_col = col,
            .status_width = col_widths[3],
            .n_rows = n_rows,
        };
    }

    pub fn patch(self: TableBuffer, row_idx: usize, status_str: []const u8) void {
        if (row_idx >= self.n_rows) return;
        const vis = visibleLen(status_str);
        const total_spaces = if (self.status_width >= vis) self.status_width - vis else 0;
        const left_pad = total_spaces / 2;
        const right_pad = total_spaces - left_pad;
        std.debug.print("\x1b[s", .{});
        std.debug.print("\x1b[{d}A", .{self.n_rows - row_idx + 3});
        std.debug.print("\x1b[{d}G", .{self.status_col});
        var i: usize = 0;
        while (i < self.status_width + padding_right) : (i += 1) std.debug.print(" ", .{});
        std.debug.print("\x1b[{d}G", .{self.status_col});
        var j: usize = 0;
        while (j < left_pad) : (j += 1) std.debug.print(" ", .{});
        std.debug.print("{s}", .{status_str});
        var k: usize = 0;
        while (k < right_pad) : (k += 1) std.debug.print(" ", .{});
        std.debug.print("\x1b[u", .{});
    }
};

pub const ReplBuffer = struct {
    pub fn init() ReplBuffer {
        std.debug.print("\n", .{});
        return .{};
    }
    pub fn log(self: ReplBuffer, comptime fmt: []const u8, args: anytype) void {
        _ = self;
        std.debug.print("\x1b[1G\x1b[2K", .{});
        std.debug.print(fmt, args);
    }
};
