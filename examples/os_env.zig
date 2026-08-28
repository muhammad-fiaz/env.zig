const std = @import("std");
const Io = std.Io;
const env_mod = @import("env");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var env = env_mod.Env.init(allocator, .{});
    defer env.deinit();

    var stdout_buffer: [0x1000]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("=== env.zig OS Environment Example (Windows/Linux/macOS) ===\n\n", .{});

    // Direct OS env (cross-platform)
    try env_mod.OsEnv.set("ENV_ZIG_DEMO_OS", "os_value");
    defer env_mod.OsEnv.unset("ENV_ZIG_DEMO_OS") catch {};
    try stdout.print("OsEnv.get ENV_ZIG_DEMO_OS = {s}\n", .{env_mod.OsEnv.get("ENV_ZIG_DEMO_OS").?});

    // Load all OS env into Env (override = true by default)
    try env.loadOsEnvIfMissing();
    try stdout.print("Loaded OS env count={d}\n", .{env.count()});

    // OS fallback via getOs
    try env.set("MY_IN_ENV", "from_env");
    try stdout.print("getOs MY_IN_ENV = {s}\n", .{env.getOs("MY_IN_ENV").?});
    try stdout.print("getOs PATH exists = {}\n", .{env.getOs("PATH") != null});

    // Load with prefix (APP_ prefix stripped)
    try env_mod.OsEnv.set("APP_PORT", "9090");
    defer env_mod.OsEnv.unset("APP_PORT") catch {};
    try env.loadOsEnvWithPrefix("APP_");
    try stdout.print("After loadOsEnvWithPrefix APP_PORT -> PORT = {s}\n", .{env.get("PORT") orelse "missing"});

    // Export to OS
    try env.set("EXPORT_TEST", "exported");
    try env.exportToOsEnv();
    try stdout.print("Exported EXPORT_TEST to OS: {s}\n", .{env_mod.OsEnv.get("EXPORT_TEST").?});
    env_mod.OsEnv.unset("EXPORT_TEST") catch {};

    // Temporary SCOPED OS env ($env style)
    try stdout.print("\n--- Scope (temporary $env) ---\n", .{});
    try stdout.print("Before scope: ENV_ZIG_DEMO_OS = {s}\n", .{env_mod.OsEnv.get("ENV_ZIG_DEMO_OS").?});
    {
        var scope = env_mod.Scope.init(allocator);
        defer scope.deinit();
        try scope.set("ENV_ZIG_DEMO_OS", "temporary");
        try scope.set("NEW_TEMP", "tempval");
        try stdout.print("Inside scope: ENV_ZIG_DEMO_OS = {s}\n", .{env_mod.OsEnv.get("ENV_ZIG_DEMO_OS").?});
        try stdout.print("Inside scope: NEW_TEMP = {s}\n", .{env_mod.OsEnv.get("NEW_TEMP").?});
    }
    try stdout.print("After scope: ENV_ZIG_DEMO_OS = {s}\n", .{env_mod.OsEnv.get("ENV_ZIG_DEMO_OS").?});
    try stdout.print("After scope: NEW_TEMP = {?s}\n", .{env_mod.OsEnv.get("NEW_TEMP")});

    // Snapshot / restore
    {
        var snap = try env_mod.OsEnv.snapshot(allocator);
        defer snap.deinit();
        try env_mod.OsEnv.set("SNAP_TEST", "snap_val");
        try stdout.print("Before restore SNAP_TEST={s}\n", .{env_mod.OsEnv.get("SNAP_TEST").?});
        try snap.restore();
        try stdout.print("After restore SNAP_TEST={?s}\n", .{env_mod.OsEnv.get("SNAP_TEST")});
    }

    // Env-level scope (in-memory)
    try stdout.print("\n--- EnvScope (in-memory) ---\n", .{});
    try env.set("SCOPE_KEY", "original");
    {
        var es = env.scope();
        defer es.deinit();
        try es.set("SCOPE_KEY", "overridden");
        try stdout.print("Inside EnvScope: SCOPE_KEY={s}\n", .{env.get("SCOPE_KEY").?});
    }
    try stdout.print("After EnvScope: SCOPE_KEY={s}\n", .{env.get("SCOPE_KEY").?});

    // Interpolation with OS fallback and defaults
    try stdout.print("\n--- Interpolation with OS & defaults ---\n", .{});
    var env2 = env_mod.Env.init(allocator, .{ .interpolate = true });
    defer env2.deinit();
    try env_mod.OsEnv.set("OS_FALLBACK_VAR", "from_os");
    defer env_mod.OsEnv.unset("OS_FALLBACK_VAR") catch {};
    try env2.parseString("A=${OS_FALLBACK_VAR}\nB=${MISSING:-default}\nC=${OS_FALLBACK_VAR:+alt}\n");
    try stdout.print("A (os fallback) = {s}\n", .{env2.get("A").?});
    try stdout.print("B (default) = {s}\n", .{env2.get("B").?});
    try stdout.print("C (alt) = {s}\n", .{env2.get("C").?});

    // Environ.Map for child processes
    var map = try env.toEnvironMap(allocator);
    defer map.deinit();
    try stdout.print("\nEnviron.Map count={d} (for spawn)\n", .{map.count()});

    try stdout.flush();
}
