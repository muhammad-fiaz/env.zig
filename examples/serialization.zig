const std = @import("std");
const Io = std.Io;
const envMod = @import("env");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var env = envMod.Env.init(allocator, .{});
    defer env.deinit();

    try env.set("DATABASE_URL", "postgres://localhost:5432/mydb");
    try env.set("API_KEY", "secret123");
    try env.set("PORT", "8080");
    try env.set("DEBUG", "true");

    var stdoutBuffer: [0x100]u8 = undefined;
    var stdoutWriter = Io.File.stdout().writer(io, &stdoutBuffer);
    const stdout = &stdoutWriter.interface;

    try stdout.print("=== Serialization Example ===\n\n", .{});

    const serialized = try env.serialize();
    defer allocator.free(serialized);

    try stdout.print("Serialized .env:\n{s}\n", .{serialized});

    try stdout.print("Sorted:\n", .{});
    var sortedEnv = envMod.Env.init(allocator, .{ .sortKeys = true });
    defer sortedEnv.deinit();
    for (env.keys()) |key| {
        try sortedEnv.set(key, env.get(key).?);
    }
    const sorted = try sortedEnv.serialize();
    defer allocator.free(sorted);
    try stdout.print("{s}\n", .{sorted});

    try stdout.flush();
}
