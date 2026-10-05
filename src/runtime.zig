const std = @import("std");
const osEnvMod = @import("os_env.zig");

pub const OsEnv = osEnvMod.OsEnv;
pub const Snapshot = osEnvMod.Snapshot;
pub const Scope = osEnvMod.Scope;

/// Explicit runtime/process-environment namespace.
///
/// `Env` is an in-memory `.env` store; `runtime` is the actual process
/// environment. All mutation here is process-global and thread-unsafe
/// by OS design. Reads distinguish missing (`null`) from empty (`""`).
///
/// This namespace reuses Zig 0.17.0 `std.process.Environ` for enumeration
/// and only uses minimal custom OS bindings for `set`/`unset`, which the
/// standard library does not expose.
pub const get = OsEnv.get;
pub const getAlloc = OsEnv.getAlloc;
pub const getOrDefault = OsEnv.getOrDefault;
pub const contains = OsEnv.contains;
pub const exists = OsEnv.exists;
pub const isEmpty = OsEnv.isEmpty;
pub const set = OsEnv.set;
pub const unset = OsEnv.unset;
pub const getAll = OsEnv.getAllAlloc;
pub const getMap = OsEnv.getMap;
pub const snapshot = OsEnv.snapshot;
pub const validateKey = OsEnv.validateKey;

test {
    std.testing.refAllDecls(@This());
}
