<div align="center">

<a href="https://muhammad-fiaz.github.io/env.zig/"><img src="https://img.shields.io/badge/docs-muhammad--fiaz.github.io%2Fenv.zig-blue" alt="Documentation"></a>
<a href="https://ziglang.org/"><img src="https://img.shields.io/badge/Zig-0.16.0-orange.svg?logo=zig" alt="Zig Version"></a>
<a href="https://github.com/muhammad-fiaz/env.zig"><img src="https://img.shields.io/github/stars/muhammad-fiaz/env.zig" alt="GitHub stars"></a>
<a href="https://github.com/muhammad-fiaz/env.zig/issues"><img src="https://img.shields.io/github/issues/muhammad-fiaz/env.zig" alt="GitHub issues"></a>
<a href="https://github.com/muhammad-fiaz/env.zig/pulls"><img src="https://img.shields.io/github/issues-pr/muhammad-fiaz/env.zig" alt="GitHub pull requests"></a>
<a href="https://github.com/muhammad-fiaz/env.zig"><img src="https://img.shields.io/github/last-commit/muhammad-fiaz/env.zig" alt="GitHub last commit"></a>
<a href="https://github.com/muhammad-fiaz/env.zig"><img src="https://img.shields.io/github/license/muhammad-fiaz/env.zig" alt="License"></a>
<a href="https://github.com/muhammad-fiaz/env.zig/actions/workflows/ci.yml"><img src="https://github.com/muhammad-fiaz/env.zig/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
<img src="https://img.shields.io/badge/platforms-linux%20%7C%20windows%20%7C%20macos-blue" alt="Supported Platforms">
<a href="https://pay.muhammadfiaz.com"><img src="https://img.shields.io/badge/Sponsor-pay.muhammadfiaz.com-ff69b4?style=flat&logo=heart" alt="Sponsor"></a>
<a href="https://github.com/sponsors/muhammad-fiaz"><img src="https://img.shields.io/badge/Sponsor-GitHub-pink?style=social&logo=github" alt="GitHub Sponsors"></a>
<a href="https://hits.sh/muhammad-fiaz/env.zig/"><img src="https://hits.sh/muhammad-fiaz/env.zig.svg?label=Visitors&extraCount=0&color=green" alt="Repo Visitors"></a>

<p><em>A production-grade runtime <code>.env</code> library for Zig — parsing, interpolation, validation, and serialization.</em></p>

<b><a href="https://muhammad-fiaz.github.io/env.zig/">Documentation</a> |
<a href="https://muhammad-fiaz.github.io/env.zig/api/env">API Reference</a> |
<a href="https://muhammad-fiaz.github.io/env.zig/guide/getting-started">Quick Start</a> |
<a href="https://muhammad-fiaz.github.io/env.zig/comparison">Comparison</a> |
<a href="CONTRIBUTING.md">Contributing</a></b>

</div>

`env.zig` is a production-grade runtime `.env` file library for Zig, providing everything needed to manage application configuration — parsing `.env` files, variable interpolation, schema validation, serialization, type-safe accessors, and modular architecture.

> [!TIP]
> If you build with env.zig, make sure to give it a star.


**Related Zig projects:**

