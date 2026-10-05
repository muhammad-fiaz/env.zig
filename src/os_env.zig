const std = @import("std");
const builtin = @import("builtin");
const nativeOs = builtin.os.tag;

const unicode = std.unicode;
const windows = std.os.windows;

// Only the process-environment mutation syscalls are custom: Zig 0.17.0
// exposes reads via `std.process.Environ` but no `set`/`unset`.
// Reads reuse `std.process.Environ` wherever possible (see `getMap` and
// `getAllAlloc`). Mutation below is the minimal isolated platform layer.
extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn unsetenv(name: [*:0]const u8) c_int;

extern "kernel32" fn GetEnvironmentVariableW(lpName: [*:0]const u16, lpBuffer: ?[*]u16, nSize: u32) callconv(.winapi) u32;
extern "kernel32" fn SetEnvironmentVariableW(lpName: [*:0]const u16, lpValue: ?[*:0]const u16) callconv(.winapi) c_int;
extern "kernel32" fn SetLastError(dwErrCode: u32) callconv(.winapi) void;

/// Cross-platform OS environment access.
///
/// Reads reuse Zig 0.17.0 `std.process.Environ`; only `set`/`unset`
/// require custom OS bindings because the standard library exposes no
/// mutation API.
///
/// Semantics:
/// - Missing (`null`) is distinct from present-with-empty (`""`).
/// - On Windows lookups are case-insensitive; on POSIX case-sensitive.
/// - Mutation is process-global and thread-unsafe by OS design.
/// - `get` returns borrowed memory (see docs); use `getAlloc` to own.
pub const OsEnv = struct {
    /// Get an OS environment variable. Returns null when missing.
    /// Distinguishes missing (`null`) from empty (`""`).
    ///
    /// Borrowed lifetime:
    /// - POSIX: owned by the OS (`getenv`); valid until the next
    ///   `set`/`unset` of the same key.
    /// - Windows: thread-local buffer, valid until the next `get` on the
    ///   same thread. Duplicate immediately to retain.
    /// On Windows the lookup is case-insensitive; on POSIX case-sensitive.
    pub fn get(key: []const u8) ?[]const u8 {
        if (!isValidKeySilent(key)) return null;
        if (nativeOs == .windows) {
            return getWindows(key);
        } else {
            return getPosix(key);
        }
    }

    /// Get an OS env var and duplicate it with `allocator`.
    /// Caller owns returned memory. Returns null when missing.
    pub fn getAlloc(allocator: std.mem.Allocator, key: []const u8) !?[]u8 {
        const val = get(key) orelse return null;
        return try allocator.dupe(u8, val);
    }

    /// Get OS env var with fallback default (borrowed).
    pub fn getOrDefault(key: []const u8, defaultValue: []const u8) []const u8 {
        return get(key) orelse defaultValue;
    }

    /// True when the key exists, even when its value is empty.
    pub fn exists(key: []const u8) bool {
        return get(key) != null;
    }

    /// Alias for `exists`.
    pub fn contains(key: []const u8) bool {
        return exists(key);
    }

    /// True when missing or present-with-empty.
    pub fn isEmpty(key: []const u8) bool {
        const v = get(key) orelse return true;
        return v.len == 0;
    }

    /// Set an OS environment variable, overwriting when present.
    /// Rejects empty keys, keys containing `=` or NUL, and values
    /// containing NUL with `error.InvalidKey` / `error.InvalidValue`.
    /// OS failures map to `error.IoError`.
    pub fn set(key: []const u8, value: []const u8) !void {
        try validateKey(key);
        if (std.mem.indexOfScalar(u8, value, 0) != null) return error.InvalidValue;
        if (nativeOs == .windows) {
            try setWindows(key, value);
        } else {
            try setPosix(key, value);
        }
    }

    /// Unset / remove an OS environment variable. No-op when missing.
    pub fn unset(key: []const u8) !void {
        try validateKey(key);
        if (nativeOs == .windows) {
            try unsetWindows(key);
        } else {
            try unsetPosix(key);
        }
    }

    /// Return all OS environment variables as an `std.process.Environ.Map`.
    /// Reuses Zig 0.17.0 `Environ.createMap` (PEB-locked on Windows).
    /// Caller must call `map.deinit()`.
    pub fn getMap(allocator: std.mem.Allocator) !std.process.Environ.Map {
        if (nativeOs == .windows) {
            const env = std.process.Environ{ .block = .{ .use_global = true } };
            return try std.process.Environ.createMap(env, allocator);
        } else {
            const env = std.process.Environ{ .block = .{ .slice = std.c.environ[0..envCount() :null] } };
            return try std.process.Environ.createMap(env, allocator);
        }
    }

    /// Load all OS env vars into a `std.StringHashMap`.
    /// Reuses `getMap` (stdlib parsing) then dupes into the map shape
    /// used by `Env` import paths. Caller owns keys and values.
    pub fn getAllAlloc(allocator: std.mem.Allocator) !std.StringHashMap([]const u8) {
        var map = try getMap(allocator);
        defer map.deinit();
        var out = std.StringHashMap([]const u8).init(allocator);
        errdefer {
            var it = out.iterator();
            while (it.next()) |e| {
                allocator.free(e.key_ptr.*);
                allocator.free(e.value_ptr.*);
            }
            out.deinit();
        }
        var it = map.iterator();
        while (it.next()) |entry| {
            const k = try allocator.dupe(u8, entry.key_ptr.*);
            errdefer allocator.free(k);
            const v = try allocator.dupe(u8, entry.value_ptr.*);
            errdefer allocator.free(v);
            try out.put(k, v);
        }
        return out;
    }

    /// Snapshot the current process environment.
    pub fn snapshot(allocator: std.mem.Allocator) !Snapshot {
        const map = try getAllAlloc(allocator);
        return .{ .map = map, .allocator = allocator };
    }

    /// Single source of truth for runtime key validation.
    /// Mirrors `std.process.Environ.Map.validateKeyForPut`: non-empty,
    /// no `=`, no NUL (and valid WTF-8 on Windows).
    pub fn validateKey(key: []const u8) !void {
        if (!std.process.Environ.Map.validateKeyForPut(key)) return error.InvalidKey;
    }

    fn isValidKeySilent(key: []const u8) bool {
        return std.process.Environ.Map.validateKeyForPut(key);
    }

    fn getPosix(key: []const u8) ?[]const u8 {
        const alloc = std.heap.page_allocator;
        const keyZ = alloc.dupeSentinel(u8, key, 0) catch return null;
        defer alloc.free(keyZ);
        const cVal = std.c.getenv(keyZ) orelse return null;
        return std.mem.span(cVal);
    }

    fn setPosix(key: []const u8, value: []const u8) !void {
        const alloc = std.heap.page_allocator;
        const keyZ = try alloc.dupeSentinel(u8, key, 0);
        defer alloc.free(keyZ);
        const valZ = try alloc.dupeSentinel(u8, value, 0);
        defer alloc.free(valZ);
        if (setenv(keyZ, valZ, 1) != 0) return error.IoError;
    }

    fn unsetPosix(key: []const u8) !void {
        const alloc = std.heap.page_allocator;
        const keyZ = try alloc.dupeSentinel(u8, key, 0);
        defer alloc.free(keyZ);
        if (unsetenv(keyZ) != 0) return error.IoError;
    }

    // Windows helpers (custom: std has no mutation API).
    // Borrowed `get` uses a thread-local owned buffer resized per call,
    // so arbitrarily long values work without fixed limits. The slice is
    // valid until the next `get` on the same thread; dupe to retain.
    threadlocal var tlsOwned: ?[]u8 = null;

    fn getWindows(key: []const u8) ?[]const u8 {
        const alloc = std.heap.page_allocator;
        const keyW = unicode.wtf8ToWtf16LeAllocZ(alloc, key) catch return null;
        defer alloc.free(keyW);
        SetLastError(0);
        const needed = GetEnvironmentVariableW(keyW.ptr, null, 0);
        if (needed == 0) {
            const errCode = @backingInt(windows.GetLastError());
            if (errCode == 203) return null; // ERROR_ENVVAR_NOT_FOUND
            return "";
        }
        var buf: [4096]u16 = undefined;
        if (needed <= buf.len) {
            SetLastError(0);
            const got = GetEnvironmentVariableW(keyW.ptr, &buf, @intCast(buf.len));
            if (got == 0) {
                const errCode2 = @backingInt(windows.GetLastError());
                if (errCode2 == 203) return null;
                return "";
            }
            return tlsConvertWtf16ToWtf8(buf[0..got]);
        } else {
            const heapBuf = alloc.alloc(u16, needed) catch return null;
            defer alloc.free(heapBuf);
            SetLastError(0);
            const got = GetEnvironmentVariableW(keyW.ptr, heapBuf.ptr, @intCast(heapBuf.len));
            if (got == 0) {
                const errCode2 = @backingInt(windows.GetLastError());
                if (errCode2 == 203) return null;
                return "";
            }
            return tlsConvertWtf16ToWtf8(heapBuf[0..got]);
        }
    }

    fn tlsConvertWtf16ToWtf8(w: []const u16) ?[]const u8 {
        const alloc = std.heap.page_allocator;
        const tmp = unicode.wtf16LeToWtf8Alloc(alloc, w) catch return null;
        defer alloc.free(tmp);
        if (tlsOwned) |old| alloc.free(old);
        const owned = alloc.dupe(u8, tmp) catch return null;
        tlsOwned = owned;
        return owned;
    }

    fn setWindows(key: []const u8, value: []const u8) !void {
        const alloc = std.heap.page_allocator;
        const keyW = unicode.wtf8ToWtf16LeAllocZ(alloc, key) catch return error.InvalidValue;
        defer alloc.free(keyW);
        const valW = unicode.wtf8ToWtf16LeAllocZ(alloc, value) catch return error.InvalidValue;
        defer alloc.free(valW);
        if (SetEnvironmentVariableW(keyW.ptr, valW.ptr) == 0) return error.IoError;
    }

    fn unsetWindows(key: []const u8) !void {
        const alloc = std.heap.page_allocator;
        const keyW = unicode.wtf8ToWtf16LeAllocZ(alloc, key) catch return error.InvalidValue;
        defer alloc.free(keyW);
        if (SetEnvironmentVariableW(keyW.ptr, null) == 0) return error.IoError;
    }

    fn envCount() usize {
        var n: usize = 0;
        while (std.c.environ[n] != null) : (n += 1) {}
        return n;
    }
};

