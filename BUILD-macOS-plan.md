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
brew install cmake pkg-config wxwidgets@3.2 sfml@2
```

zlib, libpng, and libjpeg are provided by macOS / Xcode Command Line Tools.

picojson and Google Test are not in Homebrew — clone them alongside the project:

```bash
git clone --branch v1.3.0 --depth 1 https://github.com/kazuho/picojson.git <path-of-your-choice>
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

# PicoJSON (header-only, cloned from GitHub)
set(PICOJSON_DIR "<path-to-picojson>")

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
brew uninstall cmake pkg-config wxwidgets@3.2 sfml@2

# Remove cloned repos (picojson, Google Test)
rm -rf <path-to-picojson> <path-to-googletest>

# Remove the build directory from the project
rm -rf build/
```

### Phase 4: Compile and Fix Build Errors ⬅️ (in progress)

Attempt a build and fix compilation issues iteratively. Known risk areas:
- SIMD intrinsics: ARM NEON paths already exist but may need fixes for Apple's Clang
- OpenGL: macOS deprecated OpenGL after 10.14; headers may emit deprecation warnings. Suppress with `-DGL_SILENCE_DEPRECATION`
- wxWidgets: May need framework-style linking on macOS
- Any `#ifdef __linux__` or GNU-specific code paths that should also cover macOS
- 32-bit type assumptions (macOS Apple Silicon is always 64-bit)

#### Source changes required

We aim to avoid source changes, but some are unavoidable when the compiler strictly enforces the C++ standard:

**1. Missing `template` keyword for dependent template member calls** (3 lines, 2 files)

Files changed:
- `Sources/ShipBuilderLib/Tools/TextureEraserTool.cpp` (lines 44, 359)
- `Sources/ShipBuilderLib/Tools/TextureMagicWandTool.cpp` (line 52)

The C++ standard ([temp.dep.expr] §17.6.2) requires the `template` keyword when calling a template member function on an object whose type depends on a template parameter. For example:

```cpp
// Before (accepted by GCC and MSVC, rejected by Clang):
mController.GetModelController().CloneExistingLayer<TLayerType>();

// After (standard-conforming, accepted by all compilers):
mController.GetModelController().template CloneExistingLayer<TLayerType>();
```

Without the `template` keyword, the `<` in `CloneExistingLayer<TLayerType>` is ambiguous — the compiler could parse it as a less-than comparison rather than the start of a template argument list. GCC and MSVC accept the code anyway as a non-standard extension, but Clang enforces the standard strictly and emits a hard error that cannot be suppressed with flags (we tried `-fdelayed-template-parsing` and `-Wno-*` variants — neither works because this is a parse-level ambiguity, not a warning).

**Why this is the right fix**: The `template` keyword is what the C++ standard requires. Adding it doesn't change behavior on any compiler — GCC and MSVC already accept it. This makes the code more portable, not less.

**2. Unit tests out of sync with NEON refactor** (2 test functions, 1 file)

File changed:
- `Sources/UnitTests/AlgorithmsTests.cpp`

Two issues, both caused by the NEON `DiffuseLight` implementation being refactored to take separate `lampPositionsX`/`lampPositionsY` float arrays instead of interleaved `vec2f lampPositions[]`, while the tests were not updated to match:

- `DiffuseLight_NeonVectorized_4Lamps` and `DiffuseLight_NeonVectorized_8Lamps`: Tests passed a `vec2f lampPositions[]` array (interleaved X/Y), but the function signature now takes separate `float lampPositionsX[]` and `float lampPositionsY[]` arrays. Fix: split the interleaved data into two separate arrays with the same values. The test expectations (distances, expected light values) are unchanged — only the data layout changed to match what the NEON implementation consumes.

- `SmoothBufferAndAdd_16_5_NeonVectorized`: Called `RunSmoothBufferAndAddTest_16_5()` which doesn't exist. The existing `RunSmoothBufferAndAddTest()` already has a `#if FS_IS_ARM_NEON()` / `#else` branch that provides the correct 16-element test data for NEON. Fix: call `RunSmoothBufferAndAddTest()` instead.

