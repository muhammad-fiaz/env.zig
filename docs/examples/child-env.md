---
title: Child Env Example
description: Building child process environments with toEnvironMap and OS blocks.
head:
  - - meta
    - property: og:title
      content: "Child Env Example | env.zig"
  - - meta
    - name: description
      content: Building child process environments with env.zig.
  - - meta
    - name: keywords
      content: "zig, env, child, spawn, environ, example, env.zig"
---

# Child Env Example

Builds a child-process environment map from an `Env` store, merges the
live runtime environment, and materializes the OS block passed to
`std.process.spawn`/`run`.

## Source Code

```zig
const std = @import("std");
const Io = std.Io;
const envMod = @import("env");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var stdoutBuffer: [0x2000]u8 = undefined;
    var stdoutWriter = Io.File.stdout().writer(io, &stdoutBuffer);
    const stdout = &stdoutWriter.interface;

    try stdout.print("=== Child Process Environment Example ===\n\n", .{});

    var env = envMod.Env.init(allocator, .{});
    defer env.deinit();
    try env.set("APP_NAME", "child-demo");
    try env.set("APP_PORT", "8080");

    // Build a child environment map from Env.
    var map = try env.toEnvironMap(allocator);
    defer map.deinit();
    try stdout.print("toEnvironMap count={d}\n", .{map.count()});
    try stdout.print("APP_NAME={s}\n", .{map.get("APP_NAME").?});

    // Merge OS env, then overlay Env (Env wins) for a typical child env.
    var child = try envMod.runtime.getMap(allocator);
    defer child.deinit();
    try env.applyToEnvironMap(&child);
    try stdout.print("merged child count={d} APP_PORT={s}\n", .{ child.count(), child.get("APP_PORT").? });

    // Build the OS-specific block std.process.spawn expects.
    if (@import("builtin").os.tag == .windows) {
        const block = try child.createWindowsBlock(allocator, .{});
        defer allocator.free(block.slice);
        try stdout.print("windows block units={d}\n", .{block.slice.len});
    } else {
        const block = try child.createPosixBlock(allocator, .{});
        defer block.deinit(allocator);
        try stdout.print("posix block entries={d}\n", .{block.slice.len});
        for (block.slice) |entry| {
            const span = std.mem.span(entry.?);
            if (std.mem.startsWith(u8, span, "APP_")) {
                try stdout.print("  {s}\n", .{span});
            }
        }
    }

    try stdout.print("\nPass `&child` as `environ_map` to std.process.spawn/run.\n", .{});
    try stdout.flush();
}
```

## Running

```bash
zig-out/bin/child_env_example
```

## Example Output

```env
=== Child Process Environment Example ===

toEnvironMap count=2
APP_NAME=child-demo
merged child count=70 APP_PORT=8080
windows block units=5349

Pass `&child` as `environ_map` to std.process.spawn/run.
```

## Before / After

In-memory source store before export:

```env
APP_NAME=child-demo
APP_PORT=8080
```

After `applyToEnvironMap`, the child map holds the full runtime
environment overlaid with the store (store wins):

```env
APP_NAME=child-demo
APP_PORT=8080
# ... plus all inherited runtime variables
```

Note: `merged child count` reflects the host process environment and
varies per machine.

## See Also

- [OS Environment Guide](/guide/os-env) for runtime semantics
- [API Reference](/api/env) for `toEnvironMap`
