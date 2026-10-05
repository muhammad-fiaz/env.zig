---
title: Runtime API
description: Cross-platform process environment API — get/set/unset, enumeration, snapshot/restore, and scopes.
head:
  - - meta
    - property: og:title
      content: "Runtime API | env.zig"
  - - meta
    - name: description
      content: Runtime process environment API for Windows/Linux/macOS.
  - - meta
    - name: keywords
      content: "zig, env, runtime, scope, snapshot, getenv, windows, linux, macos"
---

# Runtime API Reference

Single process-environment implementation (`env.runtime`). Reads reuse
`std.process.Environ`; only `set`/`unset` use minimal native bindings.
Windows names are case-insensitive; POSIX case-sensitive.
Missing (`null`) differs from empty (`""`).

```zig
pub fn get(key: []const u8) ?[]const u8 // borrowed; thread-local on Windows
pub fn getAlloc(allocator: std.mem.Allocator, key: []const u8) !?[]u8 // owned
pub fn getOrDefault(key: []const u8, defaultValue: []const u8) []const u8
pub fn exists(key: []const u8) bool
pub fn contains(key: []const u8) bool
pub fn isEmpty(key: []const u8) bool
pub fn set(key: []const u8, value: []const u8) !void // affects process
pub fn unset(key: []const u8) !void
pub fn getMap(allocator: std.mem.Allocator) !std.process.Environ.Map // caller deinit
pub fn getAll(allocator: std.mem.Allocator) !std.StringHashMap([]const u8) // owned keys/values
pub fn snapshot(allocator: std.mem.Allocator) !Snapshot
pub fn scope(allocator: std.mem.Allocator) !Scope // snapshot-backed, nesting LIFO
pub fn validateKey(key: []const u8) !void // std Environ.Map.validateKeyForPut
pub fn getBool(key: []const u8) ?bool
pub fn tryGetBool(key: []const u8) !?bool
pub fn getInt(comptime T: type, key: []const u8) ?T
pub fn tryGetInt(comptime T: type, key: []const u8) !?T
pub fn getFloat(comptime T: type, key: []const u8) ?T
pub fn tryGetFloat(comptime T: type, key: []const u8) !?T
pub fn getEnum(comptime E: type, key: []const u8) ?E
pub fn tryGetEnum(comptime E: type, key: []const u8) !?E
pub fn getValue(comptime T: type, key: []const u8) ?T
pub fn tryGetValue(comptime T: type, key: []const u8) !?T
```

`Snapshot.restore` removes absent keys and restores present (including
empty) values. `Scope` captures a full snapshot on `init` and restores on
`deinit`.
