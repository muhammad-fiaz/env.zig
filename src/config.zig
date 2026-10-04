const std = @import("std");

/// Configuration options for parsing and loading .env files.
pub const Config = struct {
    /// Whether to trim whitespace from keys and values.
    trim: bool = true,
    /// Whether to allow empty values (KEY= or KEY="").
    allowEmpty: bool = true,
    /// Whether to enable variable interpolation (KEY=${OTHER}).
    interpolate: bool = true,
    /// Whether to override existing values when loading multiple files.
    override: bool = true,
    /// Whether to fail on syntax errors instead of skipping invalid lines.
    strict: bool = false,
    /// Whether to allow inline comments (# comment after value).
    allowInlineComments: bool = true,
    /// Whether to allow multiline values (backslash continuation).
    allowMultiline: bool = false,
    /// Maximum interpolation recursion depth.
    maxInterpolationDepth: usize = 10,
    /// Comment character.
    commentChar: u8 = '#',
    /// Whether to export loaded values to the process environment.
    exportToEnv: bool = false,
    /// Whether to preserve comments when serializing.
    preserveComments: bool = false,
    /// Whether to sort keys when serializing.
    sortKeys: bool = false,
    /// Indentation for serialized output (number of spaces).
    indent: usize = 0,
    /// Whether to add a trailing newline when writing.
    trailingNewline: bool = true,
    /// Whether to quote values that contain spaces when writing.
    quoteSpaces: bool = true,

    /// Builder-style configuration.
    pub fn with(self: Config, overrides: anytype) Config {
        var result = self;
        const info = @typeInfo(@TypeOf(overrides));
        if (info != .@"struct") @compileError("expected a struct");
        inline for (info.@"struct".field_names) |name| {
            if (@hasField(Config, name)) {
                @field(result, name) = @field(overrides, name);
            }
        }
        return result;
    }
};

test "Config defaults" {
    const cfg = Config{};
    try std.testing.expect(cfg.trim);
    try std.testing.expect(cfg.allowEmpty);
    try std.testing.expect(cfg.interpolate);
    try std.testing.expect(cfg.override);
    try std.testing.expect(!cfg.strict);
    try std.testing.expect(cfg.allowInlineComments);
    try std.testing.expect(!cfg.allowMultiline);
    try std.testing.expectEqual(@as(usize, 10), cfg.maxInterpolationDepth);
}

test "Config with builder" {
    const base = Config{};
    const cfg = base.with(.{
        .strict = true,
        .trim = false,
        .maxInterpolationDepth = 5,
    });
    try std.testing.expect(cfg.strict);
    try std.testing.expect(!cfg.trim);
    try std.testing.expectEqual(@as(usize, 5), cfg.maxInterpolationDepth);
    try std.testing.expect(cfg.allowEmpty);
}
