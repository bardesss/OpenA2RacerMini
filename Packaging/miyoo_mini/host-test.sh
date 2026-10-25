#!/usr/bin/env bash
# Build and run the core tests in a gcc:<ver> container (default 13).
# The repo is mounted read-only; everything is built under /tmp in the container.
#
# A helper image opena2mini-hosttest:gcc<ver> (gcc:<ver> + CMake + Ninja) is
# built once from the local gcc:<ver> image and reused, so a normal run
# downloads nothing. The CMake and Ninja release archives are downloaded on the
# host into a cache dir (resumable, shared by all gcc versions) and copied in.
# --rebuild forces the helper image to be rebuilt (from the cached archives).
# --game also builds the SDL game (A2_BUILD_GAME=ON) so the headless game tests
# run. SDL2 comes from a tarball cached on the host (fetched once, checked
# against the SHA-256 pinned in CMakeLists.txt) and is handed to FetchContent,
# so the build downloads nothing. The images have no X11/ALSA headers; SDL
# builds its dummy/offscreen drivers, which is all --headless needs.
# --miyoo configures with -DA2_MIYOO=ON (host compiler, desktop SDL2), so the
# #if A2_MIYOO code compiles and the tests run in the device configuration.
# --then CMD runs CMD (with sh) in the container after ctest passes, with the
# build in /tmp/build (verify-launch.sh uses it for /tmp/build/opena2).
# --mount HOST:CONTAINER adds a read-only bind mount (repeatable).
#
# Usage: host-test.sh [--rebuild] [--game] [--miyoo] [--then CMD]
#                     [--mount HOST:CONTAINER]... [gcc-major-version]
# Env:   A2_HOSTTEST_CACHE  archive cache dir (default ~/.cache/opena2mini-hosttest)
set -euo pipefail
REBUILD=0
GAME=0
MIYOO=0
THEN=""
EXTRA_MOUNTS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --rebuild) REBUILD=1 ;;
    --game) GAME=1 ;;
    --miyoo) MIYOO=1 ;;
    --then) THEN="$2"; shift ;;
    --mount) EXTRA_MOUNTS+=(-v "$2:ro"); shift ;;
    *) break ;;
  esac
  shift
done
VER="${1:-13}"
CMAKE_VER=3.30.5
NINJA_VER=1.12.1
SDL2_VER=2.32.10
SDL2_SHA256=5f5993c530f084535c65a6879e9b26ad441169b3e25d789d83287040a9ca5165
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

GAME_ARGS="-DA2_BUILD_GAME=OFF"
MOUNTS=(-v "$ROOT:/src:ro")
if [ "$GAME" = 1 ]; then
  SDL2_TGZ="SDL2-${SDL2_VER}.tar.gz"
  fetch "$SDL2_TGZ" "https://www.libsdl.org/release/${SDL2_TGZ}"
  if ! echo "$SDL2_SHA256  $CACHE/$SDL2_TGZ" | sha256sum -c --status; then
    echo "SHA-256 mismatch for $CACHE/$SDL2_TGZ; deleting it" >&2
    rm -f "$CACHE/$SDL2_TGZ"
    exit 1
  fi
  MOUNTS+=(-v "$CACHE:/cache:ro")
  GAME_ARGS="-DA2_BUILD_GAME=ON -DA2_USE_SYSTEM_SDL2=OFF -DFETCHCONTENT_SOURCE_DIR_SDL2=/tmp/sdl2/SDL2-${SDL2_VER}"
fi
if [ "$MIYOO" = 1 ]; then
  GAME_ARGS="$GAME_ARGS -DA2_MIYOO=ON"
fi

MOUNTS+=(${EXTRA_MOUNTS[@]+"${EXTRA_MOUNTS[@]}"})
exec docker run --rm "${MOUNTS[@]}" -e "GAME_ARGS=$GAME_ARGS" -e "SDL2_TGZ=${SDL2_TGZ:-}"   -e "THEN=$THEN" "$IMAGE" bash -c '
set -euo pipefail
echo "== gcc $(gcc -dumpfullversion) =="
cmake --version | head -1
if [ -n "$SDL2_TGZ" ]; then
  mkdir -p /tmp/sdl2
  tar xzf "/cache/$SDL2_TGZ" -C /tmp/sdl2
  python3 --version
fi
# GAME_ARGS is intentionally split into separate arguments.
cmake -S /src -B /tmp/build -G Ninja $GAME_ARGS -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/build -j"$(nproc)"
cd /tmp/build && ctest --output-on-failure
if [ -n "$THEN" ]; then
  echo "== $THEN =="
  sh -c "$THEN"
fi
'
