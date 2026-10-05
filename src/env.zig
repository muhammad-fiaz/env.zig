const std = @import("std");
const parserMod = @import("parser.zig");
const configMod = @import("config.zig");
const interpolationMod = @import("interpolation.zig");
const serializerMod = @import("serializer.zig");
const writerMod = @import("writer.zig");
const iteratorMod = @import("iterator.zig");
const validatorMod = @import("validator.zig");
const schemaMod = @import("schema.zig");
const osEnvMod = @import("os_env.zig");
const runtimeMod = @import("runtime.zig");
const helpers = @import("internal/helpers.zig");

pub const Config = configMod.Config;
pub const ValidationError = validatorMod.ValidationError;
pub const schema = schemaMod;
pub const validator = validatorMod;
pub const OsEnv = osEnvMod.OsEnv;
pub const Scope = osEnvMod.Scope;
pub const Snapshot = osEnvMod.Snapshot;
pub const osEnv = osEnvMod;
/// Explicit runtime/process-environment namespace.
/// Prefer `env.runtime.get/set/...` for process env; `Env` is in-memory.
pub const runtime = runtimeMod;
pub const Cache = @import("cache.zig").Cache;
pub const Iterator = iteratorMod.Iterator;

/// In-memory `.env` store with insertion-order preservation.
/// Owns all keys and values; call `deinit` to free.
///
/// Thread-safety: `Env` itself has no internal locking. Do not share
/// across threads without external synchronization. This is distinct
/// from `runtime`, whose mutation is process-global and thread-unsafe
/// by OS design.
pub const Env = struct {
    allocator: std.mem.Allocator,
    entries: std.StringHashMap([]const u8),
    insertionOrder: std.ArrayList([]const u8),
    config: Config,

    /// Create a new empty Env.
    pub fn init(allocator: std.mem.Allocator, cfg: Config) Env {
        return .{
            .allocator = allocator,
            .entries = std.StringHashMap([]const u8).init(allocator),
            .insertionOrder = .empty,
            .config = cfg,
        };
    }

    /// Free all resources.
    pub fn deinit(self: *Env) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.entries.deinit();
        for (self.insertionOrder.items) |key| {
            self.allocator.free(key);
        }
        self.insertionOrder.deinit(self.allocator);
    }

    /// Load and parse a .env file.
    /// Maps `FileNotFound` and `AccessDenied` precisely; other I/O
    /// failures become `error.IoError`.
    pub fn load(self: *Env, path: []const u8) !void {
        try self.config.validate();
        const dir = std.Io.Dir.cwd();
        var ioThreaded: std.Io.Threaded = .init_single_threaded;
        const io = ioThreaded.io();

        const content = dir.readFileAlloc(
            io,
            path,
            self.allocator,
            .unlimited,
        ) catch |err| switch (err) {
            error.FileNotFound => return error.FileNotFound,
            error.AccessDenied => return error.PermissionDenied,
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.IoError,
        };
        defer self.allocator.free(content);

        try self.parseString(content);
    }

    /// Parse a .env string and add entries.
    /// Precedence: existing keys are kept when `config.override == false`.
    pub fn parseString(self: *Env, source: []const u8) !void {
        try self.config.validate();
        var result = try parserMod.parse(self.allocator, source, .{
            .config = self.config,
        });
        defer result.deinit(self.allocator);

        for (result.entries.items) |entry| {
            if (self.config.override or !self.entries.contains(entry.key)) {
                const existing = self.entries.fetchRemove(entry.key);
                if (existing) |kv| {
                    self.allocator.free(kv.value);
                    const ownedValue = try self.allocator.dupe(u8, entry.value);
                    try self.entries.put(kv.key, ownedValue);
                } else {
                    const ownedKey = try self.allocator.dupe(u8, entry.key);
                    errdefer self.allocator.free(ownedKey);
                    const ownedValue = try self.allocator.dupe(u8, entry.value);
                    errdefer self.allocator.free(ownedValue);
                    try self.entries.put(ownedKey, ownedValue);
                    try self.insertionOrder.append(self.allocator, ownedKey);
                }
            }
        }

        if (self.config.interpolate) {
            try self.resolveInterpolation();
        }
    }

    /// Load multiple .env files in order (later files override earlier
    /// ones when `config.override` is true).
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

    /// Reload the environment from a file (clears first).
    pub fn reload(self: *Env, path: []const u8) !void {
        self.clear();
        try self.load(path);
    }

    /// Set a key-value pair. Validates `.env` key shape and rejects NUL.
    /// When `config.exportToEnv` is set, also exports to the process
    /// environment; export failures are returned (never swallowed).
    pub fn set(self: *Env, key: []const u8, value: []const u8) !void {
        if (!helpers.isValidKey(key)) return error.InvalidKey;
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
        if (self.config.exportToEnv) {
            try osEnvMod.OsEnv.set(key, value);
        }
    }

    /// Set and also sync to OS environment (always, regardless of config).
    pub fn setOs(self: *Env, key: []const u8, value: []const u8) !void {
        try self.set(key, value);
        try osEnvMod.OsEnv.set(key, value);
    }

    /// Get a borrowed value by key. Null means missing.
    pub fn get(self: *const Env, key: []const u8) ?[]const u8 {
        return self.entries.get(key);
    }

    /// Borrowed string accessor (same as `get`).
    pub fn getString(self: *const Env, key: []const u8) ?[]const u8 {
        return self.get(key);
    }

    /// Owned copy of a value. Caller must free with `allocator.free`.
    /// Returns null when missing.
    pub fn getAlloc(self: *const Env, allocator: std.mem.Allocator, key: []const u8) !?[]u8 {
        const v = self.get(key) orelse return null;
        return try allocator.dupe(u8, v);
    }

    /// Get with default when missing (borrowed; default is borrowed).
    /// Defaults apply only to missing keys, never to invalid values.
    pub fn getOrDefault(self: *const Env, key: []const u8, defaultValue: []const u8) []const u8 {
        return self.get(key) orelse defaultValue;
    }

    /// True when the key exists, even with an empty value.
    pub fn contains(self: *const Env, key: []const u8) bool {
        return self.entries.contains(key);
    }

    /// True when missing or present-with-empty.
    pub fn isEmpty(self: *const Env, key: []const u8) bool {
        const v = self.get(key) orelse return true;
        return v.len == 0;
    }

    /// Require a key in this store. `error.MissingRequired` when missing.
    pub fn require(self: *const Env, key: []const u8) ![]const u8 {
        return self.get(key) orelse error.MissingRequired;
    }

    /// Get a boolean. Accepts true/false/yes/no/1/0/on/off (case-insensitive).
    /// Returns null when missing or malformed.
    pub fn getBool(self: *const Env, key: []const u8) ?bool {
        const val = self.get(key) orelse return null;
        return parseBoolValue(val);
    }

    /// Missing gives null; present-but-invalid gives `error.TypeMismatch`.
    pub fn tryGetBool(self: *const Env, key: []const u8) !?bool {
        const val = self.get(key) orelse return null;
        return parseBoolValue(val) orelse error.TypeMismatch;
    }

    /// Get an integer. Null when missing or malformed.
    pub fn getInt(self: *const Env, comptime T: type, key: []const u8) ?T {
        const val = self.get(key) orelse return null;
        return std.fmt.parseInt(T, std.mem.trim(u8, val, " \t\r\n"), 10) catch null;
    }

    /// Missing gives null; invalid gives `error.TypeMismatch`.
    pub fn tryGetInt(self: *const Env, comptime T: type, key: []const u8) !?T {
        const val = self.get(key) orelse return null;
        return std.fmt.parseInt(T, std.mem.trim(u8, val, " \t\r\n"), 10) catch error.TypeMismatch;
    }

    /// Get a float. Null when missing or malformed.
    pub fn getFloat(self: *const Env, comptime T: type, key: []const u8) ?T {
        const val = self.get(key) orelse return null;
        return std.fmt.parseFloat(T, std.mem.trim(u8, val, " \t\r\n")) catch null;
    }

    /// Missing gives null; invalid gives `error.TypeMismatch`.
    pub fn tryGetFloat(self: *const Env, comptime T: type, key: []const u8) !?T {
        const val = self.get(key) orelse return null;
        return std.fmt.parseFloat(T, std.mem.trim(u8, val, " \t\r\n")) catch error.TypeMismatch;
    }

    /// Get an enum. Null when missing or unmatched.
    pub fn getEnum(self: *const Env, comptime E: type, key: []const u8) ?E {
        const val = self.get(key) orelse return null;
        const trimmed = std.mem.trim(u8, val, " \t\r\n");
        return std.meta.stringToEnum(E, trimmed);
    }

    /// Missing gives null; unmatched gives `error.TypeMismatch`.
    pub fn tryGetEnum(self: *const Env, comptime E: type, key: []const u8) !?E {
        const val = self.get(key) orelse return null;
        const trimmed = std.mem.trim(u8, val, " \t\r\n");
        return std.meta.stringToEnum(E, trimmed) orelse error.TypeMismatch;
    }

    fn parseBoolValue(val: []const u8) ?bool {
        const v = std.mem.trim(u8, val, " \t\r\n");
        var buf: [16]u8 = undefined;
        if (v.len > buf.len) return null;
        for (v, 0..) |ch, i| buf[i] = std.ascii.toLower(ch);
        const lower = buf[0..v.len];
        if (std.mem.eql(u8, lower, "true") or std.mem.eql(u8, lower, "yes") or
            std.mem.eql(u8, lower, "1") or std.mem.eql(u8, lower, "on"))
            return true;
        if (std.mem.eql(u8, lower, "false") or std.mem.eql(u8, lower, "no") or
            std.mem.eql(u8, lower, "0") or std.mem.eql(u8, lower, "off"))
            return false;
        return null;
    }

    /// Generic typed getter. Supports `bool`, integers, floats, enums and
    /// `[]const u8` (borrowed string). Missing gives null; malformed gives
    /// null (use `tryGetValue` to distinguish).
    pub fn getValue(self: *const Env, comptime T: type, key: []const u8) ?T {
        return switch (@typeInfo(T)) {
            .bool => if (self.getBool(key)) |b| @as(T, b) else null,
            .int => self.getInt(T, key),
            .float => self.getFloat(T, key),
            .@"enum" => self.getEnum(T, key),
            .pointer => |ptr| blk: {
                if (ptr.size != .slice or ptr.child != u8) {
                    @compileError("getValue only supports []const u8 slices, bool, ints, floats and enums");
                }
                break :blk if (self.get(key)) |s| @as(T, s) else null;
            },
            else => @compileError("getValue: unsupported type"),
        };
    }

    /// Generic typed getter distinguishing missing (null) from malformed
    /// (`error.TypeMismatch`).
    pub fn tryGetValue(self: *const Env, comptime T: type, key: []const u8) !?T {
        return switch (@typeInfo(T)) {
            .bool => try self.tryGetBool(key),
            .int => try self.tryGetInt(T, key),
            .float => try self.tryGetFloat(T, key),
            .@"enum" => try self.tryGetEnum(T, key),
            .pointer => |ptr| blk: {
                if (ptr.size != .slice or ptr.child != u8) {
                    @compileError("tryGetValue only supports []const u8 slices, bool, ints, floats and enums");
                }
                break :blk self.get(key);
            },
            else => @compileError("tryGetValue: unsupported type"),
        };
    }

    /// Require a typed value. Missing or malformed both error:
    /// missing gives `error.MissingRequired`, malformed gives
    /// `error.TypeMismatch`.
    pub fn requireValue(self: *const Env, comptime T: type, key: []const u8) !T {
        return (try self.tryGetValue(T, key)) orelse error.MissingRequired;
    }

    /// Typed getter with default for missing keys only.
    /// Invalid values still return null (use tryGetValue to detect).
    pub fn getValueOrDefault(self: *const Env, comptime T: type, key: []const u8, defaultValue: T) T {
        return self.getValue(T, key) orelse defaultValue;
    }

    /// Split a value by delimiter into owned strings.
    /// Both the outer slice and every item are owned by the caller:
    /// free each item, then free the slice with `allocator.free`.
    /// Empty/whitespace-only segments are skipped. Returns null when missing.
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
                for (result.items) |owned| allocator.free(owned);
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

    /// Remove a key. Returns true when removed.
    /// Export failures are returned, never swallowed.
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
            if (self.config.exportToEnv) {
                try osEnvMod.OsEnv.unset(key);
            }
            return true;
        }
        return false;
    }

    /// Remove from Env and unconditionally from the OS environment.
    pub fn unsetOs(self: *Env, key: []const u8) !bool {
        const r = try self.remove(key);
        try osEnvMod.OsEnv.unset(key);
        return r;
    }

    /// Clear all entries.
    pub fn clear(self: *Env) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.entries.clearRetainingCapacity();
        for (self.insertionOrder.items) |key| {
            self.allocator.free(key);
        }
        self.insertionOrder.clearRetainingCapacity();
    }

    /// Number of entries.
    pub fn count(self: *const Env) usize {
        return self.entries.count();
    }

    /// All keys in insertion order (borrowed).
    pub fn keys(self: *const Env) []const []const u8 {
        return self.insertionOrder.items;
    }

    /// Borrowed insertion-order iterator. No allocation, no failure.
    /// Must not outlive the `Env`; do not mutate the `Env` while iterating.
    /// `deinit` is a no-op kept for call-site compatibility.
    pub fn iterator(self: *const Env) EnvIterator {
        return EnvIterator{ .env = self, .index = 0 };
    }

    /// Serialize entries to .env format (owned; caller frees).
    /// Honors `config.sortKeys`.
    pub fn serialize(self: *const Env) ![]const u8 {
        var entries: std.ArrayList(serializerMod.SerEntry) = .empty;
        defer entries.deinit(self.allocator);
        for (self.insertionOrder.items) |key| {
            if (self.entries.get(key)) |val| {
                try entries.append(self.allocator, .{ .key = key, .value = val });
            }
        }
        if (self.config.sortKeys) {
            return serializerMod.Serializer.serializeSorted(self.allocator, entries.items, self.config);
        }
        return serializerMod.Serializer.serialize(self.allocator, entries.items, self.config);
    }

    /// Write entries to a file.
    pub fn save(self: *const Env, path: []const u8) !void {
        var entries: std.ArrayList(serializerMod.SerEntry) = .empty;
        defer entries.deinit(self.allocator);
        for (self.insertionOrder.items) |key| {
            if (self.entries.get(key)) |val| {
                try entries.append(self.allocator, .{ .key = key, .value = val });
            }
        }
        try writerMod.Writer.writeToFile(self.allocator, path, entries.items, self.config);
    }

    /// Deep copy.
    pub fn clone(self: *const Env) !Env {
        var newEnv = Env.init(self.allocator, self.config);
        errdefer newEnv.deinit();
        for (self.insertionOrder.items) |key| {
            if (self.entries.get(key)) |val| {
                const ownedKey = try self.allocator.dupe(u8, key);
                errdefer self.allocator.free(ownedKey);
                const ownedValue = try self.allocator.dupe(u8, val);
                errdefer self.allocator.free(ownedValue);
                try newEnv.entries.put(ownedKey, ownedValue);
                try newEnv.insertionOrder.append(self.allocator, ownedKey);
            }
        }
        return newEnv;
    }

    /// Merge another Env into this one (other wins).
    pub fn merge(self: *Env, other: *const Env) !void {
        for (other.insertionOrder.items) |key| {
            if (other.entries.get(key)) |val| {
                try self.set(key, val);
            }
        }
    }

    /// Validate entries against a schema (owned slice; caller frees).
    pub fn validate(self: *const Env, allocator: std.mem.Allocator, s: schemaMod.Schema) ![]ValidationError {
        return s.validate(allocator, &self.entries);
    }

    /// Load all OS variables. Existing keys overwritten when `override`.
    /// Precedence: runtime -> loaded .env -> later files -> explicit override.
    pub fn loadOsEnv(self: *Env) !void {
        var all = try osEnvMod.OsEnv.getAllAlloc(self.allocator);
        defer {
            var it = all.iterator();
            while (it.next()) |e| {
                self.allocator.free(e.key_ptr.*);
                self.allocator.free(e.value_ptr.*);
            }
            all.deinit();
        }
        var it = all.iterator();
        while (it.next()) |e| {
            const k = e.key_ptr.*;
            const v = e.value_ptr.*;
            if (self.config.override or !self.entries.contains(k)) {
                // OS keys may not be `.env`-valid identifiers; insert directly.
                try self.putOsKey(k, v);
            }
        }
    }

    /// Load OS vars only for missing keys (no override).
    pub fn loadOsEnvIfMissing(self: *Env) !void {
        var all = try osEnvMod.OsEnv.getAllAlloc(self.allocator);
        defer {
            var it = all.iterator();
            while (it.next()) |e| {
                self.allocator.free(e.key_ptr.*);
                self.allocator.free(e.value_ptr.*);
            }
            all.deinit();
        }
        var it = all.iterator();
        while (it.next()) |e| {
            if (!self.contains(e.key_ptr.*)) try self.putOsKey(e.key_ptr.*, e.value_ptr.*);
        }
    }

    /// Load OS vars with prefix, stripping it. Empty prefix loads all.
    /// Empty stripped keys and invalid stripped `.env` keys are skipped.
    /// Example: `APP_PORT` with prefix `APP_` becomes `PORT`.
    pub fn loadOsEnvWithPrefix(self: *Env, prefix: []const u8) !void {
        var all = try osEnvMod.OsEnv.getAllAlloc(self.allocator);
        defer {
            var it = all.iterator();
            while (it.next()) |e| {
                self.allocator.free(e.key_ptr.*);
                self.allocator.free(e.value_ptr.*);
            }
            all.deinit();
        }
        var it = all.iterator();
        while (it.next()) |e| {
            const k = e.key_ptr.*;
            if (prefix.len == 0 or std.mem.startsWith(u8, k, prefix)) {
                const stripped = if (prefix.len == 0) k else k[prefix.len..];
                if (stripped.len == 0) continue;
                if (!helpers.isValidKey(stripped)) continue;
                if (self.config.override or !self.entries.contains(stripped)) {
                    try self.putOsKey(stripped, e.value_ptr.*);
                }
            }
        }
    }

    fn putOsKey(self: *Env, key: []const u8, value: []const u8) !void {
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

    /// Export all entries to the process environment.
    pub fn exportToOsEnv(self: *const Env) !void {
        for (self.insertionOrder.items) |k| {
            if (self.entries.get(k)) |v| try osEnvMod.OsEnv.set(k, v);
        }
    }

    /// Combined lookup: Env first, then OS fallback (like `$VAR`).
    pub fn getOs(self: *const Env, key: []const u8) ?[]const u8 {
        return self.get(key) orelse osEnvMod.OsEnv.get(key);
    }

    /// Owned combined lookup. Caller frees when non-null.
    pub fn getOsAlloc(self: *const Env, allocator: std.mem.Allocator, key: []const u8) !?[]u8 {
        if (self.get(key)) |v| return try allocator.dupe(u8, v);
        return try osEnvMod.OsEnv.getAlloc(allocator, key);
    }

    /// Legacy alias for `getOsAlloc` without Env fallback check.
    /// Prefer `getOsAlloc`.
    pub fn getOsEnvAlloc(self: *const Env, allocator: std.mem.Allocator, key: []const u8) !?[]u8 {
        return try self.getOsAlloc(allocator, key);
    }

    /// Combined lookup with fallback default.
    pub fn getWithFallback(self: *const Env, key: []const u8, fallback: []const u8) []const u8 {
        return self.getOs(key) orelse fallback;
    }

    /// Require a key from Env or OS. `error.MissingRequired` when absent.
    pub fn requireOs(self: *const Env, key: []const u8) ![]const u8 {
        return self.getOs(key) orelse error.MissingRequired;
    }

    /// Copy an OS var into the store and return it (borrowed).
    pub fn fetchOs(self: *Env, key: []const u8) !?[]const u8 {
        if (self.get(key)) |v| return v;
        const osVal = osEnvMod.OsEnv.get(key) orelse return null;
        try self.putOsKey(key, osVal);
        return self.get(key);
    }

    /// True when present in Env or OS.
    pub fn containsOs(self: *const Env, key: []const u8) bool {
        return self.contains(key) or osEnvMod.OsEnv.exists(key);
    }

    /// Convert to `std.process.Environ.Map` for child processes.
    /// Caller must call `map.deinit()`. Invalid keys return
    /// `error.InvalidKey` instead of asserting.
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

    /// Merge this Env into an existing `Environ.Map` (this wins).
    pub fn applyToEnvironMap(self: *const Env, map: *std.process.Environ.Map) !void {
        for (self.insertionOrder.items) |k| {
            if (self.entries.get(k)) |v| {
                if (!std.process.Environ.Map.validateKeyForPut(k)) return error.InvalidKey;
                if (std.mem.indexOfScalar(u8, v, 0) != null) return error.InvalidValue;
                try map.put(k, v);
            }
        }
    }

    /// Snapshot the OS environment with this Env's allocator.
    pub fn snapshotOs(self: *const Env) !osEnvMod.Snapshot {
        return try osEnvMod.OsEnv.snapshot(self.allocator);
    }

    /// In-memory temporary scope; restores on `deinit`.
    pub const EnvScope = struct {
        env: *Env,
        saved: std.StringHashMap(?[]const u8),
        allocator: std.mem.Allocator,

        pub fn init(env: *Env) EnvScope {
            return .{
                .env = env,
                .saved = std.StringHashMap(?[]const u8).init(env.allocator),
                .allocator = env.allocator,
            };
        }

        pub fn deinit(self: *EnvScope) void {
            var it = self.saved.iterator();
            while (it.next()) |e| {
                const key = e.key_ptr.*;
                const maybePrev = e.value_ptr.*;
                if (maybePrev) |prev| {
                    self.env.set(key, prev) catch {};
                    self.allocator.free(prev);
                } else {
                    _ = self.env.remove(key) catch false;
                }
                self.allocator.free(key);
            }
            self.saved.deinit();
        }

        fn ensureSaved(self: *EnvScope, key: []const u8) !void {
            if (self.saved.contains(key)) return;
            const ownedKey = try self.allocator.dupe(u8, key);
            errdefer self.allocator.free(ownedKey);
            const prev = self.env.get(key);
            const ownedVal: ?[]const u8 = if (prev) |v| try self.allocator.dupe(u8, v) else null;
            errdefer if (ownedVal) |v| self.allocator.free(v);
            try self.saved.put(ownedKey, ownedVal);
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

    /// Create a temporary in-memory scope.
    pub fn scope(self: *Env) EnvScope {
        return EnvScope.init(self);
    }

    /// Run `func` with a temporary override, restoring afterwards.
    pub fn withTemp(self: *Env, key: []const u8, value: []const u8, func: *const fn (*Env) anyerror!void) !void {
        var s = self.scope();
        defer s.deinit();
        try s.set(key, value);
        try func(self);
    }

    fn resolveInterpolation(self: *Env) !void {
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            const val = entry.value_ptr.*;
            if (std.mem.indexOf(u8, val, "${") != null or
                (val.len > 0 and val[0] == '$'))
            {
                const resolved = interpolationMod.interpolate(
                    self.allocator,
                    val,
                    &self.entries,
                    self.config.maxInterpolationDepth,
                ) catch |err| switch (err) {
                    error.CircularDependency, error.MaxDepthExceeded => continue,
                    error.OutOfMemory => return error.OutOfMemory,
                };
                self.allocator.free(val);
                entry.value_ptr.* = resolved;
            }
        }
    }
};

/// Borrowed insertion-order iterator over an `Env`.
/// No allocation; `deinit` is a no-op. Must not outlive the `Env`;
/// do not mutate the `Env` while iterating.
pub const EnvIterator = struct {
    env: *const Env,
    index: usize,

    pub const Entry = struct {
        key: []const u8,
        value: []const u8,
    };

    pub fn next(self: *EnvIterator) ?Entry {
        if (self.index >= self.env.insertionOrder.items.len) return null;
        const key = self.env.insertionOrder.items[self.index];
        const value = self.env.entries.get(key) orelse "";
        self.index += 1;
        return .{ .key = key, .value = value };
    }

    pub fn peek(self: *const EnvIterator) ?Entry {
        if (self.index >= self.env.insertionOrder.items.len) return null;
        const key = self.env.insertionOrder.items[self.index];
        const value = self.env.entries.get(key) orelse "";
        return .{ .key = key, .value = value };
    }

    pub fn reset(self: *EnvIterator) void {
        self.index = 0;
    }

    pub fn skip(self: *EnvIterator, count: usize) void {
        self.index = @min(self.index + count, self.env.insertionOrder.items.len);
    }

    pub fn remaining(self: *const EnvIterator) usize {
        return self.env.insertionOrder.items.len - self.index;
    }

    pub fn deinit(_: *EnvIterator) void {}

    pub fn collect(
        self: *EnvIterator,
        allocator: std.mem.Allocator,
        predicate: *const fn (Entry) bool,
    ) ![]Entry {
        var result: std.ArrayList(Entry) = .empty;
        errdefer result.deinit(allocator);
        while (self.next()) |entry| {
            if (predicate(entry)) {
                try result.append(allocator, entry);
            }
        }
        return try result.toOwnedSlice(allocator);
    }
};

test "Env init and deinit" {
    var env = Env.init(std.testing.allocator, .{});
    defer env.deinit();
    try std.testing.expectEqual(@as(usize, 0), env.count());
}

test "Env set and get" {
    var env = Env.init(std.testing.allocator, .{});
    defer env.deinit();

    try env.set("KEY", "value");
    try std.testing.expectEqualStrings("value", env.get("KEY").?);
    try std.testing.expectEqual(@as(?[]const u8, null), env.get("MISSING"));
}

test "Env getBool" {
    var env = Env.init(std.testing.allocator, .{});
    defer env.deinit();

    try env.set("DEBUG", "true");
    try env.set("VERBOSE", "no");

    try std.testing.expect(env.getBool("DEBUG").?);
    try std.testing.expect(!env.getBool("VERBOSE").?);
    try std.testing.expectEqual(@as(?bool, null), env.getBool("MISSING"));
}

test "Env getInt" {
    var env = Env.init(std.testing.allocator, .{});
    defer env.deinit();

    try env.set("PORT", "8080");
    try std.testing.expectEqual(@as(u16, 8080), env.getInt(u16, "PORT").?);
}

test "Env getFloat" {
    var env = Env.init(std.testing.allocator, .{});
    defer env.deinit();

    try env.set("RATIO", "3.14");
    const f = env.getFloat(f64, "RATIO");
    try std.testing.expect(f != null);
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), f.?, 0.001);
}

