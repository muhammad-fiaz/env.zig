---
title: Examples
titleTemplate: "Examples | env.zig"
description: Complete examples for env.zig — basic usage, interpolation, clone & merge, cache, iterator, validation, and serialization.
head:
  - - meta
    - property: og:title
      content: "Examples | env.zig"
  - - meta
    - name: description
      content: Complete examples for env.zig.
  - - meta
    - name: keywords
      content: "zig, env, examples, basic, interpolation, clone, merge, cache, iterator, validation, serialization"
---

# Examples

Complete working examples for env.zig.

## Running Examples

```bash
# Run all examples
zig build example

# Run a specific example
zig-out/bin/basic_example
zig-out/bin/interpolation_example
zig-out/bin/clone_merge_example
zig-out/bin/cache_example
zig-out/bin/iterator_example
zig-out/bin/validation_example
zig-out/bin/serialization_example
```

## Available Examples

| Example | Description |
|---------|-------------|
| [Basic](/examples/basic) | Set/get values, type-safe accessors, iteration, serialization |
| [Interpolation](/examples/interpolation) | Variable interpolation with `${VAR}` syntax |
| [Clone & Merge](/examples/clone-merge) | Independent copies and default value merging |
| [Cache](/examples/cache) | Built-in cache for parsed values |
| [Iterator](/examples/iterator) | Iterator API with peek, skip, reset, and collect |
| [Validation](/examples/validation) | Schema validation with built-in validators |
| [Serialization](/examples/serialization) | Serialize to .env format with sorting and quoting |
