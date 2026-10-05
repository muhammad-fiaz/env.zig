---
title: File I/O Example
description: File I/O with env.zig — load, save, loadMany, reload, and prefix-filtered runtime env.
head:
  - - meta
    - property: og:title
      content: "File I/O Example | env.zig"
  - - meta
    - name: description
      content: File I/O example for env.zig.
  - - meta
    - name: keywords
      content: "zig, env, file, load, save, example, env.zig"
---

# File I/O Example

Demonstrates file persistence, `loadMany` with override, `reload`,
and `loadRuntimeWithPrefix`.

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

    try stdout.print("=== File I/O Example ===\n\n", .{});

    // 1) Parse from string (no file needed)
    var env = envMod.Env.init(allocator, .{});
    defer env.deinit();
    try env.parseString(
        \\# app config
        \\APP_NAME=FileIODemo
        \\PORT=8080
        \\DEBUG=true
        \\
    );
    try stdout.print("Parsed {d} entries from string\n", .{env.count()});

    // 2) Save to file and reload
    try env.save(".env.demo.tmp");
    defer {
        const dir = Io.Dir.cwd();
        dir.deleteFile(io, ".env.demo.tmp") catch {};
    }
    try stdout.print("Saved to .env.demo.tmp\n", .{});

    // 2b) Explicit read: caller-owned std.Io, no load() used.
    // The caller owns the file bytes and decides when to parse them.
    var explicit = envMod.Env.init(allocator, .{});
    defer explicit.deinit();
    {
        const dir = Io.Dir.cwd();
        const raw = try dir.readFileAlloc(io, ".env.demo.tmp", allocator, .limited(8192));
        defer allocator.free(raw);
        try stdout.print("Explicit read {d} bytes from .env.demo.tmp\n", .{raw.len});
        try explicit.parseString(raw);
    }
    try stdout.print("Explicit parsed PORT={s}\n", .{explicit.get("PORT").?});

    // 2c) Explicit write: serialize to caller-owned bytes, then write
    // with the caller's io. No save() used.
    {
        const out = try explicit.serialize();
        defer allocator.free(out);
        const dir = Io.Dir.cwd();
        try dir.writeFile(io, .{ .sub_path = ".env.explicit.tmp", .data = out });
        defer dir.deleteFile(io, ".env.explicit.tmp") catch {};
        const check = try dir.readFileAlloc(io, ".env.explicit.tmp", allocator, .limited(8192));
        defer allocator.free(check);
        try stdout.print("Explicit write round-trip equal={}\n", .{std.mem.eql(u8, out, check)});
    }

    var env2 = envMod.Env.init(allocator, .{});
    defer env2.deinit();
    // Correct error handling: FileNotFound vs IoError
    env2.load(".env.demo.tmp") catch |err| switch (err) {
        error.FileNotFound => try stdout.print("File not found!\n", .{}),
        error.IoError => try stdout.print("I/O error!\n", .{}),
        else => return err,
    };
    try stdout.print("Reloaded PORT={s}\n", .{env2.get("PORT").?});

    // 3) Load many with override control
    try env2.save(".env.a.tmp");
    try env.save(".env.b.tmp");
    defer {
        const dir = Io.Dir.cwd();
        dir.deleteFile(io, ".env.a.tmp") catch {};
        dir.deleteFile(io, ".env.b.tmp") catch {};
    }
    // Write second file with override
    {
        const dir = Io.Dir.cwd();
        try dir.writeFile(io, .{ .sub_path = ".env.b.tmp", .data = "PORT=9090\nNEW_KEY=from_b\n" });
    }
    var env3 = envMod.Env.init(allocator, .{ .override = true });
    defer env3.deinit();
    try env3.loadMany(&.{ ".env.a.tmp", ".env.b.tmp" });
    try stdout.print("loadMany override PORT={s} NEW_KEY={s}\n", .{ env3.get("PORT").?, env3.get("NEW_KEY").? });

    var env4 = envMod.Env.init(allocator, .{ .override = false });
    defer env4.deinit();
    try env4.parseString("PORT=1111\n");
    try env4.loadMany(&.{".env.b.tmp"}); // will NOT override because override=false
    try stdout.print("No-override PORT stays {s} (expected 1111)\n", .{env4.get("PORT").?});

    // 4) reload (transactional: old state preserved on failure)
    try env4.reload(".env.a.tmp");
    try stdout.print("After reload count={d}\n", .{env4.count()});

    // 5) export prefix and runtime bridge
    try envMod.runtime.set("APP_FILE_IO_TEST", "prefix_val");
    defer envMod.runtime.unset("APP_FILE_IO_TEST") catch {};
    var env5 = envMod.Env.init(allocator, .{});
    defer env5.deinit();
    try env5.loadRuntimeWithPrefix("APP_");
    try stdout.print("loadRuntimeWithPrefix APP_FILE_IO_TEST -> FILE_IO_TEST={s}\n", .{env5.get("FILE_IO_TEST") orelse "missing"});

    // 6) Serialize with options
    var sorted = envMod.Env.init(allocator, .{ .sortKeys = true, .quoteSpaces = true });
    defer sorted.deinit();
    try sorted.set("Z_KEY", "last");
    try sorted.set("A_KEY", "first");
    try sorted.set("MSG", "needs quote"); // value with space is auto-quoted
    const out = try sorted.serialize();
    defer allocator.free(out);
    try stdout.print("\nSerialized sorted:\n{s}\n", .{out});

    try stdout.flush();
}
```

## Running

```bash
zig build example
zig-out/bin/file_io_example
```

## Example Output

```env
=== File I/O Example ===

Parsed 3 entries from string
Saved to .env.demo.tmp
Explicit read 41 bytes from .env.demo.tmp
Explicit parsed PORT=8080
Explicit write round-trip equal=true
Reloaded PORT=8080
loadMany override PORT=9090 NEW_KEY=from_b
No-override PORT stays 1111 (expected 1111)
After reload count=3
loadRuntimeWithPrefix APP_FILE_IO_TEST -> FILE_IO_TEST=prefix_val

Serialized sorted:
A_KEY=first
MSG="needs quote"
Z_KEY=last
```

## Before / After

Parsed input file content:

```env
APP_NAME=FileIODemo
PORT=8080
DEBUG=true
```

After `loadMany` with `override = true` over `.env.b.tmp`:

```env
PORT=9090
NEW_KEY=from_b
```

With `override = false` the existing value wins:

```env
PORT=1111
```

## Implicit vs Explicit IO

Implicit (`load`/`save`) — the library owns the `std.Io` setup:

```zig
try env.save(".env.demo.tmp");
try env2.load(".env.demo.tmp");
```

Explicit (`std.Io` + `parseString`/`serialize`) — the caller owns the
file bytes, buffers, and `io` lifetime; the library never sees the file:

```zig
const raw = try dir.readFileAlloc(io, ".env.demo.tmp", allocator, .limited(8192));
defer allocator.free(raw);
try explicit.parseString(raw);

const out = try explicit.serialize();
defer allocator.free(out);
try dir.writeFile(io, .{ .sub_path = ".env.explicit.tmp", .data = out });
```

## See Also

- [Getting Started](/guide/getting-started) for load/save semantics
- [API Reference](/api/env) for the full API
