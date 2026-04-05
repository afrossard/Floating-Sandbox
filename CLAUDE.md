# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Floating Sandbox is a 2D physics simulator written in C++17. It uses mass-spring networks to simulate rigid bodies with thermodynamics, fluid dynamics, and electrotechnics. Performance-critical code uses SSE-2 (x86) and NEON (ARM) intrinsics.

## Build System

CMake-based build. Dependencies: wxWidgets (3.1.4), SFML (2.5.1), picojson, Google Test, Google Benchmark, zlib, libjpeg, libpng. On macOS, also requires iconv.

### Configuration

Copy `UserSettings.example-linux.cmake` or `UserSettings.example-windows.cmake` to `UserSettings.cmake` and set paths to dependency roots (`SDK_ROOT`, `REPOS_ROOT`, etc.).

### Build Commands

```bash
# Configure (from repo root)
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release -DFS_BUILD_BENCHMARKS=OFF -DFS_USE_STATIC_LIBS=ON \
  -DwxWidgets_USE_DEBUG=OFF -DwxWidgets_USE_UNICODE=ON -DwxWidgets_USE_STATIC=ON \
  -DFS_INSTALL_DIRECTORY=~/floating-sandbox ..

# Build
make install -j$(nproc)

# Run unit tests
cd build && ctest
# Or run the test binary directly:
./build/Sources/UnitTests/UnitTests
```

### CMake Options

- `FS_USE_STATIC_LIBS` (default ON): Force static linking
- `FS_BUILD_BENCHMARKS` (default ON): Build benchmark suite
- `FS_INSTALL_DIRECTORY`: Override install prefix

## Architecture

The codebase is in `Sources/` with a layered library structure. Dependencies flow downward:

```
FloatingSandbox (executable - wxWidgets app, main frame, tools, audio)
    |
    +-- Game (GameController, settings, ship loading/serialization, view management)
    |     |
    |     +-- Simulation (materials, ship definition/factory, NPC database, physics params)
    |     +-- Render (OpenGL rendering contexts - world, ship, notifications)
    |
    +-- ShipBuilderLib (ship editor - MVC with Model, ModelController, Controller)
    |
    +-- UILib (shared wxWidgets UI utilities)
    +-- SoundCore (audio abstractions)
    +-- OpenGLCore (OpenGL abstractions, shader management)
    +-- Core (foundation: math, vectors, buffers, algorithms, SIMD, threading)
```

### Key Concepts

- **Core** (`Sources/Core/`): Platform-independent foundation. `SysSpecifics.h` defines architecture/OS detection macros (`FS_IS_ARCHITECTURE_ARM_64()`, `FS_IS_OS_MACOS()`, etc.) and SIMD support flags. `GameMath.h` contains vectorized math. `Buffer.h`/`Buffer2D.h` provide memory-aligned containers.

- **Simulation** (`Sources/Simulation/`): Physics data and definitions. `MaterialDatabase`/`Materials` define physical material properties. `ShipFactory` constructs ships from definitions. `SimulationParameters` holds tunable physics constants.

- **Game** (`Sources/Game/`): `GameController` is the central orchestrator - owns the simulation world, render context, and coordinates the game loop. `Settings` manages persistent game parameters.

- **Render** (`Sources/Render/`): OpenGL 2.1 rendering on a separate thread. `RenderContext` owns `WorldRenderContext`, `ShipRenderContext`, and `NotificationRenderContext`. Shaders are in `Data/Shaders/`.

- **FloatingSandbox** (`Sources/FloatingSandbox/`): The wxWidgets application. `MainApp.cpp` is the entry point. `MainFrame` manages the game window. `Tools.h`/`ToolController` handle user interaction tools. UI dialogs are in `Sources/FloatingSandbox/UI/`.

- **ShipBuilder** (`Sources/ShipBuilderLib/`): Separate MVC application for creating ships. Has its own `Controller`, `Model`, `ModelController`, and `MainFrame`.

### Data Directory

`Data/` contains runtime assets: shaders (`Shaders/`), textures (`Textures/`), fonts (`Fonts/`), sounds (`Sounds/`), music (`Music/`), built-in ships (`Built-in Ships/`), localization (`Languages/`).

## Compiler Notes

- C++17 standard required
- MSVC: Warnings are errors (`/WX`), W4 warning level
- GCC: Requires GCC 14+ (due to [gcc bug #79700](https://gcc.gnu.org/bugzilla/show_bug.cgi?id=79700))
- Heavy use of fast-math optimizations in Release builds
- Multi-architecture support via `SysSpecifics.h` - code paths branch on `FS_IS_ARCHITECTURE_*` macros
