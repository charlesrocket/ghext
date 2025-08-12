# `ghext`
[![CI](https://github.com/charlesrocket/ghext/actions/workflows/ci.yml/badge.svg?branch=trunk)](https://github.com/charlesrocket/ghext/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/charlesrocket/ghext/branch/trunk/graph/badge.svg)](https://codecov.io/gh/charlesrocket/ghext)

Extract the hashes of last commits from `git` repositories with `ghext`.

## Installation

`build.zig.zon`:
```zig
.ghext = .{
    .url = "https://github.com/charlesrocket/ghext/archive/refs/tags/0.7.3.tar.gz",
    .hash = "ghext-0.7.3-dKaQNz1QAACVOGFjt6xRQR2hwo4u3Wa-hYXdl_hYSVn2",
},
```

## Usage

> [!NOTE]
> `git` binary is not required.

[Example](https://github.com/charlesrocket/xtxf/blob/trunk/build.zig)

### Build system

`build.zig`:
```zig
const Ghext = @import("ghext").Ghext;
const build_options = b.addOptions();

exe.root_module.addOptions("build_options", build_options);
build_options.addOption([]const u8, "version", version(b));

fn version(b: *std.Build) []const u8 {
    const semver = manifest.version;
    var gxt = Ghext.init(std.heap.page_allocator) catch return semver;
    const hash = gxt.hash(Ghext.HashLen.Short, Ghext.Worktree.Checked);
    return b.fmt("{s} {s}", .{ semver, hash });
}

const manifest: struct {
    const Dependency = struct {
        url: []const u8,
        hash: []const u8,
        lazy: bool = false,
    };

    name: enum { APPNAME },
    version: []const u8,
    fingerprint: u64,
    paths: []const []const u8,
    minimum_zig_version: []const u8,
    dependencies: struct {
        ghext: Dependency,
    },
} = @import("build.zig.zon");
```

`main.zig`:
```zig
const build_options = @import("build_options");
const VERSION = build_options.version;
```

## Documentation

[API reference](https://charlesrocket.github.io/ghext/)
