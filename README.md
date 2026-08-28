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
<a href="https://github.com/muhammad-fiaz/env.zig/releases/latest"><img src="https://img.shields.io/github/v/release/muhammad-fiaz/env.zig?label=Latest%20Release&style=flat-square" alt="Latest Release"></a>
<a href="https://pay.muhammadfiaz.com"><img src="https://img.shields.io/badge/Sponsor-pay.muhammadfiaz.com-ff69b4?style=flat&logo=heart" alt="Sponsor"></a>
<a href="https://github.com/sponsors/muhammad-fiaz"><img src="https://img.shields.io/badge/Sponsor-GitHub-pink?style=social&logo=github" alt="GitHub Sponsors"></a>
<a href="https://hits.sh/muhammad-fiaz/env.zig/"><img src="https://hits.sh/muhammad-fiaz/env.zig.svg?label=Visitors&extraCount=0&color=green" alt="Repo Visitors"></a>

<p><em>A production-grade, high-performance runtime .env library for Zig.</em></p>

<b><a href="https://muhammad-fiaz.github.io/env.zig/">Documentation</a> |
<a href="https://muhammad-fiaz.github.io/env.zig/api/env">API Reference</a> |
<a href="https://muhammad-fiaz.github.io/env.zig/guide/getting-started">Quick Start</a> |
<a href="https://muhammad-fiaz.github.io/env.zig/comparison">Comparison</a> |
<a href="CONTRIBUTING.md">Contributing</a></b>

</div>

`env.zig` is a modern, high-performance `.env` library for Zig, providing everything needed to manage application configuration — `.env` parsing, variable interpolation with OS fallback, schema validation, serialization, type-safe accessors, and native OS environment bridging for Windows, Linux and macOS.

> [!TIP]
> If you build with env.zig, make sure to give it a star. ⭐

