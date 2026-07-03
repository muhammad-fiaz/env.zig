const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("env", .{
        .root_source_file = b.path("src/env.zig"),
        .target = target,
    });

    const lib = b.addLibrary(.{
        .name = "env",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/env.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "env", .module = mod },
            },
        }),
    });
    b.installArtifact(lib);

    const lib_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_lib_tests.step);

    const docs_step = b.step("docs", "Generate library documentation");
    const install_docs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    docs_step.dependOn(&install_docs.step);

    const docs_dev_step = b.step("docs:dev", "Start documentation dev server");
    const docs_dev = b.addSystemCommand(&.{ "npm", "run", "docs:dev" });
    docs_dev.setCwd(b.path("docs"));
    docs_dev_step.dependOn(&docs_dev.step);

    const example_step = b.step("example", "Run examples");

    const basic_example = b.addExecutable(.{
        .name = "basic_example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/basic.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "env", .module = mod },
            },
        }),
    });
    b.installArtifact(basic_example);
    const run_basic = b.addRunArtifact(basic_example);
    example_step.dependOn(&run_basic.step);

    const validation_example = b.addExecutable(.{
        .name = "validation_example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/validation.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "env", .module = mod },
            },
        }),
    });
    b.installArtifact(validation_example);
    const run_validation = b.addRunArtifact(validation_example);
    example_step.dependOn(&run_validation.step);

    const serialization_example = b.addExecutable(.{
        .name = "serialization_example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/serialization.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "env", .module = mod },
            },
        }),
    });
    b.installArtifact(serialization_example);
    const run_serialization = b.addRunArtifact(serialization_example);
    example_step.dependOn(&run_serialization.step);

    const interpolation_example = b.addExecutable(.{
        .name = "interpolation_example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/interpolation.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "env", .module = mod },
            },
        }),
    });
    b.installArtifact(interpolation_example);
    const run_interpolation = b.addRunArtifact(interpolation_example);
    example_step.dependOn(&run_interpolation.step);

    const clone_merge_example = b.addExecutable(.{
        .name = "clone_merge_example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/clone_merge.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "env", .module = mod },
            },
        }),
    });
    b.installArtifact(clone_merge_example);
    const run_clone_merge = b.addRunArtifact(clone_merge_example);
    example_step.dependOn(&run_clone_merge.step);

    const cache_example = b.addExecutable(.{
        .name = "cache_example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/cache.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "env", .module = mod },
            },
        }),
    });
    b.installArtifact(cache_example);
    const run_cache = b.addRunArtifact(cache_example);
    example_step.dependOn(&run_cache.step);

    const iterator_example = b.addExecutable(.{
        .name = "iterator_example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/iterator.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "env", .module = mod },
            },
        }),
    });
    b.installArtifact(iterator_example);
    const run_iterator = b.addRunArtifact(iterator_example);
    example_step.dependOn(&run_iterator.step);
}
