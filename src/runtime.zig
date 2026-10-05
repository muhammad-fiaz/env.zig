const std = @import("std");
const builtin = @import("builtin");
const typed = @import("internal/typed.zig");

const nativeOs = builtin.os.tag;
const unicode = std.unicode;
const windows = std.os.windows;

// Platform boundary: this is the only module that branches on
// `builtin.os.tag` for environment state. Reads reuse
// `std.process.Environ`; only `set`/`unset` need custom bindings
// because Zig 0.17.0 exposes no mutation API.
extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn unsetenv(name: [*:0]const u8) c_int;

extern "kernel32" fn GetEnvironmentVariableW(lpName: [*:0]const u16, lpBuffer: ?[*]u16, nSize: u32) callconv(.winapi) u32;
extern "kernel32" fn SetEnvironmentVariableW(lpName: [*:0]const u16, lpValue: ?[*:0]const u16) callconv(.winapi) c_int;
extern "kernel32" fn SetLastError(dwErrCode: u32) callconv(.winapi) void;

/// Explicit runtime/process-environment namespace.
///
/// `Env` is an in-memory `.env` store; `runtime` is the actual process
/// environment. All mutation here affects the current process, is
/// process-global and thread-unsafe by OS design.
///
/// Reads distinguish missing (`null`) from present-with-empty (`""`).
/// On Windows names are case-insensitive; on POSIX case-sensitive.
pub fn get(key: []const u8) ?[]const u8 {
    if (!std.process.Environ.Map.validateKeyForPut(key)) return null;
    if (nativeOs == .windows) return platformGetWindows(key);
    return platformGetPosix(key);
}

/// Owned copy. Caller must free with `allocator.free`. Null when missing.
pub fn getAlloc(allocator: std.mem.Allocator, key: []const u8) !?[]u8 {
    const val = get(key) orelse return null;
    return try allocator.dupe(u8, val);
}

/// Borrowed lookup with default when missing.
pub fn getOrDefault(key: []const u8, defaultValue: []const u8) []const u8 {
    return get(key) orelse defaultValue;
}

/// True when present, even with an empty value.
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

/// Set a runtime variable, overwriting when present. Affects the current
/// process (not an in-memory map). Rejects invalid keys/values.
pub fn set(key: []const u8, value: []const u8) !void {
    try setImpl(key, value);
}

/// Unset a runtime variable. No-op when missing.
pub fn unset(key: []const u8) !void {
    try unsetImpl(key);
}

fn setImpl(key: []const u8, value: []const u8) !void {
    try validateKey(key);
    if (std.mem.indexOfScalar(u8, value, 0) != null) return error.InvalidValue;
    if (nativeOs == .windows) try platformSetWindows(key, value) else try platformSetPosix(key, value);
}

fn unsetImpl(key: []const u8) !void {
    try validateKey(key);
    if (nativeOs == .windows) try platformUnsetWindows(key) else try platformUnsetPosix(key);
}

/// Complete current environment as `std.process.Environ.Map`.
/// Caller must call `map.deinit()`.
pub fn getMap(allocator: std.mem.Allocator) !std.process.Environ.Map {
    if (nativeOs == .windows) {
        return try std.process.Environ.createMap(.{ .block = .{ .use_global = true } }, allocator);
    }
    return try std.process.Environ.createMap(.{ .block = .{ .slice = std.c.environ[0..platformEnvCount() :null] } }, allocator);
}

/// Complete current environment as `StringHashMap`. Caller owns keys
/// and values. Single enumeration implementation: reuses `getMap`.
pub fn getAll(allocator: std.mem.Allocator) !std.StringHashMap([]const u8) {
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
    return Snapshot.capture(allocator);
}

/// Begin a temporary scope. Mutations via the scope are restored on
/// `deinit`. Nested scopes work LIFO.
pub fn scope(allocator: std.mem.Allocator) !Scope {
    return Scope.init(allocator);
}

/// Single source of truth for runtime key validation. Reuses
/// `std.process.Environ.Map.validateKeyForPut`: non-empty, no `=`,
/// no NUL (and valid WTF-8 on Windows).
pub fn validateKey(key: []const u8) !void {
    if (!std.process.Environ.Map.validateKeyForPut(key)) return error.InvalidKey;
}

