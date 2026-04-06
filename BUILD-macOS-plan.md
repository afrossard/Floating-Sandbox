# macOS Apple Silicon Build Plan

High-level plan for building Floating Sandbox as a native macOS app on Apple Silicon (ARM64).

## Current State

The codebase has partial macOS support from previous contributions (2019-2022):
- `SysSpecifics.h` already detects macOS (`FS_IS_OS_MACOS()`) and ARM64 (`FS_IS_ARCHITECTURE_ARM_64()`) with NEON intrinsics
- OpenGL context rebinding workaround for macOS in `RenderContext.cpp`
- `GL_APPLE_vertex_array_object` extension support in `GameOpenGL_Ext.cpp`
- Multi-threaded rendering disabled on macOS in `MainApp.cpp`
- iconv dependency handled for APPLE in `CMakeLists.txt`

What's missing:
- No AppleClang compiler flags in `CMakeLists.txt` (only MSVC and GNU handled)
- No `UserSettings.example-macos.cmake`
- No macOS build documentation
- No `.app` bundle packaging
- Never tested/built with current codebase on Apple Silicon

## Plan

### Phase 1: Dev Environment Strategy ✅

Review and decide on the dependency/environment management approach. Goals: keep the host machine clean, make builds reproducible, and be CI-portable. Options to evaluate:

- **vcpkg** — C++-native package manager, installs deps locally to the project (`vcpkg_installed/`), integrates directly with CMake via toolchain file. Widely used in C++ projects. Good CI story (manifest mode + binary caching).
- **Conan** — Similar to vcpkg but Python-based. Strong versioning and reproducibility. Also integrates with CMake.
- **Homebrew + Brewfile** — Simplest to set up, but deps are global (not per-project). Less reproducible across machines.
- **Nix** — Most isolated and reproducible, but steep learning curve and less common for C++/macOS projects.

Decision criteria:
1. Can all required deps (wxWidgets 3.1.4, SFML 2.5.1, picojson, zlib, libjpeg, libpng, Google Test) be managed by the tool?
2. Does it keep the host clean (no global installs beyond the tool itself)?
3. How well does it integrate with CMake?
4. Can the same setup drive Linux CI builds?
5. How much friction does it add to the developer workflow?

This decision shapes Phase 2 (UserSettings), Phase 3 (dependency installation), and potentially CI setup later.

#### Decision: vcpkg with a recent baseline and dependency upgrades

**Why vcpkg over Conan**: Simpler CMake integration (just a toolchain file vs. a separate `conan install` step), no Python dependency, and better CI ergonomics out of the box. Conan's main advantage — fine-grained per-package version pinning — is unnecessary given the dependency upgrade decision below.

**Why vcpkg over Homebrew**: Homebrew installs globally, is not reproducible across machines, and has no lockfile. Doesn't meet the "clean host" goal.

**Why vcpkg over Nix**: Nix is the most isolated option but has a steep learning curve, rough macOS support, and is uncommon in the C++ ecosystem. Overkill for this project.

**Why upgrade dependencies to current versions**: A compatibility review confirmed that upgrading from wxWidgets 3.1.4 to 3.2.x is safe — no breaking API changes, and the project already handles HiDPI correctly. This eliminates the need for version pinning and lets us use a recent vcpkg baseline where all packages are current and tested together on ARM64/macOS. The same applies to SFML (2.5.1 → current).

**vcpkg approach**:
- Use **manifest mode** with a `vcpkg.json` at the repo root
- Set `builtin-baseline` to a recent vcpkg commit (acts as a reproducible snapshot of all package versions)
- No version overrides needed — current versions of all deps are acceptable
- To upgrade later: bump the baseline hash forward, test, commit
- Dependencies install into `vcpkg_installed/` (gitignored), keeping the host clean

### Phase 2: CMake AppleClang Support ⬅️ (next)

Add an `elseif("${CMAKE_CXX_COMPILER_ID}" STREQUAL "AppleClang")` block in the root `CMakeLists.txt` alongside the existing MSVC and GNU blocks. This needs:
- C++17 flags (should be default with modern AppleClang, but explicit)
- Warning flags (`-Wall`, `-Wcomment`)
- Release optimization flags (`-O3`, `-ffast-math` and friends, matching the GNU block)
- Debug flags (`-D_DEBUG`)
- Additional libraries for APPLE (handle `pthread`, `iconv`, framework linking)

Also verify that any `"GNU"` compiler ID checks in sub-project CMakeLists.txt files don't exclude AppleClang where they should include it.

Additionally, the `find_package` calls need updating for vcpkg's newer dependency versions:
- **wxWidgets 3.3.x**: vcpkg provides CMake config mode — use `find_package(wxWidgets CONFIG REQUIRED)` and link via `wx::core wx::base wx::gl wx::html wx::propgrid wx::ribbon` targets
- **SFML 3.x**: use `find_package(SFML COMPONENTS Audio System CONFIG REQUIRED)` and link via `SFML::Audio SFML::System` targets
- **picojson**: header-only in vcpkg — use `find_path(PICOJSON_INCLUDE_DIRS "picojson/picojson.h")` instead of `find_package(PicoJSON)`