test "Env contains and remove" {
    var env = Env.init(std.testing.allocator, .{});
    defer env.deinit();

    try env.set("KEY", "value");
    try std.testing.expect(env.contains("KEY"));
    try std.testing.expect(try env.remove("KEY"));
    try std.testing.expect(!env.contains("KEY"));
    try std.testing.expect(!try env.remove("KEY"));
}

test "Env clear" {
    var env = Env.init(std.testing.allocator, .{});
    defer env.deinit();

    try env.set("A", "1");
    try env.set("B", "2");
    env.clear();
    try std.testing.expectEqual(@as(usize, 0), env.count());
}

test "Env keys" {
    var env = Env.init(std.testing.allocator, .{});
    defer env.deinit();

    try env.set("C", "3");
    try env.set("A", "1");
    try env.set("B", "2");

    const k = env.keys();
    try std.testing.expectEqual(@as(usize, 3), k.len);
    try std.testing.expectEqualStrings("C", k[0]);
    try std.testing.expectEqualStrings("A", k[1]);
    try std.testing.expectEqualStrings("B", k[2]);
}

test "Env merge" {
    var env1 = Env.init(std.testing.allocator, .{});
    defer env1.deinit();
    try env1.set("A", "1");
    try env1.set("B", "2");

    var env2 = Env.init(std.testing.allocator, .{});
    defer env2.deinit();
    try env2.set("B", "override");
    try env2.set("C", "3");

    try env1.merge(&env2);
    try std.testing.expectEqualStrings("1", env1.get("A").?);
    try std.testing.expectEqualStrings("override", env1.get("B").?);
    try std.testing.expectEqualStrings("3", env1.get("C").?);
}

