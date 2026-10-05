---
title: Config API
description: Configuration options API for env.zig parsing, interpolation, and serialization.
head:
  - - meta
    - property: og:title
      content: "Config API | env.zig"
  - - meta
    - name: description
      content: Configuration options API for env.zig.
  - - meta
    - name: keywords
      content: "zig, env, config, options, settings, builder"
---

# Config API Reference

Configuration options for parsing and loading `.env` files.

## Config

```zig
pub const Config = struct {
    trim: bool = true,
    allowEmpty: bool = true,
    interpolate: bool = true,
    override: bool = true,
    strict: bool = false,
    allowInlineComments: bool = true,
    allowMultiline: bool = false,
    maxInterpolationDepth: usize = 10,
    exportToRuntime: bool = false,
    sortKeys: bool = false,
    trailingNewline: bool = true,
    quoteSpaces: bool = true,
};
```

Every field is implemented. Comments use hard-coded `#`.
`maxInterpolationDepth` actually controls interpolation depth.
Strict mode returns the specific `EnvError` (e.g. `error.InvalidKey`)
instead of a generic `error.ParseError`.

## Config.with

```zig
pub fn with(self: Config, overrides: anytype) Config
```

Create a modified copy with overridden fields. Uses comptime struct reflection:

```zig
const cfg = Config{};
const strict = cfg.with(.{ .strict = true });
```
