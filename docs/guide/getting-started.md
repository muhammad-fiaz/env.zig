---
title: Getting Started
description: Install and set up env.zig — a simple and fast .env parsing and reading library for Zig with write, update, delete, interpolation, validation, and serialization.
head:
  - - meta
    - property: og:title
      content: "Getting Started | env.zig"
  - - meta
    - name: description
      content: Install and set up env.zig for parsing .env files in Zig projects.
  - - meta
    - name: keywords
      content: "zig, env, dotenv, getting started, installation, quick start, parse, read, write, update, delete"
---

# Getting Started

## Installation

### Add to your project

```bash
zig fetch https://github.com/muhammad-fiaz/env.zig/archive/refs/tags/0.0.3.tar.gz
```

Then add to your `build.zig`:

```zig
const env = b.dependency("env", .{});
exe.root_module.addImport("env", env.module("env"));
```

### From source

```bash
git clone https://github.com/muhammad-fiaz/env.zig.git
cd env.zig
zig build test    # Run tests
zig build example # Run examples
```

## Basic Usage

```zig
const std = @import("std");
const Io = std.Io;
const envMod = @import("env");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var env = envMod.Env.init(allocator, .{});
    defer env.deinit();

    // Load from file — handles export prefix, quotes, inline comments
    try env.load(".env"); // supports: export HOST=localhost  # comment
    // Or parse from string
    try env.parseString("HOST=localhost\nPORT=8080\n");

    // Read values with type-safe accessors + OS fallback
    const host = env.getOs("HOST") orelse "localhost"; // Env → OsEnv (getenv/GetEnvironmentVariableW)
    const port = env.getInt(u16, "PORT") orelse 3000;
    const debug = env.getBool("DEBUG") orelse false;

    // Write new entries
    try env.set("API_KEY", "secret123");

    // Update existing entries
    try env.set("PORT", "9090");

    // Check if key exists
    if (env.contains("HOST")) {
        std.debug.print("HOST exists\n", .{});
    }

    // Delete entries (!bool; export failures are returned)
    _ = try env.remove("DEBUG");

    // OS bridging (Windows/Linux/macOS via std.process.Environ + minimal set/unset)
    try env.loadOsEnvIfMissing(); // import OS vars only if missing
    try env.loadOsEnvWithPrefix("APP_"); // APP_PORT=8080 → PORT=8080
    try env.exportToOsEnv(); // push to process env for children
    const withDefault = env.getWithFallback("PORT", "3000");
    const required = try env.requireOs("DATABASE_URL");

    // Temporary $env isolation for tests
    {
        var scope = envMod.Scope.init(allocator);
        defer scope.deinit();
        try scope.set("TMP", "temporary");
    }

    // Print to stdout
    var stdoutBuffer: [0x100]u8 = undefined;
    var stdoutWriter = Io.File.stdout().writer(io, &stdoutBuffer);
    const stdout = &stdoutWriter.interface;
    try stdout.print("host={s} port={d} debug={} withDefault={s} required={s}\n", .{ host, port, debug, withDefault, required });
    try stdout.flush();
}
```

## What is a .env file?

A `.env` file is a simple text file for storing environment configuration (shell-compatible `export` is accepted):

```env
# Database configuration
export DATABASE_URL=postgres://localhost:5432/mydb
DATABASE_POOL_SIZE=10

# Server — interpolation with OS fallback and defaults
HOST=0.0.0.0
PORT=${PORT:-3000}
GREETING=${GREETING:-hello} world
FROM_OS=${HOME}            # falls back to OS env
ENV_STYLE=$env:HOME        # PowerShell $env: prefix

# Features
DEBUG=true
LOG_LEVEL=info
```

## Quote Styles

env.zig supports all standard .env quote styles:

```env
# Double quotes — escape sequences processed
MESSAGE="hello\nworld"
PATH="C:\\Users\\admin"

# Single quotes — literal, no escape processing
RAW='hello\nworld'  # kept as-is

# Backtick — literal, no escape processing
TEMPLATE=`hello\nworld`

# Unquoted — no escape processing
SIMPLE=hello world
```

## Escape Sequences

Double-quoted values support these escape sequences:

