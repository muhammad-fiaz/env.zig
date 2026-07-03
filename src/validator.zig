const std = @import("std");
const errors = @import("errors.zig");

/// A validation level.
pub const Level = enum {
    err,
    warning,
};

/// A validation error or warning.
pub const ValidationError = struct {
    key: []const u8,
    message: []const u8,
    level: Level = .err,
};

/// A validator function that takes a value and returns null on success
/// or an error message on failure.
pub const ValidatorFn = *const fn (value: []const u8) ?[]const u8;

/// A set of built-in validators.
pub const validators = struct {
    /// Value must not be empty.
    pub fn required(value: []const u8) ?[]const u8 {
        if (value.len == 0) return "value must not be empty";
        return null;
    }

    /// Value must be a valid boolean (true/false/yes/no/1/0).
    pub fn boolean(value: []const u8) ?[]const u8 {
        if (value.len == 0) return "value must not be empty";
        if (value.len > 8) return "value must be a valid boolean (true/false/yes/no/1/0/on/off)";
        var buf: [8]u8 = undefined;
        for (value, 0..) |ch, i| {
            buf[i] = std.ascii.toLower(ch);
        }
        const v = buf[0..value.len];
        if (std.mem.eql(u8, v, "true") or std.mem.eql(u8, v, "false") or
            std.mem.eql(u8, v, "yes") or std.mem.eql(u8, v, "no") or
            std.mem.eql(u8, v, "1") or std.mem.eql(u8, v, "0") or
            std.mem.eql(u8, v, "on") or std.mem.eql(u8, v, "off"))
        {
            return null;
        }
        return "value must be a valid boolean (true/false/yes/no/1/0/on/off)";
    }

    /// Value must be a valid integer.
    pub fn integer(value: []const u8) ?[]const u8 {
        if (value.len == 0) return "value must not be empty";
        var start: usize = 0;
        if (value[0] == '-' or value[0] == '+') {
            if (value.len == 1) return "value must be a valid integer";
            start = 1;
        }
        for (value[start..]) |ch| {
            if (!std.ascii.isDigit(ch)) return "value must be a valid integer";
        }
        return null;
    }

    /// Value must be a valid float.
    pub fn float(value: []const u8) ?[]const u8 {
        if (value.len == 0) return "value must not be empty";
        var start: usize = 0;
        if (value[0] == '-' or value[0] == '+') {
            if (value.len == 1) return "value must be a valid float";
            start = 1;
        }
        var dot_seen = false;
        for (value[start..]) |ch| {
            if (ch == '.') {
                if (dot_seen) return "value must be a valid float";
                dot_seen = true;
            } else if (!std.ascii.isDigit(ch)) {
                return "value must be a valid float";
            }
        }
        return null;
    }

    /// Value must be a valid URL.
    pub fn url(value: []const u8) ?[]const u8 {
        if (std.mem.startsWith(u8, value, "http://") or std.mem.startsWith(u8, value, "https://")) {
            return null;
        }
        return "value must be a valid URL starting with http:// or https://";
    }

    /// Value must be a valid email address.
    pub fn email(value: []const u8) ?[]const u8 {
        if (std.mem.indexOf(u8, value, "@") == null) return "value must be a valid email address";
        if (std.mem.lastIndexOf(u8, value, ".") == null) return "value must be a valid email address";
        return null;
    }

    /// Value must be a valid IPv4 address.
    pub fn ipv4(value: []const u8) ?[]const u8 {
        var parts = std.mem.splitScalar(u8, value, '.');
        var count: usize = 0;
        while (parts.next()) |part| {
            count += 1;
            if (part.len == 0 or part.len > 3) return "value must be a valid IPv4 address";
            for (part) |ch| {
                if (!std.ascii.isDigit(ch)) return "value must be a valid IPv4 address";
            }
            const num = std.fmt.parseInt(u8, part, 10) catch return "value must be a valid IPv4 address";
            _ = num;
        }
        if (count != 4) return "value must be a valid IPv4 address";
        return null;
    }

    /// Value must be a valid hostname.
    pub fn hostname(value: []const u8) ?[]const u8 {
        if (value.len == 0 or value.len > 253) return "value must be a valid hostname";
        if (value[0] == '-' or value[value.len - 1] == '-') return "hostname cannot start or end with a hyphen";
        for (value) |ch| {
            if (!std.ascii.isAlphanumeric(ch) and ch != '-' and ch != '.') return "hostname contains invalid characters";
        }
        return null;
    }

    /// Value must be a valid port number (0-65535).
    pub fn port(value: []const u8) ?[]const u8 {
        const num = std.fmt.parseInt(u16, value, 10) catch return "value must be a valid port number (0-65535)";
        _ = num;
        return null;
    }

    /// Value must be within a numeric range.
    pub fn range(comptime min_val: i64, comptime max_val: i64) ValidatorFn {
        return struct {
            pub fn validate(value: []const u8) ?[]const u8 {
                const num = std.fmt.parseInt(i64, value, 10) catch return "value must be a valid integer";
                if (num < min_val or num > max_val) return "value is out of range";
                return null;
            }
        }.validate;
    }

    /// Value must have a minimum length.
    pub fn minLength(comptime min_len: usize) ValidatorFn {
        return struct {
            pub fn validate(value: []const u8) ?[]const u8 {
                if (value.len < min_len) return "value is too short";
                return null;
            }
        }.validate;
    }

    /// Value must have a maximum length.
    pub fn maxLength(comptime max_len: usize) ValidatorFn {
        return struct {
            pub fn validate(value: []const u8) ?[]const u8 {
                if (value.len > max_len) return "value is too long";
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
    validators_list: []const ValidatorFn,

    pub fn init(validator_list: []const ValidatorFn) Validator {
        return .{ .validators_list = validator_list };
    }

    pub fn validate(self: Validator, value: []const u8) ?[]const u8 {
        for (self.validators_list) |v| {
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