/// Snapshot of process environment for save/restore.
pub const Snapshot = struct {
    map: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Snapshot) void {
        var it = self.map.iterator();
        while (it.next()) |e| {
            self.allocator.free(e.key_ptr.*);
            self.allocator.free(e.value_ptr.*);
        }
        self.map.deinit();
    }

    /// Restore environment to this snapshot state.
    /// Removes keys added after the snapshot and restores snapshot values.
    /// Process-global and thread-unsafe by OS design.
    pub fn restore(self: *const Snapshot) !void {
        var cur = try OsEnv.getAllAlloc(self.allocator);
        defer {
            var it = cur.iterator();
            while (it.next()) |e| {
                self.allocator.free(e.key_ptr.*);
                self.allocator.free(e.value_ptr.*);
            }
            cur.deinit();
        }
        var curIt = cur.iterator();
        while (curIt.next()) |e| {
            if (!self.map.contains(e.key_ptr.*)) {
                try OsEnv.unset(e.key_ptr.*);
            }
        }
        var snapIt = self.map.iterator();
        while (snapIt.next()) |e| {
            const curVal = OsEnv.get(e.key_ptr.*);
            if (curVal == null or !std.mem.eql(u8, curVal.?, e.value_ptr.*)) {
                try OsEnv.set(e.key_ptr.*, e.value_ptr.*);
            }
        }
    }
};

