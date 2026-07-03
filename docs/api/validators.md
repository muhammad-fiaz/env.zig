---
title: Validators API
titleTemplate: "Validators API | env.zig"
description: Built-in validators API reference for env.zig configuration validation.
head:
  - meta:
      - property: og:title
        content: "Validators API | env.zig"
      - meta: description
        content: Built-in validators API reference for env.zig.
      - name: keywords
        content: "zig, env, validators, required, boolean, integer, float, url, email, port"
---

# Validators API Reference

Built-in validators for `.env` values.

## Validator Function Signature

```zig
pub const ValidatorFn = *const fn (value: []const u8) ?[]const u8;
```

Returns `null` on success, or an error message on failure.

## Built-in Validators

### `validators.required`

Value must not be empty.

### `validators.boolean`

Value must be a valid boolean: `true`/`false`/`yes`/`no`/`1`/`0`/`on`/`off` (case-insensitive).

### `validators.integer`

Value must be a valid integer (optional leading `+` or `-`).

### `validators.float`

Value must be a valid float (optional leading sign, optional decimal point).

### `validators.url`

Value must start with `http://` or `https://`.

### `validators.email`

Value must contain `@` with valid local and domain parts.

### `validators.ipv4`

Value must be a valid IPv4 address (four dot-separated octets 0-255).

### `validators.hostname`

Value must be a valid hostname (alphanumeric, hyphens, dots).

### `validators.port`

Value must be a valid port number (0-65535).

### `validators.range(min, max)`

Value must be a number within the given range (inclusive).

### `validators.minLength(min)`

Value must be at least `min` characters long.

### `validators.maxLength(max)`

Value must be at most `max` characters long.

### `validators.oneOf(allowed)`

Value must be one of the allowed string values.

## Custom Validators

Create a custom validator by implementing the `ValidatorFn` signature:

```zig
fn myValidator(value: []const u8) ?[]const u8 {
    if (value.len < 3) return "must be at least 3 characters";
    return null;
}
```
