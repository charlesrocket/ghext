const std = @import("std");
pub const Ghext = @import("src/ghext.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("ghext", .{ .root_source_file = b.path("src/ghext.zig") });

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/ghext.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "Ghext",
        .linkage = .static,
        .root_module = lib_mod,
    });

    b.installArtifact(lib);

    const unit_tests = b.addTest(.{
        .root_module = lib_mod,
        .use_llvm = true,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    const lib_docs = b.addLibrary(.{
        .name = "docs",
        .linkage = .static,
        .root_module = lib_mod,
    });

    const docs_step = b.step("docs", "Generate documentation");
    const docs = lib_docs.getEmittedDocs();
    docs_step.dependOn(&b.addInstallDirectory(.{
        .source_dir = docs,
        .install_dir = .prefix,
        .install_subdir = "doc",
    }).step);

    const kcov = b.addSystemCommand(&.{
        "kcov",
        "--include-path=src",
        "kcov-out",
    });

    kcov.addArtifactArg(unit_tests);

    const coverage_step = b.step("coverage", "Generate test coverage (kcov)");
    coverage_step.dependOn(&kcov.step);
}
