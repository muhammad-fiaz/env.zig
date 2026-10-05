---
title: Iterator Example
description: Working example of the iterator API in env.zig with peek, skip, reset, and collect operations.
head:
  - - meta
    - property: og:title
      content: "Iterator Example | env.zig"
  - - meta
    - name: description
      content: Working example of the iterator API in env.zig.
  - - meta
    - name: keywords
      content: "zig, env, iterator, iterate, entries, keys, values, example, env.zig"
---

# Iterator Example

Borrowed insertion-order iterator with peek, skip, reset, and collect
(no allocation; `deinit` is a no-op).

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
        \\APP_NAME=myapp
        \\PORT=8080
        \\DEBUG=true
        \\LOG_LEVEL=info
        \\DATABASE_URL=postgres://localhost/mydb
        \\
    );

    var stdoutBuffer: [0x100]u8 = undefined;
    var stdoutWriter = Io.File.stdout().writer(io, &stdoutBuffer);
    const stdout = &stdoutWriter.interface;

    try stdout.print("=== Iterator Example ===\n\n", .{});

    // Basic iteration with keys() — no allocation
    try stdout.print("All entries (via keys):\n", .{});
    for (env.keys()) |key| {
        try stdout.print("  {s} = {s}\n", .{ key, env.get(key).? });
    }

    // Iterator API — borrowed, no allocation; deinit is a no-op.
    try stdout.print("\nAll entries (via iterator):\n", .{});
    var it = env.iterator();
    defer it.deinit();
    while (it.next()) |entry| {
        try stdout.print("  {s} = {s}\n", .{ entry.key, entry.value });
    }

    // Peek without consuming
    var it2 = env.iterator();
    defer it2.deinit();
    if (it2.peek()) |entry| {
        try stdout.print("\nPeek first: {s} = {s}\n", .{ entry.key, entry.value });
    }
    if (it2.peek()) |entry| {
        try stdout.print("Peek again: {s} = {s}\n", .{ entry.key, entry.value });
    }

    // Skip entries
    var it3 = env.iterator();
    defer it3.deinit();
    try stdout.print("\nRemaining before skip: {d}\n", .{it3.remaining()});
    it3.skip(2);
    try stdout.print("Remaining after skip(2): {d}\n", .{it3.remaining()});
    if (it3.next()) |entry| {
        try stdout.print("Next after skip: {s} = {s}\n", .{ entry.key, entry.value });
    }

    // Reset iterator
    var it4 = env.iterator();
    defer it4.deinit();
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

## Example Output

```env
=== Iterator Example ===

All entries (via keys):
  APP_NAME = myapp
  PORT = 8080
  DEBUG = true
  LOG_LEVEL = info
  DATABASE_URL = postgres://localhost/mydb

All entries (via iterator):
  APP_NAME = myapp
  PORT = 8080
  DEBUG = true
  LOG_LEVEL = info
  DATABASE_URL = postgres://localhost/mydb

Peek first: APP_NAME = myapp
Peek again: APP_NAME = myapp

Remaining before skip: 5
Remaining after skip(2): 3
Next after skip: DEBUG = true

After reset, next: APP_NAME

Total entries: 5
```

## Before / After

The iterated store (unchanged by iteration):

```env
APP_NAME=myapp
PORT=8080
DEBUG=true
LOG_LEVEL=info
DATABASE_URL=postgres://localhost/mydb
```

Iterator cursor states observed:

```env
# fresh iterator
remaining=5
# after skip(2)
remaining=3
# after reset
next=APP_NAME
```

## See Also

- [Iterator Guide](/guide/iterator) for usage details
- [API Reference](/api/env) for the full API
