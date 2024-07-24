const std = @import("std");
const fs = std.fs;

pub const Ghext = struct {
    path: []const u8 = ".git/HEAD",
    head: []const u8 = "none",
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Ghext {
        return .{ .allocator = allocator };
    }

    pub fn read(self: *Ghext) !void {
        var buffer: [164]u8 = undefined;
        const file = try std.fs.cwd().readFile(self.path, &buffer);
        const size = std.mem.replacementSize(u8, file, "ref: ", ".git/");
        const ref = try self.allocator.alloc(u8, size);
        defer self.allocator.free(ref);

        _ = std.mem.replace(u8, file, "ref: ", ".git/", ref);

        const branch = std.mem.trimRight(u8, ref, "\n");
        const head_tmp = try std.fs.cwd().readFile(branch, &buffer);
        const head = std.mem.trimRight(u8, head_tmp, "\n");

        self.head = try std.mem.Allocator.dupe(self.allocator, u8, head);
    }

    pub fn deinit(self: *Ghext) void {
        self.allocator.free(self.head);
    }
};

const testing = std.testing;

test "read" {
    var ghx = Ghext.init(testing.allocator);
    defer ghx.deinit();

    _ = try ghx.read();
}
