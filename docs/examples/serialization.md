---
title: Serialization Example
description: Serialization example for env.zig — write configurations back to .env format.
head:
  - - meta
    - property: og:title
      content: "Serialization Example | env.zig"
  - - meta
    - name: description
      content: Serialization example for env.zig — write configurations back to .env format.
  - - meta
    - name: keywords
      content: "zig, env, example, serialization, serialize, write"
---

# Serialization Example

Demonstrates serializing configurations back to `.env` format with key sorting and value quoting.

## Source Code

```zig
const std = @import("std");
const Io = std.Io;
const envMod = @import("env");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var env = envMod.Env.init(allocator, .{});
    defer env.deinit();

    try env.set("DATABASE_URL", "postgres://localhost:5432/mydb");
    try env.set("API_KEY", "secret123");
    try env.set("PORT", "8080");
    try env.set("DEBUG", "true");

    var stdoutBuffer: [0x100]u8 = undefined;
    var stdoutWriter = Io.File.stdout().writer(io, &stdoutBuffer);
    const stdout = &stdoutWriter.interface;

    try stdout.print("=== Serialization Example ===\n\n", .{});

    const serialized = try env.serialize();
    defer allocator.free(serialized);

    try stdout.print("Serialized .env:\n{s}\n", .{serialized});

    try stdout.print("Sorted:\n", .{});
    var sortedEnv = envMod.Env.init(allocator, .{ .sortKeys = true });
    defer sortedEnv.deinit();
    for (env.keys()) |key| {
        try sortedEnv.set(key, env.get(key).?);
    }
    const sorted = try sortedEnv.serialize();
    defer allocator.free(sorted);
    try stdout.print("{s}\n", .{sorted});

    try stdout.flush();
}
```

## Key Concepts

- **`env.serialize`** — Serialize to `.env` format string
- **`sortKeys`** — Sort keys alphabetically in output
- **`quoteSpaces`** — Quote values containing spaces (e.g., `"super secret key"`)
- **`env.save`** — Write directly to a file

## Running

```bash
zig-out/bin/serialization_example
```

## See Also

- [Serialization Guide](/guide/serialization) for full serialization details
- [API Reference](/api/env) for the full API
