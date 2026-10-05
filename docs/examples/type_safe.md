---
title: Type-Safe Example
description: Type-safe accessors in env.zig — getBool, getInt, getFloat, getEnum, getList with runtime fallback.
head:
  - - meta
    - property: og:title
      content: "Type-Safe Example | env.zig"
  - - meta
    - name: description
      content: Type-safe accessors example for env.zig.
  - - meta
    - name: keywords
      content: "zig, env, types, getBool, getInt, example, env.zig"
---

# Type-Safe Example

Covers `get`/`getBool`/`getInt`/`getFloat`/`getEnum`/`getList` with
`getRuntime`/`getWithFallback` and `containsRuntime`.

## Source Code

```zig
const std = @import("std");
const Io = std.Io;
const envMod = @import("env");

const Mode = enum { debug, release, testing };

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var env = envMod.Env.init(allocator, .{});
    defer env.deinit();

    try env.parseString(
        \\PORT=8080
        \\DEBUG=true
        \\RATIO=3.14
        \\MODE=release
        \\HOSTS="127.0.0.1, 10.0.0.1, localhost"
        \\EMPTY=
        \\
    );

    var stdoutBuffer: [0x2000]u8 = undefined;
    var stdoutWriter = Io.File.stdout().writer(io, &stdoutBuffer);
    const stdout = &stdoutWriter.interface;

    try stdout.print("=== Type-Safe Accessors Example ===\n\n", .{});

    // get / getString
    try stdout.print("get PORT raw: {s}\n", .{env.get("PORT").?});
    try stdout.print("getString PORT: {s}\n", .{env.getString("PORT").?});
    try stdout.print("get missing -> {?s} (null)\n", .{env.get("MISSING")});

    // getInt with different int types and error handling
    if (env.getInt(u16, "PORT")) |p| try stdout.print("getInt u16 PORT = {d}\n", .{p}) else try stdout.print("getInt failed\n", .{});
    if (env.getInt(i32, "PORT")) |p| try stdout.print("getInt i32 PORT = {d}\n", .{p});
    try stdout.print("getInt invalid EMPTY = {?d}\n", .{env.getInt(i32, "EMPTY")});
    try stdout.print("getInt missing = {?d}\n", .{env.getInt(i32, "MISSING")});

    // getFloat
    if (env.getFloat(f64, "RATIO")) |f| try stdout.print("getFloat RATIO = {d}\n", .{f});
    try stdout.print("getFloat PORT as f64 = {d}\n", .{env.getFloat(f64, "PORT").?});

    // getBool accepts true/false/yes/no/1/0/on/off (case-insensitive).
    for ([_][]const u8{ "true", "True", "yes", "1", "on", "false", "no", "0", "off", "maybe" }) |val| {
        var tmp = envMod.Env.init(allocator, .{});
        defer tmp.deinit();
        try tmp.set("K", val);
        try stdout.print("  getBool {s} -> {any}\n", .{ val, tmp.getBool("K") });
    }

    // getEnum
    try stdout.print("getEnum MODE = {any}\n", .{env.getEnum(Mode, "MODE")});
    try stdout.print("getEnum PORT as Mode = {any} (null expected)\n", .{env.getEnum(Mode, "PORT")});

    // getList returns owned strings: free each item, then the slice.
    if (env.getList(allocator, "HOSTS", ',')) |list| {
        defer {
            for (list) |item| allocator.free(item);
            allocator.free(list);
        }
        try stdout.print("getList HOSTS count={d}\n", .{list.len});
        for (list, 0..) |h, i| try stdout.print("  [{d}] {s}\n", .{ i, h });
    }

    // Empty list (null when missing or when no non-empty segments).
    if (env.getList(allocator, "EMPTY", ',')) |emptyList| {
        defer {
            for (emptyList) |item| allocator.free(item);
            allocator.free(emptyList);
        }
        try stdout.print("getList EMPTY count={d}\n", .{emptyList.len});
    } else {
        try stdout.print("getList EMPTY = null (empty)\n", .{});
    }

    // Generic typed API with defaults.
    try stdout.print("getValue u16 PORT = {d}\n", .{env.getValue(u16, "PORT").?});
    try stdout.print("getValueOrDefault u16 MISSING = {d}\n", .{env.getValueOrDefault(u16, "MISSING", 9999)});
    try stdout.print("requireValue MODE = {any}\n", .{try env.requireValue(Mode, "MODE")});

    // Fallback default (checks Env, then runtime).
    try stdout.print("getWithFallback MISSING -> {s}\n", .{env.getWithFallback("MISSING", "fallback")});
    try stdout.print("getWithFallback PORT -> {s}\n", .{env.getWithFallback("PORT", "3000")});

    // tryGet* distinguishes missing (null) from invalid (error.TypeMismatch)
    try stdout.print("tryGetInt MISSING -> {any} (null)\n", .{try env.tryGetInt(i32, "MISSING")});
    try stdout.print("tryGetInt PORT -> {d}\n", .{(try env.tryGetInt(i32, "PORT")).?});
    if (env.tryGetInt(i32, "MODE")) |_| {
        try stdout.print("tryGetInt MODE unexpectedly succeeded\n", .{});
    } else |err| {
        try stdout.print("tryGetInt MODE -> {s} (invalid, not defaulted)\n", .{@errorName(err)});
    }
    try stdout.print("tryGetBool MISSING -> {any} (null)\n", .{try env.tryGetBool("MISSING")});
    try stdout.print("tryGetEnum MODE -> {any}\n", .{try env.tryGetEnum(Mode, "MODE")});

    // contains / containsRuntime
    try stdout.print("contains PORT={} containsRuntime HOME={}\n", .{ env.contains("PORT"), env.containsRuntime("HOME") });

    // Runtime fallback display
    try envMod.runtime.set("TYPE_SAFE_OS_TEST", "from_os");
    defer envMod.runtime.unset("TYPE_SAFE_OS_TEST") catch {};
    try stdout.print("getRuntime TYPE_SAFE_OS_TEST = {s}\n", .{env.getRuntime("TYPE_SAFE_OS_TEST").?});

    try stdout.flush();
}
```

