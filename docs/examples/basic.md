---
title: Basic Example
description: Working example of basic env.zig usage with set/get, type-safe accessors, iteration, serialization.
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

Set/get values, type-safe accessors, iteration, serialization, plus
explicit `.env` and `.env.local` file creation and reload.

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

    try stdout.print("=== env.zig Basic Example ===\n\n", .{});

    // 1) In-memory entries.
    var env = envMod.Env.init(allocator, .{});
    defer env.deinit();

    try env.set("APP_NAME", "env.zig Demo");
    try env.set("PORT", "8080");
    try env.set("DEBUG", "true");
    try env.set("DATABASE_URL", "postgres://localhost:5432/mydb");

    try stdout.print("--- In-memory values (before file ops) ---\n", .{});
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

    // 2) Explicitly create a `.env` file from the in-memory store.
    try env.save(".env");
    defer {
        Io.Dir.cwd().deleteFile(io, ".env") catch {};
    }
    try stdout.print("--- Wrote .env file ---\n", .{});
    {
        const dir = Io.Dir.cwd();
        const raw = try dir.readFileAlloc(io, ".env", allocator, .limited(8192));
        defer allocator.free(raw);
        try stdout.print("File .env before local override:\n{s}\n", .{raw});
    }

    // 3) Explicitly create a `.env.local` file with local overrides.
    var local = envMod.Env.init(allocator, .{});
    defer local.deinit();
    try local.set("PORT", "9090");
    try local.set("DEBUG", "false");
    try local.save(".env.local");
    defer {
        Io.Dir.cwd().deleteFile(io, ".env.local") catch {};
    }
    {
        const dir = Io.Dir.cwd();
        const raw = try dir.readFileAlloc(io, ".env.local", allocator, .limited(8192));
        defer allocator.free(raw);
        try stdout.print("File .env.local:\n{s}\n", .{raw});
    }

    // 4) Implicit load: library owns the read via loadMany.
    // `.env.local` wins over `.env`.
    var loaded = envMod.Env.init(allocator, .{ .override = true });
    defer loaded.deinit();
    try loaded.loadMany(&.{ ".env", ".env.local" });
    try stdout.print("--- After implicit loadMany([.env, .env.local]) ---\n", .{});
    try stdout.print("PORT={s} (local override)\n", .{loaded.get("PORT").?});
    try stdout.print("DEBUG={s} (local override)\n", .{loaded.get("DEBUG").?});
    try stdout.print("APP_NAME={s} (from .env)\n", .{loaded.get("APP_NAME").?});

    // 5) Explicit read: caller owns the std.Io file read, no load() used.
    // Read raw bytes with the caller's io, then parse the owned slice.
    var explicit = envMod.Env.init(allocator, .{ .override = true });
    defer explicit.deinit();
    {
        const dir = Io.Dir.cwd();
        const dotenv = try dir.readFileAlloc(io, ".env", allocator, .limited(8192));
        defer allocator.free(dotenv);
        try explicit.parseString(dotenv);
        const localRaw = try dir.readFileAlloc(io, ".env.local", allocator, .limited(8192));
        defer allocator.free(localRaw);
        try explicit.parseString(localRaw);
    }
    try stdout.print("--- After explicit std.Io read + parseString ---\n", .{});
    try stdout.print("PORT={s} (local override)\n", .{explicit.get("PORT").?});
    try stdout.print("DEBUG={s} (local override)\n", .{explicit.get("DEBUG").?});
    try stdout.print("APP_NAME={s} (from .env)\n", .{explicit.get("APP_NAME").?});

    // 6) Explicit write: serialize to caller-owned bytes, then write
    // the file with the caller's io. No save() used.
    {
        const out = try explicit.serialize();
        defer allocator.free(out);
        const dir = Io.Dir.cwd();
        try dir.writeFile(io, .{ .sub_path = ".env.explicit.tmp", .data = out });
        defer dir.deleteFile(io, ".env.explicit.tmp") catch {};
        const check = try dir.readFileAlloc(io, ".env.explicit.tmp", allocator, .limited(8192));
        defer allocator.free(check);
        try stdout.print("--- After explicit serialize + std.Io write ---\n", .{});
        try stdout.print("round-trip equal={}\n", .{std.mem.eql(u8, out, check)});
    }

    try stdout.flush();
}
```

## Running

```bash
zig-out/bin/basic_example
```

## Example Output

```env
=== env.zig Basic Example ===

--- In-memory values (before file ops) ---
App: env.zig Demo
Port: 8080
Debug: true
DB URL: postgres://localhost:5432/mydb

All keys:
  APP_NAME=env.zig Demo
  PORT=8080
  DEBUG=true
  DATABASE_URL=postgres://localhost:5432/mydb

Serialized .env:
APP_NAME="env.zig Demo"
PORT=8080
DEBUG=true
DATABASE_URL=postgres://localhost:5432/mydb

--- Wrote .env file ---
File .env before local override:
APP_NAME="env.zig Demo"
PORT=8080
DEBUG=true
DATABASE_URL=postgres://localhost:5432/mydb

File .env.local:
PORT=9090
DEBUG=false

--- After implicit loadMany([.env, .env.local]) ---
PORT=9090 (local override)
DEBUG=false (local override)
APP_NAME=env.zig Demo (from .env)
--- After explicit std.Io read + parseString ---
PORT=9090 (local override)
DEBUG=false (local override)
APP_NAME=env.zig Demo (from .env)
--- After explicit serialize + std.Io write ---
round-trip equal=true
```

## Before / After

Before any file operation the store holds the in-memory values:

```env
APP_NAME="env.zig Demo"
PORT=8080
DEBUG=true
DATABASE_URL=postgres://localhost:5432/mydb
```

After `save(".env")` the `.env` file contains exactly those entries.
After `save(".env.local")` the `.env.local` file contains:

```env
PORT=9090
DEBUG=false
```

After `loadMany(&.{ ".env", ".env.local" })` (implicit read, library
owns the file IO) the merged store is:

```env
APP_NAME="env.zig Demo"
PORT=9090
DEBUG=false
DATABASE_URL=postgres://localhost:5432/mydb
```

The same result via explicit `std.Io` reads (caller owns the bytes,
no `load()` used):

```zig
const dotenv = try dir.readFileAlloc(io, ".env", allocator, .limited(8192));
defer allocator.free(dotenv);
try explicit.parseString(dotenv);
```

And explicit writes (caller owns the bytes, no `save()` used):

```zig
const out = try explicit.serialize();
defer allocator.free(out);
try dir.writeFile(io, .{ .sub_path = ".env.explicit.tmp", .data = out });
```

## See Also

- [Getting Started](/guide/getting-started) for configuration options
- [API Reference](/api/env) for the full API
