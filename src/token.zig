const std = @import("std");

/// Token types for .env file parsing.
pub const TokenType = enum {
    /// A key name (e.g., KEY).
    key,
    /// An equals sign (=).
    equals,
    /// An unquoted value (e.g., value).
    value,
    /// A double-quoted value (e.g., "value").
    quoted_value,
    /// A single-quoted value (e.g., 'value').
    single_quoted_value,
    /// A backtick-quoted value (e.g., `value`).
    backtick_quoted_value,
    /// A comment line starting with #.
    comment,
    /// An inline comment after a value.
    inline_comment,
    /// A newline character.
    newline,
    /// End of file.
    eof,
    /// An interpolation reference (e.g., ${KEY}).
    interpolation,
    /// An escape sequence (e.g., \n, \t).
    escape_sequence,
    /// A whitespace character.
    whitespace,
};

/// A single token from the lexer.
pub const Token = struct {
    type: TokenType,
    /// The raw text of the token.
    slice: []const u8,
    /// The line number (1-based) where this token starts.
    line: usize,
    /// The column number (1-based) where this token starts.
    column: usize,
};

test "Token type names" {
    try std.testing.expectEqualStrings("key", @tagName(TokenType.key));
    try std.testing.expectEqualStrings("equals", @tagName(TokenType.equals));
    try std.testing.expectEqualStrings("value", @tagName(TokenType.value));
    try std.testing.expectEqualStrings("eof", @tagName(TokenType.eof));
}
