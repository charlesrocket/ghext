const std = @import("std");
pub const Ghext = @import("src/ghext.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const root_source_file = b.path("src/ghext.zig");

    _ = b.addModule("ghext", .{ .root_source_file = root_source_file });

    const lib = b.addStaticLibrary(.{
        .name = "Ghext",
        .root_source_file = b.path("src/ghext.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(lib);

    const unit_tests = b.addTest(.{
        .root_source_file = root_source_file,
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    const lib_docs = b.addStaticLibrary(.{
        .name = "docs",
        .root_source_file = root_source_file,
        .target = target,
        .optimize = optimize,
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
        "kcov-out",
        "--include-path=src",
    });

    kcov.addArtifactArg(unit_tests);

    const coverage_step = b.step("coverage", "Generate test coverage (kcov)");
    coverage_step.dependOn(&kcov.step);
}
