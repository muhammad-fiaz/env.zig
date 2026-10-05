---
title: Runtime Example
description: Working runtime environment example — set/get/unset, snapshot, scope via env.runtime.
head:
  - - meta
    - property: og:title
      content: "Runtime Example | env.zig"
  - - meta
    - name: description
      content: Working runtime environment example via env.runtime.
  - - meta
    - name: keywords
      content: "zig, env, runtime, scope, snapshot, example, env.zig"
---

# Runtime Example

Single runtime namespace (`env.runtime`) with snapshot-backed scopes.
Demonstrates set/get/overwrite, missing vs empty, key validation,
long values, snapshot/restore, and scoped restoration.

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

    try stdout.print("=== Runtime Example ===\n\n", .{});

    const runtime = envMod.runtime;

    // Set / get / overwrite.
    try runtime.set("ENV_ZIG_DEMO_RT", "one");
    try stdout.print("set one -> {s}\n", .{runtime.get("ENV_ZIG_DEMO_RT").?});
    try runtime.set("ENV_ZIG_DEMO_RT", "two");
    try stdout.print("overwrite -> {s}\n", .{runtime.get("ENV_ZIG_DEMO_RT").?});

    // Empty vs missing.
    try runtime.set("ENV_ZIG_DEMO_RT_EMPTY", "");
    try stdout.print("empty get len={d} exists={} isEmpty={}\n", .{
        runtime.get("ENV_ZIG_DEMO_RT_EMPTY").?.len,
        runtime.exists("ENV_ZIG_DEMO_RT_EMPTY"),
        runtime.isEmpty("ENV_ZIG_DEMO_RT_EMPTY"),
    });
    try stdout.print("missing get={?s} exists={} isEmpty={}\n", .{
        runtime.get("ENV_ZIG_DEMO_RT_MISSING"),
        runtime.exists("ENV_ZIG_DEMO_RT_MISSING"),
        runtime.isEmpty("ENV_ZIG_DEMO_RT_MISSING"),
    });

    // Key validation rejects empty, `=` and NUL.
    for ([_][]const u8{ "", "A=B", "A\x00B" }) |bad| {
        if (runtime.set(bad, "v")) |_| {
            try stdout.print("unexpected success for bad key len={d}\n", .{bad.len});
        } else |err| {
            try stdout.print("bad key rejected -> {s}\n", .{@errorName(err)});
        }
    }
    if (runtime.set("ENV_ZIG_DEMO_RT", "a\x00b")) |_| {
        try stdout.print("unexpected NUL value success\n", .{});
    } else |err| {
        try stdout.print("NUL value rejected -> {s}\n", .{@errorName(err)});
    }

    // Long value (heap fallback, no fixed limits).
    const long = try allocator.alloc(u8, 16384);
    defer allocator.free(long);
    @memset(long, 'x');
    try runtime.set("ENV_ZIG_DEMO_RT_LONG", long);
    try stdout.print("long len={d} ok={}\n", .{
        runtime.get("ENV_ZIG_DEMO_RT_LONG").?.len,
        std.mem.eql(u8, runtime.get("ENV_ZIG_DEMO_RT_LONG").?, long),
    });

    // Snapshot / restore.
    {
        var snap = try runtime.snapshot(allocator);
        defer snap.deinit();
        try runtime.set("ENV_ZIG_DEMO_RT", "modified");
        try runtime.set("ENV_ZIG_DEMO_RT_NEW", "new");
        try snap.restore();
        try stdout.print("after restore RT={s} NEW={?s}\n", .{
            runtime.get("ENV_ZIG_DEMO_RT").?,
            runtime.get("ENV_ZIG_DEMO_RT_NEW"),
        });
    }

    // Scope with automatic restoration (built on snapshot, nesting LIFO).
    {
        var scope = try runtime.scope(allocator);
        defer scope.deinit();
        try scope.set("ENV_ZIG_DEMO_RT", "scoped");
        try scope.unset("ENV_ZIG_DEMO_RT_EMPTY");
        try stdout.print("in scope RT={s} EMPTY={?s}\n", .{
            runtime.get("ENV_ZIG_DEMO_RT").?,
            runtime.get("ENV_ZIG_DEMO_RT_EMPTY"),
        });
    }
    try stdout.print("after scope RT={s}\n", .{runtime.get("ENV_ZIG_DEMO_RT").?});

    try runtime.unset("ENV_ZIG_DEMO_RT");
    try runtime.unset("ENV_ZIG_DEMO_RT_EMPTY");
    try runtime.unset("ENV_ZIG_DEMO_RT_LONG");
    try stdout.print("cleanup done, RT={?s}\n", .{runtime.get("ENV_ZIG_DEMO_RT")});

    try stdout.flush();
}
```

## Running

```bash
zig-out/bin/runtime_example
```

## Example Output

```env
=== Runtime Example ===

set one -> one
overwrite -> two
empty get len=0 exists=true isEmpty=true
missing get=null exists=false isEmpty=true
bad key rejected -> InvalidKey
bad key rejected -> InvalidKey
bad key rejected -> InvalidKey
NUL value rejected -> InvalidValue
long len=16384 ok=true
after restore RT=two NEW=null
in scope RT=scoped EMPTY=null
after scope RT=two
cleanup done, RT=null
```

## Before / After

Before the scope block:

```env
ENV_ZIG_DEMO_RT=two
ENV_ZIG_DEMO_RT_EMPTY=
```

Inside the scope:

```env
ENV_ZIG_DEMO_RT=scoped
# ENV_ZIG_DEMO_RT_EMPTY unset (missing)
```

After `deinit` the original process state is restored:

```env
ENV_ZIG_DEMO_RT=two
ENV_ZIG_DEMO_RT_EMPTY=
```

## See Also

- [OS Environment Guide](/guide/os-env) for runtime semantics
- [API Reference](/api/runtime) for the full runtime API
