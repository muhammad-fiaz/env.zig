const std = @import("std");
const Io = std.Io;
const envMod = @import("env");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var stdoutBuffer: [0x2000]u8 = undefined;
    var stdoutWriter = Io.File.stdout().writer(io, &stdoutBuffer);
    const stdout = &stdoutWriter.interface;

    try stdout.print("=== Child Process Environment Example ===\n\n", .{});

    var env = envMod.Env.init(allocator, .{});
    defer env.deinit();
    try env.set("APP_NAME", "child-demo");
    try env.set("APP_PORT", "8080");

    // Build a child environment map from Env.
    var map = try env.toEnvironMap(allocator);
    defer map.deinit();
    try stdout.print("toEnvironMap count={d}\n", .{map.count()});
    try stdout.print("APP_NAME={s}\n", .{map.get("APP_NAME").?});

    // Merge OS env, then overlay Env (Env wins) for a typical child env.
    var child = try envMod.runtime.getMap(allocator);
    defer child.deinit();
    try env.applyToEnvironMap(&child);
    try stdout.print("merged child count={d} APP_PORT={s}\n", .{ child.count(), child.get("APP_PORT").? });

    // Build the OS-specific block std.process.spawn expects.
    if (@import("builtin").os.tag == .windows) {
        const block = try child.createWindowsBlock(allocator, .{});
        defer allocator.free(block.slice);
        try stdout.print("windows block units={d}\n", .{block.slice.len});
    } else {
        const block = try child.createPosixBlock(allocator, .{});
        defer block.deinit(allocator);
        try stdout.print("posix block entries={d}\n", .{block.slice.len});
        for (block.slice) |entry| {
            const span = std.mem.span(entry.?);
            if (std.mem.startsWith(u8, span, "APP_")) {
                try stdout.print("  {s}\n", .{span});
            }
        }
    }

    try stdout.print("\nPass `&child` as `environ_map` to std.process.spawn/run.\n", .{});
    try stdout.flush();
}
