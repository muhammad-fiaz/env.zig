const std = @import("std");
const Io = std.Io;
const envMod = @import("env");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var stdoutBuffer: [0x2000]u8 = undefined;
    var stdoutWriter = Io.File.stdout().writer(io, &stdoutBuffer);
    const stdout = &stdoutWriter.interface;

    try stdout.print("=== Unicode Example ===\n\n", .{});

    var env = envMod.Env.init(allocator, .{});
    defer env.deinit();

    try env.set("GREETING", "héllo wörld");
    try env.set("EMOJI", "🚀✨ 日本語 café naïve");
    try env.set("MIXED", "value with ✓ and emoji 🎉");

    try stdout.print("GREETING = {s}\n", .{env.get("GREETING").?});
    try stdout.print("EMOJI = {s}\n", .{env.get("EMOJI").?});
    try stdout.print("MIXED = {s}\n", .{env.get("MIXED").?});

    // Runtime Unicode round-trip.
    try envMod.runtime.set("ENV_ZIG_DEMO_UNICODE", "héllo 🚀 日本語");
    defer envMod.runtime.unset("ENV_ZIG_DEMO_UNICODE") catch {};
    const back = envMod.runtime.get("ENV_ZIG_DEMO_UNICODE").?;
    try stdout.print("runtime Unicode = {s}\n", .{back});

    // Serialize + parse preserves Unicode.
    const ser = try env.serialize();
    defer allocator.free(ser);
    try stdout.print("\nSerialized:\n{s}\n", .{ser});

    var env2 = envMod.Env.init(allocator, .{});
    defer env2.deinit();
    try env2.parseString(ser);
    try stdout.print("Round-trip GREETING = {s}\n", .{env2.get("GREETING").?});
    try stdout.print("Round-trip EMOJI = {s}\n", .{env2.get("EMOJI").?});

    try stdout.flush();
}
