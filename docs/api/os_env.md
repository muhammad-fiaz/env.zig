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

# OsEnv / runtime API Reference

Reads reuse Zig 0.17.0 `std.process.Environ` (`createMap`, PEB-locked on
Windows). Only `set`/`unset` use minimal custom OS bindings because the
standard library exposes no mutation API. Prefer `env.runtime.*` for
process env; `OsEnv` remains as an alias.

## `OsEnv`

### `get`

```zig
pub fn get(key: []const u8) ?[]const u8
```

POSIX `getenv` or Windows `GetEnvironmentVariableW` (thread-local owned
buffer resized per call, valid until the next `get` on the same thread;
dupe to retain). Distinguishes missing (`null`) from empty (`""`).
Case-insensitive on Windows.

### `getAlloc`

```zig
pub fn getAlloc(allocator: std.mem.Allocator, key: []const u8) !?[]u8
```

Owned copy.

### `getOrDefault` / `exists` / `isEmpty`

```zig
pub fn getOrDefault(key: []const u8, defaultValue: []const u8) []const u8
pub fn exists(key: []const u8) bool
pub fn isEmpty(key: []const u8) bool
```

### `set` / `unset`

```zig
pub fn set(key: []const u8, value: []const u8) !void // error.InvalidKey/InvalidValue/IoError
pub fn unset(key: []const u8) !void
```

Keys use `std.process.Environ.Map.validateKeyForPut` (non-empty, no `=`,
no NUL, valid WTF-8 on Windows). Values reject NUL.

### `getMap` / `getAllAlloc`

```zig
pub fn getMap(allocator: std.mem.Allocator) !std.process.Environ.Map // via std.process.Environ.createMap
pub fn getAllAlloc(allocator: std.mem.Allocator) !std.StringHashMap([]const u8) // caller frees keys/values
```

`getAllAlloc` reuses `getMap` (`Environ.createMap`) then dupes into a
`StringHashMap`; no manual PEB/`environ` parsing remains.

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

Re-exported as `env.runtime` (preferred) and `env.OsEnv` / `Scope` /
`Snapshot`, plus `Env` helpers: `loadOsEnv`, `loadOsEnvIfMissing`,
`loadOsEnvWithPrefix`, `exportToOsEnv`, `getOs`, `getOsAlloc`,
`containsOs`, `getWithFallback`, `requireOs`, `toEnvironMap`, `EnvScope`.

See [OS Environment Guide](/guide/os-env) for examples and Windows notes (empty `FOO=` deletes on OS, preserved in `Env`).
