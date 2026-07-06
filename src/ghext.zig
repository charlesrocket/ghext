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

fn getState(allocator: mem.Allocator, io: std.Io) State {
    const proc = process.run(allocator, io, .{
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

    if (proc.term.exited == 1) {
        return State.Dirty;
    } else {
        return State.Clean;
    }
}

fn readWithGit(
    allocator: mem.Allocator,
    arr: *std.ArrayListAligned(u8, null),
    io: std.Io,
) !void {
    const proc = process.run(allocator, io, .{
        .argv = &.{
            "git",
            "rev-parse",
            "HEAD",
        },
    }) catch {
        return error.GitProcessFailure;
    };

    defer allocator.free(proc.stdout);
    defer allocator.free(proc.stderr);

    if (proc.term.exited == 0) {
        const head = mem.trimEnd(u8, proc.stdout, "\n");
        try arr.appendSlice(allocator, head);
    }

    if (proc.term.exited > 0) {
        return error.GitFailure;
    }
}

fn readWithoutGit(
    allocator: mem.Allocator,
    arr: *std.ArrayListAligned(u8, null),
    io: std.Io,
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

    const head_file = try Dir.cwd().openFile(io, head_location, .{});
    defer head_file.close(io);

    var head_reader = head_file.reader(io, &.{});

    const content = try head_reader.interface.allocRemaining(
        allocator,
        .limited(std.math.maxInt(usize)),
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

        const branch_clean = mem.trimEnd(u8, branch, "\n");

        const branch_file = Dir.cwd().openFile(
            io,
            branch_clean,
            .{},
        ) catch |err|
            switch (err) {
                error.FileNotFound => {
                    const ref_name = mem.trimEnd(u8, target, "\n");

                    head = try readFromPacks(
                        allocator,
                        git_dir,
                        ref_name,
                        io,
                    ) orelse
                        return error.RefNotFound;

                    defer allocator.free(head);

                    try arr.appendSlice(allocator, head);
                    return;
                },
                else => return err,
            };

        defer branch_file.close(io);

        var branch_reader = branch_file.reader(io, &.{});

        const branch_content = try branch_reader.interface.allocRemaining(
            allocator,
            .limited(std.math.maxInt(usize)),
        );

        defer allocator.free(branch_content);

        head = mem.trimEnd(u8, branch_content, "\n");
        try arr.appendSlice(allocator, head);
    } else {
        head = mem.trimEnd(u8, content, "\n");
        try arr.appendSlice(allocator, head);
    }
}

fn readFromPacks(
    allocator: mem.Allocator,
    git_dir: []const u8,
    ref_name: []const u8,
    io: std.Io,
) !?[]const u8 {
    const pack_location = try std.fmt.allocPrint(
        allocator,
        "{s}packed-refs",
        .{git_dir},
    );

    defer allocator.free(pack_location);

    const pack_file = try Dir.cwd().openFile(io, pack_location, .{});
    defer pack_file.close(io);

    var file_reader = pack_file.reader(io, &.{});

    const content = try file_reader.interface.allocRemaining(
        allocator,
        .limited(std.math.maxInt(usize)),
    );

    defer allocator.free(content);

    var lines = mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| {
        if (mem.startsWith(u8, line, "#")) continue;
        if (mem.startsWith(u8, line, "^")) continue;
        if (line.len == 0) continue;

        const space = mem.indexOfScalar(u8, line, ' ') orelse continue;
        const head = line[0..space];
        const name = mem.trimEnd(u8, line[space + 1 ..], "\r");

        if (mem.eql(u8, name, ref_name)) {
            return try allocator.dupe(u8, head);
        }
    }

    return null;
}

/// Creates `Ghext` instance using specified allocator and reads
/// the state of the repository.
pub fn init(allocator: mem.Allocator) !Ghext {
    var threaded: std.Io.Threaded = .init(allocator, .{
        .environ = std.process.Environ.empty,
    });

    defer threaded.deinit();

    const io = threaded.io();
    const binary = isGitInstalled(allocator, io);

    var state: State = .None;
    var arr: std.ArrayList(u8) = .empty;

    defer arr.deinit(allocator);

    if (GIT and binary) {
        state = getState(allocator, io);
        readWithGit(allocator, &arr, io) catch try readWithoutGit(
            allocator,
            &arr,
            io,
        );
    } else {
        try readWithoutGit(allocator, &arr, io);
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

fn isGitInstalled(allocator: mem.Allocator, io: std.Io) bool {
    const proc = process.run(allocator, io, .{
        .argv = &.{ "git", "--version" },
    }) catch {
        return false;
    };

    defer allocator.free(proc.stdout);
    defer allocator.free(proc.stderr);

    return proc.term.exited == 0;
}

fn isValid(sha: []const u8) bool {
    if (sha.len != 20 and sha.len != 40 and sha.len != 64) return false;
    for (sha) |byte| if (!ascii.isHex(byte)) return false;
    return true;
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

    try readWithGit(std.testing.allocator, &sha, std.testing.io);

    try std.testing.expect(sha.items.len == 40);
}

test "read (no git)" {
    var sha: std.ArrayList(u8) = .empty;
    defer sha.deinit(std.testing.allocator);

    try readWithoutGit(std.testing.allocator, &sha, std.testing.io);

    try std.testing.expect(sha.items.len == 40);
}

fn testDir(name: []const u8) !Dir {
    try Dir.cwd().createDir(std.testing.io, name, @enumFromInt(0o755));
    const dir = try Dir.cwd().openDir(std.testing.io, name, .{});

    return dir;
}

test "hash short" {
    const allocator = testing.allocator;
    const io = testing.io;

    var test_dir = try testDir("test-short-unchecked");
    var test_file_a = try test_dir.createFile(io, "HEAD", .{});
    var test_file_b = try test_dir.createFile(
        io,
        "test-short-unchecked-hash",
        .{},
    );

    var buf: [512]u8 = undefined;
    var w_a = test_file_a.writer(io, &buf);
    var w_b = test_file_b.writer(io, &buf);

    try w_a.interface.writeAll("ref: test-short-unchecked-hash");
    try w_a.interface.flush();

    try w_b.interface.writeAll("a0f4ea7d91495df92bbac2e2149dfb850fe81396");
    try w_b.interface.flush();

    PATH = "test-short-unchecked/";
    GIT = false;

    var ghx = try Ghext.init(allocator);
    const head = ghx.hash(HashLen.Short, Worktree.Unchecked);

    defer {
        test_file_a.close(io);
        test_file_b.close(io);
        test_dir.close(io);
        Dir.cwd().deleteTree(io, "test-short-unchecked") catch unreachable;
        ghx.deinit(allocator);
    }

    try std.testing.expectEqualStrings(
        "a0f4ea7",
        head,
    );
}

test "hash short (checked)" {
    const allocator = testing.allocator;
    const io = testing.io;

    var test_dir = try testDir("test-short-checked");
    var test_file_a = try test_dir.createFile(io, "HEAD", .{});
    var test_file_b = try test_dir.createFile(
        io,
        "test-short-checked-hash",
        .{},
    );

    var buf: [512]u8 = undefined;
    var w_a = test_file_a.writer(io, &buf);
    var w_b = test_file_b.writer(io, &buf);

    try w_a.interface.writeAll("ref: test-short-checked-hash");
    try w_a.interface.flush();

    try w_b.interface.writeAll("8b3fe94968382557818350080ad5f1f2510cc5be");
    try w_b.interface.flush();

    PATH = "test-short-checked/";
    GIT = false;

    var ghx = try Ghext.init(allocator);
    ghx.state = .Unknown;

    const head = ghx.hash(HashLen.Short, Worktree.Checked);

    defer {
        test_file_a.close(io);
        test_file_b.close(io);
        test_dir.close(io);
        Dir.cwd().deleteTree(io, "test-short-checked") catch unreachable;
        ghx.deinit(allocator);
    }

    try std.testing.expectEqualStrings(
        "8b3fe94-unverified",
        head,
    );
}

test "hash long" {
    const allocator = testing.allocator;
    const io = testing.io;

    var test_dir = try testDir("test-long-unchecked");
    var test_file_a = try test_dir.createFile(io, "HEAD", .{});
    var test_file_b = try test_dir.createFile(io, "test-long-hash", .{});

    var buf: [512]u8 = undefined;
    var w_a = test_file_a.writer(io, &buf);
    var w_b = test_file_b.writer(io, &buf);

    try w_a.interface.writeAll("ref: test-long-hash");
    try w_a.interface.flush();

    try w_b.interface.writeAll("bd3027fa569ea15ca76d84db21c67e2d514c1a5a");
    try w_b.interface.flush();

    PATH = "test-long-unchecked/";
    GIT = false;

    var ghx = try Ghext.init(allocator);
    const head = ghx.hash(HashLen.Long, Worktree.Unchecked);

    defer {
        test_file_a.close(io);
        test_file_b.close(io);
        test_dir.close(io);

        Dir.cwd().deleteTree(io, "test-long-unchecked") catch unreachable;
        ghx.deinit(allocator);
    }

    try std.testing.expectEqualStrings(
        "bd3027fa569ea15ca76d84db21c67e2d514c1a5a",
        head,
    );
}

test "hash long (checked)" {
    const allocator = testing.allocator;
    const io = testing.io;

    var test_dir = try testDir("test-long-checked");
    var test_file_a = try test_dir.createFile(io, "HEAD", .{});
    var test_file_b = try test_dir.createFile(
        io,
        "test-long-checked-hash",
        .{},
    );

    var buf: [512]u8 = undefined;
    var w_a = test_file_a.writer(io, &buf);
    var w_b = test_file_b.writer(io, &buf);

    try w_a.interface.writeAll("ref: test-long-checked-hash");
    try w_a.interface.flush();

    try w_b.interface.writeAll("ae0ee9bef0a8910e712488cc7801ade57d3a203a");
    try w_b.interface.flush();

    PATH = "test-long-checked/";
    GIT = false;

    var ghx = try Ghext.init(allocator);
    const head = ghx.hash(HashLen.Long, Worktree.Checked);

    defer {
        test_file_a.close(io);
        test_file_b.close(io);
        test_dir.close(io);

        Dir.cwd().deleteTree(io, "test-long-checked") catch unreachable;
        ghx.deinit(allocator);
    }

    try std.testing.expectEqualStrings(
        "ae0ee9bef0a8910e712488cc7801ade57d3a203a",
        head,
    );
}

test "hash long 256 (checked)" {
    const allocator = testing.allocator;
    const io = testing.io;

    var test_dir = try testDir("test-long-256-checked");
    var test_file_a = try test_dir.createFile(io, "HEAD", .{});
    var test_file_b = try test_dir.createFile(
        io,
        "test-long-256-checked-hash",
        .{},
    );

    var buf: [512]u8 = undefined;
    var w_a = test_file_a.writer(io, &buf);
    var w_b = test_file_b.writer(io, &buf);

    try w_a.interface.writeAll("ref: test-long-256-checked-hash");
    try w_a.interface.flush();

    try w_b.interface
        .writeAll("488a297bf1ea189193831ff2d90fa8c8daecd190111b1b137946a1eaca4eb83d");

    try w_b.interface.flush();

    PATH = "test-long-256-checked/";
    GIT = false;

    var ghx = try Ghext.init(allocator);
    ghx.state = .Unknown;
    const head = ghx.hash(HashLen.Long, Worktree.Checked);

    defer {
        test_file_a.close(io);
        test_file_b.close(io);
        test_dir.close(io);

        Dir.cwd().deleteTree(io, "test-long-256-checked") catch unreachable;
        ghx.deinit(allocator);
    }

    try std.testing.expectEqualStrings(
        "488a297bf1ea189193831ff2d90fa8c8daecd190111b1b137946a1eaca4eb83d-unverified",
        head,
    );
}

test "hash invalid" {
    const allocator = testing.allocator;
    const io = testing.io;

    var test_dir = try testDir("test-hash-invalid");
    var test_file = try test_dir.createFile(io, "HEAD", .{});

    var buf: [512]u8 = undefined;
    var w = test_file.writer(io, &buf);

    try w.interface.writeAll("foobar");
    try w.interface.flush();

    PATH = "test-hash-invalid/";
    GIT = false;

    defer {
        test_file.close(io);
        test_dir.close(io);
        Dir.cwd().deleteTree(io, "test-hash-invalid") catch unreachable;
    }

    try std.testing.expectError(
        error.InvalidHeadHash,
        Ghext.init(allocator),
    );
}

test "dirty" {
    const allocator = testing.allocator;
    const io = testing.io;

    var test_dir = try testDir("test-dirty");
    var test_file_a = try test_dir.createFile(io, "HEAD", .{});
    var test_file_b = try test_dir.createFile(io, "dirty-hash", .{});

    var buf: [512]u8 = undefined;
    var w_a = test_file_a.writer(io, &buf);
    var w_b = test_file_b.writer(io, &buf);

    try w_a.interface.writeAll("ref: dirty-hash");
    try w_a.interface.flush();

    try w_b.interface.writeAll("33797be57bc3b248fc5bfafd60af55a61787ce85");
    try w_b.interface.flush();

    PATH = "test-dirty/";
    GIT = false;

    var ghx = try Ghext.init(allocator);
    ghx.state = .Dirty;
    const head = ghx.hash(HashLen.Short, Worktree.Checked);

    defer {
        test_file_a.close(io);
        test_file_b.close(io);
        test_dir.close(io);

        Dir.cwd().deleteTree(io, "test-dirty") catch unreachable;
        ghx.deinit(allocator);
    }

    try std.testing.expectEqualStrings(
        "33797be-dirty",
        head,
    );
}

test "branch" {
    const allocator = testing.allocator;
    const io = testing.io;

    var test_dir = try testDir("test-branch");
    var test_file_a = try test_dir.createFile(io, "HEAD", .{});
    var test_file_b = try test_dir.createFile(io, "branch-hash", .{});

    var buf: [512]u8 = undefined;
    var w_a = test_file_a.writer(io, &buf);
    var w_b = test_file_b.writer(io, &buf);

    try w_a.interface.writeAll("ref: branch-hash");
    try w_a.interface.flush();

    try w_b.interface.writeAll("10d735e581f1e2505cd69675691925490e447c44");
    try w_b.interface.flush();

    PATH = "test-branch/";
    GIT = false;

    var ghx = try Ghext.init(allocator);

    defer {
        test_file_a.close(io);
        test_file_b.close(io);
        test_dir.close(io);

        Dir.cwd().deleteTree(io, "test-branch") catch unreachable;
        ghx.deinit(allocator);
    }

    try std.testing.expectEqualStrings(
        "10d735e581f1e2505cd69675691925490e447c44",
        ghx.head,
    );
}

test "packed" {
    const allocator = testing.allocator;
    const io = testing.io;

    var test_dir = try testDir("test-packed-refs");
    var head_file = try test_dir.createFile(io, "HEAD", .{});
    var packed_file = try test_dir.createFile(io, "packed-refs", .{});

    var buf: [512]u8 = undefined;
    var w_h = head_file.writer(io, &buf);
    var w_p = packed_file.writer(io, &buf);

    try w_h.interface.writeAll("ref: refs/heads/trunk");
    try w_h.interface.flush();

    try w_p.interface.writeAll(
        "# pack-refs with: peeled fully-peeled sorted\n" ++
            "7aca22de0b050687b471256624fbefc0b93a1ef5 refs/heads/trunk\n",
    );

    try w_p.interface.flush();

    PATH = "test-packed-refs/";
    GIT = false;

    var ghx = try Ghext.init(allocator);

    defer {
        head_file.close(io);
        packed_file.close(io);
        test_dir.close(io);

        Dir.cwd().deleteTree(io, "test-packed-refs") catch unreachable;
        ghx.deinit(allocator);
    }

    try std.testing.expectEqualStrings(
        "7aca22de0b050687b471256624fbefc0b93a1ef5",
        ghx.head,
    );
}

test "headless" {
    const allocator = testing.allocator;
    const io = testing.io;

    var test_dir = try testDir("test-headless");
    var test_file = try test_dir.createFile(io, "HEAD", .{});

    var buf: [512]u8 = undefined;
    var w = test_file.writer(io, &buf);

    try w.interface.writeAll("374444ea057e4d86d40f2a50d8191d771d96c2d7");
    try w.interface.flush();

    PATH = "test-headless/";
    GIT = false;

    var ghx = try Ghext.init(allocator);

    defer {
        test_file.close(io);
        test_dir.close(io);
        Dir.cwd().deleteTree(io, "test-headless") catch unreachable;
        ghx.deinit(allocator);
    }

    try std.testing.expectEqualStrings(
        "374444ea057e4d86d40f2a50d8191d771d96c2d7",
        ghx.head,
    );
}

test "trailing slash missing" {
    const allocator = testing.allocator;
    const io = testing.io;

    var test_dir = try testDir("test-slash");
    var test_file_a = try test_dir.createFile(io, "HEAD", .{});
    var test_file_b = try test_dir.createFile(io, "test-slash-hash", .{});

    var buf: [512]u8 = undefined;
    var w_a = test_file_a.writer(io, &buf);
    var w_b = test_file_b.writer(io, &buf);

    try w_a.interface.writeAll("ref: test-slash-hash");
    try w_a.interface.flush();

    try w_b.interface.writeAll("e89ab9218a22b23ffc73d7ee24ea6c1c97dd0470");
    try w_b.interface.flush();

    PATH = "test-slash";
    GIT = false;

    var ghx = try Ghext.init(allocator);

    defer {
        test_file_a.close(io);
        test_file_b.close(io);
        test_dir.close(io);

        Dir.cwd().deleteTree(io, "test-slash") catch unreachable;
        ghx.deinit(allocator);
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
const Dir = std.Io.Dir;
const ascii = std.ascii;
const process = std.process;
const mem = std.mem;
const testing = std.testing;
