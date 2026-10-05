const std = @import("std");
const typed = @import("internal/typed.zig");

/// A validation level.
pub const Level = enum {
    err,
    warning,
};

/// A validation error or warning.
/// `message` is borrowed (static or field description); only the outer
/// slice from `Schema.validate` needs freeing.
pub const ValidationError = struct {
    key: []const u8,
    message: []const u8,
    level: Level = .err,
};

/// A validator function that takes a value and returns null on success
/// or an error message on failure.
pub const ValidatorFn = *const fn (value: []const u8) ?[]const u8;

/// Built-in validators. Guarantees are documented per validator; they use
/// Zig standard-library parsing where applicable so they agree with the
/// typed getters (`getInt`, `getFloat`, ...).
pub const validators = struct {
    /// Value must not be empty.
    pub fn required(value: []const u8) ?[]const u8 {
        if (value.len == 0) return "value must not be empty";
        return null;
    }

    /// Value must be a valid boolean (true/false/yes/no/1/0/on/off,
    /// case-insensitive, surrounding whitespace ignored).
    /// Shares `internal/typed.zig` conversion with typed getters.
    pub fn boolean(value: []const u8) ?[]const u8 {
        if (std.mem.trim(u8, value, " \t\r\n").len == 0) return "value must not be empty";
        if (typed.parseBoolValue(value) != null) return null;
        return "value must be a valid boolean (true/false/yes/no/1/0/on/off)";
    }

    /// Value must be a valid integer. Shares `typed.parseIntValue`.
    pub fn integer(value: []const u8) ?[]const u8 {
        if (std.mem.trim(u8, value, " \t\r\n").len == 0) return "value must not be empty";
        if (typed.parseIntValue(i64, value) != null) return null;
        return "value must be a valid integer";
    }

    /// Value must be a valid float. Shares `typed.parseFloatValue`.
    pub fn float(value: []const u8) ?[]const u8 {
        if (std.mem.trim(u8, value, " \t\r\n").len == 0) return "value must not be empty";
        if (typed.parseFloatValue(f64, value) != null) return null;
        return "value must be a valid float";
    }

    /// Basic URL check: must start with `http://` or `https://`.
    /// Not a full URL parser.
    pub fn url(value: []const u8) ?[]const u8 {
        if (std.mem.startsWith(u8, value, "http://") or std.mem.startsWith(u8, value, "https://")) {
            return null;
        }
        return "value must be a valid URL starting with http:// or https://";
    }

    /// Basic email check (not RFC-compliant): exactly one `@`, non-empty
    /// local and domain parts, a `.` in the domain, no spaces.
    pub fn email(value: []const u8) ?[]const u8 {
        const v = std.mem.trim(u8, value, " \t\r\n");
        if (v.len == 0 or std.mem.indexOfScalar(u8, v, ' ') != null) return "value must be a valid email address";
        var parts = std.mem.splitScalar(u8, v, '@');
        const local = parts.next() orelse return "value must be a valid email address";
        const domain = parts.next() orelse return "value must be a valid email address";
        if (parts.next() != null) return "value must be a valid email address";
        if (local.len == 0 or domain.len == 0) return "value must be a valid email address";
        if (std.mem.indexOfScalar(u8, domain, '.') == null) return "value must be a valid email address";
        return null;
    }

    /// Value must be a valid IPv4 address (four 0-255 decimal octets).
    pub fn ipv4(value: []const u8) ?[]const u8 {
        const v = std.mem.trim(u8, value, " \t\r\n");
        var parts = std.mem.splitScalar(u8, v, '.');
        var count: usize = 0;
        while (parts.next()) |part| {
            count += 1;
            if (part.len == 0 or part.len > 3) return "value must be a valid IPv4 address";
            for (part) |ch| {
                if (!std.ascii.isDigit(ch)) return "value must be a valid IPv4 address";
            }
            _ = std.fmt.parseInt(u8, part, 10) catch return "value must be a valid IPv4 address";
        }
        if (count != 4) return "value must be a valid IPv4 address";
        return null;
    }

    /// Value must be a valid hostname: 1-253 chars, dot-separated labels of
    /// 1-63 alphanumerics/hyphens, labels may not start or end with `-`.
    pub fn hostname(value: []const u8) ?[]const u8 {
        const v = std.mem.trim(u8, value, " \t\r\n");
        if (v.len == 0 or v.len > 253) return "value must be a valid hostname";
        var labels = std.mem.splitScalar(u8, v, '.');
        var labelCount: usize = 0;
        while (labels.next()) |label| {
            labelCount += 1;
            if (label.len == 0 or label.len > 63) return "value must be a valid hostname";
            if (!std.ascii.isAlphanumeric(label[0]) or !std.ascii.isAlphanumeric(label[label.len - 1])) {
                return "hostname labels must start and end with an alphanumeric";
            }
            for (label) |ch| {
                if (!std.ascii.isAlphanumeric(ch) and ch != '-') return "hostname contains invalid characters";
            }
        }
        if (labelCount == 0) return "value must be a valid hostname";
        return null;
    }

    /// Value must be a valid port number (0-65535, no empty input).
    pub fn port(value: []const u8) ?[]const u8 {
        const v = std.mem.trim(u8, value, " \t\r\n");
        if (v.len == 0) return "value must not be empty";
        _ = std.fmt.parseInt(u16, v, 10) catch return "value must be a valid port number (0-65535)";
        return null;
    }

    /// Value must be within a numeric range.
    pub fn range(comptime minVal: i64, comptime maxVal: i64) ValidatorFn {
        return struct {
            pub fn validate(value: []const u8) ?[]const u8 {
                const num = std.fmt.parseInt(i64, value, 10) catch return "value must be a valid integer";
                if (num < minVal or num > maxVal) return "value is out of range";
                return null;
            }
        }.validate;
    }

    /// Value must have a minimum length.
    pub fn minLength(comptime minLen: usize) ValidatorFn {
        return struct {
            pub fn validate(value: []const u8) ?[]const u8 {
                if (value.len < minLen) return "value is too short";
                return null;
            }
        }.validate;
    }

    /// Value must have a maximum length.
    pub fn maxLength(comptime maxLen: usize) ValidatorFn {
        return struct {
            pub fn validate(value: []const u8) ?[]const u8 {
                if (value.len > maxLen) return "value is too long";
                return null;
            }
        }.validate;
    }

    /// Value must match one of the given allowed values.
    pub fn oneOf(comptime allowed: []const []const u8) ValidatorFn {
        return struct {
            pub fn validate(value: []const u8) ?[]const u8 {
                for (allowed) |a| {
                    if (std.mem.eql(u8, value, a)) return null;
                }
                return "value is not one of the allowed values";
            }
        }.validate;
    }
};

