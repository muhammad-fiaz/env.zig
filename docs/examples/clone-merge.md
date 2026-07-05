---
title: Clone & Merge Example
description: Working example of cloning and merging env.zig instances for independent copies and default value patterns.
head:
  - - meta
    - property: og:title
      content: "Clone & Merge Example | env.zig"
  - - meta
    - name: description
      content: Working example of cloning and merging env.zig instances.
  - - meta
    - name: keywords
      content: "zig, env, clone, merge, copy, defaults, example, env.zig"
---

# Clone & Merge Example

Independent copies and default value merging.

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

    try env.set("APP_NAME", "MyApp");
    try env.set("PORT", "8080");
    try env.set("DEBUG", "true");

    var stdout_buffer: [0x100]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("=== Clone & Merge Example ===\n\n", .{});

    try stdout.print("Original env:\n", .{});
    for (env.keys()) |key| {
        try stdout.print("  {s} = {s}\n", .{ key, env.get(key).? });
    }

    var cloned = try env.clone();
    defer cloned.deinit();

    try stdout.print("\nCloned env (independent copy):\n", .{});
    for (cloned.keys()) |key| {
        try stdout.print("  {s} = {s}\n", .{ key, cloned.get(key).? });
    }

    try cloned.set("PORT", "9090");
    try cloned.set("NEW_KEY", "new_value");

    try stdout.print("\nAfter modifying clone:\n", .{});
    try stdout.print("  Original PORT = {s}\n", .{env.get("PORT").?});
    try stdout.print("  Cloned PORT = {s}\n", .{cloned.get("PORT").?});
    try stdout.print("  Original has NEW_KEY = {}\n", .{env.contains("NEW_KEY")});
    try stdout.print("  Cloned has NEW_KEY = {}\n", .{cloned.contains("NEW_KEY")});

    var defaults = env_mod.Env.init(allocator, .{});
    defer defaults.deinit();

    try defaults.set("PORT", "3000");
    try defaults.set("LOG_LEVEL", "info");
    try defaults.set("TIMEOUT", "30");

    try stdout.print("\nDefaults env:\n", .{});
    for (defaults.keys()) |key| {
        try stdout.print("  {s} = {s}\n", .{ key, defaults.get(key).? });
    }

    try env.merge(&defaults);

    try stdout.print("\nAfter merging defaults into env:\n", .{});
    for (env.keys()) |key| {
        try stdout.print("  {s} = {s}\n", .{ key, env.get(key).? });
    }
    try stdout.flush();
}
```

## Running

```bash
zig-out/bin/clone_merge_example
```

## See Also

- [Clone & Merge Guide](/guide/clone-merge) for usage details
- [API Reference](/api/env) for the full API
