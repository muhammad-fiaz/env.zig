const std = @import("std");
const Io = std.Io;
const env_mod = @import("env");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var env = env_mod.Env.init(allocator, .{ .interpolate = true });
    defer env.deinit();

    try env.parseString(
        \\APP_NAME=myapp
        \\DATABASE_HOST=localhost
        \\DATABASE_PORT=5432
        \\DATABASE_URL=postgres://${DATABASE_HOST}:${DATABASE_PORT}/mydb
        \\GREETING=hello
        \\MESSAGE=${GREETING} world
        \\SHORTCUT=${APP_NAME} is running
        \\
    );

    var stdout_buffer: [0x100]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("=== Interpolation Example ===\n\n", .{});

    try stdout.print("Original values:\n", .{});
    try stdout.print("  APP_NAME = {s}\n", .{env.get("APP_NAME").?});
    try stdout.print("  DATABASE_HOST = {s}\n", .{env.get("DATABASE_HOST").?});
    try stdout.print("  DATABASE_PORT = {s}\n", .{env.get("DATABASE_PORT").?});

    try stdout.print("\nInterpolated values:\n", .{});
    try stdout.print("  DATABASE_URL = {s}\n", .{env.get("DATABASE_URL").?});
    try stdout.print("  MESSAGE = {s}\n", .{env.get("MESSAGE").?});
    try stdout.print("  SHORTCUT = {s}\n", .{env.get("SHORTCUT").?});

    try stdout.print("\nAll resolved keys:\n", .{});
    for (env.keys()) |key| {
        try stdout.print("  {s} = {s}\n", .{ key, env.get(key).? });
    }
    try stdout.flush();
}
