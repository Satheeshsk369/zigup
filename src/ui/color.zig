const std = @import("std");
const builtin = @import("builtin");

pub const reset = "\x1b[0m";

pub const gray = "\x1b[90m";
pub const red = "\x1b[31m";
pub const green = "\x1b[32m";
pub const yellow = "\x1b[33m";
pub const blue = "\x1b[34m";
pub const magenta = "\x1b[35m";
pub const cyan = "\x1b[36m";
pub const white = "\x1b[37m";
pub fn isTerminal(file: std.Io.File, io: std.Io) bool {
    return file.isTty(io) catch false;
}
