---
title: Iterator Example
titleTemplate: "Iterator Example | env.zig"
description: Working example of the iterator API in env.zig with peek, skip, reset, and collect operations.
head:
  - meta:
      - property: og:title
        content: "Iterator Example | env.zig"
      - meta: description
        content: Working example of the iterator API in env.zig.
      - name: keywords
        content: "zig, env, iterator, iterate, entries, keys, values, example, env.zig"
---

# Iterator Example

Iterator API with peek, skip, reset, and collect operations.

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

    try env.parseString(
        \\APP_NAME=myapp
        \\PORT=8080
        \\DEBUG=true
        \\LOG_LEVEL=info
        \\DATABASE_URL=postgres://localhost/mydb
        \\
    );

    var stdout_buffer: [0x100]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("=== Iterator Example ===\n\n", .{});

    // Basic iteration with keys() — no allocation
    try stdout.print("All entries (via keys):\n", .{});
    for (env.keys()) |key| {
        try stdout.print("  {s} = {s}\n", .{ key, env.get(key).? });
    }

    // Iterator API — allocates entries, must free
    try stdout.print("\nAll entries (via iterator):\n", .{});
    var it = env.iterator();
    defer allocator.free(it.entries);
    while (it.next()) |entry| {
        try stdout.print("  {s} = {s}\n", .{ entry.key, entry.value });
    }

    // Peek without consuming
    var it2 = env.iterator();
    defer allocator.free(it2.entries);
    if (it2.peek()) |entry| {
        try stdout.print("\nPeek first: {s} = {s}\n", .{ entry.key, entry.value });
    }
    if (it2.peek()) |entry| {
        try stdout.print("Peek again: {s} = {s}\n", .{ entry.key, entry.value });
    }

    // Skip entries
    var it3 = env.iterator();
    defer allocator.free(it3.entries);
    try stdout.print("\nRemaining before skip: {d}\n", .{it3.remaining()});
    it3.skip(2);
    try stdout.print("Remaining after skip(2): {d}\n", .{it3.remaining()});
    if (it3.next()) |entry| {
        try stdout.print("Next after skip: {s} = {s}\n", .{ entry.key, entry.value });
    }

    // Reset iterator
    var it4 = env.iterator();
    defer allocator.free(it4.entries);
    _ = it4.next();
    _ = it4.next();
    it4.reset();
    try stdout.print("\nAfter reset, next: {s}\n", .{(it4.next() orelse unreachable).key});

    try stdout.print("\nTotal entries: {d}\n", .{env.count()});
    try stdout.flush();
}
```

## Running

```bash
zig-out/bin/iterator_example
```

## See Also

- [Iterator Guide](/guide/iterator) for usage details
- [API Reference](/api/env) for the full API
