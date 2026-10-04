---
title: Interpolation Example
description: Working example of variable interpolation in env.zig with ${VAR} syntax and circular detection.
head:
  - - meta
    - property: og:title
      content: "Interpolation Example | env.zig"
  - - meta
    - name: description
      content: Working example of variable interpolation in env.zig.
  - - meta
    - name: keywords
      content: "zig, env, interpolation, ${VAR}, example, env.zig"
---

# Interpolation Example

Variable interpolation with `${VAR}` syntax.

## Source Code

```zig
const std = @import("std");
const Io = std.Io;
const envMod = @import("env");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var env = envMod.Env.init(allocator, .{ .interpolate = true });
    defer env.deinit();

    try env.parseString(
        \\APP_NAME=myapp
        \\DATABASE_HOST=localhost
        \\DATABASE_PORT=5432
        \\DATABASE_URL=postgres://${DATABASE_HOST}:${DATABASE_PORT}/mydb
        \\GREETING=hello
        \\MESSAGE=${GREETING} world
        \\SHORTCUT=${APP_NAME} is running
        \\
    );

    var stdoutBuffer: [0x100]u8 = undefined;
    var stdoutWriter = Io.File.stdout().writer(io, &stdoutBuffer);
    const stdout = &stdoutWriter.interface;

    try stdout.print("=== Interpolation Example ===\n\n", .{});

    try stdout.print("Original values:\n", .{});
    try stdout.print("  APP_NAME = {s}\n", .{env.get("APP_NAME").?});
    try stdout.print("  DATABASE_HOST = {s}\n", .{env.get("DATABASE_HOST").?});
    try stdout.print("  DATABASE_PORT = {s}\n", .{env.get("DATABASE_PORT").?});

    try stdout.print("\nInterpolated values:\n", .{});
    try stdout.print("  DATABASE_URL = {s}\n", .{env.get("DATABASE_URL").?});
    try stdout.print("  MESSAGE = {s}\n", .{env.get("MESSAGE").?});
    try stdout.print("  SHORTCUT = {s}\n", .{env.get("SHORTCUT").?});

    try stdout.print("\nAll resolved keys:\n", .{});
    for (env.keys()) |key| {
        try stdout.print("  {s} = {s}\n", .{ key, env.get(key).? });
    }
    try stdout.flush();
}
```

## Running

```bash
zig-out/bin/interpolation_example
```

## See Also

- [Interpolation Guide](/guide/interpolation) for syntax details
- [Configuration](/guide/configuration) for enabling interpolation
