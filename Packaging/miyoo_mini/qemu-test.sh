#!/usr/bin/env bash
# ARM tests under qemu-user, in the toolchain image, on the build-arm/ tree
# from build.sh:
#  1. ctest on the ARM build (unit tests, simulation included, and the
#     headless game tests; CMAKE_CROSSCOMPILING_EMULATOR runs them in qemu)
#  2. synthetic smoke run: ARM opena2 --headless --demo --frames 480 writes a
#     non-empty BMP
#  3. with --x86-saves DIR: the save round trip (save-roundtrip.sh consume)
#     on saves made by the x86 build (save-roundtrip.sh produce, see
#     .github/workflows/miyoo.yml); skipped with a note without it
#
# Usage: qemu-test.sh [--x86-saves DIR] [--skip-ctest]
#        qemu-test.sh --inside ...   (the part that runs in the container)
# SDL uses its dummy drivers (the mmiyoo ones need the device's MI libs).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

if [ "${1:-}" != --inside ]; then
  args=()
  saves=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --x86-saves) saves="$2"; shift ;;
      --skip-ctest) args+=(--skip-ctest) ;;
      *) echo "qemu-test.sh: unknown option $1" >&2; exit 1 ;;
    esac
    shift
  done
  [ -x "$ROOT/build-arm/opena2" ] || { echo "qemu-test.sh: run build.sh first" >&2; exit 1; }
  if [ -n "$saves" ]; then
    # The saves go into the repo's build-arm/ so the container sees them.
    rm -rf "$ROOT/build-arm/x86-saves"
    mkdir -p "$ROOT/build-arm/x86-saves"
    cp -R "$saves/." "$ROOT/build-arm/x86-saves/"
    args+=(--x86-saves /src/build-arm/x86-saves)
  fi
  quoted=""
  if [ "${#args[@]}" -gt 0 ]; then quoted="$(printf ' %q' "${args[@]}")"; fi
  exec bash "$HERE/build.sh" --run "bash /src/Packaging/miyoo_mini/qemu-test.sh --inside$quoted"
fi

# ---- inside the toolchain container ----
shift
SAVES=""
CTEST=1
while [ $# -gt 0 ]; do
  case "$1" in
    --x86-saves) SAVES="$2"; shift ;;
    --skip-ctest) CTEST=0 ;;
  esac
  shift
done
SYSROOT="$(arm-linux-gnueabihf-gcc -print-sysroot)"
export SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy
QEMU="qemu-arm-static -L $SYSROOT"
BIN=/src/build-arm/opena2
WORK="$(mktemp -d)"
STATUS=0

if [ "$CTEST" = 1 ]; then
  echo "== 1. ARM ctest under qemu =="
  ctest --test-dir /src/build-arm --output-on-failure || STATUS=1
fi

echo "== 2. synthetic smoke run (480 frames) =="
python3 /src/tests/generate_data.py "$WORK/synthetic" >/dev/null
rm -f "$WORK/smoke.bmp"
if $QEMU "$BIN" --data "$WORK/synthetic" --headless --demo --frames 480 \
  --screenshot "$WORK/smoke.bmp" && [ -s "$WORK/smoke.bmp" ]; then
  echo "ok   - ARM smoke run wrote $(wc -c <"$WORK/smoke.bmp") byte BMP"
else
  echo "FAIL - ARM smoke run did not write a BMP"
  STATUS=1
fi

echo "== 3. x86 -> ARM save round trip =="
if [ -n "$SAVES" ]; then
  bash /src/Packaging/miyoo_mini/save-roundtrip.sh consume "$QEMU $BIN" "$WORK/synthetic" \
    "$SAVES" "$WORK/roundtrip" || STATUS=1
else
  echo "SKIP - no --x86-saves given (CI passes the x86 build's saves)"
fi

rm -rf "$WORK"
if [ "$STATUS" = 0 ]; then echo "qemu-test: PASS"; else echo "qemu-test: FAIL"; fi
exit "$STATUS"
