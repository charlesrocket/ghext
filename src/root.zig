//! Extract HEAD hashes from `git` repositories.

const std = @import("std");
const fs = std.fs;

const path: []const u8 = ".git/HEAD";
/// Commit hash.
hash: [40]u8,
/// State (requires `git` binary in the `$PATH`).
dirty: bool = false,
/// `git` binary detection.
binary: bool,

fn getState(allocator: std.mem.Allocator) !bool {
    const proc = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "diff-index", "--quiet", "HEAD", "--" },
    });

    defer allocator.free(proc.stdout);
    defer allocator.free(proc.stderr);

    if (proc.term.Exited == 1) {
        return true;
    } else {
        return false;
    }
}

fn readWithGit(allocator: std.mem.Allocator) anyerror![40]u8 {
    const proc = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "rev-parse", "HEAD" },
    });

    defer allocator.free(proc.stdout);
    defer allocator.free(proc.stderr);

    if (proc.term.Exited == 0) {
        var hash = std.mem.trimRight(u8, proc.stdout, "\n");
        return hash[0..40].*;
    } else {
        return error.unexpected;
    }
}

fn readWithoutGit() ![40]u8 {
    var buffer: [1024]u8 = undefined;
    const file = try std.fs.cwd().readFile(@This().path, &buffer);

    if (std.ascii.startsWithIgnoreCase(file, "ref: ")) {
        _ = @memcpy(file[0..5], ".git/");

        const branch = std.mem.trimRight(u8, file, "\n");
        const hash_tmp = try std.fs.cwd().readFile(branch, &buffer);

        var hash = std.mem.trimRight(u8, hash_tmp, "\n");
        return hash[0..40].*;
    } else {
        var hash = std.mem.trimRight(u8, file, "\n");
        return hash[0..40].*;
    }
}

/// Creates `Ghext` instance using specified allocator and reads the state of the repository.
pub fn read(allocator: std.mem.Allocator) !@This() {
    const git = try @This().gitInstalled(allocator);
    var dirty: bool = undefined;
    var hash: [40]u8 = undefined;

    if (git) {
        dirty = try @This().getState(allocator);
        hash = try @This().readWithGit(allocator);
    } else {
        hash = try @This().readWithoutGit();
    }

    return .{ .binary = git, .hash = hash, .dirty = dirty };
}

fn gitInstalled(allocator: std.mem.Allocator) !bool {
    const proc = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "--version" },
    });

    defer allocator.free(proc.stdout);
    defer allocator.free(proc.stderr);

    if (proc.term.Exited == 1) {
        return true;
    } else {
        return false;
    }
}

test "read" {
    const ghx = try @This().read(std.testing.allocator);

    try std.testing.expect(ghx.hash.len == 40);
}

test "read (git)" {
    const hash = try @This().readWithGit(std.testing.allocator);

    try std.testing.expect(hash.len == 40);
}

test "read (no git)" {
    const hash = try @This().readWithoutGit();

    try std.testing.expect(hash.len == 40);
}
