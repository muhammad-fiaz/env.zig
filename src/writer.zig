const std = @import("std");
const config = @import("config.zig");
const Serializer = @import("serializer.zig").Serializer;

const Config = config.Config;

/// Write .env entries to a file.
pub const Writer = struct {
    /// Write entries to a file at the given path.
    pub fn writeToFile(
        allocator: std.mem.Allocator,
        path: []const u8,
        entries: []const struct { key: []const u8, value: []const u8 },
        cfg: Config,
    ) !void {
        const content = try Serializer.serialize(allocator, entries, cfg);
        defer allocator.free(content);

        const dir = std.Io.Dir.cwd();
        var io_threaded: std.Io.Threaded = .init_single_threaded;
        const io = io_threaded.io();

        try dir.writeFile(io, .{
            .sub_path = path,
            .data = content,
        });
    }

    /// Write entries to a provided buffer and return the written slice.
    pub fn writeToBuffer(
        buf: []u8,
        entries: []const struct { key: []const u8, value: []const u8 },
        cfg: Config,
    ) ![]const u8 {
        var pos: usize = 0;
        for (entries) |entry| {
            for (entry.key) |ch| {
                if (pos >= buf.len) return error.NoSpaceLeft;
                buf[pos] = ch;
                pos += 1;
            }
            if (pos >= buf.len) return error.NoSpaceLeft;
            buf[pos] = '=';
            pos += 1;
            if (cfg.quote_spaces and
                (std.mem.indexOf(u8, entry.value, " ") != null or
                    std.mem.indexOf(u8, entry.value, "#") != null or
                    entry.value.len == 0))
            {
                if (pos >= buf.len) return error.NoSpaceLeft;
                buf[pos] = '"';
                pos += 1;
                for (entry.value) |ch| {
                    switch (ch) {
                        '"' => {
                            if (pos + 1 >= buf.len) return error.NoSpaceLeft;
                            buf[pos] = '\\';
                            buf[pos + 1] = '"';
                            pos += 2;
                        },
                        '\\' => {
                            if (pos + 1 >= buf.len) return error.NoSpaceLeft;
                            buf[pos] = '\\';
                            buf[pos + 1] = '\\';
                            pos += 2;
                        },
                        '\n' => {
                            if (pos + 1 >= buf.len) return error.NoSpaceLeft;
                            buf[pos] = '\\';
                            buf[pos + 1] = 'n';
                            pos += 2;
                        },
                        '\r' => {
                            if (pos + 1 >= buf.len) return error.NoSpaceLeft;
                            buf[pos] = '\\';
                            buf[pos + 1] = 'r';
                            pos += 2;
                        },
                        '\t' => {
                            if (pos + 1 >= buf.len) return error.NoSpaceLeft;
                            buf[pos] = '\\';
                            buf[pos + 1] = 't';
                            pos += 2;
                        },
                        else => {
                            if (pos >= buf.len) return error.NoSpaceLeft;
                            buf[pos] = ch;
                            pos += 1;
                        },
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
            if (pos >= buf.len) return error.NoSpaceLeft;
            buf[pos] = '\n';
            pos += 1;
        }
        return buf[0..pos];
    }
};

test "writeToBuffer" {
    var buf: [256]u8 = undefined;

    const entries = [_]struct { key: []const u8, value: []const u8 }{
        .{ .key = "KEY1", .value = "value1" },
        .{ .key = "KEY2", .value = "value2" },
    };

    const written = try Writer.writeToBuffer(&buf, &entries, .{});
    try std.testing.expectEqualStrings("KEY1=value1\nKEY2=value2\n", written);
}
