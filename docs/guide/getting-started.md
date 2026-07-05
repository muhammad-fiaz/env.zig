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
zig fetch --save=env https://github.com/muhammad-fiaz/env.zig/archive/refs/tags/0.0.1.tar.gz
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
const env_mod = @import("env");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var env = env_mod.Env.init(allocator, .{});
    defer env.deinit();

    // Load from file
    try env.load(".env");

    // Or parse from string
    try env.parseString("HOST=localhost\nPORT=8080\n");

    // Read values with type-safe accessors
    const host = env.get("HOST") orelse "localhost";
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

    // Delete entries
    _ = env.remove("DEBUG");

    // Print to stdout
    var stdout_buffer: [0x100]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print("host={s} port={d} debug={}\n", .{ host, port, debug });
    try stdout.flush();
}
```

## What is a .env file?

A `.env` file is a simple text file for storing environment configuration:

```env
# Database configuration
DATABASE_URL=postgres://localhost:5432/mydb
DATABASE_POOL_SIZE=10

# Server
HOST=0.0.0.0
PORT=8080

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
var env = env_mod.Env.init(allocator, .{});
defer env.deinit(); // Free all memory
```

### No Global State

`env.zig` has no global mutable state. Create as many `Env` instances as you need:

```zig
var app_env = env_mod.Env.init(allocator, .{});
var test_env = env_mod.Env.init(allocator, .{});
```

### Configuration Options

Customize behavior with the `Config` struct:

```zig
var env = env_mod.Env.init(allocator, .{
    .strict = true,           // Fail on syntax errors
    .interpolate = true,      // Enable ${VAR} interpolation
    .trim = true,             // Trim whitespace
    .override = true,         // Override existing values on load
    .sort_keys = true,        // Sort keys when serializing
    .quote_spaces = true,     // Quote values containing spaces
});
```

## Reading Values

```zig
// Raw string
const value = env.get("KEY");

// Typed accessors
const port = env.getInt(u16, "PORT");       // ?u16
const debug = env.getBool("DEBUG");         // ?bool
const ratio = env.getFloat(f64, "RATIO");   // ?f64
const mode = env.getEnum(Mode, "MODE");     // ?Mode

// List (split by delimiter)
const hosts = env.getList(allocator, "HOSTS", ','); // ?[][]const u8

// Check existence
if (env.contains("KEY")) { ... }
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
// Remove single key (returns true if existed)
if (env.remove("DEBUG")) {
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

// Use iterator
var it = env.iterator();
while (it.next()) |entry| {
    std.debug.print("{s}={s}\n", .{ entry.key, entry.value });
}
```

## Cache

Store values separately from environment entries:

```zig
// Put values into cache
try env.cache.put("token", "abc123");
try env.cache.put("config", "{ \"timeout\": 30 }");

// Get from cache
if (env.cache.get("token")) |token| {
    std.debug.print("Token: {s}\n", .{token});
}

// Check existence
if (env.cache.contains("token")) { ... }

// Remove & clear
_ = env.cache.remove("token");
env.cache.clear();
```

## Serialization

```zig
// Serialize to .env string
const output = try env.serialize();
defer allocator.free(output);

// Save to file
try env.save("output.env");
```
