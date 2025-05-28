# `ghext`
[![CI](https://github.com/charlesrocket/ghext/actions/workflows/ci.yml/badge.svg?branch=trunk)](https://github.com/charlesrocket/ghext/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/charlesrocket/ghext/branch/trunk/graph/badge.svg)](https://codecov.io/gh/charlesrocket/ghext)

Extract the hashes of last commits from `git` repositories with `ghext`. Supports standard and `build.zig` imports without requiring any dependencies.

## Installation

`build.zig.zon`:
```zig
.ghext = .{
    .url = "https://github.com/charlesrocket/ghext/archive/refs/tags/0.6.0.tar.gz",
    .hash = "1220fbef19ebbea4057d1671778bfb2b06538c921a3801d550dbf1c55523874c8c0e",
},
```

## Usage

> [!NOTE]
> `git` binary is not required.

[Example](https://github.com/charlesrocket/xtxf/blob/trunk/build.zig)

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

var gxt = try Ghext.init(allocator);
defer gxt.deinit(allocator);

const hash = gxt.hash(Ghext.HashLen.Short, Ghext.Worktree.Checked);
```

### Build system

`build.zig`:
```zig
const build_options = b.addOptions();

exe.root_module.addOptions("build_options", build_options);
build_options.addOption([]const u8, "head_hash", try hash());

fn hash() ![]const u8 {
    const gxt = @import("ghext").Ghext.init(std.heap.page_allocator) catch
        unreachable;

    return gxt.head;
}
```

`app.zig`:
```zig
const build_opt = @import("build_options");
const hash = build_opt.head_hash[0..7];
```

## Documentation

[API reference](https://charlesrocket.github.io/ghext/)
