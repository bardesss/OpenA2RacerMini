#!/usr/bin/env bash
# Task 3's device checks on an ARM binary (default build-arm/opena2):
#  - ELF 32-bit LSB, ARM, EABI5, hard-float ABI
#  - newest GLIBC_ symbol version <= 2.28 (the device's glibc)
#  - no libstdc++ NEEDED entry (it is linked statically)
#  - RUNPATH/RPATH is $ORIGIN/libs (SDL2 ships next to the binary)
# Runs inside the toolchain image (needs file and the arm-linux-gnueabihf
# binutils); build.sh --check runs it there.
#
# Usage: check-elf.sh [BINARY]
set -euo pipefail
BIN="${1:-build-arm/opena2}"
CROSS="${CROSS:-arm-linux-gnueabihf-}"
FAILS=0
ok() { echo "ok   - $1"; }
bad() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }
[ -f "$BIN" ] || { echo "check-elf: $BIN not found" >&2; exit 1; }

desc="$(file -b "$BIN")"
echo "     file: $desc"
case "$desc" in *"ELF 32-bit LSB"*"ARM, EABI5"*) ok "ELF 32-bit LSB ARM EABI5" ;; *) bad "ELF 32-bit LSB ARM EABI5" ;; esac
flags="$("${CROSS}readelf" -h "$BIN" | sed -n 's/^ *Flags: *//p')"
echo "     flags: $flags"
case "$flags" in *hard-float*) ok "hard-float ABI" ;; *) bad "hard-float ABI" ;; esac

newest="$("${CROSS}objdump" -T "$BIN" | grep -o 'GLIBC_[0-9.]*' | sort -Vu | tail -1)"
echo "     newest glibc symbol: ${newest:-none}"
if [ -n "$newest" ] && [ "$(printf '%s\nGLIBC_2.28\n' "$newest" | sort -V | tail -1)" = GLIBC_2.28 ]; then
  ok "GLIBC_ versions <= 2.28"
else
  bad "GLIBC_ versions <= 2.28"
fi

dyn="$("${CROSS}readelf" -d "$BIN")"
echo "$dyn" | grep -E 'NEEDED|RPATH|RUNPATH' | sed 's/^/    /'
if echo "$dyn" | grep NEEDED | grep -q 'libstdc++'; then bad "no libstdc++ NEEDED"; else ok "no libstdc++ NEEDED"; fi
if echo "$dyn" | grep -E 'RPATH|RUNPATH' | grep -qF '[$ORIGIN/libs]'; then
  ok 'runpath is $ORIGIN/libs'
else
  bad 'runpath is $ORIGIN/libs'
fi

if [ "$FAILS" = 0 ]; then echo "check-elf: PASS ($BIN)"; else echo "check-elf: FAIL ($FAILS)"; exit 1; fi
