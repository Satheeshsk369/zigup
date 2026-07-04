const std = @import("std");

pub const Progress = struct {
    use_color: bool,
    active: bool,

    pub fn init(use_color: bool) Progress {
        return .{ .use_color = use_color, .active = false };
    }

    /// Call after printing the status message (no trailing newline needed there).
    /// Moves to a fresh bar line below the message and leaves the cursor there.
    pub fn begin(self: *Progress) void {
        self.active = true;
        std.debug.print("\n", .{});
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

        // Overwrite the bar line in place: go to col 1, erase line, redraw.
        // No cursor-up — the cursor is already on the bar line.
        std.debug.print("\x1b[1G\x1b[2K", .{});

        if (total) |t| {
            const pct: usize = if (t > 0) @intCast(@min(100, downloaded * 100 / t)) else 0;
            const filled: usize = bar_width * pct / 100;

            std.debug.print("{s}[", .{c_bar});
            var i: usize = 0;
            while (i < filled) : (i += 1) std.debug.print("=", .{});
            if (filled < bar_width) {
                std.debug.print(">", .{});
                i += 1;
            }
            while (i < bar_width) : (i += 1) std.debug.print(" ", .{});
            std.debug.print("]{s} {s}{d:>3}%{s}  {s}{s}/s{s}", .{
                c_rst, c_pct, pct, c_rst, c_spd, fmtSize(speed), c_rst,
            });
        } else {
            const kb = downloaded / 1024;
            std.debug.print("{s}[", .{c_bar});
            var i: usize = 0;
            const spin = "=-";
            const frame: usize = (downloaded / 4096) % spin.len;
            while (i < bar_width) : (i += 1) std.debug.print("{c}", .{spin[if (i == bar_width / 2) frame else 0]});
            std.debug.print("]{s}  {s}{d} KB{s}  {s}{s}/s{s}", .{
                c_rst, c_pct, kb, c_rst, c_spd, fmtSize(speed), c_rst,
            });
        }
    }

    /// Erase the bar line and move cursor back up to the message line.
    /// After this, repl.log can overwrite the message line cleanly.
    pub fn end(self: *Progress) void {
        if (!self.active) return;
        std.debug.print("\x1b[1G\x1b[2K\x1b[1A", .{});
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