// Typed getters share `internal/typed.zig` with `Env`.
pub fn getBool(key: []const u8) ?bool {
    const v = get(key) orelse return null;
    return typed.parseBoolValue(v);
}
pub fn tryGetBool(key: []const u8) !?bool {
    const v = get(key) orelse return null;
    return typed.parseBoolValue(v) orelse error.TypeMismatch;
}
pub fn getInt(comptime T: type, key: []const u8) ?T {
    const v = get(key) orelse return null;
    return typed.parseIntValue(T, v);
}
pub fn tryGetInt(comptime T: type, key: []const u8) !?T {
    const v = get(key) orelse return null;
    return typed.parseIntValue(T, v) orelse error.TypeMismatch;
}
pub fn getFloat(comptime T: type, key: []const u8) ?T {
    const v = get(key) orelse return null;
    return typed.parseFloatValue(T, v);
}
pub fn tryGetFloat(comptime T: type, key: []const u8) !?T {
    const v = get(key) orelse return null;
    return typed.parseFloatValue(T, v) orelse error.TypeMismatch;
}
pub fn getEnum(comptime E: type, key: []const u8) ?E {
    const v = get(key) orelse return null;
    return typed.parseEnumValue(E, v);
}
pub fn tryGetEnum(comptime E: type, key: []const u8) !?E {
    const v = get(key) orelse return null;
    return typed.parseEnumValue(E, v) orelse error.TypeMismatch;
}
pub fn getValue(comptime T: type, key: []const u8) ?T {
    return switch (@typeInfo(T)) {
        .bool => if (getBool(key)) |b| @as(T, b) else null,
        .int => getInt(T, key),
        .float => getFloat(T, key),
        .@"enum" => getEnum(T, key),
        .pointer => |ptr| blk: {
            if (ptr.size != .slice or ptr.child != u8) @compileError("runtime.getValue only supports []const u8, bool, ints, floats, enums");
            break :blk if (get(key)) |s| @as(T, s) else null;
        },
        else => @compileError("runtime.getValue: unsupported type"),
    };
}
pub fn tryGetValue(comptime T: type, key: []const u8) !?T {
    return switch (@typeInfo(T)) {
        .bool => try tryGetBool(key),
        .int => try tryGetInt(T, key),
        .float => try tryGetFloat(T, key),
        .@"enum" => try tryGetEnum(T, key),
        .pointer => get(key),
        else => @compileError("runtime.tryGetValue: unsupported type"),
    };
}

/// Snapshot of the process environment. Single restore implementation
/// also backing `Scope`.
pub const Snapshot = struct {
    map: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,

    fn capture(allocator: std.mem.Allocator) !Snapshot {
        return .{ .map = try getAll(allocator), .allocator = allocator };
    }

    pub fn deinit(self: *Snapshot) void {
        var it = self.map.iterator();
        while (it.next()) |e| {
            self.allocator.free(e.key_ptr.*);
            self.allocator.free(e.value_ptr.*);
        }
        self.map.deinit();
    }

    /// Restore: remove variables absent from the snapshot, restore
    /// present (including empty) values. Does not leak; leaves no stale keys.
    pub fn restore(self: *const Snapshot) !void {
        var cur = try getAll(self.allocator);
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
            if (!self.map.contains(e.key_ptr.*)) try unsetImpl(e.key_ptr.*);
        }
        var snapIt = self.map.iterator();
        while (snapIt.next()) |e| {
            const curVal = get(e.key_ptr.*);
            if (curVal == null or !std.mem.eql(u8, curVal.?, e.value_ptr.*)) {
                try setImpl(e.key_ptr.*, e.value_ptr.*);
            }
        }
    }
};

/// Temporary runtime scope built on `Snapshot`. Captures the full
/// environment on init and restores it on `deinit`, so nesting works LIFO.
pub const Scope = struct {
    snapshot_state: Snapshot,
    active: bool,

    pub fn init(allocator: std.mem.Allocator) !Scope {
        return .{ .snapshot_state = try Snapshot.capture(allocator), .active = true };
    }

    pub fn deinit(self: *Scope) void {
        if (!self.active) return;
        self.snapshot_state.restore() catch {};
        self.snapshot_state.deinit();
        self.active = false;
    }

    pub fn set(_: *Scope, key: []const u8, value: []const u8) !void {
        try setImpl(key, value);
    }

    pub fn unset(_: *Scope, key: []const u8) !void {
        try unsetImpl(key);
    }

    /// Restore without deiniting (scope remains usable).
    pub fn restore(self: *Scope) !void {
        try self.snapshot_state.restore();
    }

    pub fn with(allocator: std.mem.Allocator, overrides: []const struct { key: []const u8, value: ?[]const u8 }, func: *const fn () anyerror!void) !void {
        var s = try Scope.init(allocator);
        defer s.deinit();
        for (overrides) |ov| {
            if (ov.value) |v| try s.set(ov.key, v) else try s.unset(ov.key);
        }
        try func();
    }
};

