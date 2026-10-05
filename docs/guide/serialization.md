---
title: Serialization
description: Serialize env.zig configurations back to .env format with sorting and quoting.
head:
  - - meta
    - property: og:title
      content: "Serialization | env.zig"
  - - meta
    - name: description
      content: Serialize env.zig configurations back to .env format.
  - - meta
    - name: keywords
      content: "zig, env, serialization, serialize, write, save, .env format"
---

# Serialization

`env.zig` can serialize configurations back to `.env` format.

## Basic Serialization

```zig
const output = try env.serialize();
defer allocator.free(output);
// output: "KEY=value\nOTHER=foo\n"
```

## Save to File

```zig
try env.save("output.env");
```

## Serialization Options

| Config Option | Default | Description |
|---------------|---------|-------------|
| `sortKeys` | `false` | Sort keys alphabetically (input slice is not mutated) |
| `quoteSpaces` | `true` | Quote values needing quotes for a lossless `parse(serialize(x))` round-trip |
| `trailingNewline` | `true` | Emit trailing `\n` after the last entry; `false` omits it |

## Sorted Keys

```zig
var env = envMod.Env.init(allocator, .{ .sortKeys = true });
// Keys will be sorted alphabetically in output
```

## Custom Quoting

Values with spaces, quotes, or special characters are automatically escaped:

```zig
try env.set("MESSAGE", "hello world");
const output = try env.serialize();
// MESSAGE="hello world"
```

## Example Output

```env
DATABASE_HOST=localhost
DATABASE_NAME=myapp
DATABASE_PORT=5432
LOG_LEVEL=info
```
