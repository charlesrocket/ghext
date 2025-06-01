# Changelog

All notable changes to this project will be documented in this file.

## [0.7.1] - 2025-06-01

### Bug Fixes

- Deallocate on errors
- Improve head detection
- Handle trailing slash

### Documentation

- Update installation

### Miscellaneous tasks

- Ignore test files

### Refactor

- Move deallocations

### Styling

- Fix test formatting
- Reformat `readWithoutGit()`

### Testing

- Add `headless`
- Add `branch`
- Add `hash invalid`
- Optimize errors
- Expand cases
- Move head files
- Add `testDir()`
- Add `empty path`

## [0.7.0] - 2025-05-30

### Bug Fixes

- Use `BoundedArray`
- Improve error handling

### Documentation

- Update installation
- Update app usage
- Update build usage
- Drop standard usage
- Comment `HashLen`
- Update example
- Fix manifest example

### Features

- [**breaking**] Add `state`
- Expose `PATH`
- Add `GIT` switch

### Refactor

- Optimize `hash()`

### Styling

- Move `deinit()`

### Testing

- Add `hash_dirty`
- Fix `ghx.state` definitions
- Rename cases

### Build

- Update `paths`

## [0.6.0] - 2025-05-28

### Documentation

- Update installation
- Update usage
- Update returned value

### Features

- [**breaking**] Improve hash getter

### Refactor

- Move validation subroutine

## [0.5.2] - 2025-05-24

### Documentation

- Update README
- Add example

### Features

- [**breaking**] Add `hash_short()`

### Refactor

- [**breaking**] `read()` -> `init()`

## [0.5.1] - 2025-04-19

### Bug Fixes

- Update name value

### Miscellaneous tasks

- Update LICENSE

### Operations

- Bump codecov/codecov-action from 4 to 5
- Run coverage in jammy
- Bump zig version to 0.14

### Styling

- Reformat root file
- Reformat build file

### Build

- Set minimum zig version
- Add fingerprint
- Bump version to 0.5.1

## [0.5.0] - 2024-08-27

### Bug Fixes

- Catch binary check errors
- [**breaking**] Make `dirty` optional

### Features

- [**breaking**] Add binary/fs errors

### Refactor

- Drop `gitInstalled()` error
- Reformat `sha.len` switch

## [0.4.1] - 2024-08-25

### Bug Fixes

- Update `root_source_file`
- Update `docs` step
- Correct library name

### Refactor

- Move source struct

### Build

- Fix `docs` step

## [0.4.0] - 2024-08-23

### Documentation

- Add example
- Use `hash_short`
- Update description
- Add build system setup
- Update ghext commit
- Add build system usage

### Features

- Expose `Ghext` for build system usage

## [0.3.0] - 2024-08-04

### Bug Fixes

- Fix binary check

### Documentation

- Update comments
- Comment `deinit()`

### Features

- Add validator
- Support SHA256

### Refactor

- Drop redundant `@This()`

## [0.2.0] - 2024-07-29

### Bug Fixes

- Use local allocator
- Replace allocators
- [**breaking**] Drop `Self.allocator`
- Correct slice ownership
- Use fixed size array

### Features

- Use local module

### Operations

- Rename docs task

### Refactor

- Drop `Self`

## [0.1.0] - 2024-07-25

### Documentation

- Add readme
- Comment main struct
- Add changelog

### Features

- Add `Ghext`
- Add `read()`
- Add `hash_short`
- Support tags
- Add repository state

### Miscellaneous tasks

- Add gitignore
- Add license

### Operations

- Setup integrations
- Configure codecov
- Add `release` job
- Deploy documentation

### Build

- Generate documentation
- Add `lib`
- Fix docs step