// Platform boundary (private).
fn platformGetPosix(key: []const u8) ?[]const u8 {
    const alloc = std.heap.page_allocator;
    const keyZ = alloc.dupeSentinel(u8, key, 0) catch return null;
    defer alloc.free(keyZ);
    const cVal = std.c.getenv(keyZ) orelse return null;
    return std.mem.span(cVal);
}
fn platformSetPosix(key: []const u8, value: []const u8) !void {
    const alloc = std.heap.page_allocator;
    const keyZ = try alloc.dupeSentinel(u8, key, 0);
    defer alloc.free(keyZ);
    const valZ = try alloc.dupeSentinel(u8, value, 0);
    defer alloc.free(valZ);
    if (setenv(keyZ, valZ, 1) != 0) return error.IoError;
}
fn platformUnsetPosix(key: []const u8) !void {
    const alloc = std.heap.page_allocator;
    const keyZ = try alloc.dupeSentinel(u8, key, 0);
    defer alloc.free(keyZ);
    if (unsetenv(keyZ) != 0) return error.IoError;
}
threadlocal var tlsOwned: ?[]u8 = null;
fn platformGetWindows(key: []const u8) ?[]const u8 {
    const alloc = std.heap.page_allocator;
    const keyW = unicode.wtf8ToWtf16LeAllocZ(alloc, key) catch return null;
    defer alloc.free(keyW);
    SetLastError(0);
    const needed = GetEnvironmentVariableW(keyW.ptr, null, 0);
    if (needed == 0) {
        if (@backingInt(windows.GetLastError()) == 203) return null;
        return "";
    }
    var stack: [1024]u16 = undefined;
    if (needed <= stack.len) {
        SetLastError(0);
        const got = GetEnvironmentVariableW(keyW.ptr, &stack, @intCast(stack.len));
        if (got == 0) {
            if (@backingInt(windows.GetLastError()) == 203) return null;
            return "";
        }
        return tlsConvert(stack[0..got]);
    }
    const heapBuf = alloc.alloc(u16, needed) catch return null;
    defer alloc.free(heapBuf);
    SetLastError(0);
    const got = GetEnvironmentVariableW(keyW.ptr, heapBuf.ptr, @intCast(heapBuf.len));
    if (got == 0) {
        if (@backingInt(windows.GetLastError()) == 203) return null;
        return "";
    }
    return tlsConvert(heapBuf[0..got]);
}
fn tlsConvert(w: []const u16) ?[]const u8 {
    const alloc = std.heap.page_allocator;
    const tmp = unicode.wtf16LeToWtf8Alloc(alloc, w) catch return null;
    defer alloc.free(tmp);
    if (tlsOwned) |old| alloc.free(old);
    const owned = alloc.dupe(u8, tmp) catch return null;
    tlsOwned = owned;
    return owned;
}
fn platformSetWindows(key: []const u8, value: []const u8) !void {
    const alloc = std.heap.page_allocator;
    const keyW = unicode.wtf8ToWtf16LeAllocZ(alloc, key) catch return error.InvalidValue;
    defer alloc.free(keyW);
    const valW = unicode.wtf8ToWtf16LeAllocZ(alloc, value) catch return error.InvalidValue;
    defer alloc.free(valW);
    if (SetEnvironmentVariableW(keyW.ptr, valW.ptr) == 0) return error.IoError;
}
fn platformUnsetWindows(key: []const u8) !void {
    const alloc = std.heap.page_allocator;
    const keyW = unicode.wtf8ToWtf16LeAllocZ(alloc, key) catch return error.InvalidValue;
    defer alloc.free(keyW);
    if (SetEnvironmentVariableW(keyW.ptr, null) == 0) return error.IoError;
}
fn platformEnvCount() usize {
    var n: usize = 0;
    while (std.c.environ[n] != null) : (n += 1) {}
    return n;
}

