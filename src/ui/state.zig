const std = @import("std");

pub const Status = enum {
    missing,
    fetching,
    downloaded,
    default,

    pub fn toString(self: Status, use_color: bool) []const u8 {
        if (use_color) {
            return switch (self) {
                .missing => "\x1b[90m-\x1b[0m",
                .fetching => "\x1b[34mfetching..\x1b[0m",
                .downloaded => "\x1b[31mdownloaded\x1b[0m",
                .default => "\x1b[32mdefault\x1b[0m",
            };
        } else {
            return switch (self) {
                .missing => "-",
                .fetching => "fetching..",
                .downloaded => "downloaded",
                .default => "default",
            };
        }
    }
};

pub const State = struct {
    statuses: []Status,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, n: usize) !State {
        const statuses = try allocator.alloc(Status, n);
        @memset(statuses, .missing);
        return .{ .statuses = statuses, .allocator = allocator };
    }

    pub fn deinit(self: *State) void {
        self.allocator.free(self.statuses);
    }

    pub fn set(self: *State, idx: usize, s: Status) void {
        if (idx < self.statuses.len) self.statuses[idx] = s;
    }

    pub fn get(self: *const State, idx: usize) Status {
        if (idx < self.statuses.len) return self.statuses[idx];
        return .missing;
    }
};
