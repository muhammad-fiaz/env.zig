---
title: Examples
description: Complete examples for env.zig — basic, interpolation, OS env, file I/O, error handling, type-safe accessors, and more.
head:
  - - meta
    - property: og:title
      content: "Examples | env.zig"
  - - meta
    - name: description
      content: Complete examples for env.zig covering all features.
  - - meta
    - name: keywords
      content: "zig, env, examples, basic, interpolation, clone, merge, cache, iterator, validation, serialization, os env, file io, error handling, type safe, scope, snapshot"
---

# Examples

Complete working examples for env.zig.

## Running Examples

```bash
# Run all examples (11 total)
zig build example

# Run a specific example
zig-out/bin/basic_example
zig-out/bin/interpolation_example
zig-out/bin/clone_merge_example
zig-out/bin/cache_example
zig-out/bin/iterator_example
zig-out/bin/validation_example
zig-out/bin/serialization_example
zig-out/bin/os_env_example
zig-out/bin/file_io_example
zig-out/bin/error_handling_example
zig-out/bin/type_safe_example
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
| [OS Environment](/examples/os-env) | Cross-platform OS env (Windows/Linux/macOS) with Scope & snapshot |
| [File I/O](/examples/file_io) | Load/save, loadMany, reload, prefix filtering, export |
| [Error Handling](/examples/error_handling) | Strict mode, diagnostics, FileNotFound, validation levels |
| [Type-Safe](/examples/type_safe) | getBool/getInt/getFloat/getEnum/getList with OS fallback |
