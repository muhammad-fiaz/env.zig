const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const token = @import("token.zig");
const config = @import("config.zig");
const errors = @import("errors.zig");
const helpers = @import("internal/helpers.zig");

const Token = token.Token;
const TokenType = token.TokenType;
const Config = config.Config;
const Diagnostic = errors.Diagnostic;

/// A parsed key-value entry from a .env file.
pub const Entry = struct {
    key: []const u8,
    value: []const u8,
    /// The original line number where this entry was defined.
    line: usize,
};

/// Options for parsing a .env file.
pub const ParseOptions = struct {
    config: Config = .{},
    /// Optional file path for error messages.
    filePath: ?[]const u8 = null,
};

/// Result of parsing a .env file.
pub const ParseResult = struct {
    entries: std.ArrayList(Entry),
    errorsList: std.ArrayList(Diagnostic),

    pub fn deinit(self: *ParseResult, allocator: std.mem.Allocator) void {
        for (self.entries.items) |entry| {
            allocator.free(entry.key);
            allocator.free(entry.value);
        }
        self.entries.deinit(allocator);
        for (self.errorsList.items) |*diag| {
            if (diag.file) |f| allocator.free(f);
            if (diag.token) |t| allocator.free(t);
            if (diag.suggestion) |s| allocator.free(s);
        }
        self.errorsList.deinit(allocator);
    }

    pub fn hasErrors(self: *const ParseResult) bool {
        return self.errorsList.items.len > 0;
    }

    pub fn getEntries(self: *const ParseResult) []const Entry {
        return self.entries.items;
    }
};

