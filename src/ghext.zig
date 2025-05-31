//! Extract HEAD hashes from `git` repositories.

const State = enum {
    Dirty,
    Clean,
    Unknown,
    None,
};

/// Working tree state check.
pub const Worktree = enum {
    Checked,
    Unchecked,
};

/// Length of the HEAD hash.
pub const HashLen = enum {
    Short,
    Long,
};

/// Location of the HEAD file.
pub var PATH: []const u8 = ".git/HEAD";
/// Git executable usage toggle.
pub var GIT: bool = true;
var PREFIX: []const u8 = ".git/";

/// HEAD commit hash.
head: []const u8,
/// Working tree state (requires `git` binary in the `$PATH`).
state: State,
/// `git` binary detection.
binary: bool,

fn getState(allocator: mem.Allocator) State {
    const proc = process.Child.run(.{
        .allocator = allocator,
        .argv = &.{
            "git",
            "diff-index",
            "--quiet",
            "HEAD",
            "--",
        },
    }) catch {
        return State.Unknown;
    };

    defer allocator.free(proc.stdout);
    defer allocator.free(proc.stderr);

    if (proc.term.Exited == 1) {
        return State.Dirty;
    } else {
        return State.Clean;
    }
}

fn readWithGit(
    allocator: mem.Allocator,
    arr: *std.ArrayListAligned(u8, null),
) !void {
    const proc = try process.Child.run(.{
        .allocator = allocator,
        .argv = &.{
            "git",
            "rev-parse",
            "HEAD",
        },
    });

    if (proc.term.Exited == 0) {
        const head = mem.trimRight(u8, proc.stdout, "\n");
        try arr.appendSlice(head);
    }

    defer allocator.free(proc.stdout);
    defer allocator.free(proc.stderr);

    if (proc.term.Exited > 0) {
        return error.GitFailure;
    }
}

fn readWithoutGit(arr: *std.ArrayListAligned(u8, null)) !void {
    var buffer: [1024]u8 = undefined;
    var head: []const u8 = undefined;

    const file = try fs.cwd().readFile(PATH, &buffer);

    if (ascii.startsWithIgnoreCase(file, "ref: ")) {
        @memcpy(file[0..5], PREFIX);
        const branch = mem.trimRight(u8, file, "\n");
        const hash_tmp = try fs.cwd().readFile(branch, &buffer);

        head = mem.trimRight(u8, hash_tmp, "\n");
    } else {
        head = mem.trimRight(u8, file, "\n");
    }

    try arr.appendSlice(head);
}

/// Creates `Ghext` instance using specified allocator and reads
/// the state of the repository.
pub fn init(allocator: mem.Allocator) !Ghext {
    const binary = gitInstalled(allocator);
    var state: State = .None;
    var arr = std.ArrayList(u8).init(allocator);
    defer arr.deinit();

    if (GIT and binary) {
        state = getState(allocator);
        readWithGit(allocator, &arr) catch try readWithoutGit(&arr);
    } else {
        try readWithoutGit(&arr);
    }

    const head = try arr.toOwnedSlice();

    if (!isValid(head)) {
        return error.InvalidHeadHash;
    }

    return .{
        .binary = binary,
        .head = head,
        .state = state,
    };
}

/// Releases allocated memory.
pub fn deinit(self: *Ghext, allocator: mem.Allocator) void {
    allocator.free(self.head);
}

/// Returns a short or long HEAD hash with an optional working tree state.
pub inline fn hash(
    self: *Ghext,
    length: HashLen,
    check: Worktree,
) []const u8 {
    var arr = std.BoundedArray(u8, 80).init(0) catch return switch (length) {
        .Short => self.head[0..7],
        .Long => self.head,
    };

    switch (length) {
        .Short => arr.appendSlice(self.head[0..7]) catch return self.head[0..7],
        .Long => arr.appendSlice(self.head) catch return self.head,
    }

    if (check == .Checked) {
        if (self.state == .Dirty) {
            arr.appendSlice("-dirty") catch
                return arr.slice();
        } else if (self.state == .Unknown) {
            arr.appendSlice("-unverified") catch
                return arr.slice();
        }
    }

    return arr.slice();
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
        20, 40, 64 => {
            for (sha[0..]) |byte| {
                if (!ascii.isHex(byte)) {
                    return false;
                }
            }

            return true;
        },
        else => {
            return false;
        },
    }
}

test init {
    var ghx = try Ghext.init(std.testing.allocator);
    defer ghx.deinit(std.testing.allocator);

    try std.testing.expect(ghx.head.len == 40);
}

