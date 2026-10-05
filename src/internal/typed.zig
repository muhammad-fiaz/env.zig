const std = @import("std");

/// Single source of truth for typed string conversion.
/// Used by both `Env` and `runtime` so the same string parses
/// identically regardless of where it was obtained.
pub fn parseBoolValue(val: []const u8) ?bool {
    const v = std.mem.trim(u8, val, " \t\r\n");
    var buf: [16]u8 = undefined;
    if (v.len > buf.len) return null;
    for (v, 0..) |ch, i| buf[i] = std.ascii.toLower(ch);
    const lower = buf[0..v.len];
    if (std.mem.eql(u8, lower, "true") or std.mem.eql(u8, lower, "yes") or
        std.mem.eql(u8, lower, "1") or std.mem.eql(u8, lower, "on"))
        return true;
    if (std.mem.eql(u8, lower, "false") or std.mem.eql(u8, lower, "no") or
        std.mem.eql(u8, lower, "0") or std.mem.eql(u8, lower, "off"))
        return false;
    return null;
}

pub fn parseIntValue(comptime T: type, val: []const u8) ?T {
    return std.fmt.parseInt(T, std.mem.trim(u8, val, " \t\r\n"), 10) catch null;
}

pub fn parseFloatValue(comptime T: type, val: []const u8) ?T {
    return std.fmt.parseFloat(T, std.mem.trim(u8, val, " \t\r\n")) catch null;
}

pub fn parseEnumValue(comptime E: type, val: []const u8) ?E {
    return std.meta.stringToEnum(E, std.mem.trim(u8, val, " \t\r\n"));
}