test "Env clone" {
    var env = Env.init(std.testing.allocator, .{});
    defer env.deinit();
    try env.set("KEY", "value");

    var cloned = try env.clone();
    defer cloned.deinit();

    try std.testing.expectEqualStrings("value", cloned.get("KEY").?);
    try std.testing.expect(env.contains("KEY"));
}

test "Env parseString" {
    var env = Env.init(std.testing.allocator, .{});
    defer env.deinit();

    try env.parseString("HOST=localhost\nPORT=8080\n");
    try std.testing.expectEqualStrings("localhost", env.get("HOST").?);
    try std.testing.expectEqualStrings("8080", env.get("PORT").?);
}

test "Env serialize" {
    var env = Env.init(std.testing.allocator, .{});
    defer env.deinit();
    try env.set("KEY", "value");

    const result = try env.serialize();
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "KEY=value") != null);
}

test "Env serialize respects sortKeys" {
    var env = Env.init(std.testing.allocator, .{ .sortKeys = true });
    defer env.deinit();
    try env.set("Z_KEY", "last");
    try env.set("A_KEY", "first");

    const result = try env.serialize();
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("A_KEY=first\nZ_KEY=last\n", result);
}

test "Env distinguishes missing, empty, and present" {
    var env = Env.init(std.testing.allocator, .{});
    defer env.deinit();

    try env.parseString("EMPTY=\nPRESENT=value\n");

    try std.testing.expect(env.get("MISSING") == null);
    try std.testing.expect(!env.contains("MISSING"));

    const empty = env.get("EMPTY");
    try std.testing.expect(empty != null);
    try std.testing.expectEqualStrings("", empty.?);
    try std.testing.expect(env.contains("EMPTY"));

    try std.testing.expectEqualStrings("value", env.get("PRESENT").?);
}

