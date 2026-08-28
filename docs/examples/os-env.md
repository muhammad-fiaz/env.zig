---
title: OS Environment Example
description: Cross-platform OS environment example for env.zig — Windows, Linux, macOS with temporary scopes and interpolation fallback.
---

# OS Environment Example

Demonstrates OS env bridging, temporary scopes (`$env`), and interpolation with OS fallback.

## Source

<<< @/examples/os_env.zig

## Running

```bash
zig build example
zig-out/bin/os_env_example
```
```
