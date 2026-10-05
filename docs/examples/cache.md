---
title: Cache Example
description: Working example of the standalone cache in env.zig for storing parsed values separately from environment entries.
head:
  - - meta
    - property: og:title
      content: "Cache Example | env.zig"
  - - meta
    - name: description
      content: Working example of the standalone cache in env.zig.
  - - meta
    - name: keywords
      content: "zig, env, cache, storage, key-value, example, env.zig"
---

# Cache Example

Standalone `Cache` for parsed values (no longer owned by `Env`).

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

    try env.parseString(
        \\API_KEY=secret123
        \\DATABASE_URL=postgres://localhost/mydb
        \\PORT=8080
        \\
    );

    var stdoutBuffer: [0x100]u8 = undefined;
    var stdoutWriter = Io.File.stdout().writer(io, &stdoutBuffer);
    const stdout = &stdoutWriter.interface;

    try stdout.print("=== Cache Example ===\n\n", .{});

    var cache = envMod.Cache.init(allocator);
    defer cache.deinit();

    try cache.put("cached_token", "abc123");
    try cache.put("cached_config", "{ \"timeout\": 30 }");

    try stdout.print("Cache count: {d}\n", .{cache.count()});

    if (cache.get("cached_token")) |token| {
        try stdout.print("Cached token: {s}\n", .{token});
    }

    try stdout.print("Has cached_token: {}\n", .{cache.contains("cached_token")});
    try stdout.print("Has missing: {}\n", .{cache.contains("missing")});

    try cache.put("cached_token", "new_token_456");
    try stdout.print("Updated token: {s}\n", .{cache.get("cached_token").?});

    _ = cache.remove("cached_config");
    try stdout.print("After remove, has cached_config: {}\n", .{cache.contains("cached_config")});
    try stdout.print("Cache count after remove: {d}\n", .{cache.count()});

    cache.clear();
    try stdout.print("Cache count after clear: {d}\n", .{cache.count()});

    try stdout.print("\nEnv entries still intact:\n", .{});
    for (env.keys()) |key| {
        try stdout.print("  {s} = {s}\n", .{ key, env.get(key).? });
    }
    try stdout.flush();
}
```

## Running

```bash
zig-out/bin/cache_example
```

## Example Output

```env
=== Cache Example ===

Cache count: 2
Cached token: abc123
Has cached_token: true
Has missing: false
Updated token: new_token_456
After remove, has cached_config: false
Cache count after remove: 1
Cache count after clear: 0

Env entries still intact:
  API_KEY = secret123
  DATABASE_URL = postgres://localhost/mydb
  PORT = 8080
```

## Before / After

Cache state transitions during the run:

```env
# after two puts
cached_token=abc123
cached_config={ "timeout": 30 }
```

```env
# after overwrite + remove + clear
# (empty — count 0)
```

The `Env` store is untouched throughout:

```env
API_KEY=secret123
DATABASE_URL=postgres://localhost/mydb
PORT=8080
```

## See Also

- [Cache Guide](/guide/cache) for usage details
- [API Reference](/api/env) for the full API
