#!/usr/bin/env bash
# Check a release archive from package.sh:
#  - it holds exactly the Onion port tree, nothing more or less
#  - no file (also none inside the source zip) has an original-data extension
#  - opena2 passes Task 3's ELF/glibc checks: 32-bit ARM, hard-float,
#    GLIBC_ versions <= 2.28, no libstdc++ NEEDED. These run only when opena2
#    is a real ARM ELF; a stand-in binary is reported as SKIP.
#
# Usage: verify-package.sh ARCHIVE.(7z|zip)
# Needs: python3; 7z for .7z archives.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
ARCHIVE="${1:?usage: verify-package.sh ARCHIVE}"
PYTHON="${PYTHON:-python3}"
VERSION="$(sed -n 's/^project(OpenA2 VERSION \([0-9.]*\).*/\1/p' "$ROOT/CMakeLists.txt")"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

case "$ARCHIVE" in
  *.7z) 7z x -o"$TMP" "$ARCHIVE" >/dev/null ;;
  *.zip) "$PYTHON" -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' \
    "$ARCHIVE" "$TMP" ;;
  *) echo "verify-package: expected a .7z or .zip" >&2; exit 1 ;;
esac

exec "$PYTHON" - "$TMP" "$VERSION" <<'PY'
import os, re, struct, sys, zipfile

tree, version = sys.argv[1], sys.argv[2]
game = "Roms/PORTS/Games/OpenA2RacerMini/"
expected = {
    game + "opena2",
    game + "launch.sh",
    game + "libs/libSDL2-2.0.so.0",
    game + "data/PUT_A2_RACER_CD_HERE.txt",
    game + "INSTALL.txt",
    game + "README.md",
    game + "licenses/OpenA2-MIT.txt",
    game + "licenses/libsmacker-LGPL-2.1.txt",
    game + "licenses/libsmacker-UPSTREAM.md",
    game + "licenses/Liberation-OFL.txt",
    game + "licenses/stb-MIT.txt",
    game + "licenses/SDL2-zlib.txt",
    game + "licenses/THIRD_PARTY.md",
    game + "source/OpenA2-%s-source.zip" % version,
    "Roms/PORTS/Imgs/OpenA2RacerMini.png",
    "Roms/PORTS/Shortcuts/Racing/OpenA2RacerMini.port",
}
# Upstream's original-data formats, plus disc images and the CD's archives.
FORBIDDEN = {".pcx", ".smk", ".wav", ".mod", ".a2r", ".iso", ".bin", ".cue",
             ".img", ".ind", ".trk", ".omp", ".d3d"}
failures = []


def check(ok, text):
    print(("ok   - " if ok else "FAIL - ") + text)
    if not ok:
        failures.append(text)


found = set()
for top, _, files in os.walk(tree):
    for name in files:
        found.add(os.path.relpath(os.path.join(top, name), tree).replace(os.sep, "/"))
check(found == expected, "archive holds exactly the port tree")
for path in sorted(found - expected):
    print("     unexpected: " + path)
for path in sorted(expected - found):
    print("     missing:    " + path)

names = list(found)
source = os.path.join(tree, game + "source/OpenA2-%s-source.zip" % version)
if os.path.isfile(source):
    with zipfile.ZipFile(source) as z:
        inner = z.namelist()
    names += ["source zip: " + n for n in inner]
    check(any(n.endswith("/src/main.cpp") for n in inner)
          and any(n.endswith("/third_party/libsmacker/smacker.c") for n in inner)
          and any(n.endswith("/Packaging/miyoo_mini/launch.sh") or
                  n.endswith("/Packaging/miyoo_mini/port/launch.sh") for n in inner),
          "source zip has the game, libsmacker and Miyoo build sources")
bad = [n for n in names if os.path.splitext(n)[1].lower() in FORBIDDEN]
check(not bad, "no original-data file extensions (%s)" % " ".join(sorted(FORBIDDEN)))
for n in bad:
    print("     data file: " + n)


def read(rel):
    with open(os.path.join(tree, rel), "rb") as f:
        return f.read()


if game + "launch.sh" in found:
    check(read(game + "launch.sh").startswith(b"#!/bin/sh"), "launch.sh is a /bin/sh script")
