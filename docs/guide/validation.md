---
title: Validation
titleTemplate: "Validation | env.zig"
description: Schema validation and built-in validators for env.zig configuration with error and warning support.
head:
  - - meta
    - property: og:title
      content: "Validation | env.zig"
  - - meta
    - name: description
      content: Schema validation and built-in validators for env.zig.
  - - meta
    - name: keywords
      content: "zig, env, validation, schema, validator, required, optional, boolean, integer, port, url, warning, error"
---

# Validation

`env.zig` provides built-in validators and schema-based validation with error and warning support.

## Validation Levels

Each validation result has a `level` field:

| Level | Meaning |
|-------|---------|
| `.err` | Required field missing or invalid — must be fixed |
| `.warning` | Optional field missing or invalid — informational |

| Condition | Level |
|-----------|-------|
| Required field missing | `.err` |
| Required field present but invalid | `.err` |
| Optional field missing (has validators or description) | `.warning` |
| Optional field present but invalid | `.warning` |
| Optional field missing (no validators, no description) | Silent (no result) |

## Built-in Validators

| Validator | Description |
|-----------|-------------|
| `validators.required` | Value must not be empty |
| `validators.boolean` | Value must be a valid boolean (`true`/`false`/`yes`/`no`/`1`/`0`/`on`/`off`) |
| `validators.integer` | Value must be a valid integer |
| `validators.float` | Value must be a valid float |
| `validators.url` | Value must be a valid URL |
| `validators.email` | Value must be a valid email address |
| `validators.ipv4` | Value must be a valid IPv4 address |
| `validators.hostname` | Value must be a valid hostname |
| `validators.port` | Value must be a valid port number (0-65535) |
| `validators.range(min, max)` | Value must be within the given range |
| `validators.minLength(min)` | Value must be at least `min` characters |
| `validators.maxLength(max)` | Value must be at most `max` characters |
| `validators.oneOf(allowed)` | Value must be one of the allowed values |

## Schema Definition

```zig
const env_mod = @import("env");

const schema = env_mod.schema.Schema{
    .fields = &.{
        .{
            .key = "DATABASE_URL",
            .required = true,
            .validators_list = &.{ env_mod.validator.validators.required, env_mod.validator.validators.url },
            .description = "Database connection URL",
        },
        .{
            .key = "PORT",
            .required = true,
            .validators_list = &.{ env_mod.validator.validators.required, env_mod.validator.validators.integer },
            .description = "Server port",
        },
        .{
            .key = "LOG_LEVEL",
            .required = false,
            .default_value = "info",
            .validators_list = &.{env_mod.validator.validators.oneOf(&.{ "debug", "info", "warn", "error" })},
            .description = "Logging level",
        },
        .{
            .key = "API_KEY",
            .required = false,
            .validators_list = &.{env_mod.validator.validators.required},
            .description = "API secret key",
        },
    },
};
```

## Running Validation

```zig
const errs = env.validate(schema);

var has_errors = false;
var has_warnings = false;

for (errs) |err| {
    if (err.level == .err) {
        if (!has_errors) {
            try stdout.print("Errors:\n", .{});
            has_errors = true;
        }
        try stdout.print("  [ERROR] {s}: {s}\n", .{ err.key, err.message });
    } else {
        if (!has_warnings) {
            try stdout.print("\nWarnings:\n", .{});
            has_warnings = true;
        }
        try stdout.print("  [WARN]  {s}: {s}\n", .{ err.key, err.message });
    }
}

if (!has_errors and !has_warnings) {
    try stdout.print("Validation passed!\n", .{});
}
```

## Default Values

Fields with `default_value` or `default_fn` are auto-populated if missing:

```zig
.{
    .key = "TIMEOUT",
    .required = false,
    .default_value = "30",
    .validators_list = &.{env_mod.validator.validators.integer},
},
```

## Custom Validators

Create a custom validator by implementing the `ValidatorFn` signature:

```zig
fn myValidator(value: []const u8) ?[]const u8 {
    if (value.len < 3) return "must be at least 3 characters";
    return null;
}
```

## See Also

- [Getting Started](/guide/getting-started) for configuration options
- [Validators Reference](/api/validators) for all built-in validators
- [API Reference](/api/env) for the full API
