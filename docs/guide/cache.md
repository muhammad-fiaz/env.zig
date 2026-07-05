---
title: Cache
description: Learn how to use the built-in cache in env.zig for storing parsed key-value pairs separately from environment entries.
head:
  - - meta
    - property: og:title
      content: "Cache | env.zig"
  - - meta
    - name: description
      content: Learn how to use the built-in cache in env.zig for storing parsed key-value pairs separately from environment entries.
  - - meta
    - name: keywords
      content: "zig, env, cache, storage, key-value, env.zig"
---

# Cache

env.zig includes a built-in `Cache` for storing parsed values separately from environment entries.

## Accessing the Cache

The cache is accessible via `env.cache`:

```zig
var env = env_mod.Env.init(allocator, .{});
defer env.deinit();

// Cache is ready to use
_ = env.cache;
```

## Basic Operations

### Put & Get

```zig
try env.cache.put("cached_token", "abc123");
try env.cache.put("cached_config", "{ \"timeout\": 30 }");

if (env.cache.get("cached_token")) |token| {
    try stdout.print("Token: {s}\n", .{token});
}
```

### Check Existence

```zig
if (env.cache.contains("cached_token")) {
    try stdout.print("Token is cached\n", .{});
}
```

### Remove & Clear

```zig
// Remove single entry
_ = env.cache.remove("cached_token");

// Clear all cache entries
env.cache.clear();
```

### Count Entries

```zig
const count = env.cache.count();
try stdout.print("Cache size: {d}\n", .{count});
```

## Cache vs Environment Entries

Cache entries are **separate** from environment entries:

```zig
try env.set("API_KEY", "secret123");

// Cache is empty
try std.testing.expectEqual(@as(usize, 0), env.cache.count());

// Add to cache
try env.cache.put("api_key_hash", "abc123");

// Environment still has original entry
try std.testing.expectEqualStrings("secret123", env.get("API_KEY").?);

// Cache has its own entry
try std.testing.expectEqualStrings("abc123", env.cache.get("api_key_hash").?);
```

## Use Cases

### Memoize Expensive Operations

```zig
// Cache parsed results of complex values
if (env.cache.get("parsed_config")) |config| {
    // Use cached version
    return config;
}

// Parse and cache
const parsed = try parseComplexValue(env.get("COMPLEX_CONFIG").?);
try env.cache.put("parsed_config", parsed);
return parsed;
```

### Temporary State

```zig
// Store computation results without polluting env entries
try env.cache.put("db_pool_size", "10");
try env.cache.put("db_connection_timeout", "30");
```

## See Also

- [Getting Started](/guide/getting-started) for configuration options
- [API Reference](/api/env) for the full API
