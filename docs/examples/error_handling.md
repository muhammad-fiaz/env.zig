---
title: Error Handling Example
description: Robust error handling in env.zig — strict mode, FileNotFound, diagnostics, and validation levels.
---

# Error Handling Example

Shows correct `!void` returns, `catch |err| switch`, strict vs lenient, and `ValidationError` levels.

## Source

<<< ../../examples/error_handling.zig

## Running

```bash
zig build example
zig-out/bin/error_handling_example
```
