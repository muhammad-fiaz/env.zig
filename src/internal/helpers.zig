const std = @import("std");

/// Check if a string is a valid .env key.
/// Valid keys start with a letter or underscore and contain only
/// alphanumeric characters and underscores. Covers all targets
/// (x86, x86_64, aarch64, 32/64-bit) uniformly — no arch-specific logic.
pub fn isValidKey(key: []const u8) bool {
    if (key.len == 0) return false;
    if (!std.ascii.isAlphabetic(key[0]) and key[0] != '_') return false;
    for (key[1..]) |ch| {
        if (!std.ascii.isAlphanumeric(ch) and ch != '_') return false;
    }
    return true;
}

/// Returns true if value needs quoting when serializing to .env.
/// Shared by serializer and writer — single source of truth.
pub fn needsQuoting(value: []const u8, quote_spaces: bool) bool {
    if (!quote_spaces) return false;
    return value.len == 0 or
        std.mem.indexOfScalar(u8, value, ' ') != null or
        std.mem.indexOfScalar(u8, value, '#') != null or
        std.mem.indexOfScalar(u8, value, '\n') != null or
        std.mem.indexOfScalar(u8, value, '\r') != null or
        std.mem.indexOfScalar(u8, value, '\t') != null;
}

/// Escaped representation for a single byte when writing quoted values.
/// Returns null if no escaping needed.
pub inline fn escapedForChar(ch: u8) ?[]const u8 {
    return switch (ch) {
        '"' => "\\\"",
        '\\' => "\\\\",
        '\n' => "\\n",
        '\r' => "\\r",
        '\t' => "\\t",
        else => null,
    };
}

/// Unescape a value string, processing escape sequences.
/// Supports: \n \r \t \\ \" \' \` \$ \0
/// Used by parser for double-quoted values — single source for unescaping.
pub fn unescape(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '\\' and i + 1 < input.len) {
            i += 1;
            const esc = input[i];
            const ch: u8 = switch (esc) {
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                '\\' => '\\',
                '"' => '"',
                '\'' => '\'',
                '`' => '`',
                '$' => '$',
                '0' => 0,
                else => esc,
            };
            try result.append(allocator, ch);
            i += 1;
        } else {
            try result.append(allocator, input[i]);
            i += 1;
        }
    }
    return try result.toOwnedSlice(allocator);
}

test "isValidKey" {
    try std.testing.expect(isValidKey("KEY"));
    try std.testing.expect(isValidKey("_KEY"));
    try std.testing.expect(isValidKey("key_123"));
    try std.testing.expect(!isValidKey(""));
    try std.testing.expect(!isValidKey("123KEY"));
    try std.testing.expect(!isValidKey("KEY-WITH-DASH"));
    try std.testing.expect(!isValidKey("KEY.WITH.DOT"));
}

test "needsQuoting" {
    try std.testing.expect(needsQuoting("", true));
    try std.testing.expect(needsQuoting("hello world", true));
    try std.testing.expect(needsQuoting("a#b", true));
    try std.testing.expect(!needsQuoting("hello", true));
    try std.testing.expect(!needsQuoting("hello world", false));
}

test "unescape" {
    const result = try unescape(std.testing.allocator, "hello\\nworld");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("hello\nworld", result);
}
