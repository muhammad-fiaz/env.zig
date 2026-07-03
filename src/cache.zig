const std = @import("std");

/// A simple cache for parsed .env values.
pub const Cache = struct {
    map: std.StringHashMap(CacheEntry),
    allocator: std.mem.Allocator,

    const CacheEntry = struct {
        value: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator) Cache {
        return .{
            .map = std.StringHashMap(CacheEntry).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Cache) void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*.value);
        }
        self.map.deinit();
    }

    /// Put a value into the cache.
    pub fn put(self: *Cache, key: []const u8, value: []const u8) !void {
        const owned_key = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(owned_key);
        const owned_value = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(owned_value);

        if (self.map.fetchRemove(key)) |kv| {
            self.allocator.free(kv.key);
            self.allocator.free(kv.value.value);
        }

        try self.map.put(owned_key, .{ .value = owned_value });
    }

    /// Get a value from the cache.
    pub fn get(self: *const Cache, key: []const u8) ?[]const u8 {
        const entry = self.map.get(key) orelse return null;
        return entry.value;
    }

    /// Check if a key exists in the cache.
    pub fn contains(self: *const Cache, key: []const u8) bool {
        return self.map.contains(key);
    }

    /// Remove a key from the cache.
    pub fn remove(self: *Cache, key: []const u8) bool {
        if (self.map.fetchRemove(key)) |kv| {
            self.allocator.free(kv.key);
            self.allocator.free(kv.value.value);
            return true;
        }
        return false;
    }

    /// Clear all entries from the cache.
    pub fn clear(self: *Cache) void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*.value);
        }
        self.map.clearRetainingCapacity();
    }

    /// Return the number of entries in the cache.
    pub fn count(self: *const Cache) usize {
        return self.map.count();
    }
};

test "Cache put and get" {
    var cache = Cache.init(std.testing.allocator);
    defer cache.deinit();

    try cache.put("KEY1", "value1");
    try cache.put("KEY2", "value2");

    try std.testing.expectEqualStrings("value1", cache.get("KEY1").?);
    try std.testing.expectEqualStrings("value2", cache.get("KEY2").?);
    try std.testing.expectEqual(@as(?[]const u8, null), cache.get("MISSING"));
}

test "Cache remove" {
    var cache = Cache.init(std.testing.allocator);
    defer cache.deinit();

    try cache.put("KEY", "value");
    try std.testing.expect(cache.remove("KEY"));
    try std.testing.expect(!cache.remove("KEY"));
    try std.testing.expectEqual(@as(?[]const u8, null), cache.get("KEY"));
}

test "Cache clear" {
    var cache = Cache.init(std.testing.allocator);
    defer cache.deinit();

    try cache.put("A", "1");
    try cache.put("B", "2");
    try std.testing.expectEqual(@as(usize, 2), cache.count());

    cache.clear();
    try std.testing.expectEqual(@as(usize, 0), cache.count());
}

test "Cache overwrite" {
    var cache = Cache.init(std.testing.allocator);
    defer cache.deinit();

    try cache.put("KEY", "old");
    try cache.put("KEY", "new");
    try std.testing.expectEqualStrings("new", cache.get("KEY").?);
    try std.testing.expectEqual(@as(usize, 1), cache.count());
}
