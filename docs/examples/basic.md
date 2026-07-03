---
title: Basic Example
titleTemplate: "Basic Example | env.zig"
description: Working example of basic env.zig usage with set/get, type-safe accessors, iteration, and serialization.
head:
  - - meta
    - property: og:title
      content: "Basic Example | env.zig"
  - - meta
    - name: description
      content: Working example of basic env.zig usage.
  - - meta
    - name: keywords
      content: "zig, env, basic, set, get, example, env.zig"
---

# Basic Example

Set/get values, type-safe accessors, iteration, and serialization.

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

    try env.set("APP_NAME", "env.zig Demo");
    try env.set("PORT", "8080");
    try env.set("DEBUG", "true");
    try env.set("DATABASE_URL", "postgres://localhost:5432/mydb");

    var stdout_buffer: [0x100]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("=== env.zig Basic Example ===\n\n", .{});

    if (env.get("APP_NAME")) |name| {
        try stdout.print("App: {s}\n", .{name});
    }

    if (env.getInt(u16, "PORT")) |port| {
        try stdout.print("Port: {d}\n", .{port});
    }

    if (env.getBool("DEBUG")) |debug| {
        try stdout.print("Debug: {}\n", .{debug});
    }

    if (env.get("DATABASE_URL")) |url| {
        try stdout.print("DB URL: {s}\n", .{url});
    }

    try stdout.print("\nAll keys:\n", .{});
    for (env.keys()) |key| {
        try stdout.print("  {s}={s}\n", .{ key, env.get(key).? });
    }

    const serialized = try env.serialize();
    defer allocator.free(serialized);

    try stdout.print("\nSerialized .env:\n{s}\n", .{serialized});
    try stdout.flush();
}
```

## Running

```bash
zig-out/bin/basic_example
```

## See Also

- [Getting Started](/guide/getting-started) for configuration options
- [API Reference](/api/env) for the full API
