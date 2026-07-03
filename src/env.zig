const std = @import("std");
const parser_mod = @import("parser.zig");
const config_mod = @import("config.zig");
const interpolation_mod = @import("interpolation.zig");
const serializer_mod = @import("serializer.zig");
const writer_mod = @import("writer.zig");
const cache_mod = @import("cache.zig");
const iterator_mod = @import("iterator.zig");
const validator_mod = @import("validator.zig");
const schema_mod = @import("schema.zig");
const errors = @import("errors.zig");

pub const Config = config_mod.Config;
pub const ValidationError = validator_mod.ValidationError;
pub const schema = schema_mod;
pub const validator = validator_mod;

/// The main environment store.
/// Owns all allocated memory. Call `deinit` to free resources.
pub const Env = struct {
    allocator: std.mem.Allocator,
    entries: std.StringHashMap([]const u8),
    insertion_order: std.ArrayList([]const u8),
    config: Config,
    cache: cache_mod.Cache,

    /// Create a new empty Env.
    pub fn init(allocator: std.mem.Allocator, cfg: Config) Env {
        return .{
            .allocator = allocator,
            .entries = std.StringHashMap([]const u8).init(allocator),
            .insertion_order = .empty,
            .config = cfg,
            .cache = cache_mod.Cache.init(allocator),
        };
    }

    /// Free all resources.
    pub fn deinit(self: *Env) void {
        self.cache.deinit();
        // Keys are shared between entries and insertion_order.
        // Free values from entries, then free keys from insertion_order only.
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.entries.deinit();
        for (self.insertion_order.items) |key| {
            self.allocator.free(key);
        }
        self.insertion_order.deinit(self.allocator);
    }

    /// Load and parse a .env file.
    pub fn load(self: *Env, path: []const u8) !void {
        const dir = std.Io.Dir.cwd();
        var io_threaded: std.Io.Threaded = .init_single_threaded;
        const io = io_threaded.io();

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
        var result = try parser_mod.parse(self.allocator, source, .{
            .config = self.config,
        });
        defer result.deinit(self.allocator);

        for (result.entries.items) |entry| {
            if (self.config.override or !self.entries.contains(entry.key)) {
                const existing = self.entries.fetchRemove(entry.key);
                if (existing) |kv| {
                    self.allocator.free(kv.key);
                    self.allocator.free(kv.value);
                }

                const owned_key = try self.allocator.dupe(u8, entry.key);
                const owned_value = try self.allocator.dupe(u8, entry.value);
                try self.entries.put(owned_key, owned_value);
                try self.insertion_order.append(self.allocator, owned_key);
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
        const owned_value = try self.allocator.dupe(u8, value);

        const existing = self.entries.fetchRemove(key);
        if (existing) |kv| {
            self.allocator.free(kv.value);
            try self.entries.put(kv.key, owned_value);
        } else {
            const owned_key = try self.allocator.dupe(u8, key);
            try self.insertion_order.append(self.allocator, owned_key);
            try self.entries.put(owned_key, owned_value);
        }
    }

    /// Get a value by key.
    pub fn get(self: *const Env, key: []const u8) ?[]const u8 {
        return self.entries.get(key);
    }

    /// Get a string value (same as get).
    pub fn getString(self: *const Env, key: []const u8) ?[]const u8 {
        return self.get(key);
    }

    /// Get a boolean value. Accepts: true/false/yes/no/1/0/on/off.
    pub fn getBool(self: *const Env, key: []const u8) ?bool {
        const val = self.get(key) orelse return null;
        const v = std.mem.trim(u8, val, " \t\r\n");
        if (std.mem.eql(u8, v, "true") or std.mem.eql(u8, v, "yes") or
            std.mem.eql(u8, v, "1") or std.mem.eql(u8, v, "on"))
            return true;
        if (std.mem.eql(u8, v, "false") or std.mem.eql(u8, v, "no") or
            std.mem.eql(u8, v, "0") or std.mem.eql(u8, v, "off"))
            return false;
        return null;
    }

    /// Get an integer value of the specified type.
    pub fn getInt(self: *const Env, comptime T: type, key: []const u8) ?T {
        const val = self.get(key) orelse return null;
        return std.fmt.parseInt(T, std.mem.trim(u8, val, " \t\r\n"), 10) catch null;
    }

    /// Get a float value.
    pub fn getFloat(self: *const Env, comptime T: type, key: []const u8) ?T {
        const val = self.get(key) orelse return null;
        return std.fmt.parseFloat(T, std.mem.trim(u8, val, " \t\r\n")) catch null;
    }

    /// Get an enum value from a string.
    pub fn getEnum(self: *const Env, comptime E: type, key: []const u8) ?E {
        const val = self.get(key) orelse return null;
        const trimmed = std.mem.trim(u8, val, " \t\r\n");
        return std.meta.stringToEnum(E, trimmed);
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
            for (self.insertion_order.items, 0..) |k, i| {
                if (std.mem.eql(u8, k, key)) {
                    _ = self.insertion_order.orderedRemove(i);
                    self.allocator.free(k);
                    break;
                }
            }
            return true;
        }
        return false;
    }

    /// Clear all entries.
    pub fn clear(self: *Env) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.entries.clearRetainingCapacity();
        for (self.insertion_order.items) |key| {
            self.allocator.free(key);
        }
        self.insertion_order.clearRetainingCapacity();
    }

    /// Get the number of entries.
    pub fn count(self: *const Env) usize {
        return self.entries.count();
    }

    /// Get all keys in insertion order.
    pub fn keys(self: *const Env) []const []const u8 {
        return self.insertion_order.items;
    }

    /// Create an iterator over entries.
    pub fn iterator(self: *const Env) iterator_mod.Iterator {
        var entries = self.allocator.alloc(iterator_mod.Iterator.Entry, self.insertion_order.items.len) catch return .init(&.{});
        for (self.insertion_order.items, 0..) |key, i| {
            entries[i] = .{
                .key = key,
                .value = self.entries.get(key) orelse "",
            };
        }
        return iterator_mod.Iterator.init(entries);
    }

    /// Serialize entries to .env format.
    pub fn serialize(self: *const Env) ![]const u8 {
        var entries: std.ArrayList(serializer_mod.SerEntry) = .empty;
        for (self.insertion_order.items) |key| {
            if (self.entries.get(key)) |val| {
                try entries.append(self.allocator, .{ .key = key, .value = val });
            }
        }
        defer entries.deinit(self.allocator);
        return serializer_mod.Serializer.serialize(self.allocator, entries.items, self.config);
    }

    /// Write entries to a file.
    pub fn save(self: *const Env, path: []const u8) !void {
        var entries: std.ArrayList(serializer_mod.SerEntry) = .empty;
        for (self.insertion_order.items) |key| {
            if (self.entries.get(key)) |val| {
                try entries.append(self.allocator, .{ .key = key, .value = val });
            }
        }
        defer entries.deinit(self.allocator);
        try writer_mod.Writer.writeToFile(self.allocator, path, entries.items, self.config);
    }

    /// Clone this Env.
    pub fn clone(self: *const Env) !Env {
        var new_env = Env.init(self.allocator, self.config);

        for (self.insertion_order.items) |key| {
            if (self.entries.get(key)) |val| {
                const owned_key = try self.allocator.dupe(u8, key);
                const owned_value = try self.allocator.dupe(u8, val);
                try new_env.entries.put(owned_key, owned_value);
                try new_env.insertion_order.append(self.allocator, owned_key);
            }
        }

        return new_env;
    }

    /// Merge another Env into this one. Entries from other override existing ones.
    pub fn merge(self: *Env, other: *const Env) !void {
        for (other.insertion_order.items) |key| {
            if (other.entries.get(key)) |val| {
                try self.set(key, val);
            }
        }
    }

    /// Validate entries against a schema.
    pub fn validate(self: *const Env, s: schema_mod.Schema) []ValidationError {
        return s.validate(&self.entries);
    }

    fn resolveInterpolation(self: *Env) !void {
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            const val = entry.value_ptr.*;
            if (std.mem.indexOf(u8, val, "${") != null or
                (val.len > 0 and val[0] == '$'))
            {
                const resolved = interpolation_mod.interpolate(
                    self.allocator,
                    val,
                    &self.entries,
                    self.config.max_interpolation_depth,
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
