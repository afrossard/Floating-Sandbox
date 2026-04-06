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

#### Initial decision: vcpkg (later rolled back — see below)

We initially chose vcpkg for its per-project isolation and reproducible version pinning:

**Why vcpkg over Conan**: Simpler CMake integration (just a toolchain file vs. a separate `conan install` step), no Python dependency, and better CI ergonomics out of the box.

**Why vcpkg over Homebrew**: Homebrew installs globally, is not reproducible across machines, and has no lockfile. Doesn't meet the "clean host" goal.

**Why vcpkg over Nix**: Nix is the most isolated option but has a steep learning curve, rough macOS support, and is uncommon in the C++ ecosystem. Overkill for this project.

We validated vcpkg end-to-end: created a `vcpkg.json` manifest, bootstrapped vcpkg, and confirmed all 23 packages (including transitive deps) build successfully on arm64-osx in ~4 minutes.

#### Problem: vcpkg forces dependency version upgrades

vcpkg's current packages are wxWidgets 3.3.x and SFML 3.x. These newer versions use **different CMake target names**:

```cmake
# Old (what the existing build uses):
${wxWidgets_LIBRARIES}           # variable-based linking
sfml-audio sfml-system           # plain library names

# New (vcpkg 3.3.x / 3.x):
wx::core wx::base wx::gl         # CMake imported targets
SFML::Audio SFML::System         # CMake imported targets
```

This means adopting vcpkg requires rewriting `find_package` calls and `target_link_libraries` across 6+ CMakeLists.txt files — not just for macOS, but in a way that either breaks the existing Windows/Linux builds or requires conditional paths for both old and new styles.

#### Key insight: the AppImage build didn't change the build system

The Linux AppImage build (in `floating-sandbox-appimage`) uses a Containerfile that installs deps via apt-get + builds wxWidgets 3.1.4 from source, then runs the existing CMake build **completely unchanged**. No new package manager, no `find_package` rewrites. This is the simplest and most proven approach.

#### Why not a macOS container/VM?

We considered using a macOS VM for isolation (similar to the Linux container approach):

| | **Pros** | **Cons** |
|---|---|---|
| Isolation | Fully clean, snapshot/restore | Heavy — 30-50GB disk per VM |
| Reproducibility | Pin macOS version + deps | Manual setup (no Dockerfile equivalent for macOS) |
| CI portability | None — GitHub Actions already provides clean macOS runners | Adds complexity without CI benefit |
| Tooling | Tart (CLI-friendly), UTM, Apple Virtualization.framework | No standard container format like Docker |

**Verdict**: Overkill for this project. GitHub Actions already gives a clean macOS VM per CI run. For local dev, Homebrew deps are easy to install and uninstall.

#### Why version pinning is a separate concern

vcpkg's main advantage — reproducible version pinning via `builtin-baseline` — solves a real problem, but it's a **cross-platform project concern**, not specific to the macOS build. The Linux build has the same issue (apt versions can drift). Solving this only for macOS while Linux uses apt and Windows uses manually downloaded libs would be inconsistent. This should be addressed as a separate project for all platforms.

#### Revised decision: Homebrew + compatible versions (no build system changes)

Homebrew provides version-pinned formulas that are compatible with the existing build system:

| Dependency | Homebrew formula | Version | Compatible with existing CMakeLists? |
|---|---|---|---|
| wxWidgets | `wxwidgets@3.2` | 3.2.10 | Yes — API compatible with 3.1.4 (verified) |
| SFML | `sfml@2` | 2.6.2 | Yes — backward compatible with 2.5.x |
| picojson | `picojson` | 1.3.0 | Yes |
| zlib, libpng, jpeg | system / brew | current | Yes |
| Google Test | build from source | any | Yes — already `add_subdirectory()` |

Both `wxwidgets@3.2` and `sfml@2` are keg-only (installed under `/opt/homebrew/opt/`, not linked globally), so they require explicit paths in `UserSettings.cmake` or `CMAKE_PREFIX_PATH` — but this is the same pattern already used on Windows and Linux.

