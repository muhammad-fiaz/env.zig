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

### `get` / `getString` / `getAlloc` / `getOrDefault` / `getBool` / `getInt` / `getFloat` / `getEnum` / `getValue` / `getList` / `contains` / `isEmpty` / `require`

```zig
pub fn get(self: *const Env, key: []const u8) ?[]const u8 // borrowed; null = missing
pub fn getAlloc(self: *const Env, allocator: std.mem.Allocator, key: []const u8) !?[]u8 // owned
pub fn getOrDefault(self: *const Env, key: []const u8, defaultValue: []const u8) []const u8
pub fn getBool(self: *const Env, key: []const u8) ?bool // true/false/yes/no/1/0/on/off
pub fn getInt(self: *const Env, comptime T: type, key: []const u8) ?T
pub fn getFloat(self: *const Env, comptime T: type, key: []const u8) ?T
pub fn getEnum(self: *const Env, comptime E: type, key: []const u8) ?E
pub fn getValue(self: *const Env, comptime T: type, key: []const u8) ?T // bool/int/float/enum/[]const u8
pub fn getValueOrDefault(self: *const Env, comptime T: type, key: []const u8, defaultValue: T) T
pub fn getList(self: *const Env, allocator: std.mem.Allocator, key: []const u8, delimiter: u8) ?[][]const u8 // owned items + slice
pub fn contains(self: *const Env, key: []const u8) bool
pub fn isEmpty(self: *const Env, key: []const u8) bool // missing or empty
pub fn require(self: *const Env, key: []const u8) ![]const u8 // store-only; error.MissingRequired
```

`getList` owns every item and the outer slice: free each item, then the slice.

### OS-aware reads (`Env` -> runtime fallback)

```zig
pub fn getOs(self: *const Env, key: []const u8) ?[]const u8 // Env → runtime fallback
pub fn getOsAlloc(self: *const Env, allocator: std.mem.Allocator, key: []const u8) !?[]u8 // owned
pub fn containsOs(self: *const Env, key: []const u8) bool
pub fn getWithFallback(self: *const Env, key: []const u8, fallback: []const u8) []const u8
pub fn requireOs(self: *const Env, key: []const u8) ![]const u8 // error.MissingRequired
pub fn fetchOs(self: *Env, key: []const u8) !?[]const u8 // copy OS → Env
```

## Writing & Updating

### `set` / `setOs` / `merge`

```zig
pub fn set(self: *Env, key: []const u8, value: []const u8) !void // respects exportToEnv
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
pub fn remove(self: *Env, key: []const u8) !bool // also runtime.unset if exportToEnv; failures returned
pub fn unsetOs(self: *Env, key: []const u8) !bool
pub fn clear(self: *Env) void
```

## Iteration

### `count` / `keys` / `iterator`

```zig
pub fn count(self: *const Env) usize
pub fn keys(self: *const Env) []const []const u8 // insertion order, borrowed
pub fn iterator(self: *const Env) EnvIterator // borrowed, no allocation; deinit is a no-op
```

## Serialization

### `serialize` / `save`

Uses `helpers.needsQuoting`/`escapedForChar` (single source) via `Serializer`.

```zig
pub fn serialize(self: *const Env) ![]const u8 // honors config.sortKeys
pub fn save(self: *const Env, path: []const u8) !void // via Writer/Serializer; honors config.sortKeys
```

## Scopes & Snapshots

### `EnvScope`

```zig
pub const EnvScope = struct { pub fn init(env: *Env) EnvScope; pub fn set(...); pub fn unset(...); pub fn deinit(...) }
pub fn scope(self: *Env) EnvScope
pub fn withTemp(self: *Env, key: []const u8, value: []const u8, func: *const fn(*Env) anyerror!void) !void
```

### `runtime` (explicit process-environment namespace)

Prefer `env.runtime.*` for process env; `Env` is the in-memory store.
Mutation is process-global and thread-unsafe by OS design.

```zig
pub const runtime = @import("runtime.zig"); // get/set/unset/getAlloc/getOrDefault/contains/isEmpty/getAll/getMap/snapshot + Scope/Snapshot
pub const OsEnv = os_env.OsEnv; // legacy alias of the same implementation
pub const Scope = os_env.Scope;
pub const Snapshot = os_env.Snapshot;
pub fn snapshotOs(self: *const Env) !Snapshot
```

```zig
// runtime direct (preferred)
try runtime.set("K","v");
const v = runtime.get("K"); // borrowed; dupe to retain (thread-local on Windows)
try runtime.unset("K");
var m = try runtime.getAll(allocator); // StringHashMap, owned
var snap = try runtime.snapshot(allocator); defer snap.deinit(); try snap.restore();
var sc = Scope.init(allocator); defer sc.deinit(); try sc.set("K","tmp");

// Env → child env
var map = try env.toEnvironMap(allocator); defer map.deinit();
try env.applyToEnvironMap(&map);
```

## Utilities

### `clone` / `validate`

```zig
pub fn clone(self: *const Env) !Env
pub fn validate(self: *const Env, allocator: std.mem.Allocator, s: Schema) ![]ValidationError // owned slice; free with allocator.free
pub fn toEnvironMap(self: *const Env, allocator: std.mem.Allocator) !std.process.Environ.Map
pub fn applyToEnvironMap(self: *const Env, map: *std.process.Environ.Map) !void
```

### `tryGetBool` / `tryGetInt` / `tryGetFloat` / `tryGetEnum`

Nullable getters return `null` for both missing keys and malformed values.
The `tryGet*` variants distinguish the two: `null` when missing,
`error.TypeMismatch` when present but invalid (never silently defaulted).

```zig
pub fn tryGetBool(self: *const Env, key: []const u8) !?bool
pub fn tryGetInt(self: *const Env, comptime T: type, key: []const u8) !?T
pub fn tryGetFloat(self: *const Env, comptime T: type, key: []const u8) !?T
pub fn tryGetEnum(self: *const Env, comptime E: type, key: []const u8) !?E
```
