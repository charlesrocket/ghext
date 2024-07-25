//! Extract HEAD hashes from `git` repositories, no dependencies.

const std = @import("std");
const fs = std.fs;

pub const Ghext = struct {
    /// Path to HEAD file.
    path: []const u8 = ".git/HEAD",
    /// Commit hash.
    hash: []const u8 = "none",
    /// Short commit hash.
    hash_short: []const u8 = "none",
    /// State
    dirty: bool = false,
    /// `git` binary detection.
    binary: bool,
    /// Memory allocator.
    allocator: std.mem.Allocator,

    fn getState(self: *Ghext) !void {
        const proc = try std.process.Child.run(.{
            .allocator = std.testing.allocator,
            .argv = &.{ "git", "diff-index", "--quiet", "HEAD", "--" },
        });

        defer self.allocator.free(proc.stdout);
        defer self.allocator.free(proc.stderr);

        if (proc.term.Exited == 1) {
            self.dirty = true;
        }
    }

    fn readWithGit(self: *Ghext) !void {
        const proc = try std.process.Child.run(.{
            .allocator = std.testing.allocator,
            .argv = &.{ "git", "rev-parse", "HEAD" },
        });

        defer self.allocator.free(proc.stdout);
        defer self.allocator.free(proc.stderr);

        if (proc.term.Exited == 0) {
            self.hash = std.mem.trimRight(u8, proc.stdout, "\n");
            self.hash_short = self.hash[0..7];
        }
    }

    fn readWithoutGit(self: *Ghext) !void {
        var buffer: [1024]u8 = undefined;
        var hash: []const u8 = undefined;
        const file = try std.fs.cwd().readFile(self.path, &buffer);

        if (std.ascii.startsWithIgnoreCase(file, "ref: ")) {
            const size = std.mem.replacementSize(u8, file, "ref: ", ".git/");
            const ref = try self.allocator.alloc(u8, size);
            defer self.allocator.free(ref);

            _ = std.mem.replace(u8, file, "ref: ", ".git/", ref);

            const branch = std.mem.trimRight(u8, ref, "\n");
            const hash_tmp = try std.fs.cwd().readFile(branch, &buffer);

            hash = std.mem.trimRight(u8, hash_tmp, "\n");
        } else {
            hash = std.mem.trimRight(u8, file, "\n");
        }

        self.hash = try std.mem.Allocator.dupe(self.allocator, u8, hash);
        defer self.allocator.free(self.hash);

        self.hash_short = self.hash[0..7];
    }

    pub fn read(self: *Ghext) !void {
        if (self.binary) {
            try self.getState();
            try self.readWithGit();
        } else {
            try self.readWithoutGit();
        }
    }

    pub fn init(allocator: std.mem.Allocator) !Ghext {
        var binary = false;
        const proc = try std.process.Child.run(.{
            .allocator = std.testing.allocator,
            .argv = &.{ "git", "--version" },
        });

        defer allocator.free(proc.stdout);
        defer allocator.free(proc.stderr);

        if (proc.term.Exited == 0) {
            binary = true;
        }

        return .{ .allocator = allocator, .binary = binary };
    }

    pub fn deinit(self: *Ghext) void {
        if (!std.mem.eql(u8, self.hash, "none")) {
            if (!self.binary) {
                self.allocator.free(self.hash);
            }
        }
    }

    fn gitInstalled(self: *Ghext) bool {
        const proc = try std.process.Child.run(.{
            .allocator = std.testing.allocator,
            .argv = &.{ "git", "--version" },
        });

        defer self.allocator.free(proc.stdout);
        defer self.allocator.free(proc.stderr);

        if (proc.term.Exited == 1) {
            return true;
        } else {
            return false;
        }
    }
};
const testing = std.testing;

test "read" {
    var ghx = try Ghext.init(testing.allocator);
    defer ghx.deinit();

    _ = try ghx.read();

    try testing.expect(ghx.hash_short.len == 7);
    try testing.expect(ghx.hash.len == 40);
}

test "read (git)" {
    var ghx = try Ghext.init(testing.allocator);
    defer ghx.deinit();

    _ = try ghx.readWithGit();

    try testing.expect(ghx.hash_short.len == 7);
    try testing.expect(ghx.hash.len == 40);
}

test "read (no git)" {
    var ghx = try Ghext.init(testing.allocator);
    defer ghx.deinit();

    _ = try ghx.readWithoutGit();

    try testing.expect(ghx.hash_short.len == 7);
    try testing.expect(ghx.hash.len == 40);
}
