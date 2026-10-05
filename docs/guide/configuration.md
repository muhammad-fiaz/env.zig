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
| `trim` | `bool` | `true` | Trim surrounding whitespace from unquoted values (quoted preserved) |
| `allowEmpty` | `bool` | `true` | Allow empty values (`KEY=` or `KEY=""`) |
| `interpolate` | `bool` | `true` | Enable variable interpolation (`${VAR}`, `$VAR`) |
| `override` | `bool` | `true` | Override existing values when loading multiple files |
| `strict` | `bool` | `false` | Fail on syntax errors instead of skipping invalid lines |
| `allowInlineComments` | `bool` | `true` | Strip ` # comment` from unquoted values; quoted `#` is literal |
| `allowMultiline` | `bool` | `false` | Backslash-newline continuation joins the next line |
| `maxInterpolationDepth` | `usize` | `10` | Maximum interpolation recursion depth (actually enforced) |
| `exportToRuntime` | `bool` | `false` | Export `set`/`remove` via single `runtime` impl (prefer explicit `exportToRuntime()`) |
| `sortKeys` | `bool` | `false` | Sort keys alphabetically when serializing |
| `trailingNewline` | `bool` | `true` | Emit trailing `\n` after the last entry |
| `quoteSpaces` | `bool` | `true` | Quote values needing quotes for a lossless round-trip |

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

In strict mode, the parser returns the specific `EnvError` for invalid syntax:

```zig
var env = envMod.Env.init(allocator, .{ .strict = true });
try env.parseString("123BAD=value\n"); // Returns error.InvalidKey
```

In non-strict mode (default), invalid lines are silently skipped.
