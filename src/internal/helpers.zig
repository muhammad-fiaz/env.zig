const std = @import("std");

/// Trim whitespace from both ends of a string.
pub fn trim(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\r\n");
}

/// Trim whitespace from the left side of a string.
pub fn trimLeft(s: []const u8) []const u8 {
    return std.mem.trimLeft(u8, s, " \t");
}

/// Trim whitespace from the right side of a string.
pub fn trimRight(s: []const u8) []const u8 {
    return std.mem.trimRight(u8, s, " \t\r");
}

/// Check if a string is a valid .env key.
/// Valid keys start with a letter or underscore and contain only
/// alphanumeric characters and underscores.
pub fn isValidKey(key: []const u8) bool {
    if (key.len == 0) return false;
    if (!std.ascii.isAlphabetic(key[0]) and key[0] != '_') return false;
    for (key[1..]) |ch| {
        if (!std.ascii.isAlphanumeric(ch) and ch != '_') return false;
    }
    return true;
}

/// Unescape a value string, processing escape sequences.
pub fn unescape(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '\\' and i + 1 < input.len) {
            i += 1;
            const escaped = input[i];
            const ch: u8 = switch (escaped) {
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                '\\' => '\\',
                '"' => '"',
                '\'' => '\'',
                '`' => '`',
                '$' => '$',
                '0' => 0,
                else => escaped,
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

/// Duplicate a string using the given allocator.
pub fn dupe(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    return try allocator.dupe(u8, s);
}

/// Check if a slice starts with a given prefix.
pub fn startsWith(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    return std.mem.startsWith(u8, haystack, needle);
}

/// Check if a slice ends with a given suffix.
pub fn endsWith(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    return std.mem.endsWith(u8, haystack, needle);
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

test "trim" {
    try std.testing.expectEqualStrings("hello", trim("  hello  "));
    try std.testing.expectEqualStrings("hello", trim("hello"));
    try std.testing.expectEqualStrings("", trim("   "));
}

test "unescape" {
    const result = try unescape(std.testing.allocator, "hello\\nworld");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("hello\nworld", result);
}

test "startsWith" {
    try std.testing.expect(startsWith("hello world", "hello"));
    try std.testing.expect(!startsWith("hello", "hello world"));
    try std.testing.expect(startsWith("", ""));
}