| Sequence | Result |
|----------|--------|
| `\n` | Newline |
| `\t` | Tab |
| `\r` | Carriage return |
| `\\` | Backslash |
| `\"` | Double quote |
| `\'` | Single quote |
| `` \` `` | Backtick |
| `\0` | Null byte |

```env
# Examples
NEWLINE="line1\nline2"
TAB="col1\tcol2"
BACKSLASH="path\\to\\file"
QUOTES="say \"hello\""
```

## Inline Comments

Comments can appear on their own line or after a value:

```env
# This is a full-line comment
HOST=localhost  # This is an inline comment
PORT=8080  # Server port
```

## Empty Values

```env
# Empty string
EMPTY=
# Also valid
EMPTY=""
```

## Key Concepts

### Allocator-Aware

Every `Env` instance owns its memory. Always call `deinit()` to free resources:

```zig
var env = envMod.Env.init(allocator, .{});
defer env.deinit(); // Free all memory
```

### No Global State

`env.zig` has no global mutable state. Create as many `Env` instances as you need:

```zig
var appEnv = envMod.Env.init(allocator, .{});
var testEnv = envMod.Env.init(allocator, .{});
```

### Configuration Options

Customize behavior with the `Config` struct:

```zig
var env = envMod.Env.init(allocator, .{
    .strict = true,           // Fail on syntax errors
    .interpolate = true,      // Enable ${VAR} interpolation
    .trim = true,             // Trim whitespace
    .override = true,         // Override existing values on load
    .sortKeys = true,        // Sort keys when serializing
    .quoteSpaces = true,     // Quote values containing spaces
});
```

## Reading Values

```zig
// Raw string (Env only, borrowed)
const value = env.get("KEY");

// OS-aware (Env → runtime fallback)
const value2 = env.getOs("KEY"); // ?[]const u8
const withDefault = env.getWithFallback("PORT", "3000");
const required = try env.requireOs("API_KEY"); // error.MissingRequired
const is_os = env.containsOs("HOME");

// Typed accessors (missing -> null; invalid -> null; tryGet* -> TypeMismatch)
const port = env.getInt(u16, "PORT");       // ?u16
const debug = env.getBool("DEBUG");         // ?bool
const ratio = env.getFloat(f64, "RATIO");   // ?f64
const mode = env.getEnum(Mode, "MODE");     // ?Mode
const generic = env.getValue(u16, "PORT");  // ?u16

// List (owned items + slice; free each item, then the slice)
const hosts = env.getList(allocator, "HOSTS", ','); // ?[][]const u8

// Check existence (missing vs empty are distinct)
if (env.contains("KEY")) { ... }
if (env.containsOs("KEY")) { ... }

// Direct runtime (preferred namespace; borrowed on Windows until next get)
const home = envMod.runtime.get("HOME");
const homeAlloc = try envMod.runtime.getAlloc(allocator, "HOME");
```

## Writing & Updating Values

```zig
// Add new entry
try env.set("NEW_KEY", "new_value");

// Update existing entry
try env.set("PORT", "9090");

// Merge from another Env
try env.merge(&defaults);
```

## Deleting Values

```zig
// Remove single key (!bool; export failures are returned, never swallowed)
if (try env.remove("DEBUG")) {
    std.debug.print("Removed DEBUG\n", .{});
}

// Clear all entries
env.clear();
```

## Iteration

```zig
// Get all keys in insertion order
const keys = env.keys();
for (keys) |key| {
    std.debug.print("{s}={s}\n", .{ key, env.get(key).? });
}

// Get entry count
const count = env.count();

// Use iterator (borrowed, no allocation; deinit is a no-op)
var it = env.iterator();
while (it.next()) |entry| {
    std.debug.print("{s}={s}\n", .{ entry.key, entry.value });
}
```

## Cache

Standalone `Cache` for values separate from `Env` entries (`Env` owns no cache):

```zig
var cache = envMod.Cache.init(allocator);
defer cache.deinit();

// Put values into cache
try cache.put("token", "abc123");
try cache.put("config", "{ \"timeout\": 30 }");

// Get from cache
if (cache.get("token")) |token| {
    std.debug.print("Token: {s}\n", .{token});
}

// Check existence
if (cache.contains("token")) { ... }

// Remove & clear
_ = cache.remove("token");
cache.clear();
```

## Serialization

```zig
// Serialize to .env string
const output = try env.serialize();
defer allocator.free(output);

// Save to file
try env.save("output.env");
```
