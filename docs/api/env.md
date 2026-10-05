---
title: Env API
description: Full API reference for Env — parsing, runtime bridging, interpolation, validation, and scopes.
head:
  - - meta
    - property: og:title
      content: "Env API | env.zig"
  - - meta
    - name: description
      content: Full API reference for Env in env.zig.
  - - meta
    - name: keywords
      content: "zig, env, API, Env, runtime, EnvScope, Snapshot, Environ.Map, interpolate"
---

# Env API Reference

In-memory `.env` store. Never touches the process environment except via
explicit `*Runtime` / `*AndExport` APIs or `config.exportToRuntime`.

## Initialization

```zig
pub fn init(allocator: std.mem.Allocator, cfg: Config) Env
pub fn deinit(self: *Env) void
```

## Loading (transactional)

`parseString` and `reload` leave the store unchanged when strict parsing fails.
`reload` stages into a fresh store and swaps, so even mid-commit
allocation failures preserve the old entries.

```zig
pub fn load(self: *Env, path: []const u8) !void
pub fn parseString(self: *Env, source: []const u8) !void // borrows source; dupes kept entries
pub fn loadMany(self: *Env, paths: []const []const u8) !void
pub fn reload(self: *Env, path: []const u8) !void
```

Ownership: file bytes are read into library-owned buffers and freed
internally; `parseString` callers keep owning `source`. For full caller
ownership of the bytes and the `Io` lifetime, read explicitly with
`std.Io` and call `parseString` (see File I/O example).

## Reading (in-memory only)

```zig
pub fn get(self: *const Env, key: []const u8) ?[]const u8 // borrowed
pub fn getString(self: *const Env, key: []const u8) ?[]const u8
pub fn getAlloc(self: *const Env, allocator: std.mem.Allocator, key: []const u8) !?[]u8 // owned
pub fn getOrDefault(self: *const Env, key: []const u8, defaultValue: []const u8) []const u8 // missing only
pub fn contains(self: *const Env, key: []const u8) bool
pub fn isEmpty(self: *const Env, key: []const u8) bool
pub fn require(self: *const Env, key: []const u8) ![]const u8
pub fn getBool(self: *const Env, key: []const u8) ?bool
pub fn getInt(self: *const Env, comptime T: type, key: []const u8) ?T
pub fn getFloat(self: *const Env, comptime T: type, key: []const u8) ?T
pub fn getEnum(self: *const Env, comptime E: type, key: []const u8) ?E
pub fn getValue(self: *const Env, comptime T: type, key: []const u8) ?T
pub fn getValueOrDefault(self: *const Env, comptime T: type, key: []const u8, defaultValue: T) T
pub fn getList(self: *const Env, allocator: std.mem.Allocator, key: []const u8, delimiter: u8) ?[][]const u8 // owned items + slice
pub fn tryGetBool(self: *const Env, key: []const u8) !?bool // null=missing, TypeMismatch=invalid
pub fn tryGetInt(self: *const Env, comptime T: type, key: []const u8) !?T
pub fn tryGetFloat(self: *const Env, comptime T: type, key: []const u8) !?T
pub fn tryGetEnum(self: *const Env, comptime E: type, key: []const u8) !?E
pub fn tryGetValue(self: *const Env, comptime T: type, key: []const u8) !?T
pub fn requireValue(self: *const Env, comptime T: type, key: []const u8) !T
```

## Writing (in-memory only unless noted)

```zig
pub fn set(self: *Env, key: []const u8, value: []const u8) !void // + runtime iff exportToRuntime
pub fn setAndExport(self: *Env, key: []const u8, value: []const u8) !void
pub fn remove(self: *Env, key: []const u8) !bool // + runtime.unset iff exportToRuntime
pub fn removeAndUnexport(self: *Env, key: []const u8) !bool
pub fn merge(self: *Env, other: *const Env) !void
pub fn clear(self: *Env) void
```

## Runtime interop (explicit)

Precedence for combined reads: in-memory `Env` > `runtime` > default.

```zig
pub fn loadRuntime(self: *Env) !void
pub fn loadRuntimeIfMissing(self: *Env) !void
pub fn loadRuntimeWithPrefix(self: *Env, prefix: []const u8) !void // APP_X -> X
pub fn exportToRuntime(self: *const Env) !void
pub fn getRuntime(self: *const Env, key: []const u8) ?[]const u8
pub fn getRuntimeAlloc(self: *const Env, allocator: std.mem.Allocator, key: []const u8) !?[]u8
pub fn getWithFallback(self: *const Env, key: []const u8, fallback: []const u8) []const u8
pub fn containsRuntime(self: *const Env, key: []const u8) bool
pub fn requireRuntime(self: *const Env, key: []const u8) ![]const u8
pub fn fetchRuntime(self: *Env, key: []const u8) !?[]const u8
pub fn snapshotRuntime(self: *const Env) !runtime.Snapshot
pub fn toEnvironMap(self: *const Env, allocator: std.mem.Allocator) !std.process.Environ.Map
pub fn applyToEnvironMap(self: *const Env, map: *std.process.Environ.Map) !void
```

## Iteration / serialization

```zig
pub fn count(self: *const Env) usize
pub fn keys(self: *const Env) []const []const u8 // borrowed, insertion order
pub fn iterator(self: *const Env) Iterator // borrowed, no allocation
pub fn serialize(self: *const Env) ![]const u8 // owned; caller frees
pub fn save(self: *const Env, path: []const u8) !void
```

Ownership: `serialize` returns caller-owned bytes; `save` frees its
internal buffer itself. For full caller ownership, `serialize` then
`std.Io.Dir.writeFile` explicitly (see File I/O example).

```zig
pub fn clone(self: *const Env) !Env
pub fn validate(self: *const Env, allocator: std.mem.Allocator, s: Schema) ![]ValidationError
pub const EnvScope = struct { pub fn set(...); pub fn unset(...); };
pub fn scope(self: *Env) EnvScope
pub fn withTemp(self: *Env, key: []const u8, value: []const u8, func: *const fn(*Env) anyerror!void) !void
```
