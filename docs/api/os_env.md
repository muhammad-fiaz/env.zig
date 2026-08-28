---
title: OsEnv API
description: Cross-platform OS environment API — get/set/unset, getAll, snapshot/restore, and Scope for Windows/Linux/macOS.
head:
  - - meta
    - property: og:title
      content: "OsEnv API | env.zig"
  - - meta
    - name: description
      content: OsEnv API for native OS env on Windows/Linux/macOS.
  - - meta
    - name: keywords
      content: "zig, env, OsEnv, Scope, Snapshot, getenv, GetEnvironmentVariableW, windows, linux, macos"
---

# OsEnv API Reference

Native OS environment bridge. Uses `std.c.getenv` / `setenv`/`unsetenv` on POSIX and `GetEnvironmentVariableW`/`SetEnvironmentVariableW`/`GetEnvironmentStringsW` (with `SetLastError(0)` and WTF-16LE ↔ WTF-8) on Windows. Reuses `std.process.Environ` semantics (case-insensitive on Windows).

## `OsEnv`

### `get`

```zig
pub fn get(key: []const u8) ?[]const u8
```

POSIX `getenv` or Windows `GetEnvironmentVariableW` (thread-local TLS buffer, valid until next `get`). Case-insensitive on Windows.

### `getAlloc`

```zig
pub fn getAlloc(allocator: std.mem.Allocator, key: []const u8) !?[]u8
```

Owned copy.

### `getOrDefault` / `exists` / `isEmpty`

```zig
pub fn getOrDefault(key: []const u8, default: []const u8) []const u8
pub fn exists(key: []const u8) bool
pub fn isEmpty(key: []const u8) bool
```

### `set` / `unset`

```zig
pub fn set(key: []const u8, value: []const u8) !void // error.InvalidKey / SetEnvFailed
pub fn unset(key: []const u8) !void
```

### `getMap` / `getAllAlloc`

```zig
pub fn getMap(allocator: std.mem.Allocator) !std.process.Environ.Map // via std.process.Environ.createMap
pub fn getAllAlloc(allocator: std.mem.Allocator) !std.StringHashMap([]const u8) // caller frees keys/values
```

`getAllAlloc` on Windows parses `GetEnvironmentStringsW` block (PEB), handling `=C:` drive prefixes; on POSIX iterates `std.c.environ`.

### `snapshot`

```zig
pub fn snapshot(allocator: std.mem.Allocator) !Snapshot
```

## `Snapshot`

```zig
pub const Snapshot = struct {
    pub fn deinit(self: *Snapshot) void
    pub fn restore(self: *const Snapshot) !void // removes added keys, restores saved
};
```

Captures `getAllAlloc`; `restore` diffs current vs snapshot.

## `Scope`

Temporary `$env`-style isolation. Saves original values for touched keys, restores on `deinit`.

```zig
pub const Scope = struct {
    pub fn init(allocator: std.mem.Allocator) Scope
    pub fn deinit(self: *Scope) void // restores
    pub fn set(self: *Scope, key: []const u8, value: []const u8) !void
    pub fn unset(self: *Scope, key: []const u8) !void
    pub fn restore(self: *Scope) !void
    pub fn with(allocator: std.mem.Allocator, overrides: []const struct{key:[]const u8, value:?[]const u8}, func: *const fn()anyerror!void) !void
};
```

## Env integration

Re-exported as `env.Mod.OsEnv` / `Scope` / `Snapshot`, plus `Env` helpers: `loadOsEnv`, `loadOsEnvIfMissing`, `loadOsEnvWithPrefix`, `exportToOsEnv`, `getOs`, `containsOs`, `getWithFallback`, `require`, `toEnvironMap`, `EnvScope`.

See [OS Environment Guide](/guide/os-env) for examples and Windows notes (empty `FOO=` deletes on OS, preserved in `Env`).
