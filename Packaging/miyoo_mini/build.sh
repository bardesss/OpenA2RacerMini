#!/usr/bin/env bash
# One-command cross build for the Miyoo Mini Plus / Mini Flip.
#
#   build.sh [--debug] [--rebuild-toolchain]   build build-arm/opena2 (+ tests)
#   build.sh --check                            only run check-elf.sh on it
#   build.sh --image-only                       only make sure the image exists
#   build.sh --run 'CMD'                        run CMD (bash) in the toolchain
#                                               container, repo at /src
#   build.sh --deps-hash                        print the toolchain input hash
#
# The image opena2mini-toolchain:latest (Dockerfile + build-deps.sh) is built
# when it is missing or its org.opena2mini.deps label (a SHA-256 of those two
# files) differs from the current files; CI builds it with a layer cache and
# the same label. Extra `docker build` arguments: $A2_DOCKER_BUILD_ARGS.
#
# Output: build-arm/opena2, the ARM test binaries, and build-arm/libs/
# {libSDL2-2.0.so.0, SDL2-LICENSE.txt} for package.sh. After a build the
# ELF/glibc checks (check-elf.sh) run and fail the build if they fail.
# Works from Git Bash on Windows (MSYS_NO_PATHCONV) and on Linux/CI.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
IMAGE="${A2_TOOLCHAIN_IMAGE:-opena2mini-toolchain:latest}"
LABEL=org.opena2mini.deps
export MSYS_NO_PATHCONV=1

BUILD_TYPE=Release
REBUILD=0
MODE=build
RUN_CMD=""
while [ $# -gt 0 ]; do
  case "$1" in
    --debug) BUILD_TYPE=Debug ;;
    --rebuild-toolchain) REBUILD=1 ;;
    --check) MODE=check ;;
    --image-only) MODE=image ;;
    --deps-hash) MODE=hash ;;
    --run) MODE=run; RUN_CMD="$2"; shift ;;
    -h | --help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "build.sh: unknown option $1" >&2; exit 1 ;;
  esac
  shift
done

deps_hash() {
  cat "$HERE/Dockerfile" "$HERE/build-deps.sh" | sha256sum | cut -c1-64
}
if [ "$MODE" = hash ]; then
  deps_hash
  exit 0
fi

ensure_image() {
  local want have ctx ctx_arg
  want="$(deps_hash)"
  have="$(docker image inspect --format "{{ index .Config.Labels \"$LABEL\" }}" "$IMAGE" 2>/dev/null || true)"
  if [ "$REBUILD" = 0 ] && [ "$have" = "$want" ]; then
    return 0
  fi
  if [ -z "$have" ]; then
    echo "== $IMAGE missing: building it (first run downloads the ~1 GB Onion toolchain) =="
  else
    echo "== $IMAGE is out of date (Dockerfile/build-deps.sh changed): rebuilding =="
  fi
  # Minimal build context: only the two inputs the hash covers.
  ctx="$(mktemp -d)"
  cp "$HERE/Dockerfile" "$HERE/build-deps.sh" "$ctx/"
  ctx_arg="$ctx"
  if command -v cygpath >/dev/null 2>&1; then ctx_arg="$(cygpath -w "$ctx")"; fi
  # shellcheck disable=SC2086  # A2_DOCKER_BUILD_ARGS is a list of arguments
  docker build --label "$LABEL=$want" -t "$IMAGE" ${A2_DOCKER_BUILD_ARGS:-} "$ctx_arg"
  rm -rf "$ctx"
}

# docker run in the toolchain image with the repo at /src (read-write, the
# build goes to /src/build-arm). On Linux run as the calling user so the
# build tree is not root-owned.
in_toolchain() {
  local user=()
  case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*) ;;
    *) user=(--user "$(id -u):$(id -g)" -e HOME=/tmp) ;;
  esac
  docker run --rm "${user[@]}" -v "$ROOT:/src" -w /src \
    -e "BUILD_TYPE=$BUILD_TYPE" "$IMAGE" bash -c "$1"
}

ensure_image
case "$MODE" in
  image) exit 0 ;;
  run) in_toolchain "$RUN_CMD"; exit $? ;;
  check) in_toolchain "bash Packaging/miyoo_mini/check-elf.sh build-arm/opena2"; exit $? ;;
esac

in_toolchain '
set -euo pipefail
SYSROOT="$(arm-linux-gnueabihf-gcc -print-sysroot)"
echo "== $(arm-linux-gnueabihf-gcc --version | head -1); $(cmake --version | head -1) =="
cmake -S /src -B /src/build-arm -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE=/src/Packaging/miyoo_mini/toolchainfile.cmake \
  -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
  -DA2_MIYOO=ON -DA2_USE_SYSTEM_SDL2=ON -DA2_FETCH_SDL2=OFF
cmake --build /src/build-arm -j"$(nproc)"
mkdir -p /src/build-arm/libs
cp -L "$SYSROOT/usr/lib/libSDL2-2.0.so.0" /src/build-arm/libs/libSDL2-2.0.so.0
cp "$SYSROOT/usr/share/licenses/SDL2/LICENSE.txt" /src/build-arm/libs/SDL2-LICENSE.txt
cat "$SYSROOT/usr/share/licenses/SDL2/SOURCE.txt"
bash /src/Packaging/miyoo_mini/check-elf.sh /src/build-arm/opena2
'
echo "Built: $ROOT/build-arm/opena2"
