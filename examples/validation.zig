const std = @import("std");
const Io = std.Io;
const envMod = @import("env");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var env = envMod.Env.init(allocator, .{});
    defer env.deinit();

    try env.parseString(
        \\APP_NAME=MyApp
        \\PORT=8080
        \\DEBUG=true
        \\LOG_LEVEL=info
        \\
    );

    var stdoutBuffer: [0x100]u8 = undefined;
    var stdoutWriter = Io.File.stdout().writer(io, &stdoutBuffer);
    const stdout = &stdoutWriter.interface;

    try stdout.print("=== Validation Example ===\n\n", .{});

    const schema = envMod.schema.Schema{
        .fields = &.{
            .{
                .key = "APP_NAME",
                .required = true,
                .validatorsList = &.{envMod.validator.validators.required},
                .description = "Application name",
            },
            .{
                .key = "PORT",
                .required = true,
                .validatorsList = &.{ envMod.validator.validators.required, envMod.validator.validators.integer },
                .description = "Server port",
            },
            .{
                .key = "DEBUG",
                .required = false,
                .validatorsList = &.{envMod.validator.validators.boolean},
                .description = "Enable debug mode",
            },
            .{
                .key = "API_KEY",
                .required = false,
                .validatorsList = &.{envMod.validator.validators.required},
                .description = "API secret key",
            },
            .{
                .key = "DATABASE_URL",
                .required = false,
                .validatorsList = &.{envMod.validator.validators.url},
                .description = "Database connection URL",
            },
        },
    };

    const errs = try env.validate(allocator, schema);
    defer allocator.free(errs);

    var hasErrors = false;
    var hasWarnings = false;

    for (errs) |err| {
        if (err.level == .err) {
            if (!hasErrors) {
                try stdout.print("Errors:\n", .{});
                hasErrors = true;
            }
            try stdout.print("  [ERROR] {s}: {s}\n", .{ err.key, err.message });
        } else {
            if (!hasWarnings) {
                try stdout.print("\nWarnings:\n", .{});
                hasWarnings = true;
            }
            try stdout.print("  [WARN]  {s}: {s}\n", .{ err.key, err.message });
        }
    }

    if (!hasErrors and !hasWarnings) {
        try stdout.print("Validation passed! All required fields present and valid.\n", .{});
    }

    try stdout.print("\nLoaded config:\n", .{});
    for (env.keys()) |key| {
        try stdout.print("  {s} = {s}\n", .{ key, env.get(key).? });
    }
    try stdout.flush();
}
