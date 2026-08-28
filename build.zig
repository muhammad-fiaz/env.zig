const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("env", .{
        .root_source_file = b.path("src/env.zig"),
        .target = target,
        .link_libc = true,
    });

    const lib = b.addLibrary(.{
        .name = "env",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/env.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "env", .module = mod }},
            .link_libc = true,
        }),
    });
    b.installArtifact(lib);

    const lib_tests = b.addTest(.{ .root_module = mod });
    const run_lib_tests = b.addRunArtifact(lib_tests);
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_lib_tests.step);

    const docs_step = b.step("docs", "Generate library documentation");
    const install_docs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    docs_step.dependOn(&install_docs.step);

    const example_step = b.step("example", "Run all examples");
    const examples = [_]struct { name: []const u8, path: []const u8 }{
        .{ .name = "basic", .path = "examples/basic.zig" },
        .{ .name = "validation", .path = "examples/validation.zig" },
        .{ .name = "serialization", .path = "examples/serialization.zig" },
        .{ .name = "interpolation", .path = "examples/interpolation.zig" },
        .{ .name = "clone_merge", .path = "examples/clone_merge.zig" },
        .{ .name = "cache", .path = "examples/cache.zig" },
        .{ .name = "iterator", .path = "examples/iterator.zig" },
        .{ .name = "os_env", .path = "examples/os_env.zig" },
        .{ .name = "file_io", .path = "examples/file_io.zig" },
        .{ .name = "error_handling", .path = "examples/error_handling.zig" },
        .{ .name = "type_safe", .path = "examples/type_safe.zig" },
    };
    inline for (examples) |ex| {
        const exe = b.addExecutable(.{
            .name = ex.name ++ "_example",
            .root_module = b.createModule(.{
                .root_source_file = b.path(ex.path),
                .target = target,
                .optimize = optimize,
                .imports = &.{.{ .name = "env", .module = mod }},
                .link_libc = true,
            }),
        });
        b.installArtifact(exe);
        const run = b.addRunArtifact(exe);
        example_step.dependOn(&run.step);
    }
}