test "Env set overwrites deterministically" {
    var env = Env.init(std.testing.allocator, .{});
    defer env.deinit();

    try env.set("KEY", "first");
    try env.set("KEY", "second");
    try env.set("KEY", "third");
    try std.testing.expectEqualStrings("third", env.get("KEY").?);
    try std.testing.expectEqual(@as(usize, 1), env.count());
    try std.testing.expectEqualStrings("KEY", env.keys()[0]);
}

test "Env tryGet distinguishes missing from invalid" {
    var env = Env.init(std.testing.allocator, .{});
    defer env.deinit();

    try env.set("PORT", "8080");
    try env.set("BAD_INT", "notanint");
    try env.set("FLAG", "yes");
    try env.set("BAD_BOOL", "maybe");

    try std.testing.expectEqual(@as(?u16, null), try env.tryGetInt(u16, "MISSING"));
    try std.testing.expectEqual(@as(u16, 8080), (try env.tryGetInt(u16, "PORT")).?);
    try std.testing.expectError(error.TypeMismatch, env.tryGetInt(u16, "BAD_INT"));

    try std.testing.expectEqual(@as(?bool, null), try env.tryGetBool("MISSING"));
    try std.testing.expect((try env.tryGetBool("FLAG")).?);
    try std.testing.expectError(error.TypeMismatch, env.tryGetBool("BAD_BOOL"));

    try std.testing.expectEqual(@as(?f64, null), try env.tryGetFloat(f64, "MISSING"));
    try std.testing.expectError(error.TypeMismatch, env.tryGetFloat(f64, "BAD_INT"));
}