**This approach**:
- Requires **zero changes** to `find_package` calls or `target_link_libraries`
- The only CMake change needed is adding **AppleClang compiler flags** (Phase 2)
- Follows the same pattern as the AppImage build: OS package manager + minimal CMake additions
- Easy to set up and easy to uninstall (`brew uninstall`)
- Works on GitHub Actions macOS runners (`brew install` in CI)

### Phase 2: CMake AppleClang Support ⬅️ (next)

Add an `elseif("${CMAKE_CXX_COMPILER_ID}" STREQUAL "AppleClang")` block in the root `CMakeLists.txt` alongside the existing MSVC and GNU blocks. This needs:
- C++17 flags (should be default with modern AppleClang, but explicit)
- Warning flags (`-Wall`, `-Wcomment`)
- Release optimization flags (`-O3`, `-ffast-math` and friends, matching the GNU block)
- Debug flags (`-D_DEBUG`)
- Additional libraries for APPLE (handle `pthread`, `iconv`, framework linking)

Also verify that any `"GNU"` compiler ID checks in sub-project CMakeLists.txt files don't exclude AppleClang where they should include it. Known location:
- `Sources/OpenGLCore/CMakeLists.txt:41` — links `${CMAKE_DL_LIBS}` only for GNU, should also apply to AppleClang

No `find_package` changes needed — Homebrew's `wxwidgets@3.2` and `sfml@2` are compatible with the existing CMake find modules.

### Phase 3: Homebrew Dependency Installation

#### Install dependencies

```bash
brew install cmake pkg-config wxwidgets@3.2 sfml@2 picojson
```

zlib, libpng, and libjpeg are provided by macOS / Xcode Command Line Tools.

Google Test is built from source via `add_subdirectory()` — clone it alongside the project:

```bash
git clone --branch v1.10.x --depth 1 https://github.com/google/googletest.git <path-of-your-choice>
```

Note: `wxwidgets@3.2` and `sfml@2` are keg-only — they install under `/opt/homebrew/opt/` and are not linked into `/opt/homebrew/lib`. The `UserSettings.cmake` file must point CMake to their locations explicitly (see below).

#### Create `UserSettings.cmake`

Copy from the example:

```bash
cp UserSettings.example-macos.cmake UserSettings.cmake
```

Edit paths as needed. The example will contain:

```cmake
set(FS_USE_STATIC_LIBS ON)

# Homebrew keg-only deps (Apple Silicon default prefix)
set(CMAKE_PREFIX_PATH "/opt/homebrew/opt/wxwidgets@3.2;/opt/homebrew/opt/sfml@2")

# Google Test (adjust to your clone location)
set(GTEST_DIR "<path-to-googletest>")

# PicoJSON
set(PICOJSON_DIR "/opt/homebrew/opt/picojson/include")

# Define macro that creates post-install actions
macro(DefineUserPostInstall)
endmacro()
```

#### Configure and build

```bash
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release -DFS_BUILD_BENCHMARKS=OFF ..
make -j$(sysctl -n hw.ncpu)
```

#### Uninstall

To fully remove the build environment from your machine:

```bash
# Remove Homebrew packages
brew uninstall cmake pkg-config wxwidgets@3.2 sfml@2 picojson

# Remove the Google Test clone
rm -rf <path-to-googletest>

# Remove the build directory from the project
rm -rf build/
```

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
1. ~~Phase 1 — decide on dev environment approach~~ ✅ initially chose vcpkg, rolled back to Homebrew (see decision trail above)
2. Phase 2 — CMake AppleClang compiler flags ⬅️ next
3. Phase 3 — Homebrew dependency installation + UserSettings.cmake
4. Phase 4 iteratively — build, fix, repeat
5. Phase 5 — smoke test
6. Phase 6 if we get a working build