/// Parse a .env file content string into key-value entries.
///
/// Supported syntax:
/// `KEY=value`, `KEY=` (empty), `KEY=""`, `KEY='v'`, ``KEY=`v` ``,
/// `export KEY=value`, full-line comments, inline ` # comment` suffixes
/// (when `allowInlineComments`), backslash-newline continuation (when
/// `allowMultiline`), CRLF/LF, quoted escapes, `=` inside values and
/// Unicode values. Comment characters inside quotes are literal.
pub fn parse(
    allocator: std.mem.Allocator,
    source: []const u8,
    options: ParseOptions,
) (std.mem.Allocator.Error || errors.EnvError)!ParseResult {
    try options.config.validate();
    var result = ParseResult{
        .entries = .empty,
        .errorsList = .empty,
    };
    errdefer {
        for (result.entries.items) |entry| {
            allocator.free(entry.key);
            allocator.free(entry.value);
        }
        result.entries.deinit(allocator);
        for (result.errorsList.items) |*diag| {
            if (diag.file) |f| allocator.free(f);
            if (diag.token) |t| allocator.free(t);
            if (diag.suggestion) |s| allocator.free(s);
        }
        result.errorsList.deinit(allocator);
    }

    var lexer = Lexer.init(source);

    while (true) {
        const tok = lexer.next();
        switch (tok.type) {
            .eof => break,
            .newline => continue,
            .comment => continue,
            .whitespace => continue,
            .key => {
                var keyText = tok.slice;
                var keyLine = tok.line;
                var keyCol = tok.column;
                if (std.mem.eql(u8, keyText, "export")) {
                    var nxt = lexer.next();
                    while (nxt.type == .whitespace) nxt = lexer.next();
                    if (nxt.type != .key) {
                        if (nxt.type == .eof or nxt.type == .newline or nxt.type == .comment) continue;
                        const diag = Diagnostic{
                            .kind = .parseError,
                            .file = options.filePath,
                            .line = nxt.line,
                            .column = nxt.column,
                            .explanation = "expected key after 'export'",
                        };
                        try addDiagnostic(allocator, &result, diag);
                        if (options.config.strict) return errors.diagnosticToError(diag);
                        skipToNewline(&lexer);
                        continue;
                    }
                    keyText = nxt.slice;
                    keyLine = nxt.line;
                    keyCol = nxt.column;
                }

                if (std.mem.indexOfScalar(u8, keyText, 0) != null or !helpers.isValidKey(keyText)) {
                    const diag = Diagnostic{
                        .kind = .invalidKey,
                        .file = options.filePath,
                        .line = keyLine,
                        .column = keyCol,
                        .token = keyText,
                        .explanation = "invalid key name",
                        .suggestion = "keys must start with a letter or underscore and contain only alphanumeric characters and underscores",
                    };
                    try addDiagnostic(allocator, &result, diag);
                    if (options.config.strict) return errors.diagnosticToError(diag);
                    skipToNewline(&lexer);
                    continue;
                }

                var eq = lexer.next();
                if (eq.type == .whitespace) eq = lexer.next();

                if (eq.type != .equals) {
                    const diag = Diagnostic{
                        .kind = .parseError,
                        .file = options.filePath,
                        .line = eq.line,
                        .column = eq.column,
                        .explanation = "expected '=' after key",
                    };
                    try addDiagnostic(allocator, &result, diag);
                    if (options.config.strict) return errors.diagnosticToError(diag);
                    skipToNewline(&lexer);
                    continue;
                }

                const collected = try collectValue(allocator, &lexer, options, &result);
                var value: []const u8 = collected;

                if (options.config.trim) {
                    value = std.mem.trim(u8, value, " \t\r\n");
                }

                if (std.mem.indexOfScalar(u8, value, 0) != null) {
                    const diag = Diagnostic{
                        .kind = .invalidValue,
                        .file = options.filePath,
                        .line = keyLine,
                        .explanation = "value contains embedded NUL byte",
                    };
                    try addDiagnostic(allocator, &result, diag);
                    allocator.free(collected);
                    if (options.config.strict) return errors.diagnosticToError(diag);
                    continue;
                }

                if (value.len == 0 and !options.config.allowEmpty) {
                    const diag = Diagnostic{
                        .kind = .invalidValue,
                        .file = options.filePath,
                        .line = keyLine,
                        .explanation = "empty value not allowed",
                        .suggestion = "set a value or use allowEmpty = true",
                    };
                    try addDiagnostic(allocator, &result, diag);
                    allocator.free(collected);
                    if (options.config.strict) return errors.diagnosticToError(diag);
                    continue;
                }

                const ownedValue: []const u8 = if (value.len == collected.len)
                    collected
                else blk: {
                    const duped = try allocator.dupe(u8, value);
                    allocator.free(collected);
                    break :blk duped;
                };
                errdefer allocator.free(ownedValue);
                const ownedKey = try allocator.dupe(u8, keyText);
                errdefer allocator.free(ownedValue);
                try result.entries.append(allocator, .{ .key = ownedKey, .value = ownedValue, .line = keyLine });
            },
            else => {
                skipToNewline(&lexer);
            },
        }
    }

    return result;
}

