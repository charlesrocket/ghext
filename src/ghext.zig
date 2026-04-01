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

    defer allocator.free(proc.stdout);
    defer allocator.free(proc.stderr);

    if (proc.term.Exited == 0) {
        const head = mem.trimRight(u8, proc.stdout, "\n");
        try arr.appendSlice(allocator, head);
    }

    if (proc.term.Exited > 0) {
        return error.GitFailure;
    }
}

fn readWithoutGit(
    allocator: mem.Allocator,
    arr: *std.ArrayListAligned(u8, null),
) !void {
    var head: []const u8 = undefined;

    const path_slash = try isTrailingSlash(PATH);
    const git_dir = if (path_slash) PATH else try std.fmt.allocPrint(
        allocator,
        "{s}/",
        .{PATH},
    );

    const head_location = try std.fmt.allocPrint(
        allocator,
        "{s}HEAD",
        .{git_dir},
    );

    defer {
        allocator.free(head_location);
        if (!path_slash) allocator.free(git_dir);
    }

    const head_file = try fs.cwd().openFile(head_location, .{});
    defer head_file.close();

    const content = try head_file.readToEndAlloc(
        allocator,
        std.math.maxInt(usize),
    );

    defer allocator.free(content);

    if (ascii.startsWithIgnoreCase(content, "ref: ")) {
        const target = try mem.replaceOwned(
            u8,
            allocator,
            content,
            "ref: ",
            "",
        );

        const branch = try std.fmt.allocPrint(
            allocator,
            "{s}{s}",
            .{ git_dir, target },
        );

        defer {
            allocator.free(target);
            allocator.free(branch);
        }

        const branch_clean = mem.trimRight(u8, branch, "\n");

        const branch_file = fs.cwd().openFile(branch_clean, .{}) catch |err|
            switch (err) {
                error.FileNotFound => {
                    const ref_name = mem.trimRight(u8, target, "\n");

                    head = try readFromPacks(
                        allocator,
                        git_dir,
                        ref_name,
                    ) orelse
                        return error.RefNotFound;

                    defer allocator.free(head);

                    try arr.appendSlice(allocator, head);
                    return;
                },
                else => return err,
            };

        defer branch_file.close();

        const hash_tmp = try branch_file.readToEndAlloc(
            allocator,
            std.math.maxInt(usize),
        );

        defer allocator.free(hash_tmp);

        head = mem.trimRight(u8, hash_tmp, "\n");
        try arr.appendSlice(allocator, head);
    } else {
        head = mem.trimRight(u8, content, "\n");
        try arr.appendSlice(allocator, head);
    }
}

fn readFromPacks(
    allocator: mem.Allocator,
    git_dir: []const u8,
    ref_name: []const u8,
) !?[]const u8 {
    const packed_path = try std.fmt.allocPrint(
        allocator,
        "{s}packed-refs",
        .{git_dir},
    );

    defer allocator.free(packed_path);

    const file = fs.cwd().openFile(packed_path, .{}) catch |err|
        switch (err) {
            error.FileNotFound => return null,
            else => return err,
        };

    defer file.close();

    const pack = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(pack);

    var lines = mem.splitScalar(u8, pack, '\n');

    while (lines.next()) |line| {
        if (mem.startsWith(u8, line, "#")) continue;
        if (mem.startsWith(u8, line, "^")) continue;
        if (line.len == 0) continue;

        const space = mem.indexOfScalar(u8, line, ' ') orelse continue;
        const head = line[0..space];
        const name = mem.trimRight(u8, line[space + 1 ..], "\r");

        if (mem.eql(u8, name, ref_name)) {
            return try allocator.dupe(u8, head);
        }
    }

    return null;
}

