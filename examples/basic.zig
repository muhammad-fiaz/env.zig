const std = @import("std");
const Io = std.Io;
const envMod = @import("env");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var stdoutBuffer: [0x2000]u8 = undefined;
    var stdoutWriter = Io.File.stdout().writer(io, &stdoutBuffer);
    const stdout = &stdoutWriter.interface;

    try stdout.print("=== env.zig Basic Example ===\n\n", .{});

    // 1) In-memory entries.
    var env = envMod.Env.init(allocator, .{});
    defer env.deinit();

    try env.set("APP_NAME", "env.zig Demo");
    try env.set("PORT", "8080");
    try env.set("DEBUG", "true");
    try env.set("DATABASE_URL", "postgres://localhost:5432/mydb");

    try stdout.print("--- In-memory values (before file ops) ---\n", .{});
    if (env.get("APP_NAME")) |name| {
        try stdout.print("App: {s}\n", .{name});
    }
    if (env.getInt(u16, "PORT")) |port| {
        try stdout.print("Port: {d}\n", .{port});
    }
    if (env.getBool("DEBUG")) |debug| {
        try stdout.print("Debug: {}\n", .{debug});
    }
    if (env.get("DATABASE_URL")) |url| {
        try stdout.print("DB URL: {s}\n", .{url});
    }

    try stdout.print("\nAll keys:\n", .{});
    for (env.keys()) |key| {
        try stdout.print("  {s}={s}\n", .{ key, env.get(key).? });
    }

    const serialized = try env.serialize();
    defer allocator.free(serialized);
    try stdout.print("\nSerialized .env:\n{s}\n", .{serialized});

    // 2) Explicitly create a `.env` file from the in-memory store.
    try env.save(".env");
    defer {
        Io.Dir.cwd().deleteFile(io, ".env") catch {};
    }
    try stdout.print("--- Wrote .env file ---\n", .{});
    {
        const dir = Io.Dir.cwd();
        const raw = try dir.readFileAlloc(io, ".env", allocator, .limited(8192));
        defer allocator.free(raw);
        try stdout.print("File .env before local override:\n{s}\n", .{raw});
    }

    // 3) Explicitly create a `.env.local` file with local overrides.
    var local = envMod.Env.init(allocator, .{});
    defer local.deinit();
    try local.set("PORT", "9090");
    try local.set("DEBUG", "false");
    try local.save(".env.local");
    defer {
        Io.Dir.cwd().deleteFile(io, ".env.local") catch {};
    }
    {
        const dir = Io.Dir.cwd();
        const raw = try dir.readFileAlloc(io, ".env.local", allocator, .limited(8192));
        defer allocator.free(raw);
        try stdout.print("File .env.local:\n{s}\n", .{raw});
    }

    // 4) Load both files back: `.env.local` wins over `.env`.
    var loaded = envMod.Env.init(allocator, .{ .override = true });
    defer loaded.deinit();
    try loaded.loadMany(&.{ ".env", ".env.local" });
    try stdout.print("--- After loadMany([.env, .env.local]) ---\n", .{});
    try stdout.print("PORT={s} (local override)\n", .{loaded.get("PORT").?});
    try stdout.print("DEBUG={s} (local override)\n", .{loaded.get("DEBUG").?});
    try stdout.print("APP_NAME={s} (from .env)\n", .{loaded.get("APP_NAME").?});

    try stdout.flush();
}
