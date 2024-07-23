const std = @import("std");
const fs = std.fs;

pub const Ghext = struct {
    pub fn init() Ghext {}
    pub fn deinit() void {}
};

const testing = std.testing;

test "default" {
}