/// Creates `Ghext` instance using specified allocator and reads
/// the state of the repository.
pub fn init(allocator: mem.Allocator) !Ghext {
    const binary = isGitInstalled(allocator);
    var state: State = .None;
    var arr: std.ArrayList(u8) = .empty;
    defer arr.deinit(allocator);

    if (GIT and binary) {
        state = getState(allocator);
        readWithGit(allocator, &arr) catch try readWithoutGit(
            allocator,
            &arr,
        );
    } else {
        try readWithoutGit(allocator, &arr);
    }

    const head = try arr.toOwnedSlice(allocator);
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
    var buffer: [75]u8 = undefined;
    var arr = std.ArrayListUnmanaged(u8).initBuffer(&buffer);

    switch (length) {
        .Short => arr.appendSliceBounded(self.head[0..7]) catch
            return self.head[0..7],
        .Long => arr.appendSliceBounded(self.head) catch return self.head,
    }

    if (check == .Checked) {
        if (self.state == .Dirty) {
            arr.appendSliceBounded("-dirty") catch
                return arr.items;
        } else if (self.state == .Unknown) {
            arr.appendSliceBounded("-unverified") catch
                return arr.items;
        }
    }

    return arr.items;
}

fn isTrailingSlash(path: []const u8) !bool {
    if (path.len == 0) return error.EmptyPath;
    const last_char = path[path.len - 1];
    return last_char == 47;
}

fn isGitInstalled(allocator: mem.Allocator) bool {
    const proc = process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "--version" },
    }) catch {
        return false;
    };

    defer allocator.free(proc.stdout);
    defer allocator.free(proc.stderr);

    return proc.term.Exited == 0;
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
    var sha: std.ArrayList(u8) = .empty;
    defer sha.deinit(std.testing.allocator);

    try readWithGit(std.testing.allocator, &sha);

    try std.testing.expect(sha.items.len == 40);
}

test "read (no git)" {
    var sha: std.ArrayList(u8) = .empty;
    defer sha.deinit(std.testing.allocator);

    try readWithoutGit(std.testing.allocator, &sha);

    try std.testing.expect(sha.items.len == 40);
}

fn testDir(name: []const u8) !fs.Dir {
    try fs.cwd().makeDir(name);
    const dir = try fs.cwd().openDir(
        name,
        .{ .iterate = true },
    );

    return dir;
}

test "hash short" {
    var test_dir = try testDir("test-short-unchecked");
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
        fs.cwd().deleteTree("test-short-unchecked") catch unreachable;
        ghx.deinit(std.testing.allocator);
    }

    try std.testing.expectEqualStrings(
        "a0f4ea7",
        head,
    );
}

test "hash short (checked)" {
    var test_dir = try testDir("test-short-checked");
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
        fs.cwd().deleteTree("test-short-checked") catch unreachable;
        ghx.deinit(std.testing.allocator);
    }

    try std.testing.expectEqualStrings(
        "8b3fe94-unverified",
        head,
    );
}

test "hash long" {
    var test_dir = try testDir("test-long-unchecked");
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
        fs.cwd().deleteTree("test-long-unchecked") catch unreachable;
        ghx.deinit(std.testing.allocator);
    }

    try std.testing.expectEqualStrings(
        "bd3027fa569ea15ca76d84db21c67e2d514c1a5a",
        head,
    );
}

test "hash long (checked)" {
    var test_dir = try testDir("test-long-checked");
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
        fs.cwd().deleteTree("test-long-checked") catch unreachable;
        ghx.deinit(std.testing.allocator);
    }

    try std.testing.expectEqualStrings(
        "ae0ee9bef0a8910e712488cc7801ade57d3a203a",
        head,
    );
}

test "hash long 256 (checked)" {
    var test_dir = try testDir("test-long-256-checked");
    var test_file_a = try test_dir.createFile("HEAD", .{});
    var test_file_b = try test_dir.createFile("test-long-256-checked-hash", .{});
    try test_file_a.writeAll("ref: test-long-256-checked-hash");
    try test_file_b
        .writeAll("488a297bf1ea189193831ff2d90fa8c8daecd190111b1b137946a1eaca4eb83d");

    PATH = "test-long-256-checked/";
    GIT = false;

    var ghx = try Ghext.init(std.testing.allocator);
    ghx.state = .Unknown;
    const head = ghx.hash(HashLen.Long, Worktree.Checked);

    defer {
        test_file_a.close();
        test_file_b.close();
        test_dir.close();
        fs.cwd().deleteTree("test-long-256-checked") catch unreachable;
        ghx.deinit(std.testing.allocator);
    }

    try std.testing.expectEqualStrings(
        "488a297bf1ea189193831ff2d90fa8c8daecd190111b1b137946a1eaca4eb83d-unverified",
        head,
    );
}

