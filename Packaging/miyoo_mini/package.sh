#!/usr/bin/env bash
# Stage the Onion port tree and pack the release archive.
#
#   dist/OpenA2RacerMini-onion-<version>-<gitshort>.<7z|zip>
#     Roms/PORTS/Games/OpenA2RacerMini/{opena2, launch.sh, libs/libSDL2-2.0.so.0,
#       data/PUT_A2_RACER_CD_HERE.txt, INSTALL.txt, README.md, licenses/...,
#       source/OpenA2-<version>-source.zip}
#     Roms/PORTS/Imgs/OpenA2RacerMini.png
#     Roms/PORTS/Shortcuts/Racing/OpenA2RacerMini.port
#
# Usage: package.sh [--stage-only] [--debug] [--format 7z|zip] [--build-dir DIR]
#                   [--binary PATH] [--sdl-lib PATH] [--sdl-license PATH] [--out DIR]
#   --stage-only   stop after staging (dist/stage/Roms/...), e.g. for deploy.sh
#   --debug        keep the binary's symbols (no strip)
#   --format       7z (default when 7z is installed) or zip (Python zipfile)
#   --build-dir    the ARM build (default build-arm): opena2,
#                  libs/libSDL2-2.0.so.0 and libs/SDL2-LICENSE.txt in it
#   --binary, --sdl-lib, --sdl-license  override single inputs (stand-ins for
#                  layout tests before the cross toolchain exists)
# Needs: python3, git (for the short hash); 7z for --format 7z;
#        $STRIP (default arm-linux-gnueabihf-strip) unless --debug.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
STAGE_ONLY=0
DEBUG=0
FORMAT=""
BUILD_DIR="$ROOT/build-arm"
BINARY="" SDL_LIB="" SDL_LICENSE=""
OUT="$ROOT/dist"
while [ $# -gt 0 ]; do
  case "$1" in
    --stage-only) STAGE_ONLY=1 ;;
    --debug) DEBUG=1 ;;
    --format) FORMAT="$2"; shift ;;
    --build-dir) BUILD_DIR="$2"; shift ;;
    --binary) BINARY="$2"; shift ;;
    --sdl-lib) SDL_LIB="$2"; shift ;;
    --sdl-license) SDL_LICENSE="$2"; shift ;;
    --out) OUT="$2"; shift ;;
    -h | --help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "package.sh: unknown option $1" >&2; exit 1 ;;
  esac
  shift
done
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
BINARY="${BINARY:-$BUILD_DIR/opena2}"
SDL_LIB="${SDL_LIB:-$BUILD_DIR/libs/libSDL2-2.0.so.0}"
SDL_LICENSE="${SDL_LICENSE:-$BUILD_DIR/libs/SDL2-LICENSE.txt}"
PYTHON="${PYTHON:-python3}"
STRIP="${STRIP:-arm-linux-gnueabihf-strip}"
for input in "$BINARY" "$SDL_LIB" "$SDL_LICENSE"; do
  [ -f "$input" ] || { echo "package.sh: missing $input (run build.sh first)" >&2; exit 1; }
done
if [ -z "$FORMAT" ]; then
  if command -v 7z >/dev/null 2>&1; then FORMAT=7z; else
    FORMAT=zip
    echo "package.sh: 7z not found, writing a .zip instead" >&2
  fi
fi
case "$FORMAT" in 7z | zip) ;; *) echo "package.sh: --format 7z or zip" >&2; exit 1 ;; esac

VERSION="$(sed -n 's/^project(OpenA2 VERSION \([0-9.]*\).*/\1/p' "$ROOT/CMakeLists.txt")"
GITSHORT="$(git -C "$ROOT" -c safe.directory='*' rev-parse --short HEAD 2>/dev/null || echo nogit)"
NAME="OpenA2RacerMini-onion-$VERSION-$GITSHORT"

