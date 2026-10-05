const std = @import("std");
const parserMod = @import("parser.zig");
const configMod = @import("config.zig");
const interpolationMod = @import("interpolation.zig");
const serializerMod = @import("serializer.zig");
const writerMod = @import("writer.zig");
const validatorMod = @import("validator.zig");
const schemaMod = @import("schema.zig");
const runtimeMod = @import("runtime.zig");
const helpers = @import("internal/helpers.zig");
const typed = @import("internal/typed.zig");

pub const Config = configMod.Config;
pub const ValidationError = validatorMod.ValidationError;
pub const schema = schemaMod;
pub const validator = validatorMod;
/// Single explicit process-environment namespace.
pub const runtime = runtimeMod;
pub const Cache = @import("cache.zig").Cache;

/// In-memory `.env` store (insertion-ordered, owning).
/// Never touches the process environment except via explicit
/// `*Runtime` / `*AndExport` APIs or `config.exportToRuntime`.
/// Not internally synchronized; runtime mutation is process-global.
pub const Env = struct {
    allocator: std.mem.Allocator,
    entries: std.StringHashMap([]const u8),
    insertionOrder: std.ArrayList([]const u8),
    config: Config,

    pub fn init(allocator: std.mem.Allocator, cfg: Config) Env {
        return .{
            .allocator = allocator,
            .entries = std.StringHashMap([]const u8).init(allocator),
            .insertionOrder = .empty,
            .config = cfg,
        };
    }

    pub fn deinit(self: *Env) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| self.allocator.free(entry.value_ptr.*);
        self.entries.deinit();
        for (self.insertionOrder.items) |key| self.allocator.free(key);
        self.insertionOrder.deinit(self.allocator);
    }

    /// Load and parse a `.env` file. Transactional on parse failure in
    /// strict mode: the existing store is unchanged when parsing fails.
    pub fn load(self: *Env, path: []const u8) !void {
        try self.config.validate();
        const content = try readContent(self.allocator, path);
        defer self.allocator.free(content);
        try self.parseString(content);
    }

    /// Shared file-read + error-map used by `load` and `reload`.
    fn readContent(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
        const dir = std.Io.Dir.cwd();
        var ioThreaded: std.Io.Threaded = .init_single_threaded;
        return dir.readFileAlloc(ioThreaded.io(), path, allocator, .unlimited) catch |err| switch (err) {
            error.FileNotFound => return error.FileNotFound,
            error.AccessDenied => return error.PermissionDenied,
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.IoError,
        };
    }

    /// Parse a string transactionally: strict errors leave `self` unchanged.
    pub fn parseString(self: *Env, source: []const u8) !void {
        try self.config.validate();
        var result = try parserMod.parse(self.allocator, source, .{ .config = self.config });
        defer result.deinit(self.allocator);
        // Commit phase: only reached when parsing succeeded.
        for (result.entries.items) |entry| {
            if (self.config.override or !self.entries.contains(entry.key)) {
                try self.putCommitted(entry.key, entry.value);
            }
        }
        if (self.config.interpolate) try self.resolveInterpolation();
    }

    fn putCommitted(self: *Env, key: []const u8, value: []const u8) !void {
        const existing = self.entries.fetchRemove(key);
        if (existing) |kv| {
            self.allocator.free(kv.value);
            const ownedValue = try self.allocator.dupe(u8, value);
            try self.entries.put(kv.key, ownedValue);
        } else {
            const ownedKey = try self.allocator.dupe(u8, key);
            errdefer self.allocator.free(ownedKey);
            const ownedValue = try self.allocator.dupe(u8, value);
            errdefer self.allocator.free(ownedValue);
            try self.entries.put(ownedKey, ownedValue);
            try self.insertionOrder.append(self.allocator, ownedKey);
        }
    }

    /// Load multiple files in order. Later files win when `override`.
    /// Only missing-file errors are skippable (non-strict); other I/O
    /// errors propagate without partial application beyond prior files.
    pub fn loadMany(self: *Env, paths: []const []const u8) !void {
        for (paths) |path| {
            self.load(path) catch |err| switch (err) {
                error.FileNotFound => {
                    if (self.config.strict) return err;
                    continue;
                },
                else => return err,
            };
        }
    }

    /// Transactional reload: on failure the old state is preserved.
    pub fn reload(self: *Env, path: []const u8) !void {
        try self.config.validate();
        const content = try readContent(self.allocator, path);
        defer self.allocator.free(content);
        var result = try parserMod.parse(self.allocator, content, .{ .config = self.config });
        defer result.deinit(self.allocator);
        // Only clear after successful parse.
        self.clear();
        errdefer self.clear();
        for (result.entries.items) |entry| {
            if (self.config.override or !self.entries.contains(entry.key)) {
                try self.putCommitted(entry.key, entry.value);
            }
        }
        if (self.config.interpolate) try self.resolveInterpolation();
    }

    /// In-memory only. Validates `.env` key shape, rejects NUL values.
    /// Exports only when `config.exportToRuntime` (same `runtime.set` impl).
    pub fn set(self: *Env, key: []const u8, value: []const u8) !void {
        if (!helpers.isValidKey(key)) return error.InvalidKey;
        if (std.mem.indexOfScalar(u8, value, 0) != null) return error.InvalidValue;
        try self.putCommitted(key, value);
        if (self.config.exportToRuntime) try runtimeMod.set(key, value);
    }

    /// Explicit in-memory + runtime mutation (regardless of config).
    pub fn setAndExport(self: *Env, key: []const u8, value: []const u8) !void {
        try self.set(key, value);
        try runtimeMod.set(key, value);
    }

    pub fn get(self: *const Env, key: []const u8) ?[]const u8 {
        return self.entries.get(key);
    }
    pub fn getString(self: *const Env, key: []const u8) ?[]const u8 {
        return self.get(key);
    }
    pub fn getAlloc(self: *const Env, allocator: std.mem.Allocator, key: []const u8) !?[]u8 {
        const v = self.get(key) orelse return null;
        return try allocator.dupe(u8, v);
    }
    /// Defaults apply to missing only, never to invalid values.
    pub fn getOrDefault(self: *const Env, key: []const u8, defaultValue: []const u8) []const u8 {
        return self.get(key) orelse defaultValue;
    }
    pub fn contains(self: *const Env, key: []const u8) bool {
        return self.entries.contains(key);
    }
    pub fn isEmpty(self: *const Env, key: []const u8) bool {
        const v = self.get(key) orelse return true;
        return v.len == 0;
    }
    pub fn require(self: *const Env, key: []const u8) ![]const u8 {
        return self.get(key) orelse error.MissingRequired;
    }

    pub fn getBool(self: *const Env, key: []const u8) ?bool {
        const v = self.get(key) orelse return null;
        return typed.parseBoolValue(v);
    }
    pub fn tryGetBool(self: *const Env, key: []const u8) !?bool {
        const v = self.get(key) orelse return null;
        return typed.parseBoolValue(v) orelse error.TypeMismatch;
    }
    pub fn getInt(self: *const Env, comptime T: type, key: []const u8) ?T {
        const v = self.get(key) orelse return null;
        return typed.parseIntValue(T, v);
    }
    pub fn tryGetInt(self: *const Env, comptime T: type, key: []const u8) !?T {
        const v = self.get(key) orelse return null;
        return typed.parseIntValue(T, v) orelse error.TypeMismatch;
    }
    pub fn getFloat(self: *const Env, comptime T: type, key: []const u8) ?T {
        const v = self.get(key) orelse return null;
        return typed.parseFloatValue(T, v);
    }
    pub fn tryGetFloat(self: *const Env, comptime T: type, key: []const u8) !?T {
        const v = self.get(key) orelse return null;
        return typed.parseFloatValue(T, v) orelse error.TypeMismatch;
    }
    pub fn getEnum(self: *const Env, comptime E: type, key: []const u8) ?E {
        const v = self.get(key) orelse return null;
        return typed.parseEnumValue(E, v);
    }
    pub fn tryGetEnum(self: *const Env, comptime E: type, key: []const u8) !?E {
        const v = self.get(key) orelse return null;
        return typed.parseEnumValue(E, v) orelse error.TypeMismatch;
    }
    pub fn getValue(self: *const Env, comptime T: type, key: []const u8) ?T {
        return switch (@typeInfo(T)) {
            .bool => if (self.getBool(key)) |b| @as(T, b) else null,
            .int => self.getInt(T, key),
            .float => self.getFloat(T, key),
            .@"enum" => self.getEnum(T, key),
            .pointer => |ptr| blk: {
                if (ptr.size != .slice or ptr.child != u8) @compileError("getValue supports []const u8, bool, ints, floats, enums");
                break :blk if (self.get(key)) |s| @as(T, s) else null;
            },
            else => @compileError("getValue: unsupported type"),
        };
    }
    pub fn tryGetValue(self: *const Env, comptime T: type, key: []const u8) !?T {
        return switch (@typeInfo(T)) {
            .bool => try self.tryGetBool(key),
            .int => try self.tryGetInt(T, key),
            .float => try self.tryGetFloat(T, key),
            .@"enum" => try self.tryGetEnum(T, key),
            .pointer => self.get(key),
            else => @compileError("tryGetValue: unsupported type"),
        };
    }
    pub fn requireValue(self: *const Env, comptime T: type, key: []const u8) !T {
        return (try self.tryGetValue(T, key)) orelse error.MissingRequired;
    }
    pub fn getValueOrDefault(self: *const Env, comptime T: type, key: []const u8, defaultValue: T) T {
        return self.getValue(T, key) orelse defaultValue;
    }

    /// Owned split: each item + outer slice owned (free items, then slice).
    /// Trims whitespace, skips empty segments, null when missing/empty.
    pub fn getList(self: *const Env, allocator: std.mem.Allocator, key: []const u8, delimiter: u8) ?[][]const u8 {
        const val = self.get(key) orelse return null;
        var result: std.ArrayList([]const u8) = .empty;
        errdefer {
            for (result.items) |item| allocator.free(item);
            result.deinit(allocator);
        }
        var it = std.mem.splitScalar(u8, val, delimiter);
        while (it.next()) |item| {
            const trimmed = std.mem.trim(u8, item, " \t\r\n");
            if (trimmed.len == 0) continue;
            const duped = allocator.dupe(u8, trimmed) catch return null;
            result.append(allocator, duped) catch {
                allocator.free(duped);
                for (result.items) |o| allocator.free(o);
                result.deinit(allocator);
                return null;
            };
        }
        if (result.items.len == 0) {
            result.deinit(allocator);
            return null;
        }
        return result.toOwnedSlice(allocator) catch null;
    }

    /// In-memory only. `!bool`; runtime failures never swallowed because
    /// no runtime mutation occurs here (unless `exportToRuntime`).
    pub fn remove(self: *Env, key: []const u8) !bool {
        if (self.entries.fetchRemove(key)) |kv| {
            self.allocator.free(kv.value);
            for (self.insertionOrder.items, 0..) |k, i| {
                if (std.mem.eql(u8, k, key)) {
                    _ = self.insertionOrder.orderedRemove(i);
                    self.allocator.free(k);
                    break;
                }
            }
            if (self.config.exportToRuntime) try runtimeMod.unset(key);
            return true;
        }
        return false;
    }

    /// Explicit in-memory + runtime removal.
    pub fn removeAndUnexport(self: *Env, key: []const u8) !bool {
        const r = try self.remove(key);
        try runtimeMod.unset(key);
        return r;
    }

    pub fn clear(self: *Env) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| self.allocator.free(entry.value_ptr.*);
        self.entries.clearRetainingCapacity();
        for (self.insertionOrder.items) |key| self.allocator.free(key);
        self.insertionOrder.clearRetainingCapacity();
    }
    pub fn count(self: *const Env) usize {
        return self.entries.count();
    }
    pub fn keys(self: *const Env) []const []const u8 {
        return self.insertionOrder.items;
    }
    /// Borrowed insertion-order iterator (no allocation).
    pub fn iterator(self: *const Env) Iterator {
        return .{ .env = self, .index = 0 };
    }

    /// Shared insertion-order entry collection used by `serialize`
    /// and `save` so both encode the exact same bytes.
    fn collectSerEntries(self: *const Env) !std.ArrayList(serializerMod.SerEntry) {
        var entries: std.ArrayList(serializerMod.SerEntry) = .empty;
        errdefer entries.deinit(self.allocator);
        for (self.insertionOrder.items) |key| {
            if (self.entries.get(key)) |val| try entries.append(self.allocator, .{ .key = key, .value = val });
        }
        return entries;
    }

    pub fn serialize(self: *const Env) ![]const u8 {
        var entries = try self.collectSerEntries();
        defer entries.deinit(self.allocator);
        if (self.config.sortKeys) return serializerMod.Serializer.serializeSorted(self.allocator, entries.items, self.config);
        return serializerMod.Serializer.serialize(self.allocator, entries.items, self.config);
    }
    pub fn save(self: *const Env, path: []const u8) !void {
        var entries = try self.collectSerEntries();
        defer entries.deinit(self.allocator);
        try writerMod.Writer.writeToFile(self.allocator, path, entries.items, self.config);
    }

    pub fn clone(self: *const Env) !Env {
        var out = Env.init(self.allocator, self.config);
        errdefer out.deinit();
        for (self.insertionOrder.items) |key| {
            if (self.entries.get(key)) |val| {
                const k = try self.allocator.dupe(u8, key);
                errdefer self.allocator.free(k);
                const v = try self.allocator.dupe(u8, val);
                errdefer self.allocator.free(v);
                try out.entries.put(k, v);
                try out.insertionOrder.append(self.allocator, k);
            }
        }
        return out;
    }
    pub fn merge(self: *Env, other: *const Env) !void {
        for (other.insertionOrder.items) |key| {
            if (other.entries.get(key)) |val| try self.set(key, val);
        }
    }
    pub fn validate(self: *const Env, allocator: std.mem.Allocator, s: schemaMod.Schema) ![]ValidationError {
        return s.validate(allocator, &self.entries);
    }

    // Explicit runtime import (never mutates runtime).
    fn putRuntimeKey(self: *Env, key: []const u8, value: []const u8) !void {
        if (std.mem.indexOfScalar(u8, value, 0) != null) return error.InvalidValue;
        const ownedValue = try self.allocator.dupe(u8, value);
        const existing = self.entries.fetchRemove(key);
        if (existing) |kv| {
            self.allocator.free(kv.value);
            try self.entries.put(kv.key, ownedValue);
        } else {
            const ownedKey = try self.allocator.dupe(u8, key);
            errdefer self.allocator.free(ownedKey);
            errdefer self.allocator.free(ownedValue);
            try self.insertionOrder.append(self.allocator, ownedKey);
            try self.entries.put(ownedKey, ownedValue);
        }
    }
    pub fn loadRuntime(self: *Env) !void {
        var all = try runtimeMod.getAll(self.allocator);
        defer freeRuntimeMap(self.allocator, &all);
        var it = all.iterator();
        while (it.next()) |e| {
            if (self.config.override or !self.entries.contains(e.key_ptr.*)) {
                try self.putRuntimeKey(e.key_ptr.*, e.value_ptr.*);
            }
        }
    }
    pub fn loadRuntimeIfMissing(self: *Env) !void {
        var all = try runtimeMod.getAll(self.allocator);
        defer freeRuntimeMap(self.allocator, &all);
        var it = all.iterator();
        while (it.next()) |e| {
            if (!self.contains(e.key_ptr.*)) try self.putRuntimeKey(e.key_ptr.*, e.value_ptr.*);
        }
    }
    /// Prefix is stripped (`APP_PORT` -> `PORT` with `"APP_"`).
    /// Empty prefix loads all. Invalid stripped `.env` keys are skipped.
    pub fn loadRuntimeWithPrefix(self: *Env, prefix: []const u8) !void {
        var all = try runtimeMod.getAll(self.allocator);
        defer freeRuntimeMap(self.allocator, &all);
        var it = all.iterator();
        while (it.next()) |e| {
            const k = e.key_ptr.*;
            if (prefix.len != 0 and !std.mem.startsWith(u8, k, prefix)) continue;
            const stripped = if (prefix.len == 0) k else k[prefix.len..];
            if (stripped.len == 0 or !helpers.isValidKey(stripped)) continue;
            if (self.config.override or !self.entries.contains(stripped)) {
                try self.putRuntimeKey(stripped, e.value_ptr.*);
            }
        }
    }
    fn freeRuntimeMap(allocator: std.mem.Allocator, map: *std.StringHashMap([]const u8)) void {
        var it = map.iterator();
        while (it.next()) |e| {
            allocator.free(e.key_ptr.*);
            allocator.free(e.value_ptr.*);
        }
        map.deinit();
    }

    /// Explicit `Env` -> runtime export via single `runtime.set`.
    pub fn exportToRuntime(self: *const Env) !void {
        for (self.insertionOrder.items) |k| {
            if (self.entries.get(k)) |v| try runtimeMod.set(k, v);
        }
    }

    /// Combined precedence: in-memory `Env` > runtime > default.
    pub fn getRuntime(self: *const Env, key: []const u8) ?[]const u8 {
        return self.get(key) orelse runtimeMod.get(key);
    }
    pub fn getRuntimeAlloc(self: *const Env, allocator: std.mem.Allocator, key: []const u8) !?[]u8 {
        if (self.get(key)) |v| return try allocator.dupe(u8, v);
        return try runtimeMod.getAlloc(allocator, key);
    }
    pub fn getWithFallback(self: *const Env, key: []const u8, fallback: []const u8) []const u8 {
        return self.getRuntime(key) orelse fallback;
    }
    pub fn requireRuntime(self: *const Env, key: []const u8) ![]const u8 {
        return self.getRuntime(key) orelse error.MissingRequired;
    }
    pub fn fetchRuntime(self: *Env, key: []const u8) !?[]const u8 {
        if (self.get(key)) |v| return v;
        const rv = runtimeMod.get(key) orelse return null;
        try self.putRuntimeKey(key, rv);
        return self.get(key);
    }
    pub fn containsRuntime(self: *const Env, key: []const u8) bool {
        return self.contains(key) or runtimeMod.exists(key);
    }

    pub fn toEnvironMap(self: *const Env, allocator: std.mem.Allocator) !std.process.Environ.Map {
        var map = std.process.Environ.Map.init(allocator);
        errdefer map.deinit();
        for (self.insertionOrder.items) |k| {
            if (self.entries.get(k)) |v| {
                if (!std.process.Environ.Map.validateKeyForPut(k)) return error.InvalidKey;
                if (std.mem.indexOfScalar(u8, v, 0) != null) return error.InvalidValue;
                try map.put(k, v);
            }
        }
        return map;
    }
    pub fn applyToEnvironMap(self: *const Env, map: *std.process.Environ.Map) !void {
        for (self.insertionOrder.items) |k| {
            if (self.entries.get(k)) |v| {
                if (!std.process.Environ.Map.validateKeyForPut(k)) return error.InvalidKey;
                if (std.mem.indexOfScalar(u8, v, 0) != null) return error.InvalidValue;
                try map.put(k, v);
            }
        }
    }
    pub fn snapshotRuntime(self: *const Env) !runtimeMod.Snapshot {
        return try runtimeMod.snapshot(self.allocator);
    }

    pub const EnvScope = struct {
        env: *Env,
        saved: std.StringHashMap(?[]const u8),
        allocator: std.mem.Allocator,
        pub fn init(env: *Env) EnvScope {
            return .{ .env = env, .saved = std.StringHashMap(?[]const u8).init(env.allocator), .allocator = env.allocator };
        }
        pub fn deinit(self: *EnvScope) void {
            var it = self.saved.iterator();
            while (it.next()) |e| {
                if (e.value_ptr.*) |prev| {
                    self.env.set(e.key_ptr.*, prev) catch {};
                    self.allocator.free(prev);
                } else {
                    _ = self.env.remove(e.key_ptr.*) catch false;
                }
                self.allocator.free(e.key_ptr.*);
            }
            self.saved.deinit();
        }
        fn ensureSaved(self: *EnvScope, key: []const u8) !void {
            if (self.saved.contains(key)) return;
            const k = try self.allocator.dupe(u8, key);
            errdefer self.allocator.free(k);
            const prev = self.env.get(key);
            const v: ?[]const u8 = if (prev) |p| try self.allocator.dupe(u8, p) else null;
            errdefer if (v) |x| self.allocator.free(x);
            try self.saved.put(k, v);
        }
        pub fn set(self: *EnvScope, key: []const u8, value: []const u8) !void {
            try self.ensureSaved(key);
            try self.env.set(key, value);
        }
        pub fn unset(self: *EnvScope, key: []const u8) !void {
            try self.ensureSaved(key);
            _ = try self.env.remove(key);
        }
    };
    pub fn scope(self: *Env) EnvScope {
        return EnvScope.init(self);
    }
    pub fn withTemp(self: *Env, key: []const u8, value: []const u8, func: *const fn (*Env) anyerror!void) !void {
        var s = self.scope();
        defer s.deinit();
        try s.set(key, value);
        try func(self);
    }

    fn resolveInterpolation(self: *Env) !void {
        // Transactional: resolve all first, then commit.
        var resolved: std.ArrayList(struct { key: []const u8, value: []const u8 }) = .empty;
        defer resolved.deinit(self.allocator);
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            const val = entry.value_ptr.*;
            if (std.mem.indexOf(u8, val, "${") != null or (val.len > 0 and val[0] == '$')) {
                const out = interpolationMod.interpolate(self.allocator, val, &self.entries, self.config.maxInterpolationDepth) catch |err| switch (err) {
                    error.CircularDependency, error.MaxDepthExceeded => continue,
                    error.OutOfMemory => return error.OutOfMemory,
                };
                try resolved.append(self.allocator, .{ .key = entry.key_ptr.*, .value = out });
            }
        }
        for (resolved.items) |r| {
            const entry = self.entries.getEntry(r.key).?;
            self.allocator.free(entry.value_ptr.*);
            entry.value_ptr.* = r.value;
        }
    }
};

