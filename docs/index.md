---
layout: home
title: env.zig
titleTemplate: A Simple and Fast Env Parsing and Reading Library for Zig
description: A simple and fast .env parsing and reading library for Zig with write support, variable interpolation, schema validation, and serialization.

hero:
  name: env.zig
  text: A Simple and Fast Env Parsing and Reading Library for Zig
  tagline: Parse, read, write, update, and delete .env files — production-grade, allocator-aware, zero global state.
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
    details: Load and parse .env files into type-safe key-value pairs with support for comments, quotes, and empty values.
  - title: Read Values
    details: Type-safe accessors for strings, booleans, integers, floats, enums, and lists with automatic parsing.
  - title: Write & Update
    details: Add new key-value pairs, update existing values, and overwrite entries with type-safe setters.
  - title: Delete Entries
    details: Remove individual keys or clear all entries while preserving memory safety.
  - title: Variable Interpolation
    details: Supports ${VAR} and $VAR syntax with circular dependency detection and configurable max depth.
  - title: Schema Validation
    details: Define schemas with required fields, types, and built-in validators (port, URL, email, IPv4, etc.).
  - title: Serialization
    details: Write configurations back to .env format with key sorting, value quoting, and trailing newlines.
  - title: Modular Architecture
    details: Parser, lexer, tokenizer, interpolation, schema, validator, serializer, writer, cache, iterator — all in separate files.
---
