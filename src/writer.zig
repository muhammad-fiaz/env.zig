const std = @import("std");
const config = @import("config.zig");
const serializerMod = @import("serializer.zig");
const Serializer = serializerMod.Serializer;
const SerEntry = serializerMod.SerEntry;
const helpers = @import("internal/helpers.zig");

const Config = config.Config;

/// Write .env entries to a file or buffer.
/// Uses the same quoting rules as `Serializer` via shared helpers,
/// so both representations are identical.
pub const Writer = struct {
    /// Write entries to a file at the given path.
    /// Honors `cfg.sortKeys` (sorted output when enabled).
    /// Maps `FileNotFound`/`AccessDenied` to the library error model
    /// without collapsing unrelated I/O failures.
    pub fn writeToFile(
        allocator: std.mem.Allocator,
        path: []const u8,
        entries: []const SerEntry,
        cfg: Config,
    ) !void {
        for (entries) |entry| {
            if (std.mem.indexOfScalar(u8, entry.key, 0) != null) return error.InvalidValue;
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

    /// Write entries to a provided buffer and return the written slice.
    /// Produces exactly the same bytes as `Serializer.serialize`.
    /// Returns `error.NoSpaceLeft` without claiming partial success and
    /// returns `error.InvalidValue` for embedded NUL bytes.
    pub fn writeToBuffer(
        buf: []u8,
        entries: []const SerEntry,
        cfg: Config,
    ) ![]const u8 {
        var pos: usize = 0;
        for (entries, 0..) |entry, idx| {
            if (std.mem.indexOfScalar(u8, entry.key, 0) != null) return error.InvalidValue;
            if (std.mem.indexOfScalar(u8, entry.value, 0) != null) return error.InvalidValue;
            const isLast = idx + 1 == entries.len;
            for (entry.key) |ch| {
                if (pos >= buf.len) return error.NoSpaceLeft;
                buf[pos] = ch;
                pos += 1;
            }
            if (pos >= buf.len) return error.NoSpaceLeft;
            buf[pos] = '=';
            pos += 1;
            if (helpers.needsQuoting(entry.value, cfg.quoteSpaces)) {
                if (pos >= buf.len) return error.NoSpaceLeft;
                buf[pos] = '"';
                pos += 1;
                for (entry.value) |ch| {
                    if (helpers.escapedForChar(ch)) |esc| {
                        if (pos + esc.len > buf.len) return error.NoSpaceLeft;
                        @memcpy(buf[pos .. pos + esc.len], esc);
                        pos += esc.len;
                    } else {
                        if (pos >= buf.len) return error.NoSpaceLeft;
                        buf[pos] = ch;
                        pos += 1;
                    }
                }
                if (pos >= buf.len) return error.NoSpaceLeft;
                buf[pos] = '"';
                pos += 1;
            } else {
                for (entry.value) |ch| {
                    if (pos >= buf.len) return error.NoSpaceLeft;
                    buf[pos] = ch;
                    pos += 1;
                }
            }
            if (!isLast or cfg.trailingNewline) {
                if (pos >= buf.len) return error.NoSpaceLeft;
                buf[pos] = '\n';
                pos += 1;
            }
        }
        return buf[0..pos];
    }
};

test "writeToBuffer" {
    var buf: [256]u8 = undefined;

    const entries = [_]SerEntry{
        .{ .key = "KEY1", .value = "value1" },
        .{ .key = "KEY2", .value = "value2" },
    };

    const written = try Writer.writeToBuffer(&buf, &entries, .{});
    try std.testing.expectEqualStrings("KEY1=value1\nKEY2=value2\n", written);
}
