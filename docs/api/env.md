---
title: Env API
description: Full API reference for Env and OsEnv — parsing, OS bridging (Windows/Linux/macOS), interpolation, validation, and scopes.
head:
  - - meta
    - property: og:title
      content: "Env API | env.zig"
  - - meta
    - name: description
      content: Full API reference for Env and OsEnv in env.zig.
  - - meta
    - name: keywords
      content: "zig, env, API, Env, OsEnv, Scope, EnvScope, Snapshot, Environ.Map, interpolate, os env"
---

# Env API Reference

The main environment store. Owns all allocated memory. Reuses `std.Io`, `std.process.Environ`, `std.unicode` primitives from `std.zig`.

## Initialization

### `Env.init`

```zig
pub fn init(allocator: std.mem.Allocator, cfg: Config) Env
```

### `Env.deinit`

```zig
pub fn deinit(self: *Env) void
```

## Loading

### `load` / `parseString` / `loadMany` / `reload`

```zig
pub fn load(self: *Env, path: []const u8) !void
pub fn parseString(self: *Env, source: []const u8) !void
pub fn loadMany(self: *Env, paths: []const []const u8) !void
pub fn reload(self: *Env, path: []const u8) !void
```

`load` uses `std.Io.Dir.cwd().readFileAlloc` + `parser.parse`; `export` prefix is stripped by `parser`.

## Reading Values

### `get` / `getString` / `getBool` / `getInt` / `getFloat` / `getEnum` / `getList` / `contains`

```zig
pub fn get(self: *const Env, key: []const u8) ?[]const u8
pub fn getBool(self: *const Env, key: []const u8) ?bool // true/false/yes/no/1/0/on/off
pub fn getInt(self: *const Env, comptime T: type, key: []const u8) ?T
pub fn getList(self: *const Env, allocator: std.mem.Allocator, key: []const u8, delimiter: u8) ?[][]const u8
```

### OS-aware reads

```zig
pub fn getOs(self: *const Env, key: []const u8) ?[]const u8 // Env → OsEnv fallback
pub fn containsOs(self: *const Env, key: []const u8) bool
pub fn getWithFallback(self: *const Env, key: []const u8, fallback: []const u8) []const u8
pub fn require(self: *const Env, key: []const u8) ![]const u8 // error.MissingRequired
pub fn fetchOs(self: *Env, key: []const u8) !?[]const u8 // copy OS → Env
```

## Writing & Updating

### `set` / `setOs` / `merge`

```zig
pub fn set(self: *Env, key: []const u8, value: []const u8) !void // respects export_to_env
pub fn setOs(self: *Env, key: []const u8, value: []const u8) !void // always syncs OsEnv
pub fn merge(self: *Env, other: *const Env) !void
```

### OS load / export

```zig
pub fn loadOsEnv(self: *Env) !void // all OS → Env (override per config)
pub fn loadOsEnvIfMissing(self: *Env) !void
pub fn loadOsEnvWithPrefix(self: *Env, prefix: []const u8) !void // APP_FOO → FOO
pub fn exportToOsEnv(self: *const Env) !void // Env → OsEnv.set
```

## Deleting

### `remove` / `unsetOs` / `clear`

```zig
pub fn remove(self: *Env, key: []const u8) bool // also OsEnv.unset if export_to_env
pub fn unsetOs(self: *Env, key: []const u8) bool
pub fn clear(self: *Env) void
```

## Iteration

### `count` / `keys` / `iterator`

```zig
pub fn count(self: *const Env) usize
pub fn keys(self: *const Env) []const []const u8 // insertion order
pub fn iterator(self: *const Env) Iterator // allocs Entry slice; free after use
```

## Serialization

### `serialize` / `save`

Uses `helpers.needsQuoting`/`escapedForChar` (single source) via `Serializer`.

```zig
pub fn serialize(self: *const Env) ![]const u8
pub fn save(self: *const Env, path: []const u8) !void // via Writer/Serializer
```

## Scopes & Snapshots

### `EnvScope`

```zig
pub const EnvScope = struct { pub fn init(env: *Env) EnvScope; pub fn set(...); pub fn unset(...); pub fn deinit(...) }
pub fn scope(self: *Env) EnvScope
pub fn withTemp(self: *Env, key: []const u8, value: []const u8, func: *const fn(*Env) anyerror!void) !void
```

### `OsEnv`

Re-exported from `os_env.zig` — cross-platform (`setenv`/`GetEnvironmentVariableW` with `SetLastError(0)`).

```zig
pub const OsEnv = os_env.OsEnv; // get/set/unset/getAll/snapshot + thread-local TLS
pub const Scope = os_env.Scope; // OS-level temporary env
pub const Snapshot = os_env.Snapshot;
pub fn snapshotOs(self: *const Env) !Snapshot
```

```zig
// OsEnv direct
try OsEnv.set("K","v");
const v = OsEnv.get("K");
try OsEnv.unset("K");
var m = try OsEnv.getAllAlloc(allocator); // StringHashMap
var snap = try OsEnv.snapshot(allocator); defer snap.deinit(); try snap.restore();
var sc = Scope.init(allocator); defer sc.deinit(); try sc.set("K","tmp");

// Env → child env
var map = try env.toEnvironMap(allocator); defer map.deinit();
try env.applyToEnvironMap(&map);
```

## Utilities

### `clone` / `validate`

```zig
pub fn clone(self: *const Env) !Env
pub fn validate(self: *const Env, s: Schema) []ValidationError
pub fn toEnvironMap(self: *const Env, allocator: std.mem.Allocator) !std.process.Environ.Map
pub fn applyToEnvironMap(self: *const Env, map: *std.process.Environ.Map) !void
```
