---
title: Configuration
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
| `allowEmpty` | `bool` | `true` | Allow empty values (`KEY=` or `KEY=""`) |
| `interpolate` | `bool` | `true` | Enable variable interpolation (`${VAR}`, `$VAR`) |
| `override` | `bool` | `true` | Override existing values when loading multiple files |
| `strict` | `bool` | `false` | Fail on syntax errors instead of skipping invalid lines |
| `allowInlineComments` | `bool` | `true` | Allow inline comments (`# comment` after value) |
| `allowMultiline` | `bool` | `false` | Allow multiline values (backslash continuation) |
| `maxInterpolationDepth` | `usize` | `10` | Maximum interpolation recursion depth |
| `commentChar` | `u8` | `#` | Character used for comments |
| `exportToEnv` | `bool` | `false` | Export loaded values to the process environment |
| `preserveComments` | `bool` | `false` | Preserve comments when serializing |
| `sortKeys` | `bool` | `false` | Sort keys alphabetically when serializing |
| `indent` | `usize` | `0` | Indentation for serialized output (number of spaces) |
| `trailingNewline` | `bool` | `true` | Add a trailing newline when writing |
| `quoteSpaces` | `bool` | `true` | Quote values that contain spaces when writing |

## Builder Pattern

Use `.with()` to create modified configs:

```zig
const config = envMod.Config{};
const strict_config = config.with(.{
    .strict = true,
    .interpolate = false,
    .maxInterpolationDepth = 5,
});
```

## Strict Mode

In strict mode, the parser returns `error.ParseError` on invalid syntax:

```zig
var env = envMod.Env.init(allocator, .{ .strict = true });
try env.parseString("123BAD=value\n"); // Returns error.ParseError
```

In non-strict mode (default), invalid lines are silently skipped.
