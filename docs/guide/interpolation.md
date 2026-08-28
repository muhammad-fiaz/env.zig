---
title: Interpolation
description: Learn how to use variable interpolation in env.zig to reference other .env variables with ${VAR} syntax.
head:
  - - meta
    - property: og:title
      content: "Interpolation | env.zig"
  - - meta
    - name: description
      content: Learn how to use variable interpolation in env.zig to reference other .env variables with ${VAR} syntax.
  - - meta
    - name: keywords
      content: "zig, env, interpolation, ${VAR}, variable substitution, env.zig"
---

# Interpolation

env.zig supports `${VAR}` / `$VAR` with shell-like fallbacks and OS env fallback on Windows/Linux/macOS.

## Enable Interpolation

```zig
var env = env_mod.Env.init(allocator, .{
    .interpolate = true, // default true
});
```

## Syntax

| Form | Meaning |
|------|---------|
| `${VAR}` / `$VAR` | Value of VAR (Env first, then OS env) |
| `${VAR:-default}` | `default` if VAR unset **or empty** |
| `${VAR-default}` | `default` if VAR unset (empty passthrough) |
| `${VAR:+alt}` | `alt` if VAR set **and non-empty**, else empty |
| `${VAR+alt}` | `alt` if VAR set (even if empty), else empty |
| `${VAR:?msg}` / `${VAR?msg}` | `msg` if VAR missing/empty (error message) |
| `${VAR:=default}` / `${VAR=default}` | Like `:-` / `-` (assign not persisted) |

Nested defaults are expanded: `${MISSING:-${FALLBACK}}`.

Reference another variable:

```env
DATABASE_HOST=localhost
DATABASE_PORT=5432
DATABASE_URL=postgres://${DATABASE_HOST}:${DATABASE_PORT}/mydb

# OS fallback — uses $HOME from process env if not in .env
MY_HOME=${HOME}
MY_PATH=$PATH:/custom/bin

# Defaults & alts
PORT=${PORT:-3000}
DEBUG_MSG=${DEBUG:+enabled}
REQUIRED=${API_KEY:?API_KEY is required}
```

OS fallback walks: `Env` entries → `OsEnv.get` (POSIX `getenv` / Windows `GetEnvironmentVariableW`).

## Circular Detection

env.zig detects circular references and prevents infinite loops:

```zig
// This will error with a circular reference detected
try env.parseString(
    \\A=${B}
    \\B=${A}
    \\
);
```

## Examples

### Basic Interpolation

```env
APP_NAME=myapp
GREETING=hello
MESSAGE=${GREETING} from ${APP_NAME}
```

```zig
try stdout.print("MESSAGE = {s}\n", .{env.get("MESSAGE").?});
// Output: MESSAGE = hello from myapp
```

### Database URL Construction

```env
DB_HOST=localhost
DB_PORT=5432
DB_NAME=mydb
DATABASE_URL=postgres://${DB_HOST}:${DB_PORT}/${DB_NAME}
```

### Nested Interpolation

```env
BASE_URL=https://api.example.com
VERSION=v1
API_ENDPOINT=${BASE_URL}/${VERSION}/users
```

## See Also

- [Getting Started](/guide/getting-started) for configuration options
- [Configuration](/guide/configuration) for all config options
- [API Reference](/api/env) for the full API