if "Roms/PORTS/Shortcuts/Racing/OpenA2RacerMini.port" in found:
    port = read("Roms/PORTS/Shortcuts/Racing/OpenA2RacerMini.port").decode()
    check(all(line in port.splitlines() for line in (
        'GameName="OpenA2RacerMini"', 'GameDir="OpenA2RacerMini"',
        'GameExecutable="launch.sh"', "KillAudioserver=1", "PerformanceMode=1",
        'Arguments=""')), ".port has the Onion standalone fields")
    # Onion's Emu/PORTS/launch.sh executes the .port file; it must hand the
    # fields to launch_standalone.sh in that script's argument order.
    check(port.startswith("#!/bin/sh\n") and
          '/mnt/SDCARD/Emu/PORTS/launch_standalone.sh "$GameName" "$GameDir" '
          '"$GameExecutable" "$Arguments" "$GameDataFile" "$KillAudioserver" '
          '"$PerformanceMode"' in port.splitlines(),
          ".port is a script that calls Onion's launch_standalone.sh")
    check(b"\r" not in port.encode() and b"\r" not in read(game + "launch.sh"),
          ".port and launch.sh have LF line endings")
if "Roms/PORTS/Imgs/OpenA2RacerMini.png" in found:
    check(read("Roms/PORTS/Imgs/OpenA2RacerMini.png").startswith(b"\x89PNG\r\n\x1a\n"),
          "box art is a PNG")


def elf_checks(blob):
    """Task 3's checks on a 32-bit little-endian ARM ELF."""
    e_flags, = struct.unpack_from("<I", blob, 36)
    check(e_flags & 0x400 != 0, "opena2 is hard-float (EF_ARM_ABI_FLOAT_HARD)")
    check(e_flags >> 24 == 5, "opena2 is EABI5")
    shoff, = struct.unpack_from("<I", blob, 32)
    shentsize, shnum, shstrndx = struct.unpack_from("<HHH", blob, 46)
    sections = [struct.unpack_from("<IIIIIIIIII", blob, shoff + i * shentsize)
                for i in range(shnum)]

    def section_name(s):
        base = sections[shstrndx][4] + s[0]
        return blob[base:blob.index(b"\0", base)].decode()

    by_name = {section_name(s): s for s in sections}
    dynamic, dynstr = by_name.get(".dynamic"), by_name.get(".dynstr")
    if not dynamic or not dynstr:
        check(False, "opena2 is dynamically linked (has .dynamic)")
        return

    def string(offset):
        base = dynstr[4] + offset
        return blob[base:blob.index(b"\0", base)].decode()

    needed = []
    for off in range(dynamic[4], dynamic[4] + dynamic[5], 8):
        tag, val = struct.unpack_from("<iI", blob, off)
        if tag == 1:
            needed.append(string(val))
        if tag == 0:
            break
    print("     NEEDED: " + " ".join(needed))
    check(not any(n.startswith("libstdc++") for n in needed), "no libstdc++ NEEDED entry")
    versions = []
    verneed = by_name.get(".gnu.version_r")
    if verneed:
        off = verneed[4]
        while True:
            _, cnt, _, aux, nxt = struct.unpack_from("<HHIII", blob, off)
            a = off + aux
            for _ in range(cnt):
                _, _, _, name, anext = struct.unpack_from("<IHHII", blob, a)
                versions.append(string(name))
                a += anext
            if not nxt:
                break
            off += nxt
    glibc = sorted({tuple(int(p) for p in v[6:].split(".")) for v in versions
                    if re.fullmatch(r"GLIBC_[0-9.]+", v)})
    newest = ".".join(map(str, glibc[-1])) if glibc else "none"
    check(bool(glibc) and glibc[-1] <= (2, 28), "newest GLIBC_ version %s <= 2.28" % newest)
    check(".symtab" not in by_name, "opena2 is stripped")


if game + "opena2" in found:
    blob = read(game + "opena2")
    if blob[:4] == b"\x7fELF" and blob[4] == 1 and blob[5] == 1 and \
            struct.unpack_from("<H", blob, 18)[0] == 40:
        elf_checks(blob)
    else:
        print("SKIP - opena2 is not a 32-bit ARM ELF (stand-in binary): ELF/glibc checks "
              "run once the Task 3 cross build exists")

print("verify-package: " + ("PASS" if not failures else "FAIL (%d)" % len(failures)))
sys.exit(1 if failures else 0)
PY
