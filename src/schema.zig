const std = @import("std");
const validator = @import("validator.zig");
const errors = @import("errors.zig");

const ValidatorFn = validator.ValidatorFn;
const ValidationError = validator.ValidationError;

/// Default value provider function.
pub const DefaultFn = *const fn () []const u8;

/// A single field definition in a schema.
pub const FieldDef = struct {
    /// The key name.
    key: []const u8,
    /// Whether this field is required.
    required: bool = true,
    /// Default value if the field is not present.
    default_value: ?[]const u8 = null,
    /// Default value provider function.
    default_fn: ?DefaultFn = null,
    /// Validators to run against the value.
    validators_list: []const ValidatorFn = &.{},
    /// Description of the field for error messages.
    description: ?[]const u8 = null,
};

/// A schema definition for validating an entire .env configuration.
pub const Schema = struct {
    fields: []const FieldDef,

    pub fn init(fields: []const FieldDef) Schema {
        return .{ .fields = fields };
    }

    /// Validate a set of key-value pairs against this schema.
    pub fn validate(
        self: Schema,
        vars: *const std.StringHashMap([]const u8),
    ) []ValidationError {
        var errors_buf: [64]ValidationError = undefined;
        var errors_len: usize = 0;
        for (self.fields) |field| {
            const value = vars.get(field.key);
            if (value == null) {
                if (field.required) {
                    if (errors_len < errors_buf.len) {
                        errors_buf[errors_len] = .{
                            .key = field.key,
                            .message = field.description orelse "required field is missing",
                            .level = .err,
                        };
                        errors_len += 1;
                    }
                } else if (field.validators_list.len > 0 or field.description != null) {
                    if (errors_len < errors_buf.len) {
                        errors_buf[errors_len] = .{
                            .key = field.key,
                            .message = if (field.description) |desc|
                                std.fmt.allocPrint(std.heap.page_allocator, "optional field '{s}' is missing", .{desc}) catch "optional field is missing"
                            else
                                "optional field is missing",
                            .level = .warning,
                        };
                        errors_len += 1;
                    }
                }
                continue;
            }
            const val = value.?;
            for (field.validators_list) |v| {
                if (v(val)) |msg| {
                    if (errors_len < errors_buf.len) {
                        errors_buf[errors_len] = .{
                            .key = field.key,
                            .message = msg,
                            .level = if (field.required) .err else .warning,
                        };
                        errors_len += 1;
                    }
                }
            }
        }
        return errors_buf[0..errors_len];
    }

    /// Apply default values to a hash map.
    pub fn applyDefaults(
        self: Schema,
        allocator: std.mem.Allocator,
        vars: *std.StringHashMap([]const u8),
    ) !void {
        for (self.fields) |field| {
            if (!vars.contains(field.key)) {
                const default_val = if (field.default_fn) |f| f() else field.default_value orelse continue;
                _ = try vars.put(field.key, try std.mem.Allocator.dupe(allocator, u8, default_val));
            }
        }
    }
};

test "Schema required field missing" {
    const schema = Schema.init(&.{
        .{ .key = "HOST", .required = true },
        .{ .key = "PORT", .required = true },
    });

    var vars = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer vars.deinit();
    _ = try vars.put("HOST", "localhost");

    const errs = schema.validate(&vars);
    try std.testing.expect(errs.len > 0);
    try std.testing.expectEqualStrings("PORT", errs[0].key);
    try std.testing.expectEqual(ValidationError.Level.err, errs[0].level);
}

test "Schema validation passes" {
    const schema = Schema.init(&.{
        .{ .key = "HOST", .required = true, .validators_list = &.{validator.validators.required} },
    });

    var vars = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer vars.deinit();
    _ = try vars.put("HOST", "localhost");

    const errs = schema.validate(&vars);
    try std.testing.expectEqual(@as(usize, 0), errs.len);
}

test "Schema apply defaults" {
    const schema = Schema.init(&.{
        .{ .key = "HOST", .required = true, .default_value = "localhost" },
        .{ .key = "PORT", .required = true, .default_value = "8080" },
    });

    var vars = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer vars.deinit();
    _ = try vars.put("HOST", "custom");

    try schema.applyDefaults(std.testing.allocator, &vars);
    defer {
        if (vars.get("HOST")) |v| std.testing.allocator.free(v);
        if (vars.get("PORT")) |v| std.testing.allocator.free(v);
    }

    try std.testing.expectEqualStrings("custom", vars.get("HOST").?);
    try std.testing.expectEqualStrings("8080", vars.get("PORT").?);
}

test "Schema optional field missing emits warning" {
    const schema = Schema.init(&.{
        .{ .key = "HOST", .required = true },
        .{ .key = "DEBUG", .required = false, .validators_list = &.{validator.validators.boolean}, .description = "Enable debug mode" },
    });

    var vars = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer vars.deinit();
    _ = try vars.put("HOST", "localhost");

    const errs = schema.validate(&vars);
    try std.testing.expectEqual(@as(usize, 1), errs.len);
    try std.testing.expectEqualStrings("DEBUG", errs[0].key);
    try std.testing.expectEqual(ValidationError.Level.warning, errs[0].level);
}

test "Schema optional field without validators is silent when missing" {
    const schema = Schema.init(&.{
        .{ .key = "HOST", .required = true },
        .{ .key = "DEBUG", .required = false },
    });

    var vars = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer vars.deinit();
    _ = try vars.put("HOST", "localhost");

    const errs = schema.validate(&vars);
    try std.testing.expectEqual(@as(usize, 0), errs.len);
}

test "Schema optional field present but invalid emits warning" {
    const schema = Schema.init(&.{
        .{ .key = "PORT", .required = true },
        .{ .key = "DEBUG", .required = false, .validators_list = &.{validator.validators.boolean} },
    });

    var vars = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer vars.deinit();
    _ = try vars.put("PORT", "8080");
    _ = try vars.put("DEBUG", "maybe");

    const errs = schema.validate(&vars);
    try std.testing.expectEqual(@as(usize, 1), errs.len);
    try std.testing.expectEqualStrings("DEBUG", errs[0].key);
    try std.testing.expectEqual(ValidationError.Level.warning, errs[0].level);
}
