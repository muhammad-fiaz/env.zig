---
title: Validation Example
titleTemplate: "Validation Example | env.zig"
description: Schema validation example for env.zig with built-in validators, errors, and warnings.
head:
  - meta:
      - property: og:title
        content: "Validation Example | env.zig"
      - meta: description
        content: Schema validation example for env.zig with built-in validators, errors, and warnings.
      - name: keywords
        content: "zig, env, example, validation, schema, validator, warning, error"
---

# Validation Example

Demonstrates schema validation with required/optional fields, errors, and warnings.

## Source Code

```zig
const std = @import("std");
const Io = std.Io;
const env_mod = @import("env");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var env = env_mod.Env.init(allocator, .{});
    defer env.deinit();

    try env.parseString(
        \\APP_NAME=MyApp
        \\PORT=8080
        \\DEBUG=true
        \\LOG_LEVEL=info
        \\
    );

    var stdout_buffer: [0x100]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("=== Validation Example ===\n\n", .{});

    const schema = env_mod.schema.Schema{
        .fields = &.{
            .{
                .key = "APP_NAME",
                .required = true,
                .validators_list = &.{env_mod.validator.validators.required},
                .description = "Application name",
            },
            .{
                .key = "PORT",
                .required = true,
                .validators_list = &.{ env_mod.validator.validators.required, env_mod.validator.validators.integer },
                .description = "Server port",
            },
            .{
                .key = "DEBUG",
                .required = false,
                .validators_list = &.{env_mod.validator.validators.boolean},
                .description = "Enable debug mode",
            },
            .{
                .key = "API_KEY",
                .required = false,
                .validators_list = &.{env_mod.validator.validators.required},
                .description = "API secret key",
            },
            .{
                .key = "DATABASE_URL",
                .required = false,
                .validators_list = &.{env_mod.validator.validators.url},
                .description = "Database connection URL",
            },
        },
    };

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
        try stdout.print("Validation passed! All required fields present and valid.\n", .{});
    }

    try stdout.print("\nLoaded config:\n", .{});
    for (env.keys()) |key| {
        try stdout.print("  {s} = {s}\n", .{ key, env.get(key).? });
    }
    try stdout.flush();
}
```

## Running

```bash
zig-out/bin/validation_example
```

## Example Output

```
=== Validation Example ===

Warnings:
  [WARN]  API_KEY: optional field 'API secret key' is missing
  [WARN]  DATABASE_URL: optional field 'Database connection URL' is missing

Loaded config:
  APP_NAME = MyApp
  PORT = 8080
  DEBUG = true
  LOG_LEVEL = info
```

## Key Concepts

- **`Level.err`** — Required field missing or invalid
- **`Level.warning`** — Optional field missing or invalid
- Optional fields without validators or description are silently ignored when missing
- Present fields failing validation emit the appropriate level based on `required`

## See Also

- [Validation Guide](/guide/validation) for full validation details
- [Validators Reference](/api/validators) for all built-in validators