/// Collect a value after `=` up to end of line.
/// Returns an owned slice. Records diagnostics into `result`; in strict
/// mode returns the specific `EnvError` for unterminated quotes.
fn collectValue(
    allocator: std.mem.Allocator,
    lexer: *Lexer,
    options: ParseOptions,
    result: *ParseResult,
) (std.mem.Allocator.Error || errors.EnvError)![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);

    while (true) {
        const t = lexer.next();
        switch (t.type) {
            .eof, .newline => {
                if (t.type == .newline and options.config.allowMultiline and buf.items.len > 0 and buf.items[buf.items.len - 1] == '\\') {
                    // Backslash continuation: drop `\` + newline, join next line.
                    _ = buf.pop();
                    while (true) {
                        const peek = lexer.peek();
                        if (peek.type == .whitespace) {
                            _ = lexer.next();
                        } else break;
                    }
                    continue;
                }
                break;
            },
            .comment => {
                if (options.config.allowInlineComments) {
                    break;
                } else {
                    try buf.appendSlice(allocator, t.slice);
                }
            },
            .value, .whitespace, .interpolation, .equals => {
                try buf.appendSlice(allocator, t.slice);
            },
            .quotedValue => {
                if (!isClosedQuote(t.slice, '"')) {
                    const diag = Diagnostic{
                        .kind = .unterminatedQuote,
                        .file = options.filePath,
                        .line = t.line,
                        .column = t.column,
                        .token = t.slice,
                        .explanation = "unterminated double quote",
                        .suggestion = "close the quote with \"",
                    };
                    try addDiagnostic(allocator, result, diag);
                    if (options.config.strict) {
                        buf.deinit(allocator);
                        return errors.diagnosticToError(diag);
                    }
                    const inner = stripOpenQuote(t.slice);
                    const un = try helpers.unescape(allocator, inner);
                    defer allocator.free(un);
                    try buf.appendSlice(allocator, un);
                } else {
                    const un = try helpers.unescape(allocator, removeQuotes(t.slice, '"'));
                    defer allocator.free(un);
                    try buf.appendSlice(allocator, un);
                }
            },
            .singleQuotedValue => {
                if (!isClosedQuote(t.slice, '\'')) {
                    const diag = Diagnostic{
                        .kind = .unterminatedQuote,
                        .file = options.filePath,
                        .line = t.line,
                        .column = t.column,
                        .token = t.slice,
                        .explanation = "unterminated single quote",
                        .suggestion = "close the quote with '",
                    };
                    try addDiagnostic(allocator, result, diag);
                    if (options.config.strict) {
                        buf.deinit(allocator);
                        return errors.diagnosticToError(diag);
                    }
                }
                try buf.appendSlice(allocator, removeQuotesAllowUnterminated(t.slice, '\''));
            },
            .backtickQuotedValue => {
                if (!isClosedQuote(t.slice, '`')) {
                    const diag = Diagnostic{
                        .kind = .unterminatedQuote,
                        .file = options.filePath,
                        .line = t.line,
                        .column = t.column,
                        .token = t.slice,
                        .explanation = "unterminated backtick quote",
                        .suggestion = "close the quote with `",
                    };
                    try addDiagnostic(allocator, result, diag);
                    if (options.config.strict) {
                        buf.deinit(allocator);
                        return errors.diagnosticToError(diag);
                    }
                }
                try buf.appendSlice(allocator, removeQuotesAllowUnterminated(t.slice, '`'));
            },
            .key => {
                try buf.appendSlice(allocator, t.slice);
            },
            else => break,
        }
    }
    return try buf.toOwnedSlice(allocator);
}

fn addDiagnostic(
    allocator: std.mem.Allocator,
    result: *ParseResult,
    diag: Diagnostic,
) !void {
    var d = diag;
    if (d.file) |f| d.file = try allocator.dupe(u8, f);
    if (d.token) |t| d.token = try allocator.dupe(u8, t);
    if (d.suggestion) |s| d.suggestion = try allocator.dupe(u8, s);
    try result.errorsList.append(allocator, d);
}

fn removeQuotes(slice: []const u8, quote: u8) []const u8 {
    if (slice.len < 2) return slice;
    if (slice[0] == quote and slice[slice.len - 1] == quote) {
        return slice[1 .. slice.len - 1];
    }
    return slice;
}

fn isClosedQuote(slice: []const u8, quote: u8) bool {
    return slice.len >= 2 and slice[0] == quote and slice[slice.len - 1] == quote;
}

fn stripOpenQuote(slice: []const u8) []const u8 {
    if (slice.len >= 1 and (slice[0] == '"' or slice[0] == '\'' or slice[0] == '`')) {
        return slice[1..];
    }
    return slice;
}

fn removeQuotesAllowUnterminated(slice: []const u8, quote: u8) []const u8 {
    if (slice.len == 0) return slice;
    const start: usize = if (slice[0] == quote) @as(usize, 1) else 0;
    const end: usize = if (slice.len >= 2 and slice[slice.len - 1] == quote) slice.len - 1 else slice.len;
    if (start >= end) return "";
    return slice[start..end];
}

fn skipToNewline(lexer: *Lexer) void {
    while (true) {
        const tok = lexer.next();
        if (tok.type == .newline or tok.type == .eof) break;
    }
}

