#!/usr/bin/env bash
#
# Build Floating Sandbox on macOS Apple Silicon.
# Installs Homebrew dependencies, clones required repos, configures, builds,
# installs, and runs unit tests.
#
# Usage:
#   ./Scripts/build-macos.sh              # full build + install + tests
#   ./Scripts/build-macos.sh --deps-only  # only install dependencies
#   ./Scripts/build-macos.sh --no-deps    # skip dependency installation
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPOS_DIR="$(cd "$PROJECT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"

# Parse arguments
INSTALL_DEPS=true
BUILD=true
for arg in "$@"; do
    case "$arg" in
        --deps-only) BUILD=false ;;
        --no-deps)   INSTALL_DEPS=false ;;
        --help|-h)
            echo "Usage: $0 [--deps-only|--no-deps]"
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            exit 1
            ;;
    esac
done

# -- Helpers ------------------------------------------------------------------

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m==>\033[0m %s\n' "$*"; }
fail()  { printf '\033[1;31m==>\033[0m %s\n' "$*" >&2; exit 1; }

# -- Check prerequisites -----------------------------------------------------

if [[ "$(uname -s)" != "Darwin" ]]; then
    fail "This script is for macOS only."
fi

if ! command -v brew &>/dev/null; then
    fail "Homebrew not found. Install it from https://brew.sh"
fi

# -- Install dependencies -----------------------------------------------------

if $INSTALL_DEPS; then
    info "Installing Homebrew packages..."
    brew install cmake pkg-config wxwidgets@3.2 sfml@2 2>/dev/null || true

    # Clone picojson if not present
    if [[ ! -d "$REPOS_DIR/picojson" ]]; then
        info "Cloning picojson..."
        git clone --branch v1.3.0 --depth 1 https://github.com/kazuho/picojson.git "$REPOS_DIR/picojson"
    else
        ok "picojson already present at $REPOS_DIR/picojson"
    fi

    # Clone Google Test if not present
    if [[ ! -d "$REPOS_DIR/googletest" ]]; then
        info "Cloning Google Test..."
        git clone --branch v1.10.x --depth 1 https://github.com/google/googletest.git "$REPOS_DIR/googletest"
    else
        ok "Google Test already present at $REPOS_DIR/googletest"
    fi
fi

if ! $BUILD; then
    ok "Dependencies installed. Exiting (--deps-only)."
    exit 0
fi

# -- Configure UserSettings.cmake --------------------------------------------

if [[ ! -f "$PROJECT_DIR/UserSettings.cmake" ]]; then
    info "Creating UserSettings.cmake from macOS example..."
    cp "$PROJECT_DIR/UserSettings.example-macos.cmake" "$PROJECT_DIR/UserSettings.cmake"
else
    ok "UserSettings.cmake already exists"
fi

# -- Configure ----------------------------------------------------------------

info "Configuring CMake build..."
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
cmake -DCMAKE_BUILD_TYPE=Release -DFS_BUILD_BENCHMARKS=OFF ..

# -- Build --------------------------------------------------------------------

NCPU=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
info "Building with $NCPU parallel jobs..."
make -j"$NCPU"

# -- Install ------------------------------------------------------------------

info "Installing to $BUILD_DIR/Install..."
make install

# -- Unit tests ---------------------------------------------------------------

info "Running unit tests..."
if ./Sources/UnitTests/UnitTests; then
    ok "All unit tests passed."
else
    fail "Some unit tests failed."
fi

# -- Done ---------------------------------------------------------------------

ok "Build complete!"
echo ""
echo "  Run from install directory:"
echo "    $BUILD_DIR/Install/FloatingSandbox"
echo ""
echo "  Run from build directory (development):"
echo "    $BUILD_DIR/Sources/FloatingSandbox/FloatingSandbox"
echo ""
