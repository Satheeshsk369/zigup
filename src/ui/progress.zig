const std = @import("std");
const out = @import("out.zig");

pub const Progress = struct {
    use_color: bool,
    active: bool,

    pub fn init(use_color: bool) Progress {
        return .{ .use_color = use_color, .active = false };
    }

    pub fn begin(self: *Progress) void {
        self.active = true;
        out.print("\n", .{});
    }

    pub fn update(self: *Progress, downloaded: u64, total: ?u64, elapsed_ns: u64) void {
        if (!self.active) return;

        const bar_width: usize = 30;
        const c_bar = if (self.use_color) "\x1b[34m" else "";
        const c_pct = if (self.use_color) "\x1b[37m" else "";
        const c_spd = if (self.use_color) "\x1b[90m" else "";
        const c_rst = if (self.use_color) "\x1b[0m" else "";

        const elapsed_s = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
        const speed = if (elapsed_s > 0)
            @as(f64, @floatFromInt(downloaded)) / elapsed_s
        else
            0.0;

        out.print("\x1b[1G\x1b[2K", .{});

        if (total) |t| {
            const pct: usize = if (t > 0) @intCast(@min(100, downloaded * 100 / t)) else 0;
            const filled: usize = bar_width * pct / 100;

            out.print("{s}[", .{c_bar});
            var i: usize = 0;
            while (i < filled) : (i += 1) out.print("=", .{});
            if (filled < bar_width) {
                out.print(">", .{});
                i += 1;
            }
            while (i < bar_width) : (i += 1) out.print(" ", .{});
            const spd_str = fmtSize(speed);
            out.print("]{s} {s}{d:>3}%{s}  {s}{s}/s{s}", .{
                c_rst, c_pct, pct, c_rst, c_spd, std.mem.trimEnd(u8, &spd_str, " "), c_rst,
            });
        } else {
            const kb = downloaded / 1024;
            out.print("{s}[", .{c_bar});
            var i: usize = 0;
            const spin = "=-";
            const frame: usize = (downloaded / 4096) % spin.len;
            while (i < bar_width) : (i += 1) out.print("{c}", .{spin[if (i == bar_width / 2) frame else 0]});
            const spd_str = fmtSize(speed);
            out.print("]{s}  {s}{d} KB{s}  {s}{s}/s{s}", .{
                c_rst, c_pct, kb, c_rst, c_spd, std.mem.trimEnd(u8, &spd_str, " "), c_rst,
            });
        }
        out.flush();
    }

    pub fn end(self: *Progress) void {
        if (!self.active) return;
        out.print("\x1b[1G\x1b[2K\x1b[1A", .{});
        out.flush();
        self.active = false;
    }
};

fn fmtSize(bytes_per_sec: f64) [12]u8 {
    var buf: [12]u8 = .{' '} ** 12;
    if (bytes_per_sec >= 1024 * 1024) {
        _ = std.fmt.bufPrint(&buf, "{d:.1} MB", .{bytes_per_sec / (1024 * 1024)}) catch {};
    } else if (bytes_per_sec >= 1024) {
        _ = std.fmt.bufPrint(&buf, "{d:.1} KB", .{bytes_per_sec / 1024}) catch {};
    } else {
        _ = std.fmt.bufPrint(&buf, "{d:.0} B", .{bytes_per_sec}) catch {};
    }
    return buf;
}
