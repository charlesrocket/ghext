//! Extract HEAD hashes from `git` repositories.

const std = @import("std");
const fs = std.fs;

const Self = @This();
/// Path to HEAD file.
const path: []const u8 = ".git/HEAD";
/// Commit hash.
hash: [40]u8,
/// State
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
    const file = try std.fs.cwd().readFile(Self.path, &buffer);

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

pub fn read(allocator: std.mem.Allocator) !Self {
    const git = try Self.gitInstalled(allocator);
    var dirty: bool = undefined;
    var hash: [40]u8 = undefined;

    if (git) {
        dirty = try Self.getState(allocator);
        hash = try Self.readWithGit(allocator);
    } else {
        hash = try Self.readWithoutGit();
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
    const ghx = try Self.read(std.testing.allocator);

    try std.testing.expect(ghx.hash.len == 40);
}

test "read (git)" {
    const hash = try Self.readWithGit(std.testing.allocator);

    try std.testing.expect(hash.len == 40);
}

test "read (no git)" {
    const hash = try Self.readWithoutGit();

    try std.testing.expect(hash.len == 40);
}
