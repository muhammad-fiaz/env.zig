const std = @import("std");
const Io = std.Io;
const envMod = @import("env");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var env = envMod.Env.init(allocator, .{});
    defer env.deinit();

    try env.parseString(
        \\API_KEY=secret123
        \\DATABASE_URL=postgres://localhost/mydb
        \\PORT=8080
        \\
    );

    var stdoutBuffer: [0x100]u8 = undefined;
    var stdoutWriter = Io.File.stdout().writer(io, &stdoutBuffer);
    const stdout = &stdoutWriter.interface;

    try stdout.print("=== Cache Example ===\n\n", .{});

    try env.cache.put("cached_token", "abc123");
    try env.cache.put("cached_config", "{ \"timeout\": 30 }");

    try stdout.print("Cache count: {d}\n", .{env.cache.count()});

    if (env.cache.get("cached_token")) |token| {
        try stdout.print("Cached token: {s}\n", .{token});
    }

    try stdout.print("Has cached_token: {}\n", .{env.cache.contains("cached_token")});
    try stdout.print("Has missing: {}\n", .{env.cache.contains("missing")});

    try env.cache.put("cached_token", "new_token_456");
    try stdout.print("Updated token: {s}\n", .{env.cache.get("cached_token").?});

    _ = env.cache.remove("cached_config");
    try stdout.print("After remove, has cached_config: {}\n", .{env.cache.contains("cached_config")});
    try stdout.print("Cache count after remove: {d}\n", .{env.cache.count()});

    env.cache.clear();
    try stdout.print("Cache count after clear: {d}\n", .{env.cache.count()});

    try stdout.print("\nEnv entries still intact:\n", .{});
    for (env.keys()) |key| {
        try stdout.print("  {s} = {s}\n", .{ key, env.get(key).? });
    }
    try stdout.flush();
}