test "Env tryGetEnum distinguishes missing from invalid" {
    const Mode = enum { debug, release };
    var env = Env.init(std.testing.allocator, .{});
    defer env.deinit();

    try env.set("MODE", "release");
    try env.set("BAD_MODE", "prod");

    try std.testing.expectEqual(Mode.release, (try env.tryGetEnum(Mode, "MODE")).?);
    try std.testing.expectEqual(@as(?Mode, null), try env.tryGetEnum(Mode, "MISSING"));
    try std.testing.expectError(error.TypeMismatch, env.tryGetEnum(Mode, "BAD_MODE"));
}

test "Env defaults apply to missing, not to invalid" {
    var env = Env.init(std.testing.allocator, .{});
    defer env.deinit();

    try env.set("BAD_INT", "abc");
    try std.testing.expectEqualStrings("3000", env.getWithFallback("MISSING", "3000"));
    try std.testing.expectEqualStrings("abc", env.getWithFallback("BAD_INT", "3000"));
    try std.testing.expectEqual(@as(?u16, null), env.getInt(u16, "BAD_INT"));
}

test "Env iterator borrows without allocation" {
    var env = Env.init(std.testing.allocator, .{});
    defer env.deinit();
    try env.set("A", "1");
    try env.set("B", "2");

    var it = env.iterator();
    defer it.deinit();
    var seen: usize = 0;
    while (it.next()) |_| seen += 1;
    try std.testing.expectEqual(@as(usize, 2), seen);
}

