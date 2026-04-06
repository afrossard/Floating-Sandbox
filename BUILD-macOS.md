These are instructions on how to build Floating Sandbox on macOS Apple Silicon (ARM64). These instructions were written at the time of Floating Sandbox 1.20.0 and tested on a clean macOS 15 (Sequoia) system with an Apple M-series chip.

# Prerequisites

You'll need Xcode Command Line Tools and Homebrew. If you don't have them:
```
xcode-select --install
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

# Installing Dependencies

### Homebrew packages
```
brew install cmake pkg-config wxwidgets@3.2 sfml@2
```

Note: `wxwidgets@3.2` and `sfml@2` are keg-only formulas -- they install under `/opt/homebrew/opt/` and are not linked into `/opt/homebrew/lib`. The `UserSettings.cmake` file points CMake to their locations explicitly.

zlib, libpng, and libjpeg are provided by macOS / Xcode Command Line Tools.

### Clone header-only and test libraries

picojson and Google Test are not in Homebrew -- clone them alongside the Floating Sandbox repo. In these instructions we'll assume all repos live under a common parent directory (e.g. `~/git`):
```
cd ~/git
git clone --branch v1.3.0 --depth 1 https://github.com/kazuho/picojson.git
git clone --branch v1.10.x --depth 1 https://github.com/google/googletest.git
```

# Building Floating Sandbox

### Cloning
```
cd ~/git
git clone https://github.com/GabrieleGiuseppini/Floating-Sandbox.git
```

### Configuring

Before we build, we must tell Floating Sandbox where to find its dependencies. Copy the macOS example settings file:
```
cd ~/git/Floating-Sandbox
cp UserSettings.example-macos.cmake UserSettings.cmake
```

The example file assumes picojson and googletest are cloned alongside Floating-Sandbox (as sibling directories). If you've placed them elsewhere, edit `UserSettings.cmake` and adjust the `REPOS_ROOT`, `GTEST_DIR`, and `PICOJSON_DIR` paths.

### Building

Create a build directory, configure, and build:
```
cd ~/git/Floating-Sandbox
mkdir build
cd build
cmake -DCMAKE_BUILD_TYPE=Release -DFS_BUILD_BENCHMARKS=OFF ..
make -j$(sysctl -n hw.ncpu)
```

### Installing

The install step assembles the complete application layout with all resources and ships:
```
make install
```

By default, this installs to `build/Install/`. You can change this by setting `FS_INSTALL_DIRECTORY` during cmake configuration:
```
cmake -DCMAKE_BUILD_TYPE=Release -DFS_BUILD_BENCHMARKS=OFF -DFS_INSTALL_DIRECTORY=~/floating-sandbox ..
```

### Running

**From the install directory** (recommended -- loads the Titanic as the default ship):
```
cd ~/git/Floating-Sandbox/build/Install
./FloatingSandbox
```

**From the build directory** (for development -- symlinks to Data/ and Ships/ are created automatically by the build):
```
cd ~/git/Floating-Sandbox
./build/Sources/FloatingSandbox/FloatingSandbox
```

### Running unit tests
```
cd ~/git/Floating-Sandbox/build
./Sources/UnitTests/UnitTests
```
Or via CTest:
```
cd ~/git/Floating-Sandbox/build
ctest
```

# Known Issues

- **Locale warning**: On some macOS systems, wxWidgets may log an internal warning about the system locale (e.g. `en_CH`) not being installed. This is suppressed in the app and does not affect functionality. The app defaults to English.

- **OpenGL deprecation**: macOS deprecated OpenGL after 10.14. The app uses OpenGL 2.1 which is still supported (macOS provides up to OpenGL 4.1 via compatibility profile), but Apple may print deprecation warnings to the console. These are harmless.

# Uninstalling

To fully remove the build environment from your machine:
```
# Remove Homebrew packages
brew uninstall cmake pkg-config wxwidgets@3.2 sfml@2

# Remove cloned repos
rm -rf ~/git/picojson ~/git/googletest

# Remove the build directory
rm -rf ~/git/Floating-Sandbox/build
```
