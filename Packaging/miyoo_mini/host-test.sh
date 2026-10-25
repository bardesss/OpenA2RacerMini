#!/usr/bin/env bash
# Build and run the core tests in a gcc:<ver> container (default 13).
# The repo is mounted read-only; everything is built under /tmp in the container.
#
# A helper image opena2mini-hosttest:gcc<ver> (gcc:<ver> + CMake + Ninja) is
# built once from the local gcc:<ver> image and reused, so a normal run
# downloads nothing. The CMake and Ninja release archives are downloaded on the
# host into a cache dir (resumable, shared by all gcc versions) and copied in.
# --rebuild forces the helper image to be rebuilt (from the cached archives).
#
# Usage: host-test.sh [--rebuild] [gcc-major-version]
# Env:   A2_HOSTTEST_CACHE  archive cache dir (default ~/.cache/opena2mini-hosttest)
set -euo pipefail
REBUILD=0
if [ "${1:-}" = "--rebuild" ]; then REBUILD=1; shift; fi
VER="${1:-13}"
CMAKE_VER=3.30.5
NINJA_VER=1.12.1
IMAGE="opena2mini-hosttest:gcc${VER}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CACHE="${A2_HOSTTEST_CACHE:-$HOME/.cache/opena2mini-hosttest}"
export MSYS_NO_PATHCONV=1

# Download $2 to $CACHE/$1 unless present. Resumes a partial .part file, so a
# dropped connection only costs the bytes not yet received.
fetch() {
  local out="$CACHE/$1" url="$2" try part
  [ -f "$out" ] && return 0
  mkdir -p "$CACHE"
  # Git Bash's curl is a native Windows binary and MSYS_NO_PATHCONV is set.
  part="$out.part"
  if command -v cygpath >/dev/null 2>&1; then part="$(cygpath -m "$part")"; fi
  for try in 1 2 3 4 5 6 7 8 9 10; do
    echo "== downloading $1 (attempt $try) =="
    if curl -fL --retry 5 --retry-delay 5 --retry-all-errors --connect-timeout 20 \
      -C - -o "$part" "$url"; then
      mv "$out.part" "$out"
      return 0
    fi
    sleep 5
  done
  echo "download failed: $url (partial file kept for the next run)" >&2
  return 1
}

if [ "$REBUILD" = 1 ] || ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  # Release binaries for the Docker host architecture (gcc images have no pip).
  case "$(docker info --format '{{.Architecture}}')" in
    x86_64 | amd64) ARCH=x86_64 NINJA_ZIP=ninja-linux.zip ;;
    aarch64 | arm64) ARCH=aarch64 NINJA_ZIP=ninja-linux-aarch64.zip ;;
    *) echo "unsupported docker architecture" >&2; exit 1 ;;
  esac
  CMAKE_TGZ="cmake-${CMAKE_VER}-linux-${ARCH}.tar.gz"
  NINJA_FILE="ninja-${NINJA_VER}-${NINJA_ZIP}"
  fetch "$CMAKE_TGZ" "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VER}/${CMAKE_TGZ}"
  fetch "$NINJA_FILE" "https://github.com/ninja-build/ninja/releases/download/v${NINJA_VER}/${NINJA_ZIP}"
  CTX="$CACHE/context-gcc${VER}"
  rm -rf "$CTX"
  mkdir -p "$CTX"
  cp "$CACHE/$CMAKE_TGZ" "$CTX/cmake.tar.gz"
  cp "$CACHE/$NINJA_FILE" "$CTX/ninja.zip"
  cat >"$CTX/Dockerfile" <<'DOCKERFILE'
ARG GCC_VER
FROM gcc:${GCC_VER}
COPY cmake.tar.gz ninja.zip /tmp/
RUN set -eux; \
    mkdir -p /opt/cmake; \
    tar xzf /tmp/cmake.tar.gz --strip-components=1 -C /opt/cmake; \
    ln -s /opt/cmake/bin/cmake /opt/cmake/bin/ctest /usr/local/bin/; \
    unzip -o /tmp/ninja.zip -d /usr/local/bin; \
    chmod +x /usr/local/bin/ninja; \
    rm /tmp/cmake.tar.gz /tmp/ninja.zip; \
    cmake --version; ninja --version
DOCKERFILE
  echo "== building $IMAGE (CMake $CMAKE_VER, Ninja $NINJA_VER) =="
  # The base image must already be local; nothing is pulled.
  # docker.exe on Windows needs a native path for the build context.
  CTX_ARG="$CTX"
  if command -v cygpath >/dev/null 2>&1; then CTX_ARG="$(cygpath -w "$CTX")"; fi
  docker build --pull=false --build-arg "GCC_VER=$VER" -t "$IMAGE" "$CTX_ARG"
  rm -rf "$CTX"
fi

exec docker run --rm -v "$ROOT:/src:ro" "$IMAGE" bash -c '
set -euo pipefail
echo "== gcc $(gcc -dumpfullversion) =="
cmake --version | head -1
cmake -S /src -B /tmp/build -G Ninja -DA2_BUILD_GAME=OFF -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/build -j"$(nproc)"
cd /tmp/build && ctest --output-on-failure
'
