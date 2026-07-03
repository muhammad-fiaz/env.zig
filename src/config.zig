const std = @import("std");

/// Configuration options for parsing and loading .env files.
pub const Config = struct {
    /// Whether to trim whitespace from keys and values.
    trim: bool = true,
    /// Whether to allow empty values (KEY= or KEY="").
    allow_empty: bool = true,
    /// Whether to enable variable interpolation (KEY=${OTHER}).
    interpolate: bool = true,
    /// Whether to override existing values when loading multiple files.
    override: bool = true,
    /// Whether to fail on syntax errors instead of skipping invalid lines.
    strict: bool = false,
    /// Whether to allow inline comments (# comment after value).
    allow_inline_comments: bool = true,
    /// Whether to allow multiline values (backslash continuation).
    allow_multiline: bool = false,
    /// Maximum interpolation recursion depth.
    max_interpolation_depth: usize = 10,
    /// Comment character.
    comment_char: u8 = '#',
    /// Whether to export loaded values to the process environment.
    export_to_env: bool = false,
    /// Whether to preserve comments when serializing.
    preserve_comments: bool = false,
    /// Whether to sort keys when serializing.
    sort_keys: bool = false,
    /// Indentation for serialized output (number of spaces).
    indent: usize = 0,
    /// Whether to add a trailing newline when writing.
    trailing_newline: bool = true,
    /// Whether to quote values that contain spaces when writing.
    quote_spaces: bool = true,

    /// Builder-style configuration.
    pub fn with(self: Config, overrides: anytype) Config {
        var result = self;
        const info = @typeInfo(@TypeOf(overrides));
        if (info != .@"struct") @compileError("expected a struct");
        inline for (info.@"struct".fields) |field| {
            if (@hasField(Config, field.name)) {
                @field(result, field.name) = @field(overrides, field.name);
            }
        }
        return result;
    }
};

test "Config defaults" {
    const cfg = Config{};
    try std.testing.expect(cfg.trim);
    try std.testing.expect(cfg.allow_empty);
    try std.testing.expect(cfg.interpolate);
    try std.testing.expect(cfg.override);
    try std.testing.expect(!cfg.strict);
    try std.testing.expect(cfg.allow_inline_comments);
    try std.testing.expect(!cfg.allow_multiline);
    try std.testing.expectEqual(@as(usize, 10), cfg.max_interpolation_depth);
}

test "Config with builder" {
    var cfg = Config{};
    cfg = cfg.with(.{
        .strict = true,
        .trim = false,
        .max_interpolation_depth = 5,
    });
    try std.testing.expect(cfg.strict);
    try std.testing.expect(!cfg.trim);
    try std.testing.expectEqual(@as(usize, 5), cfg.max_interpolation_depth);
    try std.testing.expect(cfg.allow_empty);
}