### Phase 3: vcpkg Setup & Dependency Installation ✅

#### Prerequisites (via Homebrew)

These are the only tools installed globally on the host:

```bash
brew install cmake pkg-config
```

#### Uninstall

To fully remove the build environment from your machine:

```bash
# Remove Homebrew prerequisites
brew uninstall cmake pkg-config

# Remove vcpkg and all its cached builds
rm -rf <path-to-vcpkg>

# Remove vcpkg binary cache
rm -rf ~/.cache/vcpkg

# Remove VCPKG_ROOT from your shell profile (~/.zshrc or similar)

# Remove the build directory from the project
rm -rf build/
rm -rf vcpkg_installed/
```

#### One-time machine setup

Clone vcpkg and bootstrap it. The clone location is up to you:

```bash
git clone https://github.com/microsoft/vcpkg.git <path-of-your-choice>
<path-of-your-choice>/bootstrap-vcpkg.sh -disableMetrics
```

Then set `VCPKG_ROOT` in your shell profile (e.g. `~/.zshrc`) so the build can find it:

```bash
export VCPKG_ROOT=<path-of-your-choice>
```

#### Project setup

**1. Create `vcpkg.json`** at the repo root — this is the manifest that declares all dependencies:

See `vcpkg.json` in the repo root for the actual manifest. Key findings from validation:

- wxWidgets 3.3.x on vcpkg includes `gl`, `html`, `propgrid`, `ribbon` by default — no need to list them as features (and `core` cannot be listed explicitly)
- SFML feature `audio` is sufficient — `system` is pulled in automatically
- All 23 packages (including transitive deps) resolve and build successfully on arm64-osx in ~4 minutes

**2. Configure CMake** with the vcpkg toolchain file:

```bash
cmake -B build \
  -DCMAKE_TOOLCHAIN_FILE=$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake \
  -DCMAKE_BUILD_TYPE=Release \
  -DFS_BUILD_BENCHMARKS=OFF \
  -DFS_USE_STATIC_LIBS=ON \
  -DFS_INSTALL_DIRECTORY=~/floating-sandbox \
  ..
```

The toolchain file hooks into `find_package` automatically — no changes to `CMakeLists.txt` needed for dependency resolution. Dependencies are downloaded and built on first configure, then cached in `vcpkg_installed/`.

**3. Create `UserSettings.example-macos.cmake`** — with vcpkg handling most deps, this becomes minimal:

```cmake
set(FS_USE_STATIC_LIBS ON)
# Most dependencies are handled by vcpkg toolchain file.
# Only set paths for dependencies not in vcpkg (if any).
```

**4. Add to `.gitignore`**:
- `vcpkg_installed/` (built dependencies, per-project)

#### How it works day-to-day

- `vcpkg.json` is committed to the repo — all developers get the same dependency list
- `builtin-baseline` pins the exact versions — reproducible across machines
- Dependencies build locally on first `cmake` configure (~10-15 min), then are cached
- No global pollution — everything lives in `vcpkg_installed/` under the build tree
- To upgrade: bump the `builtin-baseline` hash to a newer vcpkg commit, re-configure

### Phase 4: Compile and Fix Build Errors

Attempt a build and fix compilation issues iteratively. Known risk areas:
- SIMD intrinsics: ARM NEON paths already exist but may need fixes for Apple's Clang
- OpenGL: macOS deprecated OpenGL after 10.14; headers may emit deprecation warnings. Suppress with `-DGL_SILENCE_DEPRECATION`
- wxWidgets: May need framework-style linking on macOS
- Any `#ifdef __linux__` or GNU-specific code paths that should also cover macOS
- 32-bit type assumptions (macOS Apple Silicon is always 64-bit)

### Phase 5: Run and Validate

Get the executable running:
- Verify OpenGL 2.1 context creation (macOS supports up to OpenGL 4.1 via compatibility profile)
- Test the simulation loop, rendering, and audio
- Run unit tests (`UnitTests` target)

### Phase 6: macOS .app Bundle (Optional / Future)

Package as a proper macOS `.app` bundle:
- Add `MACOSX_BUNDLE` property to the FloatingSandbox executable target
- Create `Info.plist` with bundle metadata
- Copy `Data/` resources into `Resources/` inside the bundle
- Handle executable path resolution (`CFBundleResourcesDirectory` vs current working dir)
- Code signing considerations

---

## Iteration Strategy

We'll tackle this one phase at a time:
1. ~~Phase 1 — decide on dev environment approach~~ ✅ decided on vcpkg
2. ~~Phase 3 — vcpkg setup + dependency installation~~ ✅ all 23 packages build on arm64-osx
3. Phase 2 — CMake AppleClang support + adapt find_package calls for new dep versions ⬅️ next
4. Phase 4 iteratively — build, fix, repeat
5. Phase 5 — smoke test
6. Phase 6 if we get a working build
