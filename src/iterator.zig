const std = @import("std");

/// An iterator over key-value pairs in an env store.
pub const Iterator = struct {
    entries: []const Entry,
    index: usize,

    pub const Entry = struct {
        key: []const u8,
        value: []const u8,
    };

    pub fn init(entries: []const Entry) Iterator {
        return .{
            .entries = entries,
            .index = 0,
        };
    }

    pub fn next(self: *Iterator) ?Entry {
        if (self.index >= self.entries.len) return null;
        const entry = self.entries[self.index];
        self.index += 1;
        return entry;
    }

    pub fn peek(self: *const Iterator) ?Entry {
        if (self.index >= self.entries.len) return null;
        return self.entries[self.index];
    }

    pub fn reset(self: *Iterator) void {
        self.index = 0;
    }

    pub fn skip(self: *Iterator, count: usize) void {
        self.index = @min(self.index + count, self.entries.len);
    }

    pub fn remaining(self: *const Iterator) usize {
        return self.entries.len - self.index;
    }

    pub fn collect(
        self: *Iterator,
        allocator: std.mem.Allocator,
        predicate: *const fn (Entry) bool,
    ) ![]Entry {
        var result: std.ArrayListUnmanaged(Entry) = .empty;
        errdefer result.deinit(allocator);

        while (self.next()) |entry| {
            if (predicate(entry)) {
                try result.append(allocator, entry);
            }
        }

        return try result.toOwnedSlice(allocator);
    }
};

test "Iterator basic" {
    const entries = [_]Iterator.Entry{
        .{ .key = "A", .value = "1" },
        .{ .key = "B", .value = "2" },
        .{ .key = "C", .value = "3" },
    };

    var it = Iterator.init(&entries);
    try std.testing.expectEqual(@as(?Iterator.Entry, .{ .key = "A", .value = "1" }), it.next());
    try std.testing.expectEqual(@as(?Iterator.Entry, .{ .key = "B", .value = "2" }), it.next());
    try std.testing.expectEqual(@as(?Iterator.Entry, .{ .key = "C", .value = "3" }), it.next());
    try std.testing.expectEqual(@as(?Iterator.Entry, null), it.next());
}

test "Iterator peek" {
    const entries = [_]Iterator.Entry{
        .{ .key = "A", .value = "1" },
    };

    var it = Iterator.init(&entries);
    try std.testing.expectEqual(@as(?Iterator.Entry, .{ .key = "A", .value = "1" }), it.peek());
    try std.testing.expectEqual(@as(?Iterator.Entry, .{ .key = "A", .value = "1" }), it.peek());
    _ = it.next();
    try std.testing.expectEqual(@as(?Iterator.Entry, null), it.peek());
}

test "Iterator skip and remaining" {
    const entries = [_]Iterator.Entry{
        .{ .key = "A", .value = "1" },
        .{ .key = "B", .value = "2" },
        .{ .key = "C", .value = "3" },
    };

    var it = Iterator.init(&entries);
    try std.testing.expectEqual(@as(usize, 3), it.remaining());
    it.skip(2);
    try std.testing.expectEqual(@as(usize, 1), it.remaining());
    try std.testing.expectEqual(@as(?Iterator.Entry, .{ .key = "C", .value = "3" }), it.next());
}