test "hash invalid" {
    var test_dir = try testDir("test-hash-invalid");
    var test_file = try test_dir.createFile("HEAD", .{});
    try test_file.writeAll("foobar");

    PATH = "test-hash-invalid/";
    GIT = false;

    defer {
        test_file.close();
        test_dir.close();
        fs.cwd().deleteTree("test-hash-invalid") catch unreachable;
    }

    try std.testing.expectError(
        error.InvalidHeadHash,
        Ghext.init(std.testing.allocator),
    );
}

test "dirty" {
    var test_dir = try testDir("test-dirty");
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
        fs.cwd().deleteTree("test-dirty") catch unreachable;
        ghx.deinit(std.testing.allocator);
    }

    try std.testing.expectEqualStrings(
        "33797be-dirty",
        head,
    );
}

test "branch" {
    var test_dir = try testDir("test-branch");
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
        fs.cwd().deleteTree("test-branch") catch unreachable;
        ghx.deinit(std.testing.allocator);
    }

    try std.testing.expectEqualStrings(
        "10d735e581f1e2505cd69675691925490e447c44",
        ghx.head,
    );
}

test "packed" {
    var test_dir = try testDir("test-packed-refs");
    var head_file = try test_dir.createFile("HEAD", .{});
    var packed_file = try test_dir.createFile("packed-refs", .{});
    try head_file.writeAll("ref: refs/heads/trunk");
    try packed_file.writeAll(
        "# pack-refs with: peeled fully-peeled sorted\n" ++
            "7aca22de0b050687b471256624fbefc0b93a1ef5 refs/heads/trunk\n",
    );

    PATH = "test-packed-refs/";
    GIT = false;

    var ghx = try Ghext.init(std.testing.allocator);

    defer {
        head_file.close();
        packed_file.close();
        test_dir.close();
        fs.cwd().deleteTree("test-packed-refs") catch unreachable;
        ghx.deinit(std.testing.allocator);
    }

    try std.testing.expectEqualStrings(
        "7aca22de0b050687b471256624fbefc0b93a1ef5",
        ghx.head,
    );
}

test "headless" {
    var test_dir = try testDir("test-headless");
    var test_file = try test_dir.createFile("HEAD", .{});
    try test_file.writeAll("374444ea057e4d86d40f2a50d8191d771d96c2d7");

    PATH = "test-headless/";
    GIT = false;

    var ghx = try Ghext.init(std.testing.allocator);

    defer {
        test_file.close();
        test_dir.close();
        fs.cwd().deleteTree("test-headless") catch unreachable;
        ghx.deinit(std.testing.allocator);
    }

    try std.testing.expectEqualStrings(
        "374444ea057e4d86d40f2a50d8191d771d96c2d7",
        ghx.head,
    );
}

test "trailing slash missing" {
    var test_dir = try testDir("test-slash");
    var test_file_a = try test_dir.createFile("HEAD", .{});
    var test_file_b = try test_dir.createFile("test-slash-hash", .{});
    try test_file_a.writeAll("ref: test-slash-hash");
    try test_file_b.writeAll("e89ab9218a22b23ffc73d7ee24ea6c1c97dd0470");

    PATH = "test-slash";
    GIT = false;

    var ghx = try Ghext.init(std.testing.allocator);

    defer {
        test_file_a.close();
        test_file_b.close();
        test_dir.close();
        fs.cwd().deleteTree("test-slash") catch unreachable;
        ghx.deinit(std.testing.allocator);
    }

    try std.testing.expectEqualStrings(
        "e89ab9218a22b23ffc73d7ee24ea6c1c97dd0470",
        ghx.head,
    );
}

test "head file missing" {
    PATH = "foo";
    GIT = false;

    try std.testing.expectError(
        error.FileNotFound,
        Ghext.init(std.testing.allocator),
    );
}

test "empty path" {
    PATH = "";
    GIT = false;

    try std.testing.expectError(
        error.EmptyPath,
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
