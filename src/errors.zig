const std = @import("std");

/// The kind of error that occurred during env operations.
pub const ErrorKind = enum {
    /// The file could not be found.
    fileNotFound,
    /// The file could not be read due to permissions.
    permissionDenied,
    /// A syntax error was encountered during parsing.
    parseError,
    /// An invalid key was encountered.
    invalidKey,
    /// An invalid value was encountered.
    invalidValue,
    /// An unquoted value contains whitespace (strict mode only).
    unquotedWhitespace,
    /// A quote was not closed.
    unterminatedQuote,
    /// An escape sequence is invalid.
    invalidEscape,
    /// Interpolation has a circular dependency.
    circularDependency,
    /// Maximum interpolation depth exceeded.
    maxDepthExceeded,
    /// A required key is missing.
    missingRequired,
    /// The value could not be converted to the requested type.
    typeMismatch,
    /// An I/O error occurred.
    ioError,
    /// An allocation failed.
    outOfMemory,
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
/// Only errors that can actually be returned are listed.
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
    TypeMismatch,
    IoError,
    OutOfMemory,
};

/// Convert a Diagnostic to an EnvError.
pub fn diagnosticToError(diag: Diagnostic) EnvError {
    return switch (diag.kind) {
        .fileNotFound => error.FileNotFound,
        .permissionDenied => error.PermissionDenied,
        .parseError => error.ParseError,
        .invalidKey => error.InvalidKey,
        .invalidValue => error.InvalidValue,
        .unquotedWhitespace => error.UnquotedWhitespace,
        .unterminatedQuote => error.UnterminatedQuote,
        .invalidEscape => error.InvalidEscape,
        .circularDependency => error.CircularDependency,
        .maxDepthExceeded => error.MaxDepthExceeded,
        .missingRequired => error.MissingRequired,
        .typeMismatch => error.TypeMismatch,
        .ioError => error.IoError,
        .outOfMemory => error.OutOfMemory,
    };
}

test "Diagnostic format" {
    const diag = Diagnostic{
        .kind = .parseError,
        .file = ".env",
        .line = 5,
        .column = 12,
        .explanation = "unterminated quote",
    };
    var buf: [256]u8 = undefined;
    const result = std.fmt.bufPrint(&buf, "{}", .{diag}) catch return;
    try std.testing.expect(result.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, result, "parseError") != null);
}

test "diagnosticToError" {
    const diag = Diagnostic{ .kind = .fileNotFound };
    const err = diagnosticToError(diag);
    try std.testing.expectEqual(error.FileNotFound, err);
}
