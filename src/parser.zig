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
pub fn parse(
    allocator: std.mem.Allocator,
    source: []const u8,
    options: ParseOptions,
) (std.mem.Allocator.Error || error{ParseError})!ParseResult {
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

    var lexer = Lexer.init(source, options.config);

    while (true) {
        var tok = lexer.next();
        switch (tok.type) {
            .eof => break,
            .newline => continue,
            .comment => continue,
            .whitespace => continue,
            .key => {
                var keyText = tok.slice;
                var keyLine = tok.line;
                // Handle `export KEY=value` prefix (shell compatibility).
                if (std.mem.eql(u8, keyText, "export")) {
                    var nxt = lexer.next();
                    while (nxt.type == .whitespace) nxt = lexer.next();
                    if (nxt.type != .key) {
                        if (nxt.type == .eof or nxt.type == .newline or nxt.type == .comment) continue;
                        try addDiagnostic(allocator, &result, .{
                            .kind = .parse_error,
                            .file = options.filePath,
                            .line = nxt.line,
                            .column = nxt.column,
                            .explanation = "expected key after 'export'",
                        });
                        if (options.config.strict) return error.ParseError;
                        skipToNewline(&lexer);
                        continue;
                    }
                    keyText = nxt.slice;
                    keyLine = nxt.line;
                    tok = nxt;
                }

                if (!helpers.isValidKey(keyText)) {
                    try addDiagnostic(allocator, &result, .{
                        .kind = .invalid_key,
                        .file = options.filePath,
                        .line = tok.line,
                        .column = tok.column,
                        .token = keyText,
                        .explanation = "invalid key name",
                        .suggestion = "keys must start with a letter or underscore and contain only alphanumeric characters and underscores",
                    });
                    if (options.config.strict) return error.ParseError;
                    skipToNewline(&lexer);
                    continue;
                }

                var eq = lexer.next();
                if (eq.type == .whitespace) {
                    eq = lexer.next();
                }

                if (eq.type != .equals) {
                    try addDiagnostic(allocator, &result, .{
                        .kind = .parse_error,
                        .file = options.filePath,
                        .line = eq.line,
                        .column = eq.column,
                        .explanation = "expected '=' after key",
                    });
                    if (options.config.strict) return error.ParseError;
                    skipToNewline(&lexer);
                    continue;
                }

                const valTok = lexer.next();
                var value: []const u8 = switch (valTok.type) {
                    .value => valTok.slice,
                    .quoted_value => try helpers.unescape(allocator, removeQuotes(valTok.slice, '"')),
                    .single_quoted_value => removeQuotes(valTok.slice, '\''),
                    .backtick_quoted_value => removeQuotes(valTok.slice, '`'),
                    .interpolation => blk: {
                        // Interpolation may be followed by more text (e.g. ${GREETING} world).
                        var fullValue: std.ArrayList(u8) = .empty;
                        errdefer fullValue.deinit(allocator);
                        try fullValue.appendSlice(allocator, valTok.slice);
                        while (true) {
                            const next = lexer.next();
                            switch (next.type) {
                                .value => try fullValue.appendSlice(allocator, next.slice),
                                .whitespace => try fullValue.appendSlice(allocator, next.slice),
                                .interpolation => try fullValue.appendSlice(allocator, next.slice),
                                .newline, .eof => break,
                                else => break,
                            }
                        }
                        break :blk try fullValue.toOwnedSlice(allocator);
                    },
                    .newline, .eof => "",
                    .comment => "",
                    else => {
                        try addDiagnostic(allocator, &result, .{
                            .kind = .invalid_value,
                            .file = options.filePath,
                            .line = valTok.line,
                            .column = valTok.column,
                            .token = valTok.slice,
                            .explanation = "unexpected token after '='",
                        });
                        if (options.config.strict) return error.ParseError;
                        skipToNewline(&lexer);
                        continue;
                    },
                };

                if (options.config.trim) {
                    value = std.mem.trim(u8, value, " \t\r\n");
                }

                if (value.len == 0 and !options.config.allowEmpty) {
                    try addDiagnostic(allocator, &result, .{
                        .kind = .invalid_value,
                        .file = options.filePath,
                        .line = keyLine,
                        .explanation = "empty value not allowed",
                        .suggestion = "set a value or use allowEmpty = true",
                    });
                    if (options.config.strict) return error.ParseError;
                    // Value already consumed (newline/eof), no need to skip.
                    // Free allocated value if needed
                    if (valTok.type == .interpolation or valTok.type == .quoted_value) {
                        allocator.free(value);
                    }
                    continue;
                }

                const entry = Entry{
                    .key = try allocator.dupe(u8, keyText),
                    .value = try allocator.dupe(u8, value),
                    .line = keyLine,
                };

                // Free allocated value if it was allocated (not a source slice).
                if (valTok.type == .interpolation or valTok.type == .quoted_value) {
                    allocator.free(value);
                }

                try result.entries.append(allocator, entry);

                // Advance to the next line, unless the value token already
                // consumed the line terminator (interpolation consumes until
                // newline/eof; newline/eof values are already terminated).
                // Without this guard, an empty `KEY=` line would swallow the
                // following entry.
                switch (valTok.type) {
                    .interpolation, .newline, .eof => {},
                    else => skipToNewline(&lexer),
                }
            },
            else => {
                skipToNewline(&lexer);
            },
        }
    }

    return result;
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
    try std.testing.expectError(error.ParseError, result);
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

test "parse value with spaces" {
    var result = try parse(std.testing.allocator, "KEY=hello world\n", .{});
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), result.entries.items.len);
    try std.testing.expectEqualStrings("hello", result.entries.items[0].value);
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
