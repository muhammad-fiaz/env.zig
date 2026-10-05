const std = @import("std");
const Io = std.Io;
const envMod = @import("env");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var stdoutBuffer: [0x2000]u8 = undefined;
    var stdoutWriter = Io.File.stdout().writer(io, &stdoutBuffer);
    const stdout = &stdoutWriter.interface;

    try stdout.print("=== Runtime Example ===\n\n", .{});

    const runtime = envMod.runtime;

    // Set / get / overwrite.
    try runtime.set("ENV_ZIG_DEMO_RT", "one");
    try stdout.print("set one -> {s}\n", .{runtime.get("ENV_ZIG_DEMO_RT").?});
    try runtime.set("ENV_ZIG_DEMO_RT", "two");
    try stdout.print("overwrite -> {s}\n", .{runtime.get("ENV_ZIG_DEMO_RT").?});

    // Empty vs missing.
    try runtime.set("ENV_ZIG_DEMO_RT_EMPTY", "");
    try stdout.print("empty get len={d} exists={} isEmpty={}\n", .{
        runtime.get("ENV_ZIG_DEMO_RT_EMPTY").?.len,
        runtime.exists("ENV_ZIG_DEMO_RT_EMPTY"),
        runtime.isEmpty("ENV_ZIG_DEMO_RT_EMPTY"),
    });
    try stdout.print("missing get={?s} exists={} isEmpty={}\n", .{
        runtime.get("ENV_ZIG_DEMO_RT_MISSING"),
        runtime.exists("ENV_ZIG_DEMO_RT_MISSING"),
        runtime.isEmpty("ENV_ZIG_DEMO_RT_MISSING"),
    });

    // Key validation rejects empty, `=` and NUL.
    for ([_][]const u8{ "", "A=B", "A\x00B" }) |bad| {
        if (runtime.set(bad, "v")) |_| {
            try stdout.print("unexpected success for bad key len={d}\n", .{bad.len});
        } else |err| {
            try stdout.print("bad key rejected -> {s}\n", .{@errorName(err)});
        }
    }
    if (runtime.set("ENV_ZIG_DEMO_RT", "a\x00b")) |_| {
        try stdout.print("unexpected NUL value success\n", .{});
    } else |err| {
        try stdout.print("NUL value rejected -> {s}\n", .{@errorName(err)});
    }

    // Long value (heap fallback, no fixed limits).
    const long = try allocator.alloc(u8, 16384);
    defer allocator.free(long);
    @memset(long, 'x');
    try runtime.set("ENV_ZIG_DEMO_RT_LONG", long);
    try stdout.print("long len={d} ok={}\n", .{
        runtime.get("ENV_ZIG_DEMO_RT_LONG").?.len,
        std.mem.eql(u8, runtime.get("ENV_ZIG_DEMO_RT_LONG").?, long),
    });

    // Snapshot / restore.
    {
        var snap = try runtime.snapshot(allocator);
        defer snap.deinit();
        try runtime.set("ENV_ZIG_DEMO_RT", "modified");
        try runtime.set("ENV_ZIG_DEMO_RT_NEW", "new");
        try snap.restore();
        try stdout.print("after restore RT={s} NEW={?s}\n", .{
            runtime.get("ENV_ZIG_DEMO_RT").?,
            runtime.get("ENV_ZIG_DEMO_RT_NEW"),
        });
    }

    // Scope with automatic restoration.
    {
        var scope = envMod.Scope.init(allocator);
        defer scope.deinit();
        try scope.set("ENV_ZIG_DEMO_RT", "scoped");
        try scope.unset("ENV_ZIG_DEMO_RT_EMPTY");
        try stdout.print("in scope RT={s} EMPTY={?s}\n", .{
            runtime.get("ENV_ZIG_DEMO_RT").?,
            runtime.get("ENV_ZIG_DEMO_RT_EMPTY"),
        });
    }
    try stdout.print("after scope RT={s}\n", .{runtime.get("ENV_ZIG_DEMO_RT").?});

    try runtime.unset("ENV_ZIG_DEMO_RT");
    try runtime.unset("ENV_ZIG_DEMO_RT_EMPTY");
    try runtime.unset("ENV_ZIG_DEMO_RT_LONG");
    try stdout.print("cleanup done, RT={?s}\n", .{runtime.get("ENV_ZIG_DEMO_RT")});

    try stdout.flush();
}
