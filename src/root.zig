//! Extract HEAD hashes from `git` repositories.

const std = @import("std");
const fs = std.fs;

const Self = @This();
/// Path to HEAD file.
const path: []const u8 = ".git/HEAD";
/// Commit hash.
hash: []const u8,
/// Short commit hash.
hash_short: []const u8,
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

fn readWithGit(allocator: std.mem.Allocator) anyerror![]const u8 {
    const proc = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "rev-parse", "HEAD" },
    });

    defer allocator.free(proc.stdout);
    defer allocator.free(proc.stderr);

    if (proc.term.Exited == 0) {
        const hash = std.mem.trimRight(u8, proc.stdout, "\n");
        return hash;
    } else {
        return error.unexpected;
    }
}

fn readWithoutGit(allocator: std.mem.Allocator) ![]const u8 {
    var buffer: [1024]u8 = undefined;
    var hash: []const u8 = undefined;
    const file = try std.fs.cwd().readFile(Self.path, &buffer);

    if (std.ascii.startsWithIgnoreCase(file, "ref: ")) {
        const size = std.mem.replacementSize(u8, file, "ref: ", ".git/");
        const ref = try allocator.alloc(u8, size);
        defer allocator.free(ref);

        _ = std.mem.replace(u8, file, "ref: ", ".git/", ref);

        const branch = std.mem.trimRight(u8, ref, "\n");
        const hash_tmp = try std.fs.cwd().readFile(branch, &buffer);

        hash = std.mem.trimRight(u8, hash_tmp, "\n");
    } else {
        hash = std.mem.trimRight(u8, file, "\n");
    }

    return hash;
}

pub fn init(allocator: std.mem.Allocator) !Self {
    const git = try Self.gitInstalled(allocator);
    var dirty: bool = undefined;
    var hash: []const u8 = undefined;

    if (git) {
        dirty = try Self.getState(allocator);
        hash = try Self.readWithGit(allocator);
    } else {
        hash = try Self.readWithoutGit(allocator);
    }

    var out = try std.ArrayList(u8).initCapacity(allocator, 40);
    defer out.deinit();
    try out.insertSlice(0, hash);
    var result_short = try out.clone();
    const result = try out.toOwnedSlice();
    const result2 = try result_short.toOwnedSlice();

    return .{ .binary = git, .hash = result, .hash_short = result2[0..7], .dirty = dirty };
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

test "init" {
    const ghx = try Self.init(std.testing.allocator);

    try std.testing.expect(ghx.hash_short.len == 7);
    try std.testing.expect(ghx.hash.len == 40);
}

test "read (git)" {
    const hash = try Self.readWithGit(std.testing.allocator);

    try std.testing.expect(hash.len == 40);
}

test "read (no git)" {
    const hash = try Self.readWithoutGit(std.testing.allocator);

    try std.testing.expect(hash.len == 40);
}