> [!NOTE]
> **Project maturity:** This project is production-ready and actively maintained. It provides a comprehensive `.env` and OS environment implementation with zero global state, allocator-aware ownership, and cross-platform guarantees. The project is actively evolving and welcomes production use and contributions.
>
> **Custom OS environment from scratch:** Zig's standard library provides `std.process.Environ` as a thin wrapper, but not a full-featured env manager.
> `env.zig` implements OS bridging **entirely from scratch**, including:
> - **POSIX** `getenv` / `setenv` / `unsetenv` via `std.c.environ` with `setenv`/`unsetenv` externs, and `WTF-8` aware key validation
> - **Windows** `GetEnvironmentVariableW` / `SetEnvironmentVariableW` / `GetEnvironmentStringsW` with `PEB` locking, `WTF-16LE ↔ WTF-8` conversion, `ERROR_ENVVAR_NOT_FOUND` handling via `SetLastError(0)`, and case-insensitive `Wyhash`/`eqlIgnoreCaseWtf8` matching
> - **Interpolation** `${VAR}`, `$VAR`, `${VAR:-default}`, `${VAR:+alt}`, `${VAR:?err}`, nested `${MISSING:-${FALLBACK}}`, and `$env:VAR` / `${env:VAR}` (PowerShell `$env`) with OS fallback and circular-depth detection
> - **Shell compat** `export KEY=val` prefix, `export_to_env` auto-sync, and prefix-filtered `APP_` loading
> - **Temporary scopes** `Scope` / `EnvScope` / `Snapshot` with save/restore for `$env`-style isolation and child-process `Environ.Map` building

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
- For **UUID** support, check out **[uuid.zig](https://github.com/muhammad-fiaz/uuid.zig)**.
- For **key-value database** support, check out **[zkv.zig](https://github.com/muhammad-fiaz/zkv.zig)**.
- For **terminal color & text styles** support, check out **[hint.zig](https://github.com/muhammad-fiaz/hint.zig)**.

---

<details>
<summary><strong>Features</strong> (click to expand)</summary>

| Feature | Description | Documentation |
|---------|-------------|---------------|
| **`.env` Parsing** | Load and parse `.env` files with comments, quotes, empty values, inline comments, and `export` prefix. | https://muhammad-fiaz.github.io/env.zig/guide/getting-started |
| **Variable Interpolation** | `${VAR}`, `$VAR`, `${VAR:-default}`, `${VAR:+alt}`, `${VAR:?err}`, nested defaults, `$env:VAR` with OS fallback, circular detection, max depth. | https://muhammad-fiaz.github.io/env.zig/guide/interpolation |
| **OS Environment (Win/Linux/macOS)** | Native `get`/`set`/`unset`/`getAll`/`snapshot` via `getenv`/`SetEnvironmentVariableW` with WTF-8/WTF-16 handling, thread-local TLS buffer. | https://muhammad-fiaz.github.io/env.zig/guide/os-env |
| **Temporary / Scoped Env** | `Scope`, `EnvScope`, `Snapshot` + `with` helper for automatic restore; `$env`-style isolation for tests and child processes. | https://muhammad-fiaz.github.io/env.zig/guide/os-env |
| **Shell Compatibility** | `export KEY=val`, `export_to_env` sync, prefix-filtered `loadOsEnvWithPrefix("APP_")`. | https://muhammad-fiaz.github.io/env.zig/guide/getting-started |
| **Escape Sequences** | `\n`, `\t`, `\r`, `\\`, `\"`, `\'`, `` \` ``, `\$`, `\0` in double-quoted values (single source via `helpers.unescape`). | https://muhammad-fiaz.github.io/env.zig/guide/getting-started |
| **Schema Validation** | Define schemas with required fields, types, and custom validators. Errors for required, warnings for optional. | https://muhammad-fiaz.github.io/env.zig/guide/validation |
| **Built-in Validators** | `required`, `boolean`, `integer`, `float`, `url`, `email`, `ipv4`, `hostname`, `port`, `range`, `minLength`, `maxLength`, `oneOf`. | https://muhammad-fiaz.github.io/env.zig/api/validators |
| **Type-Safe Accessors** | `get`, `getString`, `getBool`, `getInt`, `getFloat`, `getEnum`, `getList` + `getOs`, `getWithFallback`, `require`, `containsOs`. | https://muhammad-fiaz.github.io/env.zig/api/env |
| **Serialization** | Write back to `.env` with quoting, sorting, trailing newlines; shared `needsQuoting`/`escapedForChar` helpers. | https://muhammad-fiaz.github.io/env.zig/guide/serialization |
| **Insertion Order** | Guaranteed order (unlike `std.process.Environ`). | https://muhammad-fiaz.github.io/env.zig/api/env |
| **Cache** | Built-in `Cache` for frequently accessed values. | https://muhammad-fiaz.github.io/env.zig/api/env |
| **Iterator** | `next`, `peek`, `reset`, `skip`, `remaining`, `collect`. | https://muhammad-fiaz.github.io/env.zig/api/env |
| **Config Builder** | Chainable `.with()` pattern. | https://muhammad-fiaz.github.io/env.zig/api/config |
| **Environ.Map** | `toEnvironMap` / `applyToEnvironMap` for `std.process.spawn` child envs. | https://muhammad-fiaz.github.io/env.zig/guide/os-env |
| **Clone & Merge** | Deep copy and merge `Env` instances. | https://muhammad-fiaz.github.io/env.zig/api/env |
| **Multiple File Loading** | `loadMany` with override control. | https://muhammad-fiaz.github.io/env.zig/api/env |
| **Error Handling** | Rich `Diagnostic` with file/line/column/token/suggestion, strict mode. | https://muhammad-fiaz.github.io/env.zig/guide/getting-started |
| **Allocator-Aware** | Every allocation matched with `deinit`, no leaks. | https://muhammad-fiaz.github.io/env.zig/guide/getting-started |
| **Zero Global State** | No singletons, fully composable. | https://muhammad-fiaz.github.io/env.zig/guide/getting-started |
| **No External Dependencies** | Pure Zig, works on all targets. | https://muhammad-fiaz.github.io/env.zig/guide/getting-started |

</details>

---

<details>
<summary><strong>Prerequisites and Supported Platforms</strong> (click to expand)</summary>

<br>

## Prerequisites

Before using `env.zig`, ensure you have the following:

| Requirement | Version | Notes |
|-------------|---------|-------|
| **Zig** | **0.16.0** (recommended) | Download from [ziglang.org](https://ziglang.org/download/) |
| **Operating System** | Windows 10+, Linux, macOS | Cross-platform env support |

> [!IMPORTANT]
> **Zig 0.16.0 is required.** This project currently targets Zig 0.16.0 (stable). Zig 0.17.0 is in development (dev branch, not yet a stable release) and introduces several minor breaking changes from 0.16.0. Migration to 0.17.0 will happen once it is officially released as a stable version. Please use Zig 0.16.0 for all builds.

---

## Supported Platforms

`env.zig` is validated on these architectures (single codebase, no arch-specific branches):

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

**Latest Release (v0.0.2)**

```bash
zig fetch https://github.com/muhammad-fiaz/env.zig/archive/refs/tags/0.0.2.tar.gz
```

**Previous Stable Release (v0.0.1)**

```bash
zig fetch https://github.com/muhammad-fiaz/env.zig/archive/refs/tags/0.0.1.tar.gz
```

> [!WARNING]
> Zig **0.15** is deprecated and supported only by **v0.0.1**. New projects should use **Zig 0.16.0+** with **env.zig v0.0.2**.

### Method 2: Zig Fetch (Main Branch)

Use the latest development version from the `main` branch.

```bash
zig fetch git+https://github.com/muhammad-fiaz/env.zig.git
```

### Method 3: Manual `build.zig.zon` Configuration

Add the dependency to your `build.zig.zon` file.

```zig
.dependencies = .{
    .env = .{
        .url = "https://github.com/muhammad-fiaz/env.zig/archive/refs/tags/0.0.2.tar.gz",
        .hash = "...", // Run `zig fetch <url>` to generate the hash.
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

    try env.load(".env");
    try env.parseString("HOST=localhost\nPORT=8080\n");

    const host = env.get("HOST") orelse "localhost";
    const port = env.getInt(u16, "PORT") orelse 3000;
    const debug = env.getBool("DEBUG") orelse false;

    var stdout_buffer: [0x100]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print("host={s} port={d} debug={}\n", .{ host, port, debug });
    try stdout.flush();
}
```

### OS Environment (Windows/Linux/macOS)

```zig
const OsEnv = env_mod.OsEnv;
const Scope = env_mod.Scope;

// Native OS
try OsEnv.set("MY_KEY", "value");
const v = OsEnv.get("MY_KEY"); // ?[]const u8
try OsEnv.unset("MY_KEY");

// Env + OS fallback (like $VAR)
const host = env.getOs("HOST") orelse "localhost";
try env.loadOsEnv(); // import all OS vars
try env.loadOsEnvWithPrefix("APP_"); // APP_PORT -> PORT
try env.exportToOsEnv();

// For child processes
var map = try env.toEnvironMap(allocator);
defer map.deinit();

// Temporary $env isolation
{
    var scope = Scope.init(allocator);
    defer scope.deinit();
    try scope.set("TMP", "temporary");
    // restored on deinit
}
var snap = try OsEnv.snapshot(allocator);
defer snap.deinit();
try snap.restore();
```

### Variable Interpolation

```env
GREETING=hello
MESSAGE=${GREETING} world
PORT=${PORT:-3000}
ALT=${SET:+enabled}
FALLBACK=${MISSING:-${GREETING}}
HOME_FALLBACK=${HOME}          # OS fallback via get/OS
ENV_STYLE=$env:HOME            # PowerShell $env: prefix
```

```zig
var env2 = env_mod.Env.init(allocator, .{ .interpolate = true });
defer env2.deinit();
try env2.parseString("A=${HOME}\nB=${MISSING:-default}\n");
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

const errs = schema.validate(&env.entries);
if (errs.len > 0) for (errs) |e| std.debug.print("{s}: {s}\n", .{ e.key, e.message });
```

### Serialization & Scopes

```zig
const out = try env.serialize();
defer allocator.free(out);
try env.save("output.env");

var es = env.scope();
defer es.deinit();
try es.set("PORT", "9090");
```

## Examples

The `examples/` directory contains **11 comprehensive, runnable examples** covering all error paths, callbacks and returns:

- **Basic** - Set/get, type-safe accessors, iteration.
- **Interpolation** - Nested `${VAR}`, defaults, OS fallback, `$env:VAR`.
- **OS Environment** - Native `OsEnv`, `Scope`, `Snapshot`, `Environ.Map` (Windows/Linux/macOS).
- **Validation** - Schema validation, custom `ValidatorFn` callbacks, `err` vs `warning`.
- **Serialization** - Sorting, quoting, trailing newlines.
- **Clone & Merge** - Deep copy and default merging.
- **Cache** - Built-in `Cache` API.
- **Iterator** - `peek`, `skip`, `reset`, `collect`.
- **File I/O** - `load`/`save`/`loadMany`/`reload`, `loadOsEnvWithPrefix`, `exportToOsEnv` with correct `FileNotFound`/`IoError` returns.
- **Error Handling** - `strict` mode, `ParseError`, `FileNotFound`, `CircularDependency`, `NoSpaceLeft` via `Writer`.
- **Type-Safe** - `getBool`/`getInt`/`getFloat`/`getEnum`/`getList` with `null` returns on `TypeMismatch`, `getOs`/`containsOs`.

To run:

```bash
zig build example
zig-out/bin/basic_example
zig-out/bin/os_env_example
zig-out/bin/file_io_example
zig-out/bin/error_handling_example
zig-out/bin/type_safe_example
```

## Validation Matrix

Validate host functionality and cross-target compatibility:

```bash
# Host runtime validation
zig build test
zig build docs
zig build example
zig fmt --check src/

# Cross-target library compile validation
zig build -Dtarget=aarch64-linux
zig build -Dtarget=x86_64-windows
zig build -Dtarget=aarch64-macos
zig build -Dtarget=x86-windows
```

If you need to test Linux runtime on Windows, use WSL:

```bash
zig build test -Dtarget=x86_64-linux
./zig-out/bin/test
```

## Comparison with Zig Built-in

| Feature | `std.process.Environ` | `env.zig` |
|---------|:---------------------:|:---------:|
| **Source** | OS process env vars | `.env` files + OS env + manual |
| **File Parsing** | No | Yes (`export` aware) |
| **Variable Interpolation** | No | Yes (shell-like) |
| **OS Fallback** | N/A | Yes |
| **Schema Validation** | No | Yes |
| **Type-Safe Accessors** | No | Yes |
| **Insertion Order** | OS-dependent | Guaranteed |
| **Serialization** | No | Yes |
| **Cache** | No | Yes |
| **Config Options** | OS-specific | 14+ |
| **Multiple Files** | N/A | Yes |
| **Override Control** | N/A | Yes |
| **Strict Mode** | N/A | Yes |
| **Temporary Scopes** | No | Yes |
| **Environ.Map** | Clone only | `toEnvironMap` + `apply` |
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

MIT License - see [LICENSE](LICENSE) for details.
