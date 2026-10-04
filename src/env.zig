const std = @import("std");
const builtin = @import("builtin");
const parserMod = @import("parser.zig");
const configMod = @import("config.zig");
const interpolationMod = @import("interpolation.zig");
const serializerMod = @import("serializer.zig");
const writerMod = @import("writer.zig");
const cacheMod = @import("cache.zig");
const iteratorMod = @import("iterator.zig");
const validatorMod = @import("validator.zig");
const schemaMod = @import("schema.zig");
const errors = @import("errors.zig");
const osEnvMod = @import("os_env.zig");

pub const Config = configMod.Config;
pub const ValidationError = validatorMod.ValidationError;
pub const schema = schemaMod;
pub const validator = validatorMod;
pub const OsEnv = osEnvMod.OsEnv;
pub const Scope = osEnvMod.Scope;
pub const Snapshot = osEnvMod.Snapshot;
pub const osEnv = osEnvMod;

/// The main environment store.
/// Owns all allocated memory. Call `deinit` to free resources.
pub const Env = struct {
    allocator: std.mem.Allocator,
    entries: std.StringHashMap([]const u8),
    insertionOrder: std.ArrayList([]const u8),
    config: Config,
    cache: cacheMod.Cache,

    /// Create a new empty Env.
    pub fn init(allocator: std.mem.Allocator, cfg: Config) Env {
        return .{
            .allocator = allocator,
            .entries = std.StringHashMap([]const u8).init(allocator),
            .insertionOrder = .empty,
            .config = cfg,
            .cache = cacheMod.Cache.init(allocator),
        };
    }

    /// Free all resources.
    pub fn deinit(self: *Env) void {
        self.cache.deinit();
        // Keys are shared between entries and insertionOrder.
        // Free values from entries, then free keys from insertionOrder only.
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
    pub fn load(self: *Env, path: []const u8) !void {
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
            else => return error.IoError,
        };
        defer self.allocator.free(content);

        try self.parseString(content);
    }

    /// Parse a .env string and add entries.
    pub fn parseString(self: *Env, source: []const u8) !void {
        var result = try parserMod.parse(self.allocator, source, .{
            .config = self.config,
        });
        defer result.deinit(self.allocator);

        for (result.entries.items) |entry| {
            if (self.config.override or !self.entries.contains(entry.key)) {
                const existing = self.entries.fetchRemove(entry.key);
                if (existing) |kv| {
                    // Reuse existing key pointer to keep insertionOrder stable
                    self.allocator.free(kv.value);
                    const ownedValue = try self.allocator.dupe(u8, entry.value);
                    try self.entries.put(kv.key, ownedValue);
                } else {
                    const ownedKey = try self.allocator.dupe(u8, entry.key);
                    const ownedValue = try self.allocator.dupe(u8, entry.value);
                    try self.entries.put(ownedKey, ownedValue);
                    try self.insertionOrder.append(self.allocator, ownedKey);
                }
            }
        }

        if (self.config.interpolate) {
            try self.resolveInterpolation();
        }
    }

    /// Load multiple .env files in order (later files override earlier ones).
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

    /// Reload the environment from the last loaded file.
    pub fn reload(self: *Env, path: []const u8) !void {
        self.clear();
        try self.load(path);
    }

    /// Set a key-value pair.
    pub fn set(self: *Env, key: []const u8, value: []const u8) !void {
        const ownedValue = try self.allocator.dupe(u8, value);

        const existing = self.entries.fetchRemove(key);
        if (existing) |kv| {
            self.allocator.free(kv.value);
            try self.entries.put(kv.key, ownedValue);
        } else {
            const ownedKey = try self.allocator.dupe(u8, key);
            try self.insertionOrder.append(self.allocator, ownedKey);
            try self.entries.put(ownedKey, ownedValue);
        }
        if (self.config.exportToEnv) {
            osEnvMod.OsEnv.set(key, value) catch {};
        }
    }

    /// Set and also sync to OS environment (always, regardless of config).
    pub fn setOs(self: *Env, key: []const u8, value: []const u8) !void {
        try self.set(key, value);
        try osEnvMod.OsEnv.set(key, value);
    }

    /// Get a value by key.
    pub fn get(self: *const Env, key: []const u8) ?[]const u8 {
        return self.entries.get(key);
    }

    /// Get a string value (same as get).
    pub fn getString(self: *const Env, key: []const u8) ?[]const u8 {
        return self.get(key);
    }

    /// Get a boolean value. Accepts: true/false/yes/no/1/0/on/off (case-insensitive).
    /// Returns null when the key is missing or the value is malformed.
    pub fn getBool(self: *const Env, key: []const u8) ?bool {
        const val = self.get(key) orelse return null;
        return parseBoolValue(val);
    }

    /// Get a boolean value, distinguishing missing keys from malformed values.
    /// Returns null when the key is missing; error.TypeMismatch when present but invalid.
    pub fn tryGetBool(self: *const Env, key: []const u8) !?bool {
        const val = self.get(key) orelse return null;
        return parseBoolValue(val) orelse error.TypeMismatch;
    }

    /// Get an integer value of the specified type.
    /// Returns null when the key is missing or the value is malformed.
    pub fn getInt(self: *const Env, comptime T: type, key: []const u8) ?T {
        const val = self.get(key) orelse return null;
        return std.fmt.parseInt(T, std.mem.trim(u8, val, " \t\r\n"), 10) catch null;
    }

    /// Get an integer value, distinguishing missing keys from malformed values.
    /// Returns null when the key is missing; error.TypeMismatch when present but invalid.
    pub fn tryGetInt(self: *const Env, comptime T: type, key: []const u8) !?T {
        const val = self.get(key) orelse return null;
        return std.fmt.parseInt(T, std.mem.trim(u8, val, " \t\r\n"), 10) catch error.TypeMismatch;
    }

    /// Get a float value.
    /// Returns null when the key is missing or the value is malformed.
    pub fn getFloat(self: *const Env, comptime T: type, key: []const u8) ?T {
        const val = self.get(key) orelse return null;
        return std.fmt.parseFloat(T, std.mem.trim(u8, val, " \t\r\n")) catch null;
    }

    /// Get a float value, distinguishing missing keys from malformed values.
    /// Returns null when the key is missing; error.TypeMismatch when present but invalid.
    pub fn tryGetFloat(self: *const Env, comptime T: type, key: []const u8) !?T {
        const val = self.get(key) orelse return null;
        return std.fmt.parseFloat(T, std.mem.trim(u8, val, " \t\r\n")) catch error.TypeMismatch;
    }

    /// Get an enum value from a string.
    /// Returns null when the key is missing or the value does not match.
    pub fn getEnum(self: *const Env, comptime E: type, key: []const u8) ?E {
        const val = self.get(key) orelse return null;
        const trimmed = std.mem.trim(u8, val, " \t\r\n");
        return std.meta.stringToEnum(E, trimmed);
    }

    /// Get an enum value, distinguishing missing keys from unmatched values.
    /// Returns null when the key is missing; error.TypeMismatch when present but invalid.
    pub fn tryGetEnum(self: *const Env, comptime E: type, key: []const u8) !?E {
        const val = self.get(key) orelse return null;
        const trimmed = std.mem.trim(u8, val, " \t\r\n");
        return std.meta.stringToEnum(E, trimmed) orelse error.TypeMismatch;
    }

    fn parseBoolValue(val: []const u8) ?bool {
        const v = std.mem.trim(u8, val, " \t\r\n");
        // Case-insensitive compare via lowercasing into small stack buffer
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

    /// Get a list of values by splitting on a delimiter.
    pub fn getList(self: *const Env, allocator: std.mem.Allocator, key: []const u8, delimiter: u8) ?[][]const u8 {
        const val = self.get(key) orelse return null;
        var result: std.ArrayList([]const u8) = .empty;
        var it = std.mem.splitScalar(u8, val, delimiter);
        while (it.next()) |item| {
            const trimmed = std.mem.trim(u8, item, " \t\r\n");
            if (trimmed.len > 0) {
                result.append(allocator, trimmed) catch return null;
            }
        }
        return result.toOwnedSlice(allocator) catch null;
    }

    /// Check if a key exists.
    pub fn contains(self: *const Env, key: []const u8) bool {
        return self.entries.contains(key);
    }

    /// Remove a key-value pair.
    pub fn remove(self: *Env, key: []const u8) bool {
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
                osEnvMod.OsEnv.unset(key) catch {};
            }
            return true;
        }
        return false;
    }

    /// Remove from Env and OS env.
    pub fn unsetOs(self: *Env, key: []const u8) bool {
        const r = self.remove(key);
        osEnvMod.OsEnv.unset(key) catch {};
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

    /// Get the number of entries.
    pub fn count(self: *const Env) usize {
        return self.entries.count();
    }

    /// Get all keys in insertion order.
    pub fn keys(self: *const Env) []const []const u8 {
        return self.insertionOrder.items;
    }

    /// Create an iterator over entries.
    /// The returned iterator owns its entries slice; call `deinit` when done.
    pub fn iterator(self: *const Env) iteratorMod.Iterator {
        const entries = self.allocator.alloc(iteratorMod.Iterator.Entry, self.insertionOrder.items.len) catch return .init(&.{});
        for (self.insertionOrder.items, 0..) |key, i| {
            entries[i] = .{
                .key = key,
                .value = self.entries.get(key) orelse "",
            };
        }
        return .{
            .entries = entries,
            .index = 0,
            .allocator = self.allocator,
        };
    }

    /// Serialize entries to .env format.
    /// Honors `config.sortKeys` (sorted via `Serializer.serializeSorted`).
    pub fn serialize(self: *const Env) ![]const u8 {
        var entries: std.ArrayList(serializerMod.SerEntry) = .empty;
        for (self.insertionOrder.items) |key| {
            if (self.entries.get(key)) |val| {
                try entries.append(self.allocator, .{ .key = key, .value = val });
            }
        }
        defer entries.deinit(self.allocator);
        if (self.config.sortKeys) {
            return serializerMod.Serializer.serializeSorted(self.allocator, entries.items, self.config);
        }
        return serializerMod.Serializer.serialize(self.allocator, entries.items, self.config);
    }

    /// Write entries to a file.
    pub fn save(self: *const Env, path: []const u8) !void {
        var entries: std.ArrayList(serializerMod.SerEntry) = .empty;
        for (self.insertionOrder.items) |key| {
            if (self.entries.get(key)) |val| {
                try entries.append(self.allocator, .{ .key = key, .value = val });
            }
        }
        defer entries.deinit(self.allocator);
        try writerMod.Writer.writeToFile(self.allocator, path, entries.items, self.config);
    }

    /// Clone this Env.
    pub fn clone(self: *const Env) !Env {
        var newEnv = Env.init(self.allocator, self.config);

        for (self.insertionOrder.items) |key| {
            if (self.entries.get(key)) |val| {
                const ownedKey = try self.allocator.dupe(u8, key);
                const ownedValue = try self.allocator.dupe(u8, val);
                try newEnv.entries.put(ownedKey, ownedValue);
                try newEnv.insertionOrder.append(self.allocator, ownedKey);
            }
        }

        return newEnv;
    }

    /// Merge another Env into this one. Entries from other override existing ones.
    pub fn merge(self: *Env, other: *const Env) !void {
        for (other.insertionOrder.items) |key| {
            if (other.entries.get(key)) |val| {
                try self.set(key, val);
            }
        }
    }

    /// Validate entries against a schema.
    /// Returns an owned slice; the caller must free it with `allocator.free`.
    pub fn validate(self: *const Env, allocator: std.mem.Allocator, s: schemaMod.Schema) ![]ValidationError {
        return s.validate(allocator, &self.entries);
    }

    // -----------------------------------------------------------------------
    // OS Environment Bridging (Windows / Linux / macOS)
    // -----------------------------------------------------------------------

    /// Load all current OS environment variables into this Env.
    /// Existing keys are overwritten if `config.override` is true.
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
                try self.set(k, v);
            }
        }
    }

    /// Load OS env vars only for keys not already present (no override).
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
            if (!self.contains(e.key_ptr.*)) try self.set(e.key_ptr.*, e.value_ptr.*);
        }
    }

    /// Load OS vars filtered by prefix, stripping prefix from keys.
    /// e.g. prefix "APP_" loads "APP_PORT" as "PORT".
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
            if (std.mem.startsWith(u8, k, prefix)) {
                const stripped = k[prefix.len..];
                if (stripped.len == 0) continue;
                if (self.config.override or !self.entries.contains(stripped)) {
                    try self.set(stripped, e.value_ptr.*);
                }
            }
        }
    }

    /// Export all Env entries to process OS environment.
    pub fn exportToOsEnv(self: *const Env) !void {
        for (self.insertionOrder.items) |k| {
            if (self.entries.get(k)) |v| try osEnvMod.OsEnv.set(k, v);
        }
    }

    /// Get value checking Env first, then OS env fallback (like shell `$VAR`).
    pub fn getOs(self: *const Env, key: []const u8) ?[]const u8 {
        return self.get(key) orelse osEnvMod.OsEnv.get(key);
    }

    /// Get OS var directly (without checking Env store).
    pub fn getOsEnvAlloc(self: *const Env, allocator: std.mem.Allocator, key: []const u8) !?[]u8 {
        _ = self;
        return try osEnvMod.OsEnv.getAlloc(allocator, key);
    }

    /// Get with fallback default (checks Env then OS then default).
    pub fn getWithFallback(self: *const Env, key: []const u8, fallback: []const u8) []const u8 {
        return self.getOs(key) orelse fallback;
    }

    /// Require a key, error if missing in both Env and OS.
    pub fn require(self: *const Env, key: []const u8) ![]const u8 {
        return self.getOs(key) orelse error.MissingRequired;
    }

    /// Get and copy OS var into Env, returning it.
    pub fn fetchOs(self: *Env, key: []const u8) !?[]const u8 {
        if (self.get(key)) |v| return v;
        const osVal = osEnvMod.OsEnv.get(key) orelse return null;
        try self.set(key, osVal);
        return self.get(key);
    }

    /// Check if key exists in either Env or OS env.
    pub fn containsOs(self: *const Env, key: []const u8) bool {
        return self.contains(key) or osEnvMod.OsEnv.exists(key);
    }

    /// Convert this Env to a `std.process.Environ.Map` for spawning children.
    /// Caller must call `map.deinit()`.
    pub fn toEnvironMap(self: *const Env, allocator: std.mem.Allocator) !std.process.Environ.Map {
        var map = std.process.Environ.Map.init(allocator);
        errdefer map.deinit();
        for (self.insertionOrder.items) |k| {
            if (self.entries.get(k)) |v| try map.put(k, v);
        }
        return map;
    }

    /// Merge OS environment into an existing `Environ.Map`.
    pub fn applyToEnvironMap(self: *const Env, map: *std.process.Environ.Map) !void {
        for (self.insertionOrder.items) |k| {
            if (self.entries.get(k)) |v| try map.put(k, v);
        }
    }

    /// Snapshot current OS environment via Env's allocator.
    pub fn snapshotOs(self: *const Env) !osEnvMod.Snapshot {
        return try osEnvMod.OsEnv.snapshot(self.allocator);
    }

    // -----------------------------------------------------------------------
    // Temporary / Scoped Env (in-memory)
    // -----------------------------------------------------------------------

    /// Scope for temporary in-memory overrides; restores on deinit.
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
                    _ = self.env.remove(key);
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
            _ = self.env.remove(key);
        }
    };

    /// Create a temporary scope for this Env.
    pub fn scope(self: *Env) EnvScope {
        return EnvScope.init(self);
    }

    /// Convenience: run `func` with temporary overrides, restoring afterwards.
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
    try std.testing.expect(env.remove("KEY"));
    try std.testing.expect(!env.contains("KEY"));
    try std.testing.expect(!env.remove("KEY"));
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

test "Env iterator owns entries and deinit frees them" {
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