/// Single borrowed insertion-order iterator (no allocation, no leak).
pub const Iterator = struct {
    env: *const Env,
    index: usize,
    pub const Entry = struct { key: []const u8, value: []const u8 };
    pub fn next(self: *Iterator) ?Entry {
        if (self.index >= self.env.insertionOrder.items.len) return null;
        const key = self.env.insertionOrder.items[self.index];
        self.index += 1;
        return .{ .key = key, .value = self.env.entries.get(key) orelse "" };
    }
    pub fn peek(self: *const Iterator) ?Entry {
        if (self.index >= self.env.insertionOrder.items.len) return null;
        const key = self.env.insertionOrder.items[self.index];
        return .{ .key = key, .value = self.env.entries.get(key) orelse "" };
    }
    pub fn reset(self: *Iterator) void {
        self.index = 0;
    }
    pub fn skip(self: *Iterator, count: usize) void {
        self.index = @min(self.index + count, self.env.insertionOrder.items.len);
    }
    pub fn remaining(self: *const Iterator) usize {
        return self.env.insertionOrder.items.len - self.index;
    }
    pub fn deinit(_: *Iterator) void {}
    pub fn collect(self: *Iterator, allocator: std.mem.Allocator, predicate: *const fn (Entry) bool) ![]Entry {
        var out: std.ArrayList(Entry) = .empty;
        errdefer out.deinit(allocator);
        while (self.next()) |e| if (predicate(e)) try out.append(allocator, e);
        return try out.toOwnedSlice(allocator);
    }
};