**Why this is the right fix**: These tests were already broken — they could never have compiled on ARM. The function signatures changed in a prior NEON refactor but the tests were not updated (presumably because the project was only built on x86 and Windows at the time, where these `#if FS_IS_ARM_NEON()` blocks are compiled out). The fixes align the test call sites with the current implementation without changing any test logic or expected values.

### Phase 5: Run and Validate ✅

- ✅ All 1002 unit tests pass
- ✅ App launches, renders the simulation, and displays a ship
- Known issues to fix in Phase 7 (see below)

### Phase 6: Review Source Changes for Upstream ✅

Reviewed all code changes on the `macos-apple-silicon-build` branch vs `master` (`git diff master..HEAD`). Goal: determine which changes are safe to upstream and which need conditional compilation.

#### Files changed vs master (excluding docs)

| File | Change | Upstream risk |
|---|---|---|
| **CMakeLists.txt** (root) | Merged GNU+AppleClang compiler flags with `OR`; added separate AppleClang libraries block | **None** — the `OR` doesn't change GNU behavior; the new `elseif` only triggers on AppleClang |
| **Sources/OpenGLCore/CMakeLists.txt** | `if (GNU)` → `if (GNU OR AppleClang)` for `dl_libs` linking | **None** — additive condition, only triggers on AppleClang |
| **Sources/ShipBuilderLib/Tools/TextureEraserTool.cpp** | Added `template` keyword before `CloneExistingLayer<TLayerType>()` (2 sites) | **Positive** — C++ standard conformance. GCC/MSVC already accept it |
| **Sources/ShipBuilderLib/Tools/TextureMagicWandTool.cpp** | Added `template` keyword before `CloneExistingLayer<TLayerType>()` (1 site) | **Positive** — same as above |
| **Sources/UnitTests/AlgorithmsTests.cpp** | Fixed NEON test signatures, added `EXPECT_NEAR` tolerance, guarded Naive test buffer size | **None** — all changes inside `#if FS_IS_ARM_NEON()` (lines 326-436) or `#if !FS_IS_ARM_NEON()` guards. x86 builds compile out these blocks entirely |
| **UserSettings.example-macos.cmake** *(new)* | macOS build config template, parallel to existing Windows/Linux examples | **None** — new file only |

#### Verified

- All NEON test changes confirmed inside `#if FS_IS_ARM_NEON()` ... `#endif` guards — x86 builds never see them
- The `SmoothBufferAndAdd_12_5_Naive` test is now guarded with `#if !FS_IS_ARM_NEON()` so x86 keeps the 12-element version; ARM gets `SmoothBufferAndAdd_16_5_Naive` with the 16-element version
- The `template` keyword is the **only** change that compiles on all platforms, and it's what the C++ standard requires

#### Verdict

**All changes are safe to upstream.** No existing behavior is modified on Windows (MSVC) or Linux (GNU). Changes fall into three categories:
1. **Additive** (CMake AppleClang branches, new example file) — no effect on existing platforms
2. **Standards-conforming** (`template` keyword) — accepted by all compilers, required by the standard
3. **Bug fixes in dead code** (NEON tests) — only compiled on ARM, were already broken

### Phase 7: Fix Runtime Issues ⬅️ next

Three runtime issues observed during Phase 5 validation:

#### 7a. Data/Ships directory not found next to executable

**Problem**: The app resolves its resource root from `argv[0]`'s parent directory (`GameAssetManager.cpp:24`). It expects `Data/` and `Ships/` next to the executable. The CMake `file(COPY ...)` rules (lines 136-141 of `Sources/FloatingSandbox/CMakeLists.txt`) copy into `Debug/`, `Release/`, `RelWithDebInfo/` subdirs — this is for multi-config generators (MSVC, Xcode) but does nothing for single-config Makefiles where the executable lands directly in the build output dir.

