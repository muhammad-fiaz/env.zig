const std = @import("std");
const token = @import("token.zig");
const config = @import("config.zig");

const Token = token.Token;
const TokenType = token.TokenType;
const Config = config.Config;

/// A streaming lexer for .env files.
pub const Lexer = struct {
    source: []const u8,
    pos: usize,
    line: usize,
    col: usize,
    config: Config,

    pub fn init(source: []const u8, cfg: Config) Lexer {
        return .{
            .source = source,
            .pos = 0,
            .line = 1,
            .col = 1,
            .config = cfg,
        };
    }

    pub fn next(self: *Lexer) Token {
        if (self.pos >= self.source.len) {
            return .{
                .type = .eof,
                .slice = "",
                .line = self.line,
                .column = self.col,
            };
        }

        const start = self.pos;
        const start_line = self.line;
        const start_col = self.col;
        const ch = self.source[self.pos];

        if (ch == '\n' or ch == '\r') {
            if (ch == '\r' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '\n') {
                self.pos += 2;
                self.col = 1;
                self.line += 1;
            } else {
                self.pos += 1;
                self.col = 1;
                self.line += 1;
            }
            return .{
                .type = .newline,
                .slice = self.source[start..self.pos],
                .line = start_line,
                .column = start_col,
            };
        }

        if (ch == self.config.comment_char) {
            self.skipToEndOfLine();
            return .{
                .type = .comment,
                .slice = self.source[start..self.pos],
                .line = start_line,
                .column = start_col,
            };
        }

        if (std.ascii.isWhitespace(ch)) {
            while (self.pos < self.source.len and std.ascii.isWhitespace(self.source[self.pos]) and self.source[self.pos] != '\n' and self.source[self.pos] != '\r') {
                self.pos += 1;
                self.col += 1;
            }
            return .{
                .type = .whitespace,
                .slice = self.source[start..self.pos],
                .line = start_line,
                .column = start_col,
            };
        }

        if (ch == '=') {
            self.pos += 1;
            self.col += 1;
            return .{
                .type = .equals,
                .slice = self.source[start..self.pos],
                .line = start_line,
                .column = start_col,
            };
        }

        if (ch == '"') {
            return self.readQuoted(.quoted_value, '"');
        }

        if (ch == '\'') {
            return self.readQuoted(.single_quoted_value, '\'');
        }

        if (ch == '`') {
            return self.readQuoted(.backtick_quoted_value, '`');
        }

        if (ch == '$' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '{') {
            return self.readInterpolation();
        }

        return self.readUnquoted();
    }

    fn readQuoted(self: *Lexer, tt: TokenType, quote: u8) Token {
        const start = self.pos;
        const start_line = self.line;
        const start_col = self.col;
        self.pos += 1;
        self.col += 1;

        while (self.pos < self.source.len) {
            const ch = self.source[self.pos];
            if (ch == '\\' and self.pos + 1 < self.source.len) {
                self.pos += 2;
                self.col += 2;
            } else if (ch == quote) {
                self.pos += 1;
                self.col += 1;
                return .{
                    .type = tt,
                    .slice = self.source[start..self.pos],
                    .line = start_line,
                    .column = start_col,
                };
            } else if (ch == '\n' or ch == '\r') {
                if (ch == '\r' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '\n') {
                    self.pos += 2;
                    self.col = 1;
                    self.line += 1;
                } else {
                    self.pos += 1;
                    self.col = 1;
                    self.line += 1;
                }
            } else {
                self.pos += 1;
                self.col += 1;
            }
        }

        return .{
            .type = tt,
            .slice = self.source[start..self.pos],
            .line = start_line,
            .column = start_col,
        };
    }

    fn readInterpolation(self: *Lexer) Token {
        const start = self.pos;
        const start_line = self.line;
        const start_col = self.col;
        self.pos += 2;
        self.col += 2;

        while (self.pos < self.source.len and self.source[self.pos] != '}') {
            if (self.source[self.pos] == '\n' or self.source[self.pos] == '\r') {
                self.line += 1;
                self.col = 1;
            } else {
                self.col += 1;
            }
            self.pos += 1;
        }

        if (self.pos < self.source.len) {
            self.pos += 1;
            self.col += 1;
        }

        return .{
            .type = .interpolation,
            .slice = self.source[start..self.pos],
            .line = start_line,
            .column = start_col,
        };
    }

    fn readUnquoted(self: *Lexer) Token {
        const start = self.pos;
        const start_line = self.line;
        const start_col = self.col;

        while (self.pos < self.source.len) {
            const ch = self.source[self.pos];
            if (ch == '\n' or ch == '\r' or ch == '=' or ch == '#' or
                ch == '"' or ch == '\'' or ch == '`' or std.ascii.isWhitespace(ch))
            {
                break;
            }
            self.pos += 1;
            self.col += 1;
        }

        return .{
            .type = if (start == 0 or (start > 0 and self.source[start - 1] == '\n' or
                (start > 1 and self.source[start - 1] == '\r')))
                .key
            else
                .value,
            .slice = self.source[start..self.pos],
            .line = start_line,
            .column = start_col,
        };
    }

    fn skipToEndOfLine(self: *Lexer) void {
        while (self.pos < self.source.len and self.source[self.pos] != '\n' and self.source[self.pos] != '\r') {
            self.pos += 1;
            self.col += 1;
        }
    }

    pub fn peek(self: *const Lexer) Token {
        var copy = self.*;
        return copy.next();
    }
};

test "Lexer basic" {
    var lex = Lexer.init("KEY=value\n", .{});
    const tok = lex.next();
    try std.testing.expectEqual(TokenType.key, tok.type);
    try std.testing.expectEqualStrings("KEY", tok.slice);
}

test "Lexer quoted value" {
    var lex = Lexer.init("KEY=\"hello world\"\n", .{});
    _ = lex.next();
    const eq = lex.next();
    try std.testing.expectEqual(TokenType.equals, eq.type);
    const val = lex.next();
    try std.testing.expectEqual(TokenType.quoted_value, val.type);
    try std.testing.expectEqualStrings("\"hello world\"", val.slice);
}

test "Lexer comment" {
    var lex = Lexer.init("# this is a comment\n", .{});
    const tok = lex.next();
    try std.testing.expectEqual(TokenType.comment, tok.type);
}

test "Lexer interpolation" {
    var lex = Lexer.init("${KEY}", .{});
    const tok = lex.next();
    try std.testing.expectEqual(TokenType.interpolation, tok.type);
    try std.testing.expectEqualStrings("${KEY}", tok.slice);
}