test "hash short" {
    var ghx = try Ghext.init(std.testing.allocator);
    defer ghx.deinit(std.testing.allocator);

    const head = ghx.hash(HashLen.Short, Worktree.Unchecked);

    try std.testing.expect(head.len == 7);
}

test "hash short (checked)" {
    var ghx = try Ghext.init(std.testing.allocator);
    defer ghx.deinit(std.testing.allocator);

    ghx.state = .Unknown;
    const head = ghx.hash(HashLen.Short, Worktree.Checked);

    try std.testing.expect(head.len == 18);
}

test "hash long" {
    var ghx = try Ghext.init(std.testing.allocator);
    defer ghx.deinit(std.testing.allocator);

    const head = ghx.hash(HashLen.Long, Worktree.Unchecked);

    try std.testing.expect(head.len == 40);
}

test "hash long (checked)" {
    var ghx = try Ghext.init(std.testing.allocator);
    defer ghx.deinit(std.testing.allocator);

    ghx.state = .Unknown;
    const head = ghx.hash(HashLen.Long, Worktree.Checked);

    try std.testing.expect(head.len == 51);
}

test "hash dirty" {
    var ghx = try Ghext.init(std.testing.allocator);
    defer ghx.deinit(std.testing.allocator);

    ghx.state = .Dirty;
    const head = ghx.hash(HashLen.Short, Worktree.Checked);

    try std.testing.expect(head.len == 13);
}

test "read (git)" {
    var sha = std.ArrayList(u8).init(std.testing.allocator);
    defer sha.deinit();

    try readWithGit(std.testing.allocator, &sha);

    try std.testing.expect(sha.items.len == 40);
}

test "read (no git)" {
    var sha = std.ArrayList(u8).init(std.testing.allocator);
    defer sha.deinit();

    try readWithoutGit(&sha);

    try std.testing.expect(sha.items.len == 40);
}

test "branch" {
    const test_file_a = try std.fs.cwd().createFile(
        "test-branch",
        .{ .read = true },
    );

    const test_file_b = try std.fs.cwd().createFile(
        "test-branch-hash",
        .{ .read = true },
    );

    test_file_a.writeAll("ref: branch-hash") catch unreachable;
    test_file_b.writeAll("2c26b46b68ffc68ff99b") catch unreachable;

    PATH = "test-branch";
    PREFIX = "test-";
    GIT = false;

    var ghx = try Ghext.init(std.testing.allocator);

    defer {
        test_file_a.close();
        test_file_b.close();
        std.fs.cwd().deleteFile("test-branch-hash") catch unreachable;
        std.fs.cwd().deleteFile("test-branch") catch unreachable;
        ghx.deinit(std.testing.allocator);
    }

    try std.testing.expect(std.mem.eql(
        u8,
        "2c26b46b68ffc68ff99b",
        ghx.head,
    ));
}

test "headless" {
    const test_file = try std.fs.cwd().createFile(
        "test-hash",
        .{ .read = true },
    );

    test_file.writeAll("0beec7b5ea3f0fdbc95d0dd47f3c5bc275da8a33") catch
        unreachable;

    PATH = "test-hash";
    GIT = false;

    var ghx = try Ghext.init(std.testing.allocator);

    defer {
        test_file.close();
        std.fs.cwd().deleteFile("test-hash") catch unreachable;
        ghx.deinit(std.testing.allocator);
    }

    try std.testing.expect(std.mem.eql(
        u8,
        "0beec7b5ea3f0fdbc95d0dd47f3c5bc275da8a33",
        ghx.head,
    ));
}

test "head file missing" {
    PATH = "foo";
    GIT = false;

    try std.testing.expectError(
        error.FileNotFound,
        Ghext.init(std.testing.allocator),
    );
}

test "validation" {
    const sha1 = "0beec7b5ea3f0fdbc95d0dd47f3c5bc275da8a33";
    const sha256t = "2c26b46b68ffc68ff99b";
    const sha256 =
        "2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae";

    const invalid_a = "2c26b46b68ffc68ff99z";
    const invalid_b = "2c26b46b68ffc68ff96";

    try std.testing.expect(isValid(sha1));
    try std.testing.expect(isValid(sha256));
    try std.testing.expect(isValid(sha256t));
    try std.testing.expect(!isValid(invalid_a));
    try std.testing.expect(!isValid(invalid_b));
}

const Ghext = @This();

const std = @import("std");
const fs = std.fs;
const ascii = std.ascii;
const process = std.process;
const mem = std.mem;