/// Temporary environment scope.
/// Saves original values for keys it touches and restores on `deinit`.
/// Process-global and thread-unsafe; do not share across threads.
pub const Scope = struct {
    allocator: std.mem.Allocator,
    saved: std.StringHashMap(?[]const u8),
    active: bool,

    pub fn init(allocator: std.mem.Allocator) Scope {
        return .{
            .allocator = allocator,
            .saved = std.StringHashMap(?[]const u8).init(allocator),
            .active = true,
        };
    }

    pub fn deinit(self: *Scope) void {
        if (!self.active) return;
        self.restore() catch {};
        var it = self.saved.iterator();
        while (it.next()) |e| {
            self.allocator.free(e.key_ptr.*);
            if (e.value_ptr.*) |v| self.allocator.free(v);
        }
        self.saved.deinit();
        self.active = false;
    }

    fn ensureSaved(self: *Scope, key: []const u8) !void {
        if (self.saved.contains(key)) return;
        const ownedKey = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(ownedKey);
        const orig = OsEnv.get(key);
        const ownedVal: ?[]const u8 = if (orig) |v| try self.allocator.dupe(u8, v) else null;
        errdefer if (ownedVal) |v| self.allocator.free(v);
        try self.saved.put(ownedKey, ownedVal);
    }

    /// Set a key to value within the scope.
    pub fn set(self: *Scope, key: []const u8, value: []const u8) !void {
        try self.ensureSaved(key);
        try OsEnv.set(key, value);
    }

    /// Unset a key within the scope.
    pub fn unset(self: *Scope, key: []const u8) !void {
        try self.ensureSaved(key);
        try OsEnv.unset(key);
    }

    /// Restore all keys to original state without fully deiniting.
    pub fn restore(self: *Scope) !void {
        var it = self.saved.iterator();
        while (it.next()) |e| {
            const key = e.key_ptr.*;
            const maybeVal = e.value_ptr.*;
            if (maybeVal) |v| {
                try OsEnv.set(key, v);
            } else {
                OsEnv.unset(key) catch {};
            }
        }
    }

    /// Temporarily run a function with given overrides.
    pub fn with(allocator: std.mem.Allocator, overrides: []const struct { key: []const u8, value: ?[]const u8 }, func: *const fn () anyerror!void) !void {
        var scope = Scope.init(allocator);
        defer scope.deinit();
        for (overrides) |ov| {
            if (ov.value) |v| try scope.set(ov.key, v) else try scope.unset(ov.key);
        }
        try func();
    }
};

