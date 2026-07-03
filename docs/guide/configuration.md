---
title: Configuration
titleTemplate: "Configuration | env.zig"
description: Configure env.zig parsing, interpolation, and serialization behavior with the Config struct.
head:
  - - meta
    - property: og:title
      content: "Configuration | env.zig"
  - - meta
    - name: description
      content: Configure env.zig parsing, interpolation, and serialization behavior.
  - - meta
    - name: keywords
      content: "zig, env, config, configuration, options, settings"
---

# Configuration

The `Config` struct controls parsing, interpolation, and serialization behavior.

## Config Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `trim` | `bool` | `true` | Trim whitespace from keys and values |
| `allow_empty` | `bool` | `true` | Allow empty values (`KEY=` or `KEY=""`) |
| `interpolate` | `bool` | `true` | Enable variable interpolation (`${VAR}`, `$VAR`) |
| `override` | `bool` | `true` | Override existing values when loading multiple files |
| `strict` | `bool` | `false` | Fail on syntax errors instead of skipping invalid lines |
| `allow_inline_comments` | `bool` | `true` | Allow inline comments (`# comment` after value) |
| `allow_multiline` | `bool` | `false` | Allow multiline values (backslash continuation) |
| `max_interpolation_depth` | `usize` | `10` | Maximum interpolation recursion depth |
| `comment_char` | `u8` | `#` | Character used for comments |
| `export_to_env` | `bool` | `false` | Export loaded values to the process environment |
| `preserve_comments` | `bool` | `false` | Preserve comments when serializing |
| `sort_keys` | `bool` | `false` | Sort keys alphabetically when serializing |
| `indent` | `usize` | `0` | Indentation for serialized output (number of spaces) |
| `trailing_newline` | `bool` | `true` | Add a trailing newline when writing |
| `quote_spaces` | `bool` | `true` | Quote values that contain spaces when writing |

## Builder Pattern

Use `.with()` to create modified configs:

```zig
const config = env_mod.Config{};
const strict_config = config.with(.{
    .strict = true,
    .interpolate = false,
    .max_interpolation_depth = 5,
});
```

## Strict Mode

In strict mode, the parser returns `error.ParseError` on invalid syntax:

```zig
var env = env_mod.Env.init(allocator, .{ .strict = true });
try env.parseString("123BAD=value\n"); // Returns error.ParseError
```

In non-strict mode (default), invalid lines are silently skipped.
