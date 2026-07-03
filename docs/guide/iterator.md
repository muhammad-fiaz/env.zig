---
title: Iterator
titleTemplate: "Iterator | env.zig"
description: Learn how to iterate over env.zig key-value pairs with peek, skip, reset, and collect operations.
head:
  - - meta
    - property: og:title
      content: "Iterator | env.zig"
  - - meta
    - name: description
      content: Learn how to iterate over env.zig key-value pairs with peek, skip, reset, and collect operations.
  - - meta
    - name: keywords
      content: "zig, env, iterator, iterate, entries, keys, values, env.zig"
---

# Iterator

env.zig provides an `Iterator` for traversing key-value pairs with advanced operations.

## Basic Iteration

### Using keys()

```zig
for (env.keys()) |key| {
    try stdout.print("{s} = {s}\n", .{ key, env.get(key).? });
}
```

### Using the Iterator

```zig
var it = env.iterator();
defer allocator.free(it.entries); // Free allocated entries
while (it.next()) |entry| {
    try stdout.print("{s} = {s}\n", .{ entry.key, entry.value });
}
```

::: warning
The iterator allocates an entries slice. Always free it with `defer allocator.free(it.entries)`.
:::

## Advanced Operations

### Peek

Look at the next entry without consuming it:

```zig
var it = env.iterator();
defer allocator.free(it.entries);

if (it.peek()) |entry| {
    try stdout.print("Next: {s}\n", .{entry.key});
}

// Still at the same position
if (it.peek()) |entry| {
    try stdout.print("Same: {s}\n", .{entry.key}); // Same entry
}
```

### Skip

Skip entries ahead:

```zig
var it = env.iterator();
defer allocator.free(it.entries);
it.skip(2); // Skip first 2 entries

while (it.next()) |entry| {
    // Starts from 3rd entry
}
```

### Reset

Return to the beginning:

```zig
var it = env.iterator();
defer allocator.free(it.entries);
_ = it.next();
_ = it.next();

it.reset(); // Back to first entry
```

### Remaining

Check how many entries are left:

```zig
var it = env.iterator();
defer allocator.free(it.entries);
try std.testing.expectEqual(@as(usize, 5), it.remaining());

it.skip(2);
try std.testing.expectEqual(@as(usize, 3), it.remaining());
```

### Collect

Gather entries matching a predicate:

```zig
const isDatabase = struct {
    fn predicate(entry: env_mod.Iterator.Entry) bool {
        return std.mem.startsWith(u8, entry.key, "DATABASE");
    }
}.predicate;

var it = env.iterator();
defer allocator.free(it.entries);
const db_entries = try it.collect(allocator, isDatabase);
defer allocator.free(db_entries);

for (db_entries) |entry| {
    try stdout.print("DB config: {s} = {s}\n", .{ entry.key, entry.value });
}
```

## Entry Count

```zig
const count = env.count();
try stdout.print("Total entries: {d}\n", .{count});
```

## See Also

- [Getting Started](/guide/getting-started) for configuration options
- [API Reference](/api/env) for the full API