// Tests
test "OsEnv set/get/unset" {
    const key = "ENV_ZIG_TEST_OS_ENV_BASIC";
    OsEnv.unset(key) catch {};
    try std.testing.expect(OsEnv.get(key) == null);
    try OsEnv.set(key, "hello");
    try std.testing.expectEqualStrings("hello", OsEnv.get(key).?);
    try OsEnv.set(key, "world");
    try std.testing.expectEqualStrings("world", OsEnv.get(key).?);
    try OsEnv.unset(key);
    try std.testing.expect(OsEnv.get(key) == null);
}

test "OsEnv exists and isEmpty" {
    const key = "ENV_ZIG_TEST_OS_ENV_EXISTS";
    OsEnv.unset(key) catch {};
    try std.testing.expect(!OsEnv.exists(key));
    try std.testing.expect(OsEnv.isEmpty(key));
    try OsEnv.set(key, "x");
    try std.testing.expect(OsEnv.exists(key));
    try std.testing.expect(!OsEnv.isEmpty(key));
    try OsEnv.set(key, "");
    const g = OsEnv.get(key);
    try std.testing.expect(g != null);
    try std.testing.expect(g.?.len == 0);
    try std.testing.expect(OsEnv.exists(key));
    try std.testing.expect(OsEnv.isEmpty(key));
    try OsEnv.unset(key);
}

test "OsEnv getAlloc" {
    const key = "ENV_ZIG_TEST_OS_ENV_ALLOC";
    OsEnv.unset(key) catch {};
    try OsEnv.set(key, "allocVal");
    const v = try OsEnv.getAlloc(std.testing.allocator, key);
    defer if (v) |s| std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("allocVal", v.?);
    const missing = try OsEnv.getAlloc(std.testing.allocator, "ENV_ZIG_TEST_MISSING_12345");
    try std.testing.expect(missing == null);
    try OsEnv.unset(key);
}

test "OsEnv rejects invalid keys and NUL" {
    try std.testing.expectError(error.InvalidKey, OsEnv.set("", "v"));
    try std.testing.expectError(error.InvalidKey, OsEnv.set("A=B", "v"));
    try std.testing.expectError(error.InvalidKey, OsEnv.set("A\x00B", "v"));
    try std.testing.expectError(error.InvalidValue, OsEnv.set("ENV_ZIG_TEST_NUL", "a\x00b"));
    OsEnv.unset("ENV_ZIG_TEST_NUL") catch {};
}

test "OsEnv Scope restores" {
    const key = "ENV_ZIG_TEST_SCOPE";
    OsEnv.unset(key) catch {};
    try OsEnv.set(key, "original");
    {
        var scope = Scope.init(std.testing.allocator);
        defer scope.deinit();
        try scope.set(key, "temporary");
        try std.testing.expectEqualStrings("temporary", OsEnv.get(key).?);
        try scope.set("ENV_ZIG_TEST_SCOPE_NEW", "newval");
        try std.testing.expectEqualStrings("newval", OsEnv.get("ENV_ZIG_TEST_SCOPE_NEW").?);
    }
    try std.testing.expectEqualStrings("original", OsEnv.get(key).?);
    try std.testing.expect(OsEnv.get("ENV_ZIG_TEST_SCOPE_NEW") == null);
    try OsEnv.unset(key);
}

test "OsEnv snapshot restore" {
    const key = "ENV_ZIG_TEST_SNAPSHOT";
    OsEnv.unset(key) catch {};
    try OsEnv.set(key, "before");
    var snap = try OsEnv.snapshot(std.testing.allocator);
    defer snap.deinit();
    try OsEnv.set(key, "after");
    try OsEnv.set("ENV_ZIG_TEST_SNAPSHOT_EXTRA", "extra");
    try std.testing.expectEqualStrings("after", OsEnv.get(key).?);
    try snap.restore();
    try std.testing.expectEqualStrings("before", OsEnv.get(key).?);
    try std.testing.expect(OsEnv.get("ENV_ZIG_TEST_SNAPSHOT_EXTRA") == null);
    try OsEnv.unset(key);
}

test "OsEnv getAllAlloc" {
    const key = "ENV_ZIG_TEST_GETALL";
    try OsEnv.set(key, "val123");
    var map = try OsEnv.getAllAlloc(std.testing.allocator);
    defer {
        var it = map.iterator();
        while (it.next()) |e| {
            std.testing.allocator.free(e.key_ptr.*);
            std.testing.allocator.free(e.value_ptr.*);
        }
        map.deinit();
    }
    try std.testing.expect(map.contains(key));
    try std.testing.expectEqualStrings("val123", map.get(key).?);
    try OsEnv.unset(key);
}
