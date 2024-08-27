//! Extract HEAD hashes from `git` repositories.

const std = @import("std");
const fs = std.fs;
const ascii = std.ascii;
const process = std.process;
const mem = std.mem;

const Ghext = @This();
const PATH: []const u8 = ".git/HEAD";

/// Possible error types.
pub const Error = error{
    /// Failed to read branch file.
    BranchError,
    /// Failed to read `HEAD` file.
    ReadFailed,
    /// Invalid hash received.
    InvalidHash,
    /// Process failure.
    ProcFailed,
    /// Git binary failure.
    GitError,
};

/// HEAD commit hash.
hash: []const u8,
/// State (requires `git` binary in the `$PATH`).
dirty: ?bool = null,
/// `git` binary detection.
binary: bool,

fn getState(allocator: mem.Allocator) !bool {
    const proc = process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "diff-index", "--quiet", "HEAD", "--" },
    }) catch {
        return Error.ProcFailed;
    };

    defer allocator.free(proc.stdout);
    defer allocator.free(proc.stderr);

    if (proc.term.Exited == 1) {
        return true;
    } else {
        return false;
    }
}

fn readWithGit(allocator: mem.Allocator, arr: *std.ArrayListAligned(u8, null)) anyerror!void {
    const proc = process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "rev-parse", "HEAD" },
    }) catch {
        return Error.ProcFailed;
    };

    if (proc.term.Exited == 0) {
        const hash = mem.trimRight(u8, proc.stdout, "\n");
        try arr.appendSlice(hash);
    }

    defer allocator.free(proc.stdout);
    defer allocator.free(proc.stderr);

    if (proc.term.Exited > 0) {
        return Error.GitError;
    }
}

fn readWithoutGit(arr: *std.ArrayListAligned(u8, null)) !void {
    var buffer: [1024]u8 = undefined;
    var hash: []const u8 = undefined;
    const file = fs.cwd().readFile(PATH, &buffer) catch {
        return Error.ReadFailed;
    };

    if (ascii.startsWithIgnoreCase(file, "ref: ")) {
        _ = @memcpy(file[0..5], ".git/");

        const branch = mem.trimRight(u8, file, "\n");
        const hash_tmp = fs.cwd().readFile(branch, &buffer) catch {
            return Error.BranchError;
        };

        hash = mem.trimRight(u8, hash_tmp, "\n");
        try arr.appendSlice(hash);
    } else {
        hash = mem.trimRight(u8, file, "\n");
        try arr.appendSlice(hash);
    }
}

/// Creates `Ghext` instance using specified allocator and reads the state of the repository.
pub fn read(allocator: mem.Allocator) !Ghext {
    const git = gitInstalled(allocator);
    var dirty: ?bool = null;
    var arr = std.ArrayList(u8).init(allocator);
    defer arr.deinit();

    if (git) {
        dirty = try getState(allocator);

        _ = try readWithGit(allocator, &arr);
    } else {
        _ = try readWithoutGit(&arr);
    }

    const hash = try arr.toOwnedSlice();

    if (!isValid(hash)) {
        return Error.InvalidHash;
    }

    return .{ .binary = git, .hash = hash, .dirty = dirty };
}

/// Releases allocated memory.
pub fn deinit(self: *Ghext, allocator: mem.Allocator) void {
    allocator.free(self.hash);
}

fn gitInstalled(allocator: mem.Allocator) bool {
    const proc = process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "--version" },
    }) catch {
        return false;
    };

    defer allocator.free(proc.stdout);
    defer allocator.free(proc.stderr);

    if (proc.term.Exited == 0) {
        return true;
    } else {
        return false;
    }
}

fn isValid(sha: []const u8) bool {
    switch (sha.len) {
        20, 40, 64 => {},
        else => {
            return false;
        },
    }

    for (sha[0..]) |byte| {
        if (!ascii.isHex(byte)) {
            return false;
        }
    }

    return true;
}

test read {
    var ghx = try Ghext.read(std.testing.allocator);
    defer ghx.deinit(std.testing.allocator);

    try std.testing.expect(ghx.hash.len == 40);
}

test "read (git)" {
    var sha = std.ArrayList(u8).init(std.testing.allocator);
    defer sha.deinit();

    _ = try readWithGit(std.testing.allocator, &sha);

    try std.testing.expect(sha.items.len == 40);
}

test "read (no git)" {
    var sha = std.ArrayList(u8).init(std.testing.allocator);
    defer sha.deinit();

    _ = try readWithoutGit(&sha);

    try std.testing.expect(sha.items.len == 40);
}

test "validation" {
    const sha1 = "0beec7b5ea3f0fdbc95d0dd47f3c5bc275da8a33";
    const sha256 = "2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae";
    const sha256t = "2c26b46b68ffc68ff99b";
    const invalid_a = "2c26b46b68ffc68ff99z";
    const invalid_b = "2c26b46b68ffc68ff96";

    try std.testing.expect(isValid(sha1));
    try std.testing.expect(isValid(sha256));
    try std.testing.expect(isValid(sha256t));
    try std.testing.expect(!isValid(invalid_a));
    try std.testing.expect(!isValid(invalid_b));
}
