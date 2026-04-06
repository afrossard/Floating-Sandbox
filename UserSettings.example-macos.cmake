# Enable static linking
set(FS_USE_STATIC_LIBS ON)

# Homebrew keg-only deps (Apple Silicon default prefix)
set(CMAKE_PREFIX_PATH "/opt/homebrew/opt/wxwidgets@3.2;/opt/homebrew/opt/sfml@2")

# Sibling repo locations (adjust to your clone locations)
set(REPOS_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/..")
set(GTEST_DIR "${REPOS_ROOT}/googletest")
set(PICOJSON_DIR "${REPOS_ROOT}/picojson")

# Define macro that creates post-install actions
macro(DefineUserPostInstall)
endmacro()
