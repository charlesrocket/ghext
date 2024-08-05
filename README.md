# `ghext`
[![CI](https://github.com/charlesrocket/ghext/actions/workflows/ci.yml/badge.svg?branch=trunk)](https://github.com/charlesrocket/ghext/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/charlesrocket/ghext/branch/trunk/graph/badge.svg)](https://codecov.io/gh/charlesrocket/ghext)

Extract the hashes of the last commit from `git` repositories with `ghext`.

## Installation

`build.zig`:
```zig
const ghext_dep = b.dependency("ghext", .{
    .target = target,
    .optimize = optimize,
});

const ghext = ghext_dep.module("ghext");
exe.root_module.addImport("ghext", ghext);
```

`build.zig.zon`:
```zig
.ghext = .{
    .url = "https://github.com/charlesrocket/ghext/archive/refs/tags/0.3.0.tar.gz",
    .hash = "12200acee906e217dafde5539a1e5905d093c97b6ba2408e0653772814e3643efc76",
},
```

### Example

```zig
const Ghext = @import("ghext");
var gxt = try Ghext.read(allocator);
defer gxt.deinit(allocator);

const hash_short = gxt.hash[0..7];
```

## Documentation

[API reference](https://charlesrocket.github.io/ghext/)
