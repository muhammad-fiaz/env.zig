const std = @import("std");
const builtin = @import("builtin");
const native_os = builtin.os.tag;

const unicode = std.unicode;
const windows = std.os.windows;

// ---------------------------------------------------------------------------
// C / Windows bindings
// ---------------------------------------------------------------------------
extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn unsetenv(name: [*:0]const u8) c_int;

extern "kernel32" fn GetEnvironmentVariableW(lpName: [*:0]const u16, lpBuffer: ?[*]u16, nSize: u32) callconv(.winapi) u32;
extern "kernel32" fn SetEnvironmentVariableW(lpName: [*:0]const u16, lpValue: ?[*:0]const u16) callconv(.winapi) c_int;
extern "kernel32" fn GetEnvironmentStringsW() callconv(.winapi) ?[*:0]u16;
extern "kernel32" fn FreeEnvironmentStringsW(penv: [*:0]u16) callconv(.winapi) c_int;
extern "kernel32" fn SetLastError(dwErrCode: u32) callconv(.winapi) void;

/// Cross-platform OS environment access.
/// Wraps POSIX `getenv`/`setenv`/`unsetenv` and Windows
/// `GetEnvironmentVariableW`/`SetEnvironmentVariableW`.
/// All functions work on Linux, macOS and Windows.
pub const OsEnv = struct {
    /// Get an OS environment variable. Returns null if not set.
    /// The returned slice is owned by the OS; to keep it, dupe it.
    /// On Windows the lookup is case-insensitive; on POSIX it is case-sensitive.
    pub fn get(key: []const u8) ?[]const u8 {
        if (key.len == 0) return null;
        if (native_os == .windows) {
            return getWindows(key);
        } else {
            return getPosix(key);
        }
    }

    /// Get an OS env var and duplicate it with `allocator`.
    /// Caller owns returned memory. Returns null if missing.
    pub fn getAlloc(allocator: std.mem.Allocator, key: []const u8) !?[]u8 {
        const val = get(key) orelse return null;
        return try allocator.dupe(u8, val);
    }

    /// Get OS env var with fallback default.
    pub fn getOrDefault(key: []const u8, default_value: []const u8) []const u8 {
        return get(key) orelse default_value;
    }

    pub fn exists(key: []const u8) bool {
        return get(key) != null;
    }

    pub fn isEmpty(key: []const u8) bool {
        const v = get(key) orelse return true;
        return v.len == 0;
    }

    /// Set an OS environment variable. Overwrites if existing.
    /// Works on all platforms.
    pub fn set(key: []const u8, value: []const u8) !void {
        try validateKey(key);
        if (native_os == .windows) {
            try setWindows(key, value);
        } else {
            try setPosix(key, value);
        }
    }

    /// Unset / remove an OS environment variable.
    pub fn unset(key: []const u8) !void {
        try validateKey(key);
        if (native_os == .windows) {
            try unsetWindows(key);
        } else {
            try unsetPosix(key);
        }
    }

    /// Return all OS environment variables as an `std.process.Environ.Map`.
    /// Caller must call `map.deinit()`.
    pub fn getMap(allocator: std.mem.Allocator) !std.process.Environ.Map {
        if (native_os == .windows) {
            const env = std.process.Environ{ .block = .{ .use_global = true } };
            return try std.process.Environ.createMap(env, allocator);
        } else {
            const env = std.process.Environ{ .block = .{ .slice = std.c.environ[0..envCount() :null] } };
            return try std.process.Environ.createMap(env, allocator);
        }
    }

    /// Load all OS env vars into a `std.StringHashMap`.
    /// Caller owns keys and values and must free them.
    pub fn getAllAlloc(allocator: std.mem.Allocator) !std.StringHashMap([]const u8) {
        var out = std.StringHashMap([]const u8).init(allocator);
        errdefer {
            var it = out.iterator();
            while (it.next()) |e| {
                allocator.free(e.key_ptr.*);
                allocator.free(e.value_ptr.*);
            }
            out.deinit();
        }
        if (native_os == .windows) {
            const block = GetEnvironmentStringsW() orelse return out;
            defer _ = FreeEnvironmentStringsW(block);
            var ptr: usize = 0;
            while (block[ptr] != 0) {
                const start = ptr;
                while (block[ptr] != 0) : (ptr += 1) {}
                const entry_len = ptr - start;
                const entry_w = block[start .. start + entry_len];
                // Split at first '=' (skip leading '=' for drive vars)
                var eq: ?usize = null;
                const search_start: usize = if (entry_w.len > 0 and entry_w[0] == '=') 1 else 0;
                for (entry_w[search_start..], search_start..) |ch, idx| {
                    if (ch == '=') {
                        eq = idx;
                        break;
                    }
                }
                if (eq) |eq_idx| {
                    const key_w = entry_w[0..eq_idx];
                    const val_w = entry_w[eq_idx + 1 ..];
                    const key = try unicode.wtf16LeToWtf8Alloc(allocator, key_w);
                    errdefer allocator.free(key);
                    const val = try unicode.wtf16LeToWtf8Alloc(allocator, val_w);
                    errdefer allocator.free(val);
                    try out.put(key, val);
                }
                ptr += 1;
            }
        } else {
            var i: usize = 0;
            while (std.c.environ[i]) |entry| : (i += 1) {
                const span = std.mem.span(entry);
                const eq = std.mem.indexOfScalar(u8, span, '=') orelse continue;
                const key = span[0..eq];
                const val = span[eq + 1 ..];
                const k = try allocator.dupe(u8, key);
                errdefer allocator.free(k);
                const v = try allocator.dupe(u8, val);
                errdefer allocator.free(v);
                try out.put(k, v);
            }
        }
        return out;
    }

    /// Snapshot the current process environment.
    pub fn snapshot(allocator: std.mem.Allocator) !Snapshot {
        const map = try getAllAlloc(allocator);
        return .{ .map = map, .allocator = allocator };
    }

    /// Validate env key (common rules).
    fn validateKey(key: []const u8) !void {
        if (key.len == 0) return error.InvalidKey;
        if (std.mem.indexOfScalar(u8, key, '=') != null) return error.InvalidKey;
        if (std.mem.indexOfScalar(u8, key, 0) != null) return error.InvalidKey;
    }

    // ---- POSIX helpers — stack-first for efficiency (no alloc for typical keys) ----
    fn getPosix(key: []const u8) ?[]const u8 {
        // Fast stack path for keys < 512
        var stack_buf: [512]u8 = undefined;
        const key_z: [:0]const u8 = if (key.len < stack_buf.len) blk: {
            @memcpy(stack_buf[0..key.len], key);
            stack_buf[key.len] = 0;
            break :blk stack_buf[0..key.len :0];
        } else blk: {
            const alloc = std.heap.page_allocator;
            const dup = alloc.dupeZ(u8, key) catch return null;
            // leak is avoided by using page_allocator and freeing after call via defer
            // but for this branch we need to free after getenv; use errdefer not possible.
            // Simplify: use page_allocator and free after
            break :blk dup;
        };
        // For stack path, no alloc to free; for heap path, free.
        const needs_free = key.len >= 512;
        defer if (needs_free) std.heap.page_allocator.free(key_z);
        const c_val = std.c.getenv(key_z) orelse return null;
        return std.mem.span(c_val);
    }

    fn setPosix(key: []const u8, value: []const u8) !void {
        if (std.mem.indexOfScalar(u8, value, 0) != null) return error.InvalidValue;
        // Stack for both key and value if small
        var key_stack: [512]u8 = undefined;
        var val_stack: [1024]u8 = undefined;
        const use_key_stack = key.len < key_stack.len;
        const use_val_stack = value.len < val_stack.len;
        const key_z: [:0]const u8 = if (use_key_stack) blk: {
            @memcpy(key_stack[0..key.len], key);
            key_stack[key.len] = 0;
            break :blk key_stack[0..key.len :0];
        } else try std.heap.page_allocator.dupeZ(u8, key);
        defer if (!use_key_stack) std.heap.page_allocator.free(key_z);
        const val_z: [:0]const u8 = if (use_val_stack) blk: {
            @memcpy(val_stack[0..value.len], value);
            val_stack[value.len] = 0;
            break :blk val_stack[0..value.len :0];
        } else try std.heap.page_allocator.dupeZ(u8, value);
        defer if (!use_val_stack) std.heap.page_allocator.free(val_z);
        const ret = setenv(key_z, val_z, 1);
        if (ret != 0) return error.SetEnvFailed;
    }

    fn unsetPosix(key: []const u8) !void {
        var stack_buf: [512]u8 = undefined;
        const use_stack = key.len < stack_buf.len;
        const key_z: [:0]const u8 = if (use_stack) blk: {
            @memcpy(stack_buf[0..key.len], key);
            stack_buf[key.len] = 0;
            break :blk stack_buf[0..key.len :0];
        } else try std.heap.page_allocator.dupeZ(u8, key);
        defer if (!use_stack) std.heap.page_allocator.free(key_z);
        const ret = unsetenv(key_z);
        if (ret != 0) return error.UnsetEnvFailed;
    }

    // ---- Windows helpers ----
    threadlocal var tls_buf: [8192]u8 = undefined;
    threadlocal var tls_len: usize = 0;

    fn getWindows(key: []const u8) ?[]const u8 {
        const alloc = std.heap.page_allocator;
        const key_w = unicode.wtf8ToWtf16LeAllocZ(alloc, key) catch return null;
        defer alloc.free(key_w);
        SetLastError(0);
        const needed = GetEnvironmentVariableW(key_w.ptr, null, 0);
        if (needed == 0) {
            const err_code = @intFromEnum(windows.GetLastError());
            if (err_code == 203) return null; // ERROR_ENVVAR_NOT_FOUND
            // exists but empty
            return "";
        }
        // needed includes space for NUL? docs: if buffer too small, return required size including NUL.
        // When we call with null, needed is size required including NUL.
        // For actual data we need buffer of needed
        var buf: [4096]u16 = undefined;
        if (needed <= buf.len) {
            SetLastError(0);
            const got = GetEnvironmentVariableW(key_w.ptr, &buf, @intCast(buf.len));
            if (got == 0) {
                const e2 = @intFromEnum(windows.GetLastError());
                if (e2 == 203) return null;
                return "";
            }
            return tlsConvertWtf16ToWtf8(buf[0..got]);
        } else {
            const heap_buf = alloc.alloc(u16, needed) catch return null;
            defer alloc.free(heap_buf);
            SetLastError(0);
            const got = GetEnvironmentVariableW(key_w.ptr, heap_buf.ptr, @intCast(heap_buf.len));
            if (got == 0) {
                const e2 = @intFromEnum(windows.GetLastError());
                if (e2 == 203) return null;
                return "";
            }
            return tlsConvertWtf16ToWtf8(heap_buf[0..got]);
        }
    }

    fn tlsConvertWtf16ToWtf8(w: []const u16) ?[]const u8 {
        const alloc = std.heap.page_allocator;
        const tmp = unicode.wtf16LeToWtf8Alloc(alloc, w) catch return null;
        defer alloc.free(tmp);
        if (tmp.len > tls_buf.len) return null;
        @memcpy(tls_buf[0..tmp.len], tmp);
        tls_len = tmp.len;
        return tls_buf[0..tls_len];
    }

    fn setWindows(key: []const u8, value: []const u8) !void {
        const alloc = std.heap.page_allocator;
        const key_w = try unicode.wtf8ToWtf16LeAllocZ(alloc, key);
        defer alloc.free(key_w);
        const val_w = try unicode.wtf8ToWtf16LeAllocZ(alloc, value);
        defer alloc.free(val_w);
        const ret = SetEnvironmentVariableW(key_w.ptr, val_w.ptr);
        if (ret == 0) return error.SetEnvFailed;
    }

    fn unsetWindows(key: []const u8) !void {
        const alloc = std.heap.page_allocator;
        const key_w = try unicode.wtf8ToWtf16LeAllocZ(alloc, key);
        defer alloc.free(key_w);
        const ret = SetEnvironmentVariableW(key_w.ptr, null);
        if (ret == 0) return error.UnsetEnvFailed;
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
    /// Removes keys not in snapshot, restores/sets keys in snapshot.
    pub fn restore(self: *const Snapshot) !void {
        // Collect current keys
        var cur = try OsEnv.getAllAlloc(self.allocator);
        defer {
            var it = cur.iterator();
            while (it.next()) |e| {
                self.allocator.free(e.key_ptr.*);
                self.allocator.free(e.value_ptr.*);
            }
            cur.deinit();
        }
        // Remove keys that were added after snapshot
        var cur_it = cur.iterator();
        while (cur_it.next()) |e| {
            if (!self.map.contains(e.key_ptr.*)) {
                try OsEnv.unset(e.key_ptr.*);
            }
        }
        // Set/restore snapshot keys
        var snap_it = self.map.iterator();
        while (snap_it.next()) |e| {
            // Only set if different or missing
            const cur_val = OsEnv.get(e.key_ptr.*);
            if (cur_val == null or !std.mem.eql(u8, cur_val.?, e.value_ptr.*)) {
                try OsEnv.set(e.key_ptr.*, e.value_ptr.*);
            }
        }
    }
};

/// Temporary environment scope.
/// Saves original values for keys it touches and restores on `deinit`.
/// Works on all platforms. Thread-unsafe (process env is global).
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
        const owned_key = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(owned_key);
        const orig = OsEnv.get(key);
        const owned_val: ?[]const u8 = if (orig) |v| try self.allocator.dupe(u8, v) else null;
        errdefer if (owned_val) |v| self.allocator.free(v);
        try self.saved.put(owned_key, owned_val);
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
            const maybe_val = e.value_ptr.*;
            if (maybe_val) |v| {
                try OsEnv.set(key, v);
            } else {
                // Was not set originally -> unset
                // Unset may fail if already missing (ok)
                OsEnv.unset(key) catch {};
            }
        }
    }

    /// Temporarily run a function with given overrides.
    /// Example: `try Scope.with(allocator, &.{ .{ .key="FOO", .value="bar" } }, myFunc);`
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
    // Ensure clean
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
    // Empty string should be considered exists (POSIX) – on Windows we preserve empty via GetEnvironmentStringsW
    try std.testing.expect(g != null);
    try std.testing.expect(g.?.len == 0);
    try std.testing.expect(OsEnv.exists(key));
    try std.testing.expect(OsEnv.isEmpty(key));
    try OsEnv.unset(key);
}

test "OsEnv getAlloc" {
    const key = "ENV_ZIG_TEST_OS_ENV_ALLOC";
    OsEnv.unset(key) catch {};
    try OsEnv.set(key, "alloc_val");
    const v = try OsEnv.getAlloc(std.testing.allocator, key);
    defer if (v) |s| std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("alloc_val", v.?);
    const missing = try OsEnv.getAlloc(std.testing.allocator, "ENV_ZIG_TEST_MISSING_12345");
    try std.testing.expect(missing == null);
    try OsEnv.unset(key);
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