## Running

```bash
zig build example
zig-out/bin/type_safe_example
```

## Example Output

```env
=== Type-Safe Accessors Example ===

get PORT raw: 8080
getString PORT: 8080
get missing -> null (null)
getInt u16 PORT = 8080
getInt i32 PORT = 8080
getInt invalid EMPTY = null
getInt missing = null
getFloat RATIO = 3.14
getFloat PORT as f64 = 8080
  getBool true -> true
  getBool True -> true
  getBool yes -> true
  getBool 1 -> true
  getBool on -> true
  getBool false -> false
  getBool no -> false
  getBool 0 -> false
  getBool off -> false
  getBool maybe -> null
getEnum MODE = .release
getEnum PORT as Mode = null (null expected)
getList HOSTS count=3
  [0] 127.0.0.1
  [1] 10.0.0.1
  [2] localhost
getList EMPTY = null (empty)
getValue u16 PORT = 8080
getValueOrDefault u16 MISSING = 9999
requireValue MODE = .release
getWithFallback MISSING -> fallback
getWithFallback PORT -> 8080
tryGetInt MISSING -> null (null)
tryGetInt PORT -> 8080
tryGetInt MODE -> TypeMismatch (invalid, not defaulted)
tryGetBool MISSING -> null (null)
tryGetEnum MODE -> .release
contains PORT=true containsRuntime HOME=false
getRuntime TYPE_SAFE_OS_TEST = from_os
```

## Before / After

Parsed input:

```env
PORT=8080
DEBUG=true
RATIO=3.14
MODE=release
HOSTS="127.0.0.1, 10.0.0.1, localhost"
EMPTY=
```

Typed view after conversion:

```env
PORT=8080
DEBUG=true
RATIO=3.14
MODE=release
HOSTS=127.0.0.1, 10.0.0.1, localhost
EMPTY=
```

Note: `HOSTS` splits into three owned items; `EMPTY` yields `null`.

## See Also

- [API Reference](/api/env) for typed getters
- [Runtime Reference](/api/runtime) for runtime typed getters
