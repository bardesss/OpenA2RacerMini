#!/usr/bin/env bash
# Build and run the core tests in a gcc:<ver> container (default 13).
# The repo is mounted read-only; everything is built under /tmp in the container.
# Usage: host-test.sh [gcc-major-version]
set -euo pipefail
VER="${1:-13}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export MSYS_NO_PATHCONV=1
exec docker run --rm -v "$ROOT:/src:ro" "gcc:${VER}" bash -c '
set -euo pipefail
echo "== gcc $(gcc -dumpfullversion) =="
if ! command -v pip3 >/dev/null; then
  apt-get update -qq >/dev/null 2>&1 || true
  apt-get install -y -qq python3-pip >/dev/null 2>&1 || true
fi
if command -v pip3 >/dev/null; then
  pip3 install -q --no-cache-dir --break-system-packages "cmake==3.30.*" ninja 2>/dev/null \
    || pip3 install -q --no-cache-dir "cmake==3.30.*" ninja
else
  # Kitware static tarball fallback
  mkdir -p /tmp/cmake && curl -fsSL https://github.com/Kitware/CMake/releases/download/v3.30.5/cmake-3.30.5-linux-x86_64.tar.gz \
    | tar xz --strip-components=1 -C /tmp/cmake
  export PATH=/tmp/cmake/bin:$PATH
fi
cmake --version | head -1
cmake -S /src -B /tmp/build -DA2_BUILD_GAME=OFF -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/build -j"$(nproc)"
cd /tmp/build && ctest --output-on-failure
'
