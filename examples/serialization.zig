const std = @import("std");
const Io = std.Io;
const env_mod = @import("env");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var env = env_mod.Env.init(allocator, .{});
    defer env.deinit();

    try env.set("DATABASE_URL", "postgres://localhost:5432/mydb");
    try env.set("API_KEY", "secret123");
    try env.set("PORT", "8080");
    try env.set("DEBUG", "true");

    var stdout_buffer: [0x100]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("=== Serialization Example ===\n\n", .{});

    const serialized = try env.serialize();
    defer allocator.free(serialized);

    try stdout.print("Serialized .env:\n{s}\n", .{serialized});

    try stdout.print("Sorted:\n", .{});
    var sorted_env = env_mod.Env.init(allocator, .{ .sort_keys = true });
    defer sorted_env.deinit();
    for (env.keys()) |key| {
        try sorted_env.set(key, env.get(key).?);
    }
    const sorted = try sorted_env.serialize();
    defer allocator.free(sorted);
    try stdout.print("{s}\n", .{sorted});

    try stdout.flush();
}