**Current workaround**: Manual symlinks (`ln -s ../../Data .` and `ln -s ../../Ships .` in the executable's directory).

**Proper fix options**:
1. Add a `file(COPY ...)` rule for the Makefile generator case (no config subdirectory)
2. Add a CMake post-build command to create symlinks on Unix
3. Use `make install` to a staging directory (already works — the install rules handle Data/Ships correctly, including the default ship rename)

**Recommendation**: Option 3 (`make install`) is the intended workflow and already works. For development convenience, option 2 (post-build symlinks) avoids the full install step. Investigate which approach works best.

#### 7b. Locale warning: "Cannot set locale to language 'English (Switzerland)'"

**Problem**: wxWidgets tries to set the system locale (`en_CH`) but the locale isn't installed. This is a non-fatal warning — the app runs fine — but it's noisy.

**Root cause**: wxWidgets' `wxLocale::Init()` calls `setlocale()` with the system's preferred language. On macOS, the system language may map to a locale that isn't in `/usr/share/locale/`. Unlike Linux, macOS doesn't install all locale data by default.

**Fix options**:
1. Suppress the warning (cosmetic fix only)
2. Set a fallback locale in the app when the preferred one isn't available
3. Document it as a known cosmetic issue (non-blocking)

**Recommendation**: Investigate whether this is coming from wxWidgets initialization or from the app's `LocalizationManager`. If it's wxWidgets, option 3 is appropriate — it's a platform quirk, not a bug.

#### 7c. Default ship is not the Titanic

**Problem**: When running from the build directory with symlinked `Ships/`, the app loads `Ships/default_ship.png` (a simple test ship). On an installed build (Linux, Windows), the install rules rename `R.M.S. Titanic (With Power).shp2` to `Ships/default_ship.shp2`, which takes priority (the code checks `.shp2` first, then falls back to `.png`).

**Root cause**: The symlink points to the source `Ships/` directory, which has the original `default_ship.png` but not the renamed Titanic `.shp2`.

**Fix**: This is the same issue as 7a — using `make install` resolves it, since the install rules already handle the rename:
```cmake
install(DIRECTORY "${CMAKE_SOURCE_DIR}/Ships"
    DESTINATION .
    PATTERN "default_ship.png" EXCLUDE)
install(FILES "${CMAKE_SOURCE_DIR}/Ships/R.M.S. Titanic (With Power).shp2"
    DESTINATION Ships
    RENAME "default_ship.shp2")
```

**Recommendation**: Solve 7a and 7c together. Either `make install` to a staging directory, or add a post-build step that creates the correct `default_ship.shp2` alongside the symlinked/copied resources.

### Phase 8: Document Build Steps and Automate ⬅️ after Phase 7

Create a reproducible, automated build process for a fresh macOS Apple Silicon machine.

#### 8a. Document the manual build steps

Write a complete `BUILD-macOS.md` guide covering:
1. Prerequisites (Xcode Command Line Tools, Homebrew)
2. Dependency installation (`brew install cmake pkg-config wxwidgets@3.2 sfml@2`)
3. Cloning picojson and Google Test
4. Creating `UserSettings.cmake` from the example
5. Configure, build, install
6. Running the app
7. Running unit tests
8. Uninstall / cleanup

#### 8b. Create a build automation script

Write a `Scripts/build-macos.sh` that automates the full process on a fresh machine:
```
1. Check/install Homebrew dependencies
2. Clone picojson + Google Test if not present
3. Generate UserSettings.cmake if not present
4. cmake configure
5. make -j$(sysctl -n hw.ncpu)
6. make install
7. Run unit tests
8. Report success/failure
```

#### 8c. Test on a fresh environment

Validate the script works from scratch (clean checkout, no prior build artifacts). Ideally test in a fresh macOS VM or GitHub Actions runner.

### Phase 9: macOS .app Bundle (Optional / Future)

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
2. ~~Phase 2 — CMake AppleClang compiler flags~~ ✅
3. ~~Phase 3 — Homebrew dependency installation + UserSettings.cmake~~ ✅
4. ~~Phase 4 — build, fix, repeat~~ ✅ all targets compile, all 1002 tests pass
5. ~~Phase 5 — smoke test~~ ✅ app launches and renders on Apple Silicon
6. ~~Phase 6 — review source changes for upstream~~ ✅ all changes safe to upstream
7. Phase 7 — fix runtime issues (Data dir, locale, default ship)
8. Phase 8 — document and automate build steps
9. Phase 9 — .app bundle (if we get to it)
