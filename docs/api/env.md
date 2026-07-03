---
title: Env API
titleTemplate: "Env API | env.zig"
description: Full API reference for the Env struct — parsing, reading, writing, updating, and deleting .env entries in env.zig.
head:
  - meta:
      - property: og:title
        content: "Env API | env.zig"
      - meta: description
        content: Full API reference for the Env struct in env.zig.
      - name: keywords
        content: "zig, env, API, Env, init, deinit, load, get, set, remove, clear, serialize"
---

# Env API Reference

The main environment store. Owns all allocated memory.

## Initialization

### `Env.init`

```zig
pub fn init(allocator: std.mem.Allocator, cfg: Config) Env
```

Create a new empty `Env` instance.

### `Env.deinit`

```zig
pub fn deinit(self: *Env) void
```

Free all resources. Must be called when done.

## Loading

### `load`

```zig
pub fn load(self: *Env, path: []const u8) !void
```

Load and parse a `.env` file from disk.

### `parseString`

```zig
pub fn parseString(self: *Env, source: []const u8) !void
```

Parse a `.env` string and add entries.

### `loadMany`

```zig
pub fn loadMany(self: *Env, paths: []const []const u8) !void
```

Load multiple `.env` files in order. Later files override earlier ones.

### `reload`

```zig
pub fn reload(self: *Env, path: []const u8) !void
```

Clear all entries and reload from a file.

## Reading Values

### `get`

```zig
pub fn get(self: *const Env, key: []const u8) ?[]const u8
```

Get a value by key. Returns `null` if not found.

### `getString`

```zig
pub fn getString(self: *const Env, key: []const u8) ?[]const u8
```

Alias for `get`.

### `getBool`

```zig
pub fn getBool(self: *const Env, key: []const u8) ?bool
```

Get a boolean value. Accepts: `true`/`false`/`yes`/`no`/`1`/`0`/`on`/`off`.

### `getInt`

```zig
pub fn getInt(self: *const Env, comptime T: type, key: []const u8) ?T
```

Get an integer value of the specified type.

### `getFloat`

```zig
pub fn getFloat(self: *const Env, comptime T: type, key: []const u8) ?T
```

Get a float value.

### `getEnum`

```zig
pub fn getEnum(self: *const Env, comptime E: type, key: []const u8) ?E
```

Get an enum value from a string.

### `getList`

```zig
pub fn getList(self: *const Env, allocator: std.mem.Allocator, key: []const u8, delimiter: u8) ?[][]const u8
```

Get a list of values by splitting on a delimiter.

### `contains`

```zig
pub fn contains(self: *const Env, key: []const u8) bool
```

Check if a key exists.

## Writing & Updating Values

### `set`

```zig
pub fn set(self: *Env, key: []const u8, value: []const u8) !void
```

Set a key-value pair. If the key already exists, the value is updated. If the key doesn't exist, a new entry is created.

```zig
// Add new entry
try env.set("API_KEY", "secret123");

// Update existing entry
try env.set("PORT", "9090");
```

### `merge`

```zig
pub fn merge(self: *Env, other: *const Env) !void
```

Merge another `Env` into this one. Entries from `other` override existing ones.

```zig
try env.merge(&defaults);
```

## Deleting Values

### `remove`

```zig
pub fn remove(self: *Env, key: []const u8) bool
```

Remove a key-value pair. Returns `true` if the key existed, `false` otherwise.

```zig
if (env.remove("DEBUG")) {
    std.debug.print("Removed DEBUG\n", .{});
}
```

### `clear`

```zig
pub fn clear(self: *Env) void
```

Remove all entries.

```zig
env.clear();
```

## Iteration

### `count`

```zig
pub fn count(self: *const Env) usize
```

Get the number of entries.

### `keys`

```zig
pub fn keys(self: *const Env) []const []const u8
```

Get all keys in insertion order.

### `iterator`

```zig
pub fn iterator(self: *const Env) Iterator
```

Create an iterator over entries.

## Serialization

### `serialize`

```zig
pub fn serialize(self: *const Env) ![]const u8
```

Serialize entries to `.env` format.

### `save`

```zig
pub fn save(self: *const Env, path: []const u8) !void
```

Write entries to a file.

## Utilities

### `clone`

```zig
pub fn clone(self: *const Env) !Env
```

Create an independent deep copy.

### `validate`

```zig
pub fn validate(self: *const Env, s: schema_mod.Schema) []ValidationError
```

Validate entries against a schema.