test "parse simple key-value" {
    var result = try parse(std.testing.allocator, "KEY=value\n", .{});
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), result.entries.items.len);
    try std.testing.expectEqualStrings("KEY", result.entries.items[0].key);
    try std.testing.expectEqualStrings("value", result.entries.items[0].value);
}

test "parse quoted value" {
    var result = try parse(std.testing.allocator, "KEY=\"hello world\"\n", .{});
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), result.entries.items.len);
    try std.testing.expectEqualStrings("hello world", result.entries.items[0].value);
}

test "parse comment" {
    var result = try parse(std.testing.allocator, "# comment\nKEY=value\n", .{});
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), result.entries.items.len);
    try std.testing.expectEqualStrings("KEY", result.entries.items[0].key);
}

test "parse multiple entries" {
    const src =
        \\KEY1=value1
        \\KEY2=value2
        \\KEY3=value3
    ;
    var result = try parse(std.testing.allocator, src, .{});
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), result.entries.items.len);
}

test "parse strict mode rejects invalid key" {
    const result = parse(std.testing.allocator, "123BAD=value\n", .{
        .config = .{ .strict = true },
    });
    try std.testing.expectError(error.InvalidKey, result);
}

test "parse double-quoted value with escape sequences" {
    var result = try parse(std.testing.allocator, "KEY=\"hello\\nworld\"\n", .{});
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), result.entries.items.len);
    try std.testing.expectEqualStrings("hello\nworld", result.entries.items[0].value);
}

test "parse single-quoted value without escape processing" {
    var result = try parse(std.testing.allocator, "KEY='hello\\nworld'\n", .{});
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), result.entries.items.len);
    try std.testing.expectEqualStrings("hello\\nworld", result.entries.items[0].value);
}

test "parse inline comment" {
    var result = try parse(std.testing.allocator, "KEY=value # this is a comment\n", .{});
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), result.entries.items.len);
    try std.testing.expectEqualStrings("value", result.entries.items[0].value);
}

test "parse various comment styles" {
    var result = try parse(std.testing.allocator, "# full line comment\nKEY=value\n", .{});
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), result.entries.items.len);
    try std.testing.expectEqualStrings("KEY", result.entries.items[0].key);
    try std.testing.expectEqualStrings("value", result.entries.items[0].value);
}

test "parse empty value" {
    var result = try parse(std.testing.allocator, "KEY=\n", .{});
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), result.entries.items.len);
    try std.testing.expectEqualStrings("", result.entries.items[0].value);
}

test "parse empty value does not swallow next entry" {
    var result = try parse(std.testing.allocator, "EMPTY=\nPRESENT=value\n", .{});
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), result.entries.items.len);
    try std.testing.expectEqualStrings("EMPTY", result.entries.items[0].key);
    try std.testing.expectEqualStrings("", result.entries.items[0].value);
    try std.testing.expectEqualStrings("PRESENT", result.entries.items[1].key);
    try std.testing.expectEqualStrings("value", result.entries.items[1].value);
}

test "parse value with spaces preserves unquoted trailing words" {
    var result = try parse(std.testing.allocator, "KEY=hello world\n", .{});
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), result.entries.items.len);
    try std.testing.expectEqualStrings("hello world", result.entries.items[0].value);
}

test "parse double-quoted value with spaces" {
    var result = try parse(std.testing.allocator, "KEY=\"hello world\"\n", .{});
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), result.entries.items.len);
    try std.testing.expectEqualStrings("hello world", result.entries.items[0].value);
}

test "parse various escape sequences" {
    var result = try parse(std.testing.allocator, "KEY=\"tab\\there\\\\done\"\n", .{});
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), result.entries.items.len);
    // Input after Zig string unescaping is KEY="tab\there\\done";
    // \t decodes to a tab and \\ decodes to a backslash.
    try std.testing.expectEqualStrings("tab\there\\done", result.entries.items[0].value);
}

test "parse backtick value without escape processing" {
    var result = try parse(std.testing.allocator, "KEY=`hello\\nworld`\n", .{});
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), result.entries.items.len);
    try std.testing.expectEqualStrings("hello\\nworld", result.entries.items[0].value);
}