- For **env.zig** (.env parsing), check out **[env.zig](https://github.com/muhammad-fiaz/env.zig)**.
- For **TUI** support, check out **[tui.zig](https://github.com/muhammad-fiaz/tui.zig)**.
- For **ZON file format** support, check out **[zon.zig](https://github.com/muhammad-fiaz/zon.zig)**.
- For **spinners/loading/progress bar** support, check out **[loaders.zig](https://github.com/muhammad-fiaz/loaders.zig)**.
- For **MCP** support, check out **[mcp.zig](https://github.com/muhammad-fiaz/mcp.zig)**.
- For **args parsing** support, check out **[args.zig](https://github.com/muhammad-fiaz/args.zig)**.
- For **HTTP client/server** support, check out **[httpx.zig](https://github.com/muhammad-fiaz/httpx.zig)**.
- For **API framework** support, check out **[api.zig](https://github.com/muhammad-fiaz/api.zig)**.
- For **web framework** support, check out **[zix](https://github.com/muhammad-fiaz/zix)**.
- For **archive/compression** support, check out **[archive.zig](https://github.com/muhammad-fiaz/archive.zig)**.
- For **compression file format** support, check out **[zigx](https://github.com/muhammad-fiaz/zigx)**.
- For **file downloading** support, check out **[downloader.zig](https://github.com/muhammad-fiaz/downloader.zig)**.
- For **update checker/auto-updater** support, check out **[updater.zig](https://github.com/muhammad-fiaz/updater.zig)**.
- For **numerical computing** support, check out **[num.zig](https://github.com/muhammad-fiaz/num.zig)**.
- For **logging** support, check out **[logly.zig](https://github.com/muhammad-fiaz/logly.zig)**.
- For **data validation and serialization** support, check out **[zigantic](https://github.com/muhammad-fiaz/zigantic)**.


---

<details>
<summary><strong>Features</strong> (click to expand)</summary>

| Feature | Description | Documentation |
|---------|-------------|---------------|
| **`.env` File Parsing** | Load and parse `.env` files with comments, quotes, empty values, and inline comments. | https://muhammad-fiaz.github.io/env.zig/guide/getting-started |
| **Variable Interpolation** | `${VAR}` syntax with circular dependency detection and configurable max depth. | https://muhammad-fiaz.github.io/env.zig/guide/interpolation |
| **Escape Sequences** | `\n`, `\t`, `\r`, `\\`, `\"`, `\'`, `` \` `` in double-quoted values. | https://muhammad-fiaz.github.io/env.zig/guide/getting-started |
| **Schema Validation** | Define schemas with required fields, types, and custom validators. Errors for required, warnings for optional. | https://muhammad-fiaz.github.io/env.zig/guide/validation |
| **Built-in Validators** | `required`, `boolean`, `integer`, `float`, `url`, `email`, `ipv4`, `hostname`, `port`, `range`, `minLength`, `maxLength`, `oneOf`. | https://muhammad-fiaz.github.io/env.zig/api/validators |
| **Type-Safe Accessors** | `get`, `getString`, `getBool`, `getInt`, `getFloat`, `getEnum`, `getList` — automatic parsing and type conversion. | https://muhammad-fiaz.github.io/env.zig/api/env |
| **Serialization** | Write configurations back to `.env` format with key sorting, value quoting, and trailing newlines. | https://muhammad-fiaz.github.io/env.zig/guide/serialization |
| **Insertion Order** | Guaranteed key iteration order (unlike `std.process.Environ`). | https://muhammad-fiaz.github.io/env.zig/api/env |
| **Cache** | Built-in key-value cache for frequently accessed values. | https://muhammad-fiaz.github.io/env.zig/api/env |
| **Iterator** | Iterate over entries with `next`, `peek`, `reset`, `skip`, `remaining`, `collect`. | https://muhammad-fiaz.github.io/env.zig/api/env |
| **Config Builder** | Chainable `.with()` pattern for configuration customization. | https://muhammad-fiaz.github.io/env.zig/api/config |
| **Modular Architecture** | Parser, lexer, tokenizer, interpolation, schema, validator, serializer, writer, cache, iterator — all in separate files. | https://muhammad-fiaz.github.io/env.zig/api/env |
| **Allocator-Aware** | Every allocation has a matching `deinit`, no leaks. | https://muhammad-fiaz.github.io/env.zig/guide/getting-started |
| **Zero Global State** | No OOP, no singletons, fully composable. | https://muhammad-fiaz.github.io/env.zig/guide/getting-started |
| **Multiple File Loading** | Load multiple `.env` files in order with override control. | https://muhammad-fiaz.github.io/env.zig/api/env |
| **Clone & Merge** | Deep copy and merge `Env` instances. | https://muhammad-fiaz.github.io/env.zig/api/env |
| **Error Handling** | Graceful handling of corrupted files, missing keys, invalid formats with rich diagnostics. | https://muhammad-fiaz.github.io/env.zig/guide/getting-started |
| **No External Dependencies** | Pure Zig implementation for maximum portability. | https://muhammad-fiaz.github.io/env.zig/guide/getting-started |

</details>

---

<details>
<summary><strong>Prerequisites and Supported Platforms</strong> (click to expand)</summary>

<br>

## Prerequisites

Before using `env.zig`, ensure you have the following:

| Requirement | Version | Notes |
|-------------|---------|-------|
| **Zig** | 0.16.0+ | Download from [ziglang.org](https://ziglang.org/download/) |
| **Operating System** | Windows 10+, Linux, macOS | Cross-platform support |

---

## Supported Platforms

`env.zig` is validated on these architectures:

| Platform | x86_64 (64-bit) | aarch64 (ARM64) | x86 (32-bit) |
|----------|-----------------|-----------------|--------------|
| **Linux** | Yes | Yes | Yes |
| **Windows** | Yes | Yes | Yes |
| **macOS** | Yes | Yes (Apple Silicon) | No |

### Cross-Compilation

Zig makes cross-compilation easy. Build for any target from any host:

```bash
# Build for Linux ARM64 from Windows
zig build -Dtarget=aarch64-linux

# Build for Windows from Linux
zig build -Dtarget=x86_64-windows

# Build for macOS Apple Silicon from Linux
zig build -Dtarget=aarch64-macos

# Build for 32-bit Windows
zig build -Dtarget=x86-windows
```

</details>

---

## Installation

### Method 1: Zig Fetch (Recommended)

```bash
zig fetch --save=env https://github.com/muhammad-fiaz/env.zig/archive/refs/tags/0.0.1.tar.gz
```

### Method 2: Zig Fetch (Main Branch)

Use the latest development version from the `main` branch.

```bash
zig fetch --save=env git+https://github.com/muhammad-fiaz/env.zig.git
```

### Method 3: Manual `build.zig.zon` Configuration

Add the dependency to your `build.zig.zon` file.

```zig
.dependencies = .{
    .env = .{
        .url = "https://github.com/muhammad-fiaz/env.zig/archive/refs/tags/0.0.1.tar.gz",
        .hash = "...", // Run `zig fetch --save=env <url>` to generate the hash.
    },
},
```

### Method 4: Local Source Checkout

Clone the repository locally.

```bash
git clone https://github.com/muhammad-fiaz/env.zig.git
cd env.zig
zig build
```

To use a local checkout from another project, add a path dependency to your `build.zig.zon`:

```zig
.dependencies = .{
    .env = .{
        .path = "../env.zig",
    },
},
```

### Wire into `build.zig`

After adding the dependency, import the module in your `build.zig`:

```zig
const env_dep = b.dependency("env", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("env", env_dep.module("env"));
```

## Quick Start

### Basic Usage

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

    // Print to stdout
    var stdout_buffer: [0x100]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print("host={s} port={d} debug={}\n", .{ host, port, debug });
    try stdout.flush();
}
```

### Configuration

```zig
var env = env_mod.Env.init(allocator, .{
    .strict = true,           // Fail on syntax errors
    .interpolate = true,      // Enable ${VAR} interpolation
    .trim = true,             // Trim whitespace from keys/values
    .override = true,         // Override existing values when loading multiple files
    .sort_keys = true,        // Sort keys when serializing
    .quote_spaces = true,     // Quote values containing spaces
});
```

### Schema Validation

```zig
const schema = env_mod.schema.Schema.init(&.{
    .{
        .key = "DATABASE_URL",
        .required = true,
        .validators_list = &.{ validators.required, validators.url },
        .description = "Database connection URL",
    },
    .{
        .key = "PORT",
        .required = true,
        .validators_list = &.{ validators.required, validators.integer, validators.port },
        .description = "Server port",
    },
    .{
        .key = "LOG_LEVEL",
        .required = false,
        .default_value = "info",
        .validators_list = &.{validators.oneOf(&.{ "debug", "info", "warn", "error" })},
        .description = "Logging level",
    },
});

const errors = schema.validate(&env.entries);
if (errors.len > 0) {
    for (errors) |err| {
        std.debug.print("{s}: {s}\n", .{ err.key, err.message });
    }
}
```

### Serialization

```zig
// Serialize to .env string
const output = try env.serialize();
defer allocator.free(output);

// Save to file
try env.save("output.env");
```

### Clone & Merge

```zig
// Deep copy
var cloned = try env.clone();
defer cloned.deinit();

// Merge (other overrides self)
try env.merge(&other_env);
```

### Variable Interpolation

```env
GREETING=hello
MESSAGE=${GREETING} world
```

```zig
// MESSAGE resolves to "hello world"
const msg = env.get("MESSAGE");
```

## Examples

The `examples/` directory contains comprehensive, runnable examples:

- **Basic** — Set/get values, type-safe accessors, iteration, serialization.
- **Validation** — Schema validation with built-in validators.
- **Serialization** — Serialize to `.env` format with sorting and quoting.

To run any example:

```bash
zig build example
zig-out/bin/basic_example
zig-out/bin/validation_example
zig-out/bin/serialization_example
```

## Validation Matrix

Validate host functionality and cross-target compatibility:

```bash
# Host runtime validation
zig build test

# Generate native documentation
zig build docs

# Run examples
zig build example

# Check formatting
zig fmt --check src/
```

## Comparison with Zig Built-in

| Feature | `std.process.Environ` | `env.zig` |
|---------|:---------------------:|:---------:|
| **Source** | OS process env vars | `.env` files + manual entries |
| **File Parsing** | No | Yes |
| **Variable Interpolation** | No | Yes |
| **Schema Validation** | No | Yes |
| **Type-Safe Accessors** | No | Yes |
| **Insertion Order** | OS-dependent | Guaranteed |
| **Serialization** | No | Yes |
| **Cache** | No | Yes |
| **Config Options** | OS-specific | 14+ options |
| **Multiple Files** | N/A | Yes |
| **Override Control** | N/A | Yes |
| **Strict Mode** | N/A | Yes |
| **Clone/Merge** | Clone only | Both |
| **Allocator-Aware** | Yes | Yes |

See the full [comparison](https://muhammad-fiaz.github.io/env.zig/comparison).

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass: `zig build test`
5. Ensure formatting is clean: `zig fmt --check src/`
6. Submit a pull request

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

## License

MIT License — see [LICENSE](LICENSE) for details.
