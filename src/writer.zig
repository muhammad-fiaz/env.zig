const std = @import("std");
const config = @import("config.zig");
const serializerMod = @import("serializer.zig");
const Serializer = serializerMod.Serializer;
const SerEntry = serializerMod.SerEntry;
const helpers = @import("internal/helpers.zig");

const Config = config.Config;

/// Write `.env` entries to a file or buffer.
/// Single serialization implementation: buffer output calls
/// `Serializer.serialize` with a fixed-buffer allocator, guaranteeing
/// byte-for-byte equivalence.
pub const Writer = struct {
    /// Write entries to a file at the given path.
    pub fn writeToFile(
        allocator: std.mem.Allocator,
        path: []const u8,
        entries: []const SerEntry,
        cfg: Config,
    ) !void {
        for (entries) |entry| {
            if (!helpers.isValidKey(entry.key)) return error.InvalidKey;
            if (std.mem.indexOfScalar(u8, entry.value, 0) != null) return error.InvalidValue;
        }
        const content = if (cfg.sortKeys)
            try Serializer.serializeSorted(allocator, entries, cfg)
        else
            try Serializer.serialize(allocator, entries, cfg);
        defer allocator.free(content);

        const dir = std.Io.Dir.cwd();
        var ioThreaded: std.Io.Threaded = .init_single_threaded;
        const io = ioThreaded.io();

        dir.writeFile(io, .{
            .sub_path = path,
            .data = content,
        }) catch |err| switch (err) {
            error.FileNotFound => return error.FileNotFound,
            error.AccessDenied, error.PermissionDenied => return error.PermissionDenied,
            else => return error.IoError,
        };
    }

    /// Write entries to `buf`, returning the written slice.
    /// Byte-identical to `Serializer.serialize`. `error.NoSpaceLeft`
    /// claims no partial success; `error.InvalidKey`/`error.InvalidValue`
    /// for non-`.env` keys or NUL values.
    pub fn writeToBuffer(buf: []u8, entries: []const SerEntry, cfg: Config) ![]const u8 {
        var fba = std.heap.FixedBufferAllocator.init(buf);
        const content = Serializer.serialize(fba.allocator(), entries, cfg) catch |err| switch (err) {
            error.OutOfMemory => return error.NoSpaceLeft,
            else => |e| return e,
        };
        return buf[0..content.len];
    }
};

test "writeToBuffer equals serializer" {
    const entries = [_]SerEntry{
        .{ .key = "KEY1", .value = "value1" },
        .{ .key = "MSG", .value = "hello world # hi" },
        .{ .key = "EMPTY", .value = "" },
    };
    const cfg: Config = .{};
    var buf: [256]u8 = undefined;
    const written = try Writer.writeToBuffer(&buf, &entries, cfg);
    const expected = try Serializer.serialize(std.testing.allocator, &entries, cfg);
    defer std.testing.allocator.free(expected);
    try std.testing.expectEqualStrings(expected, written);
}

test "writeToBuffer exact fit and one short" {
    const entries = [_]SerEntry{.{ .key = "A", .value = "1" }};
    var exact: [4]u8 = undefined; // "A=1\n"
    try std.testing.expectEqualStrings("A=1\n", try Writer.writeToBuffer(&exact, &entries, .{}));
    var short: [3]u8 = undefined;
    try std.testing.expectError(error.NoSpaceLeft, Writer.writeToBuffer(&short, &entries, .{}));
    var empty: [0]u8 = undefined;
    try std.testing.expectError(error.NoSpaceLeft, Writer.writeToBuffer(&empty, &entries, .{}));
}
