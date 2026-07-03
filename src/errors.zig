const std = @import("std");

/// The kind of error that occurred during env operations.
pub const ErrorKind = enum {
    /// The file could not be read.
    file_not_found,
    /// The file could not be read due to permissions.
    permission_denied,
    /// A syntax error was encountered during parsing.
    parse_error,
    /// An invalid key was encountered.
    invalid_key,
    /// An invalid value was encountered.
    invalid_value,
    /// An unquoted string contains whitespace.
    unquoted_whitespace,
    /// A quote was not closed.
    unterminated_quote,
    /// An escape sequence is invalid.
    invalid_escape,
    /// Interpolation has a circular dependency.
    circular_dependency,
    /// Maximum interpolation depth exceeded.
    max_depth_exceeded,
    /// A required key is missing.
    missing_required,
    /// A value failed validation.
    validation_failed,
    /// The value could not be converted to the requested type.
    type_mismatch,
    /// An I/O error occurred.
    io_error,
    /// An allocation failed.
    out_of_memory,
    /// The operation is not supported.
    not_supported,
    /// Invalid configuration.
    invalid_config,
};

/// A diagnostic error with rich context for env operations.
pub const Diagnostic = struct {
    kind: ErrorKind,
    /// The file path where the error occurred, if applicable.
    file: ?[]const u8 = null,
    /// The line number (1-based) where the error occurred, if applicable.
    line: ?usize = null,
    /// The column number (1-based) where the error occurred, if applicable.
    column: ?usize = null,
    /// The offending token or text, if applicable.
    token: ?[]const u8 = null,
    /// Human-readable explanation of the error.
    explanation: []const u8 = "",
    /// Suggested fix for the error, if available.
    suggestion: ?[]const u8 = null,

    pub fn format(
        self: Diagnostic,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.writeAll("env error: ");
        try writer.writeAll(@tagName(self.kind));

        if (self.file) |file| {
            try writer.writeAll(" in ");
            try writer.writeAll(file);
        }
        if (self.line) |line| {
            try writer.print(" at line {d}", .{line});
            if (self.column) |col| {
                try writer.print(":{d}", .{col});
            }
        }
        if (self.token) |token| {
            try writer.writeAll(" near '");
            try writer.writeAll(token);
            try writer.writeAll("'");
        }
        if (self.explanation.len > 0) {
            try writer.writeAll(": ");
            try writer.writeAll(self.explanation);
        }
        if (self.suggestion) |suggestion| {
            try writer.writeAll(" (suggestion: ");
            try writer.writeAll(suggestion);
            try writer.writeAll(")");
        }
    }
};

/// Error union type used throughout the library.
pub const EnvError = error{
    FileNotFound,
    PermissionDenied,
    ParseError,
    InvalidKey,
    InvalidValue,
    UnquotedWhitespace,
    UnterminatedQuote,
    InvalidEscape,
    CircularDependency,
    MaxDepthExceeded,
    MissingRequired,
    ValidationFailed,
    TypeMismatch,
    IoError,
    OutOfMemory,
    NotSupported,
    InvalidConfig,
};

/// Convert a Diagnostic to an EnvError.
pub fn diagnosticToError(diag: Diagnostic) EnvError {
    return switch (diag.kind) {
        .file_not_found => error.FileNotFound,
        .permission_denied => error.PermissionDenied,
        .parse_error => error.ParseError,
        .invalid_key => error.InvalidKey,
        .invalid_value => error.InvalidValue,
        .unquoted_whitespace => error.UnquotedWhitespace,
        .unterminated_quote => error.UnterminatedQuote,
        .invalid_escape => error.InvalidEscape,
        .circular_dependency => error.CircularDependency,
        .max_depth_exceeded => error.MaxDepthExceeded,
        .missing_required => error.MissingRequired,
        .validation_failed => error.ValidationFailed,
        .type_mismatch => error.TypeMismatch,
        .io_error => error.IoError,
        .out_of_memory => error.OutOfMemory,
        .not_supported => error.NotSupported,
        .invalid_config => error.InvalidConfig,
    };
}

test "Diagnostic format" {
    const diag = Diagnostic{
        .kind = .parse_error,
        .file = ".env",
        .line = 5,
        .column = 12,
        .explanation = "unterminated quote",
    };
    var buf: [256]u8 = undefined;
    const result = std.fmt.bufPrint(&buf, "{}", .{diag}) catch return;
    try std.testing.expect(result.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, result, "parse_error") != null);
}

test "diagnosticToError" {
    const diag = Diagnostic{ .kind = .file_not_found };
    const err = diagnosticToError(diag);
    try std.testing.expectEqual(error.FileNotFound, err);
}
