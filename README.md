# `ghext`
[![CI](https://github.com/charlesrocket/ghext/actions/workflows/ci.yml/badge.svg?branch=trunk)](https://github.com/charlesrocket/ghext/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/charlesrocket/ghext/branch/trunk/graph/badge.svg)](https://codecov.io/gh/charlesrocket/ghext)

Extract the hashes of last commits from `git` repositories with `ghext`. Supports standard and `build.zig` imports without requiring any dependencies.

## Installation

`build.zig.zon`:
```zig
.ghext = .{
    .url = "https://github.com/charlesrocket/ghext/archive/983eac9d280b2db7c7ca9ede2c977815c26b0074.tar.gz",
    .hash = "122081d642ad5e81b306b7a0b849b4f9e976f4653468eb18580d2115c3b4654b23b6",
},
```

## Usage

> [!NOTE]
> `git` binary is not required.

### Standard

`build.zig`:
```zig
const ghext_dep = b.dependency("ghext", .{
    .target = target,
    .optimize = optimize,
});

const ghext = ghext_dep.module("ghext");
exe.root_module.addImport("ghext", ghext);
```

`app.zig`:
```zig
const Ghext = @import("ghext");
var gxt = try Ghext.read(allocator);
defer gxt.deinit(allocator);

const hash_short = gxt.hash[0..7];
```

### Build system

`build.zig`:
```zig
const build_options = b.addOptions();

exe.root_module.addOptions("build_options", build_options);
build_options.addOption([]const u8, "head_hash", try hash());

inline fn hash() ![]const u8 {
    const gxt = @import("ghext").Ghext.read(std.heap.page_allocator) catch unreachable;
    return gxt.hash;
}
```

`app.zig`:
```zig
const build_opt = @import("build_options");
const hash = build_opt.head_hash[0..7];
```

## Documentation

[API reference](https://charlesrocket.github.io/ghext/)
