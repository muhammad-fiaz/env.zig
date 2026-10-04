---
title: Clone & Merge
description: Learn how to clone and merge env.zig instances for independent copies and default value patterns.
head:
  - - meta
    - property: og:title
      content: "Clone & Merge | env.zig"
  - - meta
    - name: description
      content: Learn how to clone and merge env.zig instances for independent copies and default value patterns.
  - - meta
    - name: keywords
      content: "zig, env, clone, merge, copy, defaults, env.zig"
---

# Clone & Merge

env.zig supports cloning entire environments and merging them for default value patterns.

## Cloning

Create an independent copy of an `Env` instance:

```zig
var env = envMod.Env.init(allocator, .{});
defer env.deinit();

try env.set("APP_NAME", "MyApp");
try env.set("PORT", "8080");

// Clone creates an independent copy
var cloned = try env.clone();
defer cloned.deinit();

// Modifying clone doesn't affect original
try cloned.set("PORT", "9090");
try stdout.print("Original: {s}\n", .{env.get("PORT").?});      // 8080
try stdout.print("Cloned: {s}\n", .{cloned.get("PORT").?});     // 9090
```

## Merging

Merge another `Env` into the current one. Entries from the other `Env` override existing values:

```zig
var env = envMod.Env.init(allocator, .{});
defer env.deinit();

try env.set("PORT", "8080");
try env.set("APP_NAME", "MyApp");

var defaults = envMod.Env.init(allocator, .{});
defer defaults.deinit();

try defaults.set("PORT", "3000");
try defaults.set("LOG_LEVEL", "info");
try defaults.set("TIMEOUT", "30");

// Merge defaults — defaults' values override existing
try env.merge(&defaults);

// PORT becomes "3000" (defaults overrides)
// APP_NAME stays "MyApp" (not in defaults)
// LOG_LEVEL becomes "info" (from defaults)
// TIMEOUT becomes "30" (from defaults)
```

## Use Cases

### Configuration Layering

```zig
// Start with base config
var config = envMod.Env.init(allocator, .{});
defer config.deinit();
try config.parseString(
    \\PORT=3000
    \\LOG_LEVEL=info
    \\
);

// Load and merge user overrides (user values win)
var userConfig = envMod.Env.init(allocator, .{});
defer userConfig.deinit();
try userConfig.load("user.env");
try config.merge(&userConfig);
```

### Defaults Pattern

```zig
// Apply defaults first, then override with actual values
var env = envMod.Env.init(allocator, .{});
defer env.deinit();

// Set defaults
try env.set("PORT", "3000");
try env.set("LOG_LEVEL", "info");
try env.set("TIMEOUT", "30");

// Override with actual values from file
try env.load(".env");
```

### Testing

```zig
// Create base config for testing
var baseConfig = envMod.Env.init(allocator, .{});
defer baseConfig.deinit();
try baseConfig.parseString(
    \\APP_NAME=MyApp
    \\DATABASE_URL=postgres://localhost/prod_db
    \\DEBUG=false
    \\
);

// Clone for test environment
var testConfig = try baseConfig.clone();
defer testConfig.deinit();

// Override for testing
try testConfig.set("DATABASE_URL", "postgres://localhost/test_db");
try testConfig.set("DEBUG", "true");
```

## See Also

- [Getting Started](/guide/getting-started) for configuration options
- [Configuration](/guide/configuration) for all config options
- [API Reference](/api/env) for the full API
