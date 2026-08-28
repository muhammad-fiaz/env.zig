---
layout: home
title: env.zig
description: A production-grade runtime .env library for Zig — parsing, interpolation, OS environment, validation, and serialization for Windows, Linux and macOS.

hero:
  name: env.zig
  text: Production-Grade .env for Zig
  tagline: Parse, interpolate, validate, and bridge OS env with one library — zero global state, allocator-aware.
  actions:
    - theme: brand
      text: Get Started
      link: /guide/getting-started
    - theme: alt
      text: API Reference
      link: /api/env
    - theme: alt
      text: View on GitHub
      link: https://github.com/muhammad-fiaz/env.zig

features:
  - title: Parse .env Files
    details: Load and parse .env files with comments, quotes, empty values, inline comments, and export prefix.
  - title: Type-Safe Accessors
    details: get, getBool, getInt, getFloat, getEnum, getList with automatic parsing and OS fallback via getOs.
  - title: Write & Update
    details: Add, overwrite and merge entries with set / merge; optionally sync to OS env via export_to_env.
  - title: Delete & Clear
    details: Remove single keys or clear all entries while preserving allocator ownership and insertion order.
  - title: Variable Interpolation
    details: ${VAR}, $VAR, ${VAR:-default}, ${VAR:+alt}, ${VAR:?err}, nested defaults, $env:VAR, OS fallback.
  - title: OS Environment
    details: Native get/set/unset, getAll, snapshot/restore and Environ.Map for child processes — Windows/Linux/macOS.
  - title: Temporary Scopes
    details: Scope / EnvScope / Snapshot for $env-style isolation — automatic restore on deinit, ideal for tests.
  - title: Schema Validation
    details: Required/optional fields, 13 built-in validators (port, url, email, ipv4, etc.) and custom validators.
  - title: Serialization
    details: Serialize back to .env with quoting, sorting, trailing newlines — shared needsQuoting/escapedForChar.
  - title: Insertion Order
    details: Guaranteed order unlike std.process.Environ; stable across x86, x64, aarch64.
  - title: Cache & Iterator
    details: Built-in Cache and Iterator with peek, skip, reset, remaining, collect.
  - title: Modular & Zero-Copy
    details: Parser, lexer, interpolation, validator, serializer — pure Zig, no deps, allocator-aware.
---
