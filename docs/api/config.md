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
    allow_empty: bool = true,
    interpolate: bool = true,
    override: bool = true,
    strict: bool = false,
    allow_inline_comments: bool = true,
    allow_multiline: bool = false,
    max_interpolation_depth: usize = 10,
    comment_char: u8 = '#',
    export_to_env: bool = false,
    preserve_comments: bool = false,
    sort_keys: bool = false,
    indent: usize = 0,
    trailing_newline: bool = true,
    quote_spaces: bool = true,
};
```

## Config.with

```zig
pub fn with(self: Config, overrides: anytype) Config
```

Create a modified copy with overridden fields. Uses comptime struct reflection:

```zig
const cfg = Config{};
const strict = cfg.with(.{ .strict = true });
```
