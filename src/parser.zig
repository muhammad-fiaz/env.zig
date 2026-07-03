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
    file_path: ?[]const u8 = null,
};

/// Result of parsing a .env file.
pub const ParseResult = struct {
    entries: std.ArrayList(Entry),
    errors_list: std.ArrayList(Diagnostic),

    pub fn deinit(self: *ParseResult, allocator: std.mem.Allocator) void {
        for (self.entries.items) |entry| {
            allocator.free(entry.key);
            allocator.free(entry.value);
        }
        self.entries.deinit(allocator);
        for (self.errors_list.items) |*diag| {
            if (diag.file) |f| allocator.free(f);
            if (diag.token) |t| allocator.free(t);
            if (diag.suggestion) |s| allocator.free(s);
        }
        self.errors_list.deinit(allocator);
    }

    pub fn hasErrors(self: *const ParseResult) bool {
        return self.errors_list.items.len > 0;
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
        .errors_list = .empty,
    };
    errdefer {
        for (result.entries.items) |entry| {
            allocator.free(entry.key);
            allocator.free(entry.value);
        }
        result.entries.deinit(allocator);
        for (result.errors_list.items) |*diag| {
            if (diag.file) |f| allocator.free(f);
            if (diag.token) |t| allocator.free(t);
            if (diag.suggestion) |s| allocator.free(s);
        }
        result.errors_list.deinit(allocator);
    }

    var lexer = Lexer.init(source, options.config);

    while (true) {
        const tok = lexer.next();
        switch (tok.type) {
            .eof => break,
            .newline => continue,
            .comment => continue,
            .whitespace => continue,
            .key => {
                const key_text = tok.slice;
                const key_line = tok.line;

                if (!helpers.isValidKey(key_text)) {
                    try addDiagnostic(allocator, &result, .{
                        .kind = .invalid_key,
                        .file = options.file_path,
                        .line = tok.line,
                        .column = tok.column,
                        .token = key_text,
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
                        .file = options.file_path,
                        .line = eq.line,
                        .column = eq.column,
                        .explanation = "expected '=' after key",
                    });
                    if (options.config.strict) return error.ParseError;
                    skipToNewline(&lexer);
                    continue;
                }

                const val_tok = lexer.next();
                var value: []const u8 = switch (val_tok.type) {
                    .value => val_tok.slice,
                    .quoted_value => try processEscapes(allocator, removeQuotes(val_tok.slice, '"')),
                    .single_quoted_value => removeQuotes(val_tok.slice, '\''),
                    .backtick_quoted_value => removeQuotes(val_tok.slice, '`'),
                    .interpolation => blk: {
                        // Interpolation may be followed by more text (e.g. ${GREETING} world)
                        var full_value: std.ArrayList(u8) = .empty;
                        errdefer full_value.deinit(allocator);
                        try full_value.appendSlice(allocator, val_tok.slice);
                        while (true) {
                            const next = lexer.next();
                            switch (next.type) {
                                .value => try full_value.appendSlice(allocator, next.slice),
                                .whitespace => try full_value.appendSlice(allocator, next.slice),
                                .interpolation => try full_value.appendSlice(allocator, next.slice),
                                .newline, .eof => break,
                                else => break,
                            }
                        }
                        break :blk try full_value.toOwnedSlice(allocator);
                    },
                    .newline, .eof => "",
                    .comment => "",
                    else => {
                        try addDiagnostic(allocator, &result, .{
                            .kind = .invalid_value,
                            .file = options.file_path,
                            .line = val_tok.line,
                            .column = val_tok.column,
                            .token = try helpers.dupe(allocator, val_tok.slice),
                            .explanation = "unexpected token after '='",
                        });
                        if (options.config.strict) return error.ParseError;
                        skipToNewline(&lexer);
                        continue;
                    },
                };

                if (options.config.trim) {
                    value = helpers.trim(value);
                }

                if (value.len == 0 and !options.config.allow_empty) {
                    try addDiagnostic(allocator, &result, .{
                        .kind = .invalid_value,
                        .file = options.file_path,
                        .line = key_line,
                        .explanation = "empty value not allowed",
                        .suggestion = try helpers.dupe(allocator, "set a value or use allow_empty = true"),
                    });
                    if (options.config.strict) return error.ParseError;
                    skipToNewline(&lexer);
                    continue;
                }

                const entry = Entry{
                    .key = try helpers.dupe(allocator, key_text),
                    .value = try helpers.dupe(allocator, value),
                    .line = key_line,
                };

                // Free allocated value if it was allocated (not a source slice)
                if (val_tok.type == .interpolation or val_tok.type == .quoted_value) {
                    allocator.free(value);
                }

                try result.entries.append(allocator, entry);

                // skipToNewline only needed for non-interpolation values,
                // since interpolation handler already consumed until newline/eof
                if (val_tok.type != .interpolation) {
                    skipToNewline(&lexer);
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
    if (d.file) |f| d.file = try helpers.dupe(allocator, f);
    if (d.token) |t| d.token = try helpers.dupe(allocator, t);
    if (d.suggestion) |s| d.suggestion = try helpers.dupe(allocator, s);
    try result.errors_list.append(allocator, d);
}

fn removeQuotes(slice: []const u8, quote: u8) []const u8 {
    if (slice.len < 2) return slice;
    if (slice[0] == quote and slice[slice.len - 1] == quote) {
        return slice[1 .. slice.len - 1];
    }
    return slice;
}

/// Process escape sequences in a quoted value.
/// Supports: \n, \t, \r, \\, \", \', \`
fn processEscapes(allocator: std.mem.Allocator, slice: []const u8) ![]const u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < slice.len) {
        if (slice[i] == '\\' and i + 1 < slice.len) {
            const next = slice[i + 1];
            switch (next) {
                'n' => {
                    try result.append(allocator, '\n');
                    i += 2;
                },
                't' => {
                    try result.append(allocator, '\t');
                    i += 2;
                },
                'r' => {
                    try result.append(allocator, '\r');
                    i += 2;
                },
                '\\' => {
                    try result.append(allocator, '\\');
                    i += 2;
                },
                '"' => {
                    try result.append(allocator, '"');
                    i += 2;
                },
                '\'' => {
                    try result.append(allocator, '\'');
                    i += 2;
                },
                '`' => {
                    try result.append(allocator, '`');
                    i += 2;
                },
                '0' => {
                    try result.append(allocator, 0);
                    i += 2;
                },
                else => {
                    // Not a recognized escape, keep as-is
                    try result.append(allocator, slice[i]);
                    i += 1;
                },
            }
        } else {
            try result.append(allocator, slice[i]);
            i += 1;
        }
    }
    return try result.toOwnedSlice(allocator);
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
    // In Zig source: \\ becomes \ in the string literal
    // So the input string is: KEY="tab\there\\done"
    // After escape processing: \t → tab, \\ → \
    // Result: tab<tab>here\done
    try std.testing.expectEqualStrings("tab\there\\done", result.entries.items[0].value);
}

test "parse backtick value without escape processing" {
    var result = try parse(std.testing.allocator, "KEY=`hello\\nworld`\n", .{});
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), result.entries.items.len);
    try std.testing.expectEqualStrings("hello\\nworld", result.entries.items[0].value);
}
