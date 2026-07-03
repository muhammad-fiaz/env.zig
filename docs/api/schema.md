---
title: Schema API
titleTemplate: "Schema API | env.zig"
description: Schema-based validation API for env.zig configurations.
head:
  - meta:
      - property: og:title
        content: "Schema API | env.zig"
      - meta: description
        content: Schema-based validation API for env.zig.
      - name: keywords
        content: "zig, env, schema, validation, FieldDef, ValidationError"
---

# Schema API Reference

Schema-based validation for `.env` configurations.

## Schema

### `Schema.init`

```zig
pub fn init(fields: []const FieldDef) Schema
```

Create a new schema from field definitions.

### `Schema.validate`

```zig
pub fn validate(self: Schema, vars: *const std.StringHashMap([]const u8)) []ValidationError
```

Validate a set of key-value pairs against this schema.

## FieldDef

```zig
pub const FieldDef = struct {
    key: []const u8,
    required: bool = true,
    default_value: ?[]const u8 = null,
    default_fn: ?DefaultFn = null,
    validators_list: []const ValidatorFn = &.{},
    description: ?[]const u8 = null,
};
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `key` | `[]const u8` | — | The key name |
| `required` | `bool` | `true` | Whether the field is required |
| `default_value` | `?[]const u8` | `null` | Default value if missing |
| `default_fn` | `?DefaultFn` | `null` | Default value provider function |
| `validators_list` | `[]const ValidatorFn` | `&.{}` | Validators to run |
| `description` | `?[]const u8` | `null` | Description for error messages |

## ValidationError

```zig
pub const ValidationError = struct {
    key: []const u8,
    message: []const u8,
    level: Level = .err,
};
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `key` | `[]const u8` | — | The key that failed validation |
| `message` | `[]const u8` | — | Error or warning message |
| `level` | `Level` | `.err` | `.err` for errors, `.warning` for warnings |
