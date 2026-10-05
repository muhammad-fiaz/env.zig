---
title: OS Environment & Temporary Scopes
description: Cross-platform OS environment access on Windows, Linux, macOS — get/set/unset, snapshot/restore, and scoped temporary env ($env) with env.zig.
head:
  - - meta
    - property: og:title
      content: "OS Environment | env.zig"
  - - meta
    - name: description
      content: OS env bridging for Windows/Linux/macOS with temporary scopes.
  - - meta
    - name: keywords
      content: "zig, env, os env, getenv, setenv, windows, linux, macos, scope, temporary env, $env"
---

# OS Environment & Temporary Scopes

`env.zig` bridges `.env` files with the **real OS process environment** on Windows, Linux and macOS. Reads reuse Zig 0.17.0 `std.process.Environ` (case-insensitive on Windows, case-sensitive on POSIX); only `set`/`unset` use minimal custom bindings because std exposes no mutation API.

## Quick Start

```zig
const envMod = @import("env");
const runtime = envMod.runtime;

// Direct runtime access (cross-platform, process-global, thread-unsafe)
try runtime.set("MY_KEY", "my_value");
const v = runtime.get("MY_KEY"); // ?[]const u8, borrowed
try runtime.unset("MY_KEY");

// Env store with OS fallback
var env = envMod.Env.init(allocator, .{});
defer env.deinit();
try env.load(".env");
const host = env.getRuntime("HOST") orelse "localhost"; // Env first, then runtime
try env.loadRuntime();               // import all OS vars into Env
try env.loadRuntimeIfMissing();      // only missing keys
try env.loadRuntimeWithPrefix("APP_"); // APP_PORT -> PORT
try env.exportToRuntime();           // push Env -> OS
```

## Import / Export

```zig
// Import everything
try env.loadRuntime();

// Import only keys with prefix, stripped
// OS: APP_PORT=8080 -> Env: PORT=8080
try env.loadRuntimeWithPrefix("APP_");

// Export
try env.exportToRuntime();

// Also via config:
var env2 = envMod.Env.init(allocator, .{ .exportToRuntime = true });
try env2.set("FOO", "bar"); // automatically sets OS env too
```

## `getRuntime` / `containsRuntime` / `requireRuntime`

```zig
// Checks Env first, then runtime (like shell $VAR fallback)
const url = env.getRuntime("DATABASE_URL");
const ok = env.containsRuntime("HOME");
const val = try env.requireRuntime("API_KEY"); // error.MissingRequired if absent

// With default
const port = env.getWithFallback("PORT", "3000");

// Direct runtime (bypass Env); get is borrowed, getAlloc is owned
const home = runtime.get("HOME");
const home2 = try runtime.getAlloc(allocator, "HOME");
const all = try runtime.getAll(allocator);
// free keys/values when done
```

## Process Env Map (for child processes)

```zig
// Build an Environ.Map suitable for std.process.spawn / Child
var map = try env.toEnvironMap(allocator);
defer map.deinit();
try map.put("EXTRA", "value");

// Apply Env on top of an existing map
try env.applyToEnvironMap(&map);

// Then spawn with custom env:
// try std.process.spawn(io, .{ .argv = &.{ "myapp" }, .environ_map = &map });
```

## Temporary / Scoped Env (`$env` style)

OS environment is **global**. `Scope` saves original values and restores on `deinit` — perfect for tests and `$env:FOO=bar` shell-style isolation.

### OS-level Scope

```zig
{
    var scope = try runtime.scope(allocator);
    defer scope.deinit();
    try scope.set("TMP_KEY", "temporary");
    try scope.unset("REMOVE_ME");
    // ... do work, spawn children, etc.
    // original values restored on deinit
}
// TMP_KEY and REMOVE_ME are back to what they were
```

### With helper

```zig
try runtime.Scope.with(allocator, &.{ .{ .key = "FOO", .value = "bar" } }, struct {
    fn run() !void { std.debug.print("FOO={s}\n", .{runtime.get("FOO").?}); }
}.run);
```

### Snapshot / Restore

```zig
var snap = try runtime.snapshot(allocator);
defer snap.deinit();
try runtime.set("A", "new");
try snap.restore(); // back to snapshot
```

### Env-level Scope (in-memory)

```zig
{
    var s = env.scope(); // Env.EnvScope
    defer s.deinit();
    try s.set("PORT", "9090");
    try s.unset("DEBUG");
    // env.get("PORT") now 9090
}
// restored
```

## `export` Prefix

`.env` files may use shell-style `export` — it is ignored but accepted:

```env
export DATABASE_URL=postgres://localhost/mydb
export PORT=8080
```

## Windows Notes

- Case-insensitive: `PATH` and `Path` are the same.
- Missing (`null`) is distinct from empty (`""`); both are preserved.
- `runtime.get` is borrowed from a thread-local buffer resized per call
  (valid until the next `get` on the same thread); dupe to retain.
  `Environ.createMap` (PEB-locked) backs enumeration.

## See Also

- [Interpolation](/guide/interpolation) — `${VAR:-default}`, `${VAR:+alt}`, OS fallback
- [Configuration](/guide/configuration)
- [API Reference](/api/env)
