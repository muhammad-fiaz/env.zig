---
title: Cache
description: Learn how to use the standalone Cache in env.zig for storing parsed key-value pairs separately from environment entries.
head:
  - - meta
    - property: og:title
      content: "Cache | env.zig"
  - - meta
    - name: description
      content: Learn how to use the standalone Cache in env.zig for storing parsed key-value pairs separately from environment entries.
  - - meta
    - name: keywords
      content: "zig, env, cache, storage, key-value, env.zig"
---

# Cache

env.zig provides a standalone `Cache` for storing values separately from
`Env` entries. `Env` no longer owns a cache; use `Cache` directly when you
need memoization without polluting the environment store.

## Standalone Cache

```zig
var env = envMod.Env.init(allocator, .{});
defer env.deinit();

var cache = envMod.Cache.init(allocator);
defer cache.deinit();
```

## Basic Operations

### Put & Get

```zig
try cache.put("cached_token", "abc123");
try cache.put("cached_config", "{ \"timeout\": 30 }");

if (cache.get("cached_token")) |token| {
    try stdout.print("Token: {s}\n", .{token});
}
```

### Check Existence

```zig
if (cache.contains("cached_token")) {
    try stdout.print("Token is cached\n", .{});
}
```

### Remove & Clear

```zig
// Remove single entry
_ = cache.remove("cached_token");

// Clear all cache entries
cache.clear();
```

### Count Entries

```zig
const count = cache.count();
try stdout.print("Cache size: {d}\n", .{count});
```

## Cache vs Environment Entries

Cache entries are **separate** from environment entries:

```zig
try env.set("API_KEY", "secret123");

var cache2 = envMod.Cache.init(allocator);
defer cache2.deinit();

// Cache is empty
try std.testing.expectEqual(@as(usize, 0), cache2.count());

// Add to cache
try cache2.put("api_key_hash", "abc123");

// Environment still has original entry
try std.testing.expectEqualStrings("secret123", env.get("API_KEY").?);

// Cache has its own entry
try std.testing.expectEqualStrings("abc123", cache2.get("api_key_hash").?);
```

## Use Cases

### Memoize Expensive Operations

```zig
// Cache parsed results of complex values
if (cache.get("parsed_config")) |config| {
    // Use cached version
    return config;
}

// Parse and cache
const parsed = try parseComplexValue(env.get("COMPLEX_CONFIG").?);
try cache.put("parsed_config", parsed);
return parsed;
```

### Temporary State

```zig
// Store computation results without polluting env entries
try cache.put("db_pool_size", "10");
try cache.put("db_connection_timeout", "30");
```

## See Also

- [Getting Started](/guide/getting-started) for configuration options
- [API Reference](/api/env) for the full API