test "Env handles long and unicode values" {
    var env = Env.init(std.testing.allocator, .{});
    defer env.deinit();

    const long = try std.testing.allocator.alloc(u8, 8192);
    defer std.testing.allocator.free(long);
    @memset(long, 'x');
    try env.set("ENV_ZIG_TEST_LONG", long);
    try std.testing.expectEqualStrings(long, env.get("ENV_ZIG_TEST_LONG").?);

    try env.set("ENV_ZIG_TEST_UNICODE", "héllo wörld ✓ 日本語");
    try std.testing.expectEqualStrings("héllo wörld ✓ 日本語", env.get("ENV_ZIG_TEST_UNICODE").?);
}

test "Env validate returns owned slice" {
    var env = Env.init(std.testing.allocator, .{});
    defer env.deinit();
    try env.set("PORT", "8080");

    const s = schemaMod.Schema.init(&.{
        .{ .key = "PORT", .required = true },
        .{ .key = "MISSING_REQ", .required = true },
    });
    const errs = try env.validate(std.testing.allocator, s);
    defer std.testing.allocator.free(errs);
    try std.testing.expectEqual(@as(usize, 1), errs.len);
    try std.testing.expectEqualStrings("MISSING_REQ", errs[0].key);
}

test "Env generic getValue" {
    const Mode = enum { debug, release };
    var env = Env.init(std.testing.allocator, .{});
    defer env.deinit();
    try env.set("PORT", "8080");
    try env.set("FLAG", "true");
    try env.set("MODE", "release");
    try env.set("NAME", "app");

    try std.testing.expectEqual(@as(u16, 8080), env.getValue(u16, "PORT").?);
    try std.testing.expect(env.getValue(bool, "FLAG").?);
    try std.testing.expectEqual(Mode.release, env.getValue(Mode, "MODE").?);
    try std.testing.expectEqualStrings("app", env.getValue([]const u8, "NAME").?);
    try std.testing.expectEqual(@as(?u16, null), env.getValue(u16, "MISSING"));
    try std.testing.expectEqual(@as(u16, 8080), try env.requireValue(u16, "PORT"));
    try std.testing.expectError(error.MissingRequired, env.requireValue(u16, "MISSING"));
    try std.testing.expectEqual(@as(u16, 9999), env.getValueOrDefault(u16, "MISSING", 9999));
}

