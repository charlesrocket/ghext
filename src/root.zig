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
    /// Memory allocator.
    allocator: std.mem.Allocator,

    pub fn readWithoutGit(self: *Ghext) !void {
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
        self.hash_short = self.hash[0..7];
    }

    pub fn init(allocator: std.mem.Allocator) Ghext {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Ghext) void {
        self.allocator.free(self.hash);
    }
};

const testing = std.testing;

test "read" {
    var ghx = Ghext.init(testing.allocator);
    defer ghx.deinit();

    _ = try ghx.readWithoutGit();

    try testing.expect(ghx.hash_short.len == 7);
    try testing.expect(ghx.hash.len == 40);
}
