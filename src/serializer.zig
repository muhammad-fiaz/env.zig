const std = @import("std");
const config = @import("config.zig");
const helpers = @import("internal/helpers.zig");

const Config = config.Config;

/// A key-value entry for serialization.
pub const SerEntry = struct {
    key: []const u8,
    value: []const u8,
};

/// Serialize key-value pairs back to .env format.
/// Every value produced here parses back to an equal value.
pub const Serializer = struct {
    /// Serialize entries to a .env formatted string.
    /// Honors `cfg.sortKeys` only via `serializeSorted`; honors
    /// `cfg.trailingNewline` and `cfg.quoteSpaces`.
    /// Returns `error.InvalidValue` when a key or value contains NUL.
    pub fn serialize(
        allocator: std.mem.Allocator,
        entries: []const SerEntry,
        cfg: Config,
    ) ![]const u8 {
        for (entries) |entry| {
            if (std.mem.indexOfScalar(u8, entry.key, 0) != null) return error.InvalidValue;
            if (std.mem.indexOfScalar(u8, entry.value, 0) != null) return error.InvalidValue;
        }
        var result: std.ArrayList(u8) = .empty;
        errdefer result.deinit(allocator);

        for (entries, 0..) |entry, idx| {
            const isLast = idx + 1 == entries.len;
            try encodeEntry(allocator, &result, entry, cfg);
            if (!isLast or cfg.trailingNewline) {
                try result.append(allocator, '\n');
            }
        }

        return try result.toOwnedSlice(allocator);
    }

    /// Serialize entries sorted by key without mutating the input.
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

    /// Shared entry encoder used by `Serializer` and `Writer`.
    /// Appends `KEY[=value]` without the trailing newline.
    pub fn encodeEntry(
        allocator: std.mem.Allocator,
        out: *std.ArrayList(u8),
        entry: SerEntry,
        cfg: Config,
    ) !void {
        try out.appendSlice(allocator, entry.key);
        try out.append(allocator, '=');
        if (helpers.needsQuoting(entry.value, cfg.quoteSpaces)) {
            try out.append(allocator, '"');
            for (entry.value) |ch| {
                if (helpers.escapedForChar(ch)) |esc| {
                    try out.appendSlice(allocator, esc);
                } else {
                    try out.append(allocator, ch);
                }
            }
            try out.append(allocator, '"');
        } else {
            try out.appendSlice(allocator, entry.value);
        }
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
    const result = try Serializer.serialize(std.testing.allocator, &entries, .{ .quoteSpaces = true });
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("KEY=\"hello world\"\n", result);
}

test "serialize empty value" {
    const entries = [_]SerEntry{
        .{ .key = "KEY", .value = "" },
    };
    const result = try Serializer.serialize(std.testing.allocator, &entries, .{ .quoteSpaces = true });
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
