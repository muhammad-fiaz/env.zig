---
title: Serialization Example
titleTemplate: "Serialization Example | env.zig"
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
const env_mod = @import("env");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var env = env_mod.Env.init(allocator, .{});
    defer env.deinit();

    try env.set("DATABASE_URL", "postgres://localhost:5432/mydb");
    try env.set("API_KEY", "secret123");
    try env.set("PORT", "8080");
    try env.set("DEBUG", "true");

    var stdout_buffer: [0x100]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("=== Serialization Example ===\n\n", .{});

    const serialized = try env.serialize();
    defer allocator.free(serialized);

    try stdout.print("Serialized .env:\n{s}\n", .{serialized});

    try stdout.print("Sorted:\n", .{});
    var sorted_env = env_mod.Env.init(allocator, .{ .sort_keys = true });
    defer sorted_env.deinit();
    for (env.keys()) |key| {
        try sorted_env.set(key, env.get(key).?);
    }
    const sorted = try sorted_env.serialize();
    defer allocator.free(sorted);
    try stdout.print("{s}\n", .{sorted});

    try stdout.flush();
}
```

## Key Concepts

- **`env.serialize`** — Serialize to `.env` format string
- **`sort_keys`** — Sort keys alphabetically in output
- **`quote_spaces`** — Quote values containing spaces (e.g., `"super secret key"`)
- **`env.save`** — Write directly to a file

## Running

```bash
zig-out/bin/serialization_example
```

## See Also

- [Serialization Guide](/guide/serialization) for full serialization details
- [API Reference](/api/env) for the full API
