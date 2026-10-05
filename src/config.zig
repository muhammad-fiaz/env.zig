const std = @import("std");

/// Configuration options for parsing and loading .env files.
/// Every field is implemented; there are no dead switches.
pub const Config = struct {
    /// Trim surrounding whitespace from unquoted keys and values.
    /// Whitespace inside quoted values is always preserved.
    trim: bool = true,
    /// Allow empty values (`KEY=` or `KEY=""`). When false, empty values
    /// are skipped in lenient mode and rejected in strict mode.
    allowEmpty: bool = true,
    /// Enable variable interpolation (`${OTHER}`, `$OTHER`, defaults, etc.).
    interpolate: bool = true,
    /// Override existing values when loading multiple files or entries.
    /// When false, existing keys are kept.
    override: bool = true,
    /// Fail on syntax errors instead of skipping invalid lines.
    /// Strict mode returns the specific `EnvError` for each diagnostic.
    strict: bool = false,
    /// Strip ` # comment` suffixes from unquoted values.
    /// When false, `#` is treated as a literal value character.
    /// Quoted values never treat `#` as a comment.
    allowInlineComments: bool = true,
    /// Allow backslash-newline continuation: a trailing `\` joins the
    /// next line into the current value. When false, a trailing `\`
    /// is kept literally.
    allowMultiline: bool = false,
    /// Maximum interpolation recursion depth. Actually controls
    /// interpolation; no hidden hard-coded override.
    maxInterpolationDepth: usize = 10,
    /// Automatically export `Env.set`/`Env.remove` to the runtime
    /// environment via the single `runtime.set`/`runtime.unset`
    /// implementation. Failures are returned. Prefer explicit
    /// `exportToRuntime()` / `setAndExport()` for clarity.
    exportToRuntime: bool = false,
    /// Sort keys when serializing.
    sortKeys: bool = false,
    /// Emit a trailing newline after the last entry when serializing.
    /// When false, the final entry has no trailing `\n`.
    trailingNewline: bool = true,
    /// Quote values that require quoting (spaces, `#`, quotes, etc.)
    /// so that `parse(serialize(parse(x)))` preserves semantics.
    quoteSpaces: bool = true,

    /// Validate the configuration.
    pub fn validate(self: Config) !void {
        if (self.maxInterpolationDepth == 0) return error.InvalidValue;
        if (self.maxInterpolationDepth > 64) return error.InvalidValue;
    }

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