test "runtime set/get/unset" {
    const key = "ENV_ZIG_TEST_RT_BASIC";
    unset(key) catch {};
    try std.testing.expect(get(key) == null);
    try set(key, "hello");
    try std.testing.expectEqualStrings("hello", get(key).?);
    try set(key, "world");
    try std.testing.expectEqualStrings("world", get(key).?);
    try unset(key);
    try std.testing.expect(get(key) == null);
}
test "runtime exists and isEmpty" {
    const key = "ENV_ZIG_TEST_RT_EXISTS";
    unset(key) catch {};
    try std.testing.expect(!exists(key));
    try std.testing.expect(isEmpty(key));
    try set(key, "x");
    try std.testing.expect(exists(key));
    try std.testing.expect(!isEmpty(key));
    try set(key, "");
    try std.testing.expect(get(key) != null);
    try std.testing.expect(get(key).?.len == 0);
    try std.testing.expect(exists(key));
    try std.testing.expect(isEmpty(key));
    try unset(key);
}
test "runtime rejects invalid keys and NUL" {
    try std.testing.expectError(error.InvalidKey, set("", "v"));
    try std.testing.expectError(error.InvalidKey, set("A=B", "v"));
    try std.testing.expectError(error.InvalidValue, set("ENV_ZIG_TEST_RT_NUL", "a\x00b"));
    unset("ENV_ZIG_TEST_RT_NUL") catch {};
}
test "runtime scope restores including nesting" {
    const key = "ENV_ZIG_TEST_RT_SCOPE";
    unset(key) catch {};
    try set(key, "production");
    {
        var outer = try scope(std.testing.allocator);
        defer outer.deinit();
        try outer.set(key, "test");
        try std.testing.expectEqualStrings("test", get(key).?);
        {
            var inner = try scope(std.testing.allocator);
            defer inner.deinit();
            try inner.set(key, "nested");
            try std.testing.expectEqualStrings("nested", get(key).?);
        }
        try std.testing.expectEqualStrings("test", get(key).?);
    }
    try std.testing.expectEqualStrings("production", get(key).?);
    try unset(key);
}
test "runtime snapshot restore" {
    const key = "ENV_ZIG_TEST_RT_SNAP";
    unset(key) catch {};
    try set(key, "before");
    var snap = try snapshot(std.testing.allocator);
    defer snap.deinit();
    try set(key, "after");
    try set("ENV_ZIG_TEST_RT_SNAP_EXTRA", "extra");
    try snap.restore();
    try std.testing.expectEqualStrings("before", get(key).?);
    try std.testing.expect(get("ENV_ZIG_TEST_RT_SNAP_EXTRA") == null);
    try unset(key);
}
test "runtime long and unicode" {
    const key = "ENV_ZIG_TEST_RT_LONG";
    const long = try std.testing.allocator.alloc(u8, 16384);
    defer std.testing.allocator.free(long);
    @memset(long, 'x');
    try set(key, long);
    try std.testing.expectEqualStrings(long, get(key).?);
    try unset(key);
    try set("ENV_ZIG_TEST_RT_UNI", "héllo 🚀");
    try std.testing.expectEqualStrings("héllo 🚀", get("ENV_ZIG_TEST_RT_UNI").?);
    try unset("ENV_ZIG_TEST_RT_UNI");
}
test "runtime typed getters share conversion" {
    try set("ENV_ZIG_TEST_RT_INT", "8080");
    defer unset("ENV_ZIG_TEST_RT_INT") catch {};
    try std.testing.expectEqual(@as(u16, 8080), getInt(u16, "ENV_ZIG_TEST_RT_INT").?);
    try std.testing.expect(getInt(u16, "ENV_ZIG_TEST_RT_MISSING") == null);
    try set("ENV_ZIG_TEST_RT_BAD", "abc");
    defer unset("ENV_ZIG_TEST_RT_BAD") catch {};
    try std.testing.expect(getInt(u16, "ENV_ZIG_TEST_RT_BAD") == null);
    try std.testing.expectError(error.TypeMismatch, tryGetInt(u16, "ENV_ZIG_TEST_RT_BAD"));
}