STAGE="$OUT/stage"
PORTS="$STAGE/Roms/PORTS"
GAME="$PORTS/Games/OpenA2RacerMini"
rm -rf "$STAGE"
mkdir -p "$GAME/libs" "$GAME/data" "$GAME/licenses" "$GAME/source" \
  "$PORTS/Imgs" "$PORTS/Shortcuts/Racing"

cp "$BINARY" "$GAME/opena2"
if [ "$DEBUG" = 0 ]; then
  if command -v "$STRIP" >/dev/null 2>&1; then
    "$STRIP" --strip-unneeded "$GAME/opena2"
  else
    echo "package.sh: $STRIP not found, opena2 is NOT stripped" >&2
  fi
fi
chmod 755 "$GAME/opena2"
cp "$SDL_LIB" "$GAME/libs/libSDL2-2.0.so.0"
cp "$HERE/port/launch.sh" "$GAME/launch.sh"
chmod 755 "$GAME/launch.sh"
cp "$HERE/port/INSTALL.txt" "$GAME/INSTALL.txt"
cp "$ROOT/README-MIYOO.md" "$GAME/README.md"
cat >"$GAME/data/PUT_A2_RACER_CD_HERE.txt" <<'EOF'
Put your own copy of the Dutch A2 Racer CD in this folder, in one of these forms:

  CD/          the CD folder (the files RCS.IND, RCS.IMG, ETAPPE1.TRK, ... inside;
               any folder name works)
  the CD's files directly in this folder
  CD.iso       or any other .iso disc image
  track.bin    a raw BIN/CUE disc image (keep the .cue next to it)

This port contains no game files. See INSTALL.txt.
EOF
cp "$ROOT/LICENSE" "$GAME/licenses/OpenA2-MIT.txt"
cp "$ROOT/third_party/libsmacker/COPYING" "$GAME/licenses/libsmacker-LGPL-2.1.txt"
cp "$ROOT/third_party/libsmacker/UPSTREAM.md" "$GAME/licenses/libsmacker-UPSTREAM.md"
cp "$ROOT/third_party/liberation/LICENSE" "$GAME/licenses/Liberation-OFL.txt"
cp "$ROOT/third_party/stb/LICENSE" "$GAME/licenses/stb-MIT.txt"
cp "$SDL_LICENSE" "$GAME/licenses/SDL2-zlib.txt"
cp "$ROOT/docs/THIRD_PARTY.md" "$GAME/licenses/THIRD_PARTY.md"
"$PYTHON" "$ROOT/tools/package_source.py" --miyoo \
  --output "$GAME/source/OpenA2-$VERSION-source.zip"
cp "$HERE/port/box_art.png" "$PORTS/Imgs/OpenA2RacerMini.png"
cp "$HERE/port/OpenA2RacerMini.port" "$PORTS/Shortcuts/Racing/OpenA2RacerMini.port"

if [ "$STAGE_ONLY" = 1 ]; then
  echo "Staged: $STAGE/Roms"
  exit 0
fi

ARCHIVE="$OUT/$NAME.$FORMAT"
rm -f "$ARCHIVE"
if [ "$FORMAT" = 7z ]; then
  (cd "$STAGE" && 7z a -t7z -mx=9 "$ARCHIVE" Roms >/dev/null)
else
  # Deterministic zip with Unix modes (launch.sh and opena2 executable).
  "$PYTHON" - "$STAGE" "$ARCHIVE" <<'PY'
import os, sys, zipfile
stage, archive = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for top, dirs, files in os.walk(os.path.join(stage, "Roms")):
        dirs.sort()
        for name in sorted(files):
            path = os.path.join(top, name)
            info = zipfile.ZipInfo(os.path.relpath(path, stage).replace(os.sep, "/"),
                                   (2026, 1, 1, 0, 0, 0))
            info.create_system = 3
            mode = 0o755 if name in ("opena2", "launch.sh") else 0o644
            info.external_attr = (0o100000 | mode) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            with open(path, "rb") as f:
                z.writestr(info, f.read())
PY
fi
echo "Archive: $ARCHIVE"
