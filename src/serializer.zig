const std = @import("std");
const config = @import("config.zig");

const Config = config.Config;

/// A key-value entry for serialization.
pub const SerEntry = struct {
    key: []const u8,
    value: []const u8,
};

/// Serialize key-value pairs back to .env format.
pub const Serializer = struct {
    /// Serialize entries to a .env formatted string.
    pub fn serialize(
        allocator: std.mem.Allocator,
        entries: []const SerEntry,
        cfg: Config,
    ) ![]const u8 {
        var result: std.ArrayList(u8) = .empty;
        errdefer result.deinit(allocator);

        for (entries) |entry| {
            try result.appendSlice(allocator, entry.key);
            try result.append(allocator, '=');
            if (cfg.quote_spaces and
                (std.mem.indexOf(u8, entry.value, " ") != null or
                    std.mem.indexOf(u8, entry.value, "#") != null or
                    entry.value.len == 0))
            {
                try result.append(allocator, '"');
                for (entry.value) |ch| {
                    switch (ch) {
                        '"' => try result.appendSlice(allocator, "\\\""),
                        '\\' => try result.appendSlice(allocator, "\\\\"),
                        '\n' => try result.appendSlice(allocator, "\\n"),
                        '\r' => try result.appendSlice(allocator, "\\r"),
                        '\t' => try result.appendSlice(allocator, "\\t"),
                        else => try result.append(allocator, ch),
                    }
                }
                try result.append(allocator, '"');
            } else {
                try result.appendSlice(allocator, entry.value);
            }
            try result.append(allocator, '\n');
        }

        return try result.toOwnedSlice(allocator);
    }

    /// Serialize with sorting and pretty formatting.
    pub fn serializeSorted(
        allocator: std.mem.Allocator,
        entries: []const SerEntry,
        cfg: Config,
    ) ![]const u8 {
        var sorted: std.ArrayList(SerEntry) = .empty;
        defer sorted.deinit(allocator);

        for (entries) |entry| {
            try sorted.append(allocator, entry);
        }

        std.mem.sort(
            SerEntry,
            sorted.items,
            {},
            struct {
                fn lessThan(_: void, a: SerEntry, b: SerEntry) bool {
                    return std.mem.lessThan(u8, a.key, b.key);
                }
            }.lessThan,
        );

        return serialize(allocator, sorted.items, cfg);
    }
};

test "serialize basic" {
    const entries = [_]SerEntry{
        .{ .key = "KEY1", .value = "value1" },
        .{ .key = "KEY2", .value = "value2" },
    };
    const result = try Serializer.serialize(std.testing.allocator, &entries, .{});
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("KEY1=value1\nKEY2=value2\n", result);
}

test "serialize with spaces" {
    const entries = [_]SerEntry{
        .{ .key = "KEY", .value = "hello world" },
    };
    const result = try Serializer.serialize(std.testing.allocator, &entries, .{ .quote_spaces = true });
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("KEY=\"hello world\"\n", result);
}

test "serialize empty value" {
    const entries = [_]SerEntry{
        .{ .key = "KEY", .value = "" },
    };
    const result = try Serializer.serialize(std.testing.allocator, &entries, .{ .quote_spaces = true });
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("KEY=\"\"\n", result);
}

test "serialize sorted" {
    const entries = [_]SerEntry{
        .{ .key = "Z", .value = "1" },
        .{ .key = "A", .value = "2" },
        .{ .key = "M", .value = "3" },
    };
    const result = try Serializer.serializeSorted(std.testing.allocator, &entries, .{});
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("A=2\nM=3\nZ=1\n", result);
}