/// A validation pipeline that runs multiple validators.
pub const Validator = struct {
    validatorsList: []const ValidatorFn,

    pub fn init(validatorList: []const ValidatorFn) Validator {
        return .{ .validatorsList = validatorList };
    }

    pub fn validate(self: Validator, value: []const u8) ?[]const u8 {
        for (self.validatorsList) |v| {
            if (v(value)) |err| return err;
        }
        return null;
    }
};

test "required validator" {
    try std.testing.expectEqual(@as(?[]const u8, null), validators.required("hello"));
    try std.testing.expectEqual(@as(?[]const u8, null), validators.required("x"));
    try std.testing.expect(validators.required("") != null);
}

test "boolean validator" {
    try std.testing.expectEqual(@as(?[]const u8, null), validators.boolean("true"));
    try std.testing.expectEqual(@as(?[]const u8, null), validators.boolean("false"));
    try std.testing.expectEqual(@as(?[]const u8, null), validators.boolean("yes"));
    try std.testing.expectEqual(@as(?[]const u8, null), validators.boolean("no"));
    try std.testing.expect(validators.boolean("maybe") != null);
}

test "integer validator" {
    try std.testing.expectEqual(@as(?[]const u8, null), validators.integer("123"));
    try std.testing.expectEqual(@as(?[]const u8, null), validators.integer("-42"));
    try std.testing.expectEqual(@as(?[]const u8, null), validators.integer("+100"));
    try std.testing.expect(validators.integer("abc") != null);
    try std.testing.expect(validators.integer("12.34") != null);
}

test "url validator" {
    try std.testing.expectEqual(@as(?[]const u8, null), validators.url("http://example.com"));
    try std.testing.expectEqual(@as(?[]const u8, null), validators.url("https://example.com"));
    try std.testing.expect(validators.url("ftp://example.com") != null);
}

test "email validator" {
    try std.testing.expectEqual(@as(?[]const u8, null), validators.email("user@example.com"));
    try std.testing.expect(validators.email("invalid") != null);
}

test "port validator" {
    try std.testing.expectEqual(@as(?[]const u8, null), validators.port("8080"));
    try std.testing.expectEqual(@as(?[]const u8, null), validators.port("0"));
    try std.testing.expect(validators.port("99999") != null);
}

test "validator pipeline" {
    const v = Validator.init(&.{ validators.required, validators.integer });
    try std.testing.expectEqual(@as(?[]const u8, null), v.validate("123"));
    try std.testing.expect(v.validate("") != null);
    try std.testing.expect(v.validate("abc") != null);
}
