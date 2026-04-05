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

### Phase 1: CMake AppleClang Support

Add an `elseif("${CMAKE_CXX_COMPILER_ID}" STREQUAL "AppleClang")` block in the root `CMakeLists.txt` alongside the existing MSVC and GNU blocks. This needs:
- C++17 flags (should be default with modern AppleClang, but explicit)
- Warning flags (`-Wall`, `-Wcomment`)
- Release optimization flags (`-O3`, `-ffast-math` and friends, matching the GNU block)
- Debug flags (`-D_DEBUG`)
- Additional libraries for APPLE (handle `pthread`, `iconv`, framework linking)

Also verify that any `"GNU"` compiler ID checks in sub-project CMakeLists.txt files don't exclude AppleClang where they should include it.

### Phase 2: UserSettings Template for macOS

Create `UserSettings.example-macos.cmake` with Homebrew-friendly defaults for dependency paths. On macOS with Homebrew, many dependencies (zlib, libjpeg, libpng, sfml) are available via `brew install`. wxWidgets and picojson may need to be built from source or installed via brew.

Typical Homebrew prefix on Apple Silicon: `/opt/homebrew`.

### Phase 3: Install and Configure Dependencies

Document and verify the full dependency installation on macOS Apple Silicon:
- `brew install cmake sfml zlib libpng jpeg picojson`
- wxWidgets 3.1.4 (build from source or `brew install wxwidgets`)
- Google Test (cloned, built alongside as current setup)
- Google Benchmark (optional)

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
1. Start with Phase 1 + 2 (CMake changes) — small, reviewable
2. Phase 3 on the local machine — install deps
3. Phase 4 iteratively — build, fix, repeat
4. Phase 5 — smoke test
5. Phase 6 if we get a working build
