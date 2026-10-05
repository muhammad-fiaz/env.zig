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
# Run all examples (13 total)
zig build example

# Run a specific example
zig-out/bin/basic_example
zig-out/bin/interpolation_example
zig-out/bin/clone_merge_example
zig-out/bin/cache_example
zig-out/bin/iterator_example
zig-out/bin/validation_example
zig-out/bin/serialization_example
zig-out/bin/runtime_example
zig-out/bin/file_io_example
zig-out/bin/error_handling_example
zig-out/bin/type_safe_example
zig-out/bin/unicode_example
zig-out/bin/child_env_example
```

## Available Examples

| Example | Description |
|---------|-------------|
| [Basic](/examples/basic) | Set/get, explicit `.env` + `.env.local` creation, `loadMany` override |
| [Interpolation](/examples/interpolation) | Variable interpolation with `${VAR}` syntax |
| [Clone & Merge](/examples/clone-merge) | Independent copies and default value merging |
| [Cache](/examples/cache) | Standalone cache for parsed values |
| [Iterator](/examples/iterator) | Borrowed iterator with peek, skip, reset, and collect |
| [Validation](/examples/validation) | Schema validation with built-in validators |
| [Serialization](/examples/serialization) | Serialize to .env format with sorting and quoting |
| [Runtime](/examples/runtime) | Cross-platform runtime env via `env.runtime` with scope & snapshot |
| [Child Env](/examples/child-env) | `toEnvironMap`/`applyToEnvironMap` for child processes |
| [Unicode](/examples/unicode) | UTF-8 values, emoji, runtime round-trip |
| [File I/O](/examples/file_io) | Load/save, loadMany, reload, prefix filtering, export |
| [Error Handling](/examples/error_handling) | Strict mode, diagnostics, FileNotFound, validation levels |
| [Type-Safe](/examples/type_safe) | getBool/getInt/getFloat/getEnum/getList/getValue with runtime fallback |