test "Env init and deinit" {
    var env = Env.init(std.testing.allocator, .{});
    defer env.deinit();
    try std.testing.expectEqual(@as(usize, 0), env.count());
}
test "Env set and get in-memory only" {
    var env = Env.init(std.testing.allocator, .{});
    defer env.deinit();
    try env.set("KEY", "value");
    try std.testing.expectEqualStrings("value", env.get("KEY").?);
    try std.testing.expect(runtime.get("KEY") == null);
}
test "Env getBool" {
    var env = Env.init(std.testing.allocator, .{});
    defer env.deinit();
    try env.set("DEBUG", "true");
    try env.set("VERBOSE", "no");
    try std.testing.expect(env.getBool("DEBUG").?);
    try std.testing.expect(!env.getBool("VERBOSE").?);
}
test "Env contains and remove in-memory only" {
    var env = Env.init(std.testing.allocator, .{});
    defer env.deinit();
    try env.set("KEY", "value");
    try std.testing.expect(try env.remove("KEY"));
    try std.testing.expect(!try env.remove("KEY"));
    try runtime.set("ENV_ZIG_TEST_ENV_REMOVE", "x");
    defer runtime.unset("ENV_ZIG_TEST_ENV_REMOVE") catch {};
    try env.set("ENV_ZIG_TEST_ENV_REMOVE", "y");
    _ = try env.remove("ENV_ZIG_TEST_ENV_REMOVE");
    try std.testing.expectEqualStrings("x", runtime.get("ENV_ZIG_TEST_ENV_REMOVE").?);
}
test "Env reload is transactional" {
    var env = Env.init(std.testing.allocator, .{});
    defer env.deinit();
    try env.set("KEEP", "1");
    const r = env.reload("definitely_missing_env_zig_12345.env");
    try std.testing.expectError(error.FileNotFound, r);
    try std.testing.expectEqualStrings("1", env.get("KEEP").?);
}
test "Env parseString strict leaves state unchanged" {
    var env = Env.init(std.testing.allocator, .{ .strict = true });
    defer env.deinit();
    try env.set("KEEP", "1");
    try std.testing.expectError(error.InvalidKey, env.parseString("123BAD=x\n"));
    try std.testing.expectEqualStrings("1", env.get("KEEP").?);
    try std.testing.expectEqual(@as(usize, 1), env.count());
}
test "Env generic getValue shares conversion" {
    const Mode = enum { debug, release };
    var env = Env.init(std.testing.allocator, .{});
    defer env.deinit();
    try env.set("PORT", "8080");
    try runtime.set("ENV_ZIG_TEST_SHARED_CONV", "8080");
    defer runtime.unset("ENV_ZIG_TEST_SHARED_CONV") catch {};
    try std.testing.expectEqual(@as(u16, 8080), env.getValue(u16, "PORT").?);
    try std.testing.expectEqual(@as(u16, 8080), runtime.getValue(u16, "ENV_ZIG_TEST_SHARED_CONV").?);
    try std.testing.expectEqual(Mode.release, blk: {
        try env.set("MODE", "release");
        break :blk env.getValue(Mode, "MODE").?;
    });
}
test "Env getList owned" {
    var env = Env.init(std.testing.allocator, .{});
    defer env.deinit();
    try env.set("HOSTS", "a, b ,c");
    const list = env.getList(std.testing.allocator, "HOSTS", ',').?;
    defer {
        for (list) |item| std.testing.allocator.free(item);
        std.testing.allocator.free(list);
    }
    try std.testing.expectEqualStrings("a", list[0]);
    try std.testing.expectEqualStrings("b", list[1]);
    try std.testing.expectEqualStrings("c", list[2]);
}
test "Env round-trip" {
    var env = Env.init(std.testing.allocator, .{});
    defer env.deinit();
    try env.parseString("A=hello world\nB=a=b\nEMPTY=\nUNI=héllo ✓\n");
    const ser = try env.serialize();
    defer std.testing.allocator.free(ser);
    var env2 = Env.init(std.testing.allocator, .{});
    defer env2.deinit();
    try env2.parseString(ser);
    try std.testing.expectEqualStrings(env.get("A").?, env2.get("A").?);
    try std.testing.expectEqualStrings(env.get("B").?, env2.get("B").?);
}
test "Env import/export prefix" {
    try runtime.set("ENV_ZIG_TEST_PREFIX_A", "1");
    defer runtime.unset("ENV_ZIG_TEST_PREFIX_A") catch {};
    var env = Env.init(std.testing.allocator, .{});
    defer env.deinit();
    try env.loadRuntimeWithPrefix("ENV_ZIG_TEST_PREFIX_");
    try std.testing.expectEqualStrings("1", env.get("A").?);
    try env.set("ENV_ZIG_TEST_EXPORT_ME", "v");
    defer runtime.unset("ENV_ZIG_TEST_EXPORT_ME") catch {};
    try std.testing.expect(runtime.get("ENV_ZIG_TEST_EXPORT_ME") == null);
    try env.exportToRuntime();
    try std.testing.expectEqualStrings("v", runtime.get("ENV_ZIG_TEST_EXPORT_ME").?);
}
