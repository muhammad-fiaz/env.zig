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
    defaultValue: ?[]const u8 = null,
    /// Default value provider function.
    defaultFn: ?DefaultFn = null,
    /// Validators to run against the value.
    validatorsList: []const ValidatorFn = &.{},
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
    /// Returns an owned slice; the caller must free it with `allocator.free`.
    /// Messages are borrowed (static strings or field descriptions), so only
    /// the outer slice needs freeing.
    pub fn validate(
        self: Schema,
        allocator: std.mem.Allocator,
        vars: *const std.StringHashMap([]const u8),
    ) ![]ValidationError {
        var errorsList: std.ArrayList(ValidationError) = .empty;
        errdefer errorsList.deinit(allocator);
        for (self.fields) |field| {
            const value = vars.get(field.key);
            if (value == null) {
                if (field.required) {
                    try errorsList.append(allocator, .{
                        .key = field.key,
                        .message = field.description orelse "required field is missing",
                        .level = .err,
                    });
                } else if (field.validatorsList.len > 0 or field.description != null) {
                    try errorsList.append(allocator, .{
                        .key = field.key,
                        .message = "optional field is missing",
                        .level = .warning,
                    });
                }
                continue;
            }
            const val = value.?;
            for (field.validatorsList) |v| {
                if (v(val)) |msg| {
                    try errorsList.append(allocator, .{
                        .key = field.key,
                        .message = msg,
                        .level = if (field.required) .err else .warning,
                    });
                }
            }
        }
        return try errorsList.toOwnedSlice(allocator);
    }

    /// Apply default values to a hash map.
    pub fn applyDefaults(
        self: Schema,
        allocator: std.mem.Allocator,
        vars: *std.StringHashMap([]const u8),
    ) !void {
        for (self.fields) |field| {
            if (!vars.contains(field.key)) {
                const defaultVal = if (field.defaultFn) |f| f() else field.defaultValue orelse continue;
                _ = try vars.put(field.key, try allocator.dupe(u8, defaultVal));
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

    const errs = try schema.validate(std.testing.allocator, &vars);
    defer std.testing.allocator.free(errs);
    try std.testing.expect(errs.len > 0);
    try std.testing.expectEqualStrings("PORT", errs[0].key);
    try std.testing.expectEqual(validator.Level.err, errs[0].level);
}

test "Schema validation passes" {
    const schema = Schema.init(&.{
        .{ .key = "HOST", .required = true, .validatorsList = &.{validator.validators.required} },
    });

    var vars = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer vars.deinit();
    _ = try vars.put("HOST", "localhost");

    const errs = try schema.validate(std.testing.allocator, &vars);
    defer std.testing.allocator.free(errs);
    try std.testing.expectEqual(@as(usize, 0), errs.len);
}

test "Schema apply defaults" {
    const schema = Schema.init(&.{
        .{ .key = "HOST", .required = true, .defaultValue = "localhost" },
        .{ .key = "PORT", .required = true, .defaultValue = "8080" },
    });

    var vars = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer vars.deinit();
    _ = try vars.put("HOST", "custom");

    try schema.applyDefaults(std.testing.allocator, &vars);
    defer {
        if (vars.get("PORT")) |v| std.testing.allocator.free(v);
    }

    try std.testing.expectEqualStrings("custom", vars.get("HOST").?);
    try std.testing.expectEqualStrings("8080", vars.get("PORT").?);
}

test "Schema optional field missing emits warning" {
    const schema = Schema.init(&.{
        .{ .key = "HOST", .required = true },
        .{ .key = "DEBUG", .required = false, .validatorsList = &.{validator.validators.boolean}, .description = "Enable debug mode" },
    });

    var vars = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer vars.deinit();
    _ = try vars.put("HOST", "localhost");

    const errs = try schema.validate(std.testing.allocator, &vars);
    defer std.testing.allocator.free(errs);
    try std.testing.expectEqual(@as(usize, 1), errs.len);
    try std.testing.expectEqualStrings("DEBUG", errs[0].key);
    try std.testing.expectEqual(validator.Level.warning, errs[0].level);
}

test "Schema optional field without validators is silent when missing" {
    const schema = Schema.init(&.{
        .{ .key = "HOST", .required = true },
        .{ .key = "DEBUG", .required = false },
    });

    var vars = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer vars.deinit();
    _ = try vars.put("HOST", "localhost");

    const errs = try schema.validate(std.testing.allocator, &vars);
    defer std.testing.allocator.free(errs);
    try std.testing.expectEqual(@as(usize, 0), errs.len);
}

test "Schema optional field present but invalid emits warning" {
    const schema = Schema.init(&.{
        .{ .key = "PORT", .required = true },
        .{ .key = "DEBUG", .required = false, .validatorsList = &.{validator.validators.boolean} },
    });

    var vars = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer vars.deinit();
    _ = try vars.put("PORT", "8080");
    _ = try vars.put("DEBUG", "maybe");

    const errs = try schema.validate(std.testing.allocator, &vars);
    defer std.testing.allocator.free(errs);
    try std.testing.expectEqual(@as(usize, 1), errs.len);
    try std.testing.expectEqualStrings("DEBUG", errs[0].key);
    try std.testing.expectEqual(validator.Level.warning, errs[0].level);
}
