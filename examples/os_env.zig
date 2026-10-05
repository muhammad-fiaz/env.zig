const std = @import("std");
const Io = std.Io;
const envMod = @import("env");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var env = envMod.Env.init(allocator, .{});
    defer env.deinit();

    var stdoutBuffer: [0x1000]u8 = undefined;
    var stdoutWriter = Io.File.stdout().writer(io, &stdoutBuffer);
    const stdout = &stdoutWriter.interface;

    try stdout.print("=== env.zig OS Environment Example (Windows/Linux/macOS) ===\n\n", .{});

    const runtime = envMod.runtime;

    // Direct runtime env (cross-platform, process-global, thread-unsafe).
    try runtime.set("ENV_ZIG_DEMO_OS", "os_value");
    defer runtime.unset("ENV_ZIG_DEMO_OS") catch {};
    try stdout.print("runtime.get ENV_ZIG_DEMO_OS = {s}\n", .{runtime.get("ENV_ZIG_DEMO_OS").?});
    try stdout.print("runtime.contains = {} isEmpty = {}\n", .{ runtime.contains("ENV_ZIG_DEMO_OS"), runtime.isEmpty("ENV_ZIG_DEMO_OS") });

    // Owned copy and default.
    if (try runtime.getAlloc(allocator, "ENV_ZIG_DEMO_OS")) |owned| {
        defer allocator.free(owned);
        try stdout.print("runtime.getAlloc = {s}\n", .{owned});
    }
    try stdout.print("runtime.getOrDefault MISSING = {s}\n", .{runtime.getOrDefault("ENV_ZIG_DEMO_MISSING", "fallback")});

    // Missing vs empty distinction.
    try runtime.set("ENV_ZIG_DEMO_EMPTY", "");
    try stdout.print("empty exists={} isEmpty={} len={d}\n", .{
        runtime.exists("ENV_ZIG_DEMO_EMPTY"),
        runtime.isEmpty("ENV_ZIG_DEMO_EMPTY"),
        runtime.get("ENV_ZIG_DEMO_EMPTY").?.len,
    });
    try stdout.print("missing isEmpty={}\n", .{runtime.isEmpty("ENV_ZIG_DEMO_MISSING")});
    try runtime.unset("ENV_ZIG_DEMO_EMPTY");

    // Load all OS env into Env (override = true by default).
    try env.loadOsEnvIfMissing();
    try stdout.print("Loaded OS env count={d}\n", .{env.count()});

    // OS fallback via getOs.
    try env.set("MY_IN_ENV", "from_env");
    try stdout.print("getOs MY_IN_ENV = {s}\n", .{env.getOs("MY_IN_ENV").?});
    try stdout.print("getOs PATH exists = {}\n", .{env.getOs("PATH") != null});

    // Load with prefix (APP_ prefix stripped).
    try runtime.set("APP_PORT", "9090");
    defer runtime.unset("APP_PORT") catch {};
    try env.loadOsEnvWithPrefix("APP_");
    try stdout.print("After loadOsEnvWithPrefix APP_PORT -> PORT = {s}\n", .{env.get("PORT") orelse "missing"});

    // Export to OS.
    try env.set("EXPORT_TEST", "exported");
    try env.exportToOsEnv();
    try stdout.print("Exported EXPORT_TEST to OS: {s}\n", .{runtime.get("EXPORT_TEST").?});
    try runtime.unset("EXPORT_TEST");

    // Temporary scoped OS env.
    try stdout.print("\n--- Scope (temporary runtime) ---\n", .{});
    try stdout.print("Before scope: ENV_ZIG_DEMO_OS = {s}\n", .{runtime.get("ENV_ZIG_DEMO_OS").?});
    {
        var scope = envMod.Scope.init(allocator);
        defer scope.deinit();
        try scope.set("ENV_ZIG_DEMO_OS", "temporary");
        try scope.set("NEW_TEMP", "tempval");
        try stdout.print("Inside scope: ENV_ZIG_DEMO_OS = {s}\n", .{runtime.get("ENV_ZIG_DEMO_OS").?});
        try stdout.print("Inside scope: NEW_TEMP = {s}\n", .{runtime.get("NEW_TEMP").?});
        try scope.unset("ENV_ZIG_DEMO_OS");
        try stdout.print("Inside scope after unset: {?s}\n", .{runtime.get("ENV_ZIG_DEMO_OS")});
    }
    try stdout.print("After scope: ENV_ZIG_DEMO_OS = {s}\n", .{runtime.get("ENV_ZIG_DEMO_OS").?});
    try stdout.print("After scope: NEW_TEMP = {?s}\n", .{runtime.get("NEW_TEMP")});

    // Snapshot / restore.
    {
        var snap = try runtime.snapshot(allocator);
        defer snap.deinit();
        try runtime.set("SNAP_TEST", "snap_val");
        try stdout.print("Before restore SNAP_TEST={s}\n", .{runtime.get("SNAP_TEST").?});
        try snap.restore();
        try stdout.print("After restore SNAP_TEST={?s}\n", .{runtime.get("SNAP_TEST")});
    }

    // Env-level scope (in-memory, distinct from process scope).
    try stdout.print("\n--- EnvScope (in-memory) ---\n", .{});
    try env.set("SCOPE_KEY", "original");
    {
        var es = env.scope();
        defer es.deinit();
        try es.set("SCOPE_KEY", "overridden");
        try stdout.print("Inside EnvScope: SCOPE_KEY={s}\n", .{env.get("SCOPE_KEY").?});
    }
    try stdout.print("After EnvScope: SCOPE_KEY={s}\n", .{env.get("SCOPE_KEY").?});

    // Interpolation with OS fallback and defaults.
    try stdout.print("\n--- Interpolation with OS & defaults ---\n", .{});
    var env2 = envMod.Env.init(allocator, .{ .interpolate = true });
    defer env2.deinit();
    try runtime.set("OS_FALLBACK_VAR", "from_os");
    defer runtime.unset("OS_FALLBACK_VAR") catch {};
    try env2.parseString("A=${OS_FALLBACK_VAR}\nB=${MISSING:-default}\nC=${OS_FALLBACK_VAR:+alt}\n");
    try stdout.print("A (os fallback) = {s}\n", .{env2.get("A").?});
    try stdout.print("B (default) = {s}\n", .{env2.get("B").?});
    try stdout.print("C (alt) = {s}\n", .{env2.get("C").?});

    // Environ.Map for child processes.
    var map = try env.toEnvironMap(allocator);
    defer map.deinit();
    try stdout.print("\nEnviron.Map count={d} (for spawn)\n", .{map.count()});

    try stdout.flush();
}
