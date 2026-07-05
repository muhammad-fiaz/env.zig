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

env.zig supports `${VAR}` syntax to reference other environment variables.

## Enable Interpolation

```zig
var env = env_mod.Env.init(allocator, .{
    .interpolate = true,
});
```

## Syntax

Reference another variable with `${VARIABLE_NAME}`:

```env
DATABASE_HOST=localhost
DATABASE_PORT=5432
DATABASE_URL=postgres://${DATABASE_HOST}:${DATABASE_PORT}/mydb
```

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