test "Env getList returns owned strings" {
    var env = Env.init(std.testing.allocator, .{});
    defer env.deinit();
    try env.set("HOSTS", "a, b ,c");

    const list = env.getList(std.testing.allocator, "HOSTS", ',').?;
    defer {
        for (list) |item| std.testing.allocator.free(item);
        std.testing.allocator.free(list);
    }
    try std.testing.expectEqual(@as(usize, 3), list.len);
    try std.testing.expectEqualStrings("a", list[0]);
    try std.testing.expectEqualStrings("b", list[1]);
    try std.testing.expectEqualStrings("c", list[2]);
    try std.testing.expect(env.getList(std.testing.allocator, "MISSING", ',') == null);
}

test "Env rejects invalid keys and NUL values" {
    var env = Env.init(std.testing.allocator, .{});
    defer env.deinit();
    try std.testing.expectError(error.InvalidKey, env.set("123BAD", "v"));
    try std.testing.expectError(error.InvalidKey, env.set("", "v"));
    try std.testing.expectError(error.InvalidValue, env.set("OK_KEY", "a\x00b"));
}

test "Env round-trip parse serialize parse" {
    var env = Env.init(std.testing.allocator, .{});
    defer env.deinit();
    try env.parseString("A=hello world\nB=a=b\nC=\"q # not comment\"\nEMPTY=\nUNI=héllo ✓\n");
    const ser = try env.serialize();
    defer std.testing.allocator.free(ser);
    var env2 = Env.init(std.testing.allocator, .{});
    defer env2.deinit();
    try env2.parseString(ser);
    try std.testing.expectEqualStrings(env.get("A").?, env2.get("A").?);
    try std.testing.expectEqualStrings(env.get("B").?, env2.get("B").?);
    try std.testing.expectEqualStrings(env.get("C").?, env2.get("C").?);
    try std.testing.expectEqualStrings("", env2.get("EMPTY").?);
    try std.testing.expectEqualStrings(env.get("UNI").?, env2.get("UNI").?);
}
