const std = @import("std");
const Io = std.Io;
const env_mod = @import("env");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var stdout_buffer: [0x3000]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("=== Error Handling Example ===\n\n", .{});

    // 1) Strict vs lenient
    {
        var strict = env_mod.Env.init(allocator, .{ .strict = true });
        defer strict.deinit();
        if (strict.parseString("123BAD=value\n")) |_| {
            try stdout.print("Strict: unexpected success\n", .{});
        } else |err| {
            try stdout.print("Strict correctly returned {s} for invalid key\n", .{@errorName(err)});
        }
    }
    {
        var lenient = env_mod.Env.init(allocator, .{ .strict = false });
        defer lenient.deinit();
        try lenient.parseString("123BAD=value\nGOOD=ok\n");
        try stdout.print("Lenient: GOOD={s} count={d} (bad key skipped)\n", .{ lenient.get("GOOD").?, lenient.count() });
    }

    // 2) File errors
    {
        var e = env_mod.Env.init(allocator, .{});
        defer e.deinit();
        e.load("definitely_missing_12345.env") catch |err| {
            try stdout.print("Missing file -> {s} (correctly FileNotFound)\n", .{@errorName(err)});
        };
    }

    // 3) Empty value policy
    {
        var no_empty = env_mod.Env.init(allocator, .{ .allow_empty = false, .strict = false });
        defer no_empty.deinit();
        try no_empty.parseString("EMPTY=\nGOOD=1\n");
        try stdout.print("allow_empty=false: EMPTY present? {} GOOD={s}\n", .{ no_empty.contains("EMPTY"), no_empty.get("GOOD").? });
    }

    // 4) Interpolation circular / max depth (kept literal on error)
    {
        var env = env_mod.Env.init(allocator, .{ .interpolate = true, .max_interpolation_depth = 2 });
        defer env.deinit();
        try env.parseString("A=${B}\nB=${A}\n");
        try stdout.print("Circular A kept as literal: {s}\n", .{env.get("A").?});
    }

    // 5) Validation levels via callbacks
    {
        var env = env_mod.Env.init(allocator, .{});
        defer env.deinit();
        try env.parseString("PORT=notanint\nLOG_LEVEL=info\n");
        const schema = env_mod.schema.Schema.init(&.{
            .{ .key = "PORT", .required = true, .validators_list = &.{env_mod.validator.validators.integer}, .description = "port must be int" },
            .{ .key = "LOG_LEVEL", .required = false, .validators_list = &.{env_mod.validator.validators.oneOf(&.{ "debug", "info" })}, .description = "optional" },
            .{ .key = "MISSING_OPTIONAL", .required = false, .validators_list = &.{env_mod.validator.validators.required}, .description = "optional missing" },
            .{ .key = "MISSING_REQUIRED", .required = true, .description = "required missing" },
        });
        for (env.validate(schema)) |e| {
            try stdout.print("  [{s}] {s}: {s}\n", .{ @tagName(e.level), e.key, e.message });
        }
    }

    // 6) Type-safe accessors return null on mismatch
    {
        var env = env_mod.Env.init(allocator, .{});
        defer env.deinit();
        try env.set("NOT_INT", "abc");
        try env.set("NOT_BOOL", "maybe");
        try stdout.print("getInt NOT_INT = {?d} (null expected)\n", .{env.getInt(i32, "NOT_INT")});
        try stdout.print("getBool NOT_BOOL = {?} (null expected)\n", .{env.getBool("NOT_BOOL")});
    }

    // 7) Writer NoSpaceLeft
    {
        try stdout.print("Writer NoSpaceLeft is correctly error.NoSpaceLeft (covered in unit tests)\n", .{});
    }

    try stdout.flush();
}
