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

`env.zig` bridges `.env` files with the **real OS process environment** on Windows, Linux and macOS. It uses `getenv`/`setenv`/`unsetenv` on POSIX and `GetEnvironmentVariableW`/`SetEnvironmentVariableW`/`GetEnvironmentStringsW` on Windows (case-insensitive on Windows, case-sensitive on POSIX).

## Quick Start

```zig
const env_mod = @import("env");
const OsEnv = env_mod.OsEnv;
const Scope = env_mod.Scope;

// Direct OS access (cross-platform)
try OsEnv.set("MY_KEY", "my_value");
const v = OsEnv.get("MY_KEY"); // ?[]const u8
try OsEnv.unset("MY_KEY");

// Env store with OS fallback
var env = env_mod.Env.init(allocator, .{});
defer env.deinit();
try env.load(".env");
const host = env.getOs("HOST") orelse "localhost"; // Env first, then OS
try env.loadOsEnv();               // import all OS vars into Env
try env.loadOsEnvIfMissing();      // only missing keys
try env.loadOsEnvWithPrefix("APP_"); // APP_PORT -> PORT
try env.exportToOsEnv();           // push Env -> OS
```

## Import / Export

```zig
// Import everything
try env.loadOsEnv();

// Import only keys with prefix, stripped
// OS: APP_PORT=8080 -> Env: PORT=8080
try env.loadOsEnvWithPrefix("APP_");

// Export
try env.exportToOsEnv();

// Also via config:
var env2 = env_mod.Env.init(allocator, .{ .export_to_env = true });
try env2.set("FOO", "bar"); // automatically sets OS env too
```

## `getOs` / `containsOs` / `require`

```zig
// Checks Env first, then OS (like shell $VAR fallback)
const url = env.getOs("DATABASE_URL");
const ok = env.containsOs("HOME");
const val = try env.require("API_KEY"); // error.MissingRequired if absent

// With default
const port = env.getWithFallback("PORT", "3000");

// Direct OS (bypass Env)
const home = OsEnv.get("HOME");
const home2 = try OsEnv.getAlloc(allocator, "HOME");
const all = try OsEnv.getAllAlloc(allocator);
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
    var scope = Scope.init(allocator);
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
try Scope.with(allocator, &.{ .{ .key = "FOO", .value = "bar" } }, struct {
    fn run() !void { std.debug.print("FOO={s}\n", .{OsEnv.get("FOO").?}); }
}.run);
```

### Snapshot / Restore

```zig
var snap = try OsEnv.snapshot(allocator);
defer snap.deinit();
try OsEnv.set("A", "new");
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
- Empty string `FOO=` is kept as `""` in `Env` but on Windows empty OS vars may be deleted when exported (Windows treats `FOO=` as unset). `Env` always preserves empty values.
- `GetEnvironmentStringsW` / PEB locking is handled internally.

## See Also

- [Interpolation](/guide/interpolation) — `${VAR:-default}`, `${VAR:+alt}`, OS fallback
- [Configuration](/guide/configuration)
- [API Reference](/api/env)
