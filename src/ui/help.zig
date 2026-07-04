const std = @import("std");

pub fn print(use_color: bool) []const u8 {
    _ = use_color;
    return "fetch <n>  delete <n>  help  q";
}
