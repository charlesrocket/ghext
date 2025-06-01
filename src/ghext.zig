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

/// Directory of the HEAD file.
pub var PATH: []const u8 = ".git/";
/// Git executable usage toggle.
pub var GIT: bool = true;

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

fn readWithoutGit(
    arr: *std.ArrayListAligned(u8, null),
    allocator: mem.Allocator,
) !void {
    var buffer: [1024]u8 = undefined;
    var head: []const u8 = undefined;

    const head_location = try std.fmt.allocPrint(allocator, "{s}/HEAD", .{PATH});
    defer allocator.free(head_location);

    const content = try fs.cwd().readFile(head_location, &buffer);
    if (ascii.startsWithIgnoreCase(content, "ref: ")) {
        const target = try std.mem.replaceOwned(u8, allocator, content, "ref: ", "");
        defer allocator.free(target);
        const branch = try std.fmt.allocPrint(allocator, "{s}{s}", .{ PATH, target });
        defer allocator.free(branch);

        const branch_clean = mem.trimRight(u8, branch, "\n");
        const hash_tmp = try fs.cwd().readFile(branch_clean, &buffer);

        head = mem.trimRight(u8, hash_tmp, "\n");
    } else {
        head = mem.trimRight(u8, content, "\n");
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
        readWithGit(allocator, &arr) catch try readWithoutGit(&arr, allocator);
    } else {
        try readWithoutGit(&arr, allocator);
    }

    const head = try arr.toOwnedSlice();
    errdefer allocator.free(head);

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

test hash {
    var ghx = try Ghext.init(std.testing.allocator);
    defer ghx.deinit(std.testing.allocator);

    const short_hash = ghx.hash(HashLen.Short, Worktree.Unchecked);
    try std.testing.expect(short_hash.len == 7);
}

test "read" {
    var sha = std.ArrayList(u8).init(std.testing.allocator);
    defer sha.deinit();

    try readWithGit(std.testing.allocator, &sha);

    try std.testing.expect(sha.items.len == 40);
}

test "read (no git)" {
    var sha = std.ArrayList(u8).init(std.testing.allocator);
    defer sha.deinit();

    try readWithGit(std.testing.allocator, &sha);

    try std.testing.expect(sha.items.len == 40);
}

test "hash short" {
    try std.fs.cwd().makeDir("test-short-unchecked");
    var test_dir = try std.fs.cwd().openDir(
        "test-short-unchecked",
        .{ .iterate = true },
    );

    var test_file_a = try test_dir.createFile("HEAD", .{});
    var test_file_b = try test_dir.createFile("test-short-unchecked-hash", .{});
    try test_file_a.writeAll("ref: test-short-unchecked-hash");
    try test_file_b.writeAll("a0f4ea7d91495df92bbac2e2149dfb850fe81396");

    PATH = "test-short-unchecked/";
    GIT = false;

    var ghx = try Ghext.init(std.testing.allocator);
    const head = ghx.hash(HashLen.Short, Worktree.Unchecked);

    defer {
        test_file_a.close();
        test_file_b.close();
        test_dir.close();
        std.fs.cwd().deleteTree("test-short-unchecked") catch unreachable;
        ghx.deinit(std.testing.allocator);
    }

    try std.testing.expect(std.mem.eql(
        u8,
        "a0f4ea7",
        head,
    ));
}

test "hash short (checked)" {
    try std.fs.cwd().makeDir("test-short-checked");
    var test_dir = try std.fs.cwd().openDir(
        "test-short-checked",
        .{ .iterate = true },
    );

    var test_file_a = try test_dir.createFile("HEAD", .{});
    var test_file_b = try test_dir.createFile("test-short-checked-hash", .{});
    try test_file_a.writeAll("ref: test-short-checked-hash");
    try test_file_b.writeAll("8b3fe94968382557818350080ad5f1f2510cc5be");

    PATH = "test-short-checked/";
    GIT = false;

    var ghx = try Ghext.init(std.testing.allocator);
    ghx.state = .Unknown;

    const head = ghx.hash(HashLen.Short, Worktree.Checked);

    defer {
        test_file_a.close();
        test_file_b.close();
        test_dir.close();
        std.fs.cwd().deleteTree("test-short-checked") catch unreachable;
        ghx.deinit(std.testing.allocator);
    }

    try std.testing.expect(std.mem.eql(
        u8,
        "8b3fe94-unverified",
        head,
    ));
}

test "hash long" {
    try std.fs.cwd().makeDir("test-long-unchecked");
    var test_dir = try std.fs.cwd().openDir(
        "test-long-unchecked",
        .{ .iterate = true },
    );

    var test_file_a = try test_dir.createFile("HEAD", .{});
    var test_file_b = try test_dir.createFile("test-long-hash", .{});
    try test_file_a.writeAll("ref: test-long-hash");
    try test_file_b.writeAll("bd3027fa569ea15ca76d84db21c67e2d514c1a5a");

    PATH = "test-long-unchecked/";
    GIT = false;

    var ghx = try Ghext.init(std.testing.allocator);
    const head = ghx.hash(HashLen.Long, Worktree.Unchecked);

    defer {
        test_file_a.close();
        test_file_b.close();
        test_dir.close();
        std.fs.cwd().deleteTree("test-long-unchecked") catch unreachable;
        ghx.deinit(std.testing.allocator);
    }

    try std.testing.expect(std.mem.eql(
        u8,
        "bd3027fa569ea15ca76d84db21c67e2d514c1a5a",
        head,
    ));
}

test "hash long (checked)" {
    try std.fs.cwd().makeDir("test-long-checked");
    var test_dir = try std.fs.cwd().openDir(
        "test-long-checked",
        .{ .iterate = true },
    );

    var test_file_a = try test_dir.createFile("HEAD", .{});
    var test_file_b = try test_dir.createFile("test-long-checked-hash", .{});
    try test_file_a.writeAll("ref: test-long-checked-hash");
    try test_file_b.writeAll("ae0ee9bef0a8910e712488cc7801ade57d3a203a");

    PATH = "test-long-checked/";
    GIT = false;

    var ghx = try Ghext.init(std.testing.allocator);
    const head = ghx.hash(HashLen.Long, Worktree.Checked);

    defer {
        test_file_a.close();
        test_file_b.close();
        test_dir.close();
        std.fs.cwd().deleteTree("test-long-checked") catch unreachable;
        ghx.deinit(std.testing.allocator);
    }

    try std.testing.expect(std.mem.eql(
        u8,
        "ae0ee9bef0a8910e712488cc7801ade57d3a203a",
        head,
    ));
}

test "hash invalid" {
    try std.fs.cwd().makeDir("test-hash-invalid");
    var test_dir = try std.fs.cwd().openDir(
        "test-hash-invalid",
        .{ .iterate = true },
    );

    var test_file = try test_dir.createFile("HEAD", .{});
    try test_file.writeAll("foobar");

    PATH = "test-hash-invalid/";
    GIT = false;

    defer {
        test_file.close();
        test_dir.close();
        std.fs.cwd().deleteTree("test-hash-invalid") catch unreachable;
    }

    try std.testing.expectError(
        error.InvalidHeadHash,
        Ghext.init(std.testing.allocator),
    );
}

test "dirty" {
    try std.fs.cwd().makeDir("test-dirty");
    var test_dir = try std.fs.cwd().openDir(
        "test-dirty",
        .{ .iterate = true },
    );

    var test_file_a = try test_dir.createFile("HEAD", .{});
    var test_file_b = try test_dir.createFile("dirty-hash", .{});
    try test_file_a.writeAll("ref: dirty-hash");
    try test_file_b.writeAll("33797be57bc3b248fc5bfafd60af55a61787ce85");

    PATH = "test-dirty/";
    GIT = false;

    var ghx = try Ghext.init(std.testing.allocator);
    ghx.state = .Dirty;
    const head = ghx.hash(HashLen.Short, Worktree.Checked);

    defer {
        test_file_a.close();
        test_file_b.close();
        test_dir.close();
        std.fs.cwd().deleteTree("test-dirty") catch unreachable;
        ghx.deinit(std.testing.allocator);
    }

    try std.testing.expect(std.mem.eql(
        u8,
        "33797be-dirty",
        head,
    ));
}

test "branch" {
    try std.fs.cwd().makeDir("test-branch");
    var test_dir = try std.fs.cwd().openDir(
        "test-branch",
        .{ .iterate = true },
    );

    var test_file_a = try test_dir.createFile("HEAD", .{});
    var test_file_b = try test_dir.createFile("branch-hash", .{});
    try test_file_a.writeAll("ref: branch-hash");
    try test_file_b.writeAll("10d735e581f1e2505cd69675691925490e447c44");

    PATH = "test-branch/";
    GIT = false;

    var ghx = try Ghext.init(std.testing.allocator);

    defer {
        test_file_a.close();
        test_file_b.close();
        test_dir.close();
        std.fs.cwd().deleteTree("test-branch") catch unreachable;
        ghx.deinit(std.testing.allocator);
    }

    try std.testing.expect(std.mem.eql(
        u8,
        "10d735e581f1e2505cd69675691925490e447c44",
        ghx.head,
    ));
}

test "headless" {
    try std.fs.cwd().makeDir("test-headless");
    var test_dir = try std.fs.cwd().openDir(
        "test-headless",
        .{ .iterate = true },
    );

    var test_file = try test_dir.createFile("HEAD", .{});
    try test_file.writeAll("374444ea057e4d86d40f2a50d8191d771d96c2d7");

    PATH = "test-headless/";
    GIT = false;

    var ghx = try Ghext.init(std.testing.allocator);

    defer {
        test_file.close();
        test_dir.close();
        std.fs.cwd().deleteTree("test-headless") catch unreachable;
        ghx.deinit(std.testing.allocator);
    }

    try std.testing.expect(std.mem.eql(
        u8,
        "374444ea057e4d86d40f2a50d8191d771d96c2d7",
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
