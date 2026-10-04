const std = @import("std");
const Io = std.Io;
const envMod = @import("env");

const Mode = enum { debug, release, testing };

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var env = envMod.Env.init(allocator, .{});
    defer env.deinit();

    try env.parseString(
        \\PORT=8080
        \\DEBUG=true
        \\RATIO=3.14
        \\MODE=release
        \\HOSTS="127.0.0.1, 10.0.0.1, localhost"
        \\EMPTY=
        \\
    );

    var stdoutBuffer: [0x2000]u8 = undefined;
    var stdoutWriter = Io.File.stdout().writer(io, &stdoutBuffer);
    const stdout = &stdoutWriter.interface;

    try stdout.print("=== Type-Safe Accessors Example ===\n\n", .{});

    // get / getString
    try stdout.print("get PORT raw: {s}\n", .{env.get("PORT").?});
    try stdout.print("getString PORT: {s}\n", .{env.getString("PORT").?});
    try stdout.print("get missing -> {?s} (null)\n", .{env.get("MISSING")});

    // getInt with different int types and error handling
    if (env.getInt(u16, "PORT")) |p| try stdout.print("getInt u16 PORT = {d}\n", .{p}) else try stdout.print("getInt failed\n", .{});
    if (env.getInt(i32, "PORT")) |p| try stdout.print("getInt i32 PORT = {d}\n", .{p});
    try stdout.print("getInt invalid EMPTY = {?d}\n", .{env.getInt(i32, "EMPTY")});
    try stdout.print("getInt missing = {?d}\n", .{env.getInt(i32, "MISSING")});

    // getFloat
    if (env.getFloat(f64, "RATIO")) |f| try stdout.print("getFloat RATIO = {d}\n", .{f});
    try stdout.print("getFloat PORT as f64 = {d}\n", .{env.getFloat(f64, "PORT").?});

    // getBool accepts true/false/yes/no/1/0/on/off case-insensitive
    for ([_][]const u8{ "true", "True", "yes", "1", "on", "false", "no", "0", "off", "maybe" }) |val| {
        var tmp = envMod.Env.init(allocator, .{});
        defer tmp.deinit();
        try tmp.set("K", val);
        try stdout.print("  getBool {s} -> {any}\n", .{ val, tmp.getBool("K") });
    }

    // getEnum
    try stdout.print("getEnum MODE = {any}\n", .{env.getEnum(Mode, "MODE")});
    try stdout.print("getEnum PORT as Mode = {any} (null expected)\n", .{env.getEnum(Mode, "PORT")});

    // getList with delimiter and trimming
    if (env.getList(allocator, "HOSTS", ',')) |list| {
        defer allocator.free(list);
        try stdout.print("getList HOSTS count={d}\n", .{list.len});
        for (list, 0..) |h, i| try stdout.print("  [{d}] {s}\n", .{ i, h });
        // Note: list elements are slices into original value — no dupe needed, free only outer slice
    }

    // Empty list
    try stdout.print("getList EMPTY = {any} (null or empty)\n", .{env.getList(allocator, "EMPTY", ',')});

    // require-style via getOrDefault helpers
    try stdout.print("getWithFallback MISSING -> {s}\n", .{env.getWithFallback("MISSING", "fallback")});
    try stdout.print("getWithFallback PORT -> {s}\n", .{env.getWithFallback("PORT", "3000")});

    // tryGet* distinguishes missing (null) from invalid (error.TypeMismatch)
    try stdout.print("tryGetInt MISSING -> {any} (null)\n", .{try env.tryGetInt(i32, "MISSING")});
    try stdout.print("tryGetInt PORT -> {d}\n", .{(try env.tryGetInt(i32, "PORT")).?});
    if (env.tryGetInt(i32, "MODE")) |_| {
        try stdout.print("tryGetInt MODE unexpectedly succeeded\n", .{});
    } else |err| {
        try stdout.print("tryGetInt MODE -> {s} (invalid, not defaulted)\n", .{@errorName(err)});
    }
    try stdout.print("tryGetBool MISSING -> {any} (null)\n", .{try env.tryGetBool("MISSING")});
    try stdout.print("tryGetEnum MODE -> {any}\n", .{try env.tryGetEnum(Mode, "MODE")});

    // contains / containsOs
    try stdout.print("contains PORT={} containsOs HOME={}\n", .{ env.contains("PORT"), env.containsOs("HOME") });

    // OS fallback display
    try envMod.OsEnv.set("TYPE_SAFE_OS_TEST", "from_os");
    defer envMod.OsEnv.unset("TYPE_SAFE_OS_TEST") catch {};
    try stdout.print("getOs TYPE_SAFE_OS_TEST = {s}\n", .{env.getOs("TYPE_SAFE_OS_TEST").?});

    try stdout.flush();
}
