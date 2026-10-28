#!/usr/bin/env bash
# Cross-platform save round trip (Task 4 step 3, ruling R2), built on the
# existing debug flags --autosave-on-exit / --load-autosave (Task 5).
#
#   save-roundtrip.sh produce RUN DATA OUT
#     With opena2 started as RUN (a command, e.g. "/tmp/build/opena2"):
#     demo race for 300 frames, autosave -> OUT/first/autosave.sav; then load
#     that, drive 300 more frames, autosave -> OUT/second/autosave.sav.
#     CI runs this with the x86 build (host-test.sh --game).
#
#   save-roundtrip.sh consume RUN DATA IN WORK
#     Load IN/first/autosave.sav (made by another build) with RUN, drive 300
#     frames, autosave -> WORK/second/autosave.sav. Asserted: the load works,
#     the race continues and is saved, and both second saves (IN's and ours)
#     load again. Byte identity of the two second saves is reported only:
#     different libm builds may round differently (R2).
#     CI runs this with the ARM build under qemu (qemu-test.sh).
#
# DATA is synthetic data from tests/generate_data.py (never original data).
set -uo pipefail
MODE="${1:?usage: save-roundtrip.sh produce|consume RUN DATA ...}"
RUN="${2:?RUN}"
DATA="${3:?DATA}"
FAILS=0
ok() { echo "ok   - $1"; }
bad() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

# opena2 PREFS ARGS...: run the game headless with PREFS; output in $OUTPUT.
opena2() {
  local prefs="$1"
  shift
  # shellcheck disable=SC2086  # RUN may be "qemu-arm-static -L ... opena2"
  OUTPUT="$($RUN --data "$DATA" --headless --prefs "$prefs" "$@" 2>&1)"
  STATUS=$?
  printf '%s\n' "$OUTPUT" | sed 's/^/     | /'
  return $STATUS
}

# continue_from SAVE PREFS: load SAVE, drive 300 frames, autosave in PREFS.
continue_from() {
  mkdir -p "$2"
  cp "$1" "$2/autosave.sav"
  if opena2 "$2" --load-autosave --demo --frames 300 --autosave-on-exit &&
    printf '%s' "$OUTPUT" | grep -q "Autosave loaded" &&
    printf '%s' "$OUTPUT" | grep -q "Autosave written"; then
    ok "$3"
  else
    bad "$3 (status $STATUS)"
  fi
}

# loads SAVE NAME: the save loads and the game runs a frame.
loads() {
  local dir
  dir="$(mktemp -d)"
  cp "$1" "$dir/autosave.sav"
  if opena2 "$dir" --load-autosave --frames 1 && printf '%s' "$OUTPUT" | grep -q "Autosave loaded"; then
    ok "$2 loads"
  else
    bad "$2 loads (status $STATUS)"
  fi
  rm -rf "$dir"
}

case "$MODE" in
  produce)
    OUT="${4:?OUT}"
    rm -rf "$OUT/first" "$OUT/second"
    mkdir -p "$OUT/first"
    if opena2 "$OUT/first" --demo --frames 300 --autosave-on-exit &&
      [ -s "$OUT/first/autosave.sav" ]; then
      ok "first save after 300 demo frames"
    else
      bad "first save after 300 demo frames (status $STATUS)"
    fi
    [ -s "$OUT/first/autosave.sav" ] &&
      continue_from "$OUT/first/autosave.sav" "$OUT/second" "load, 300 more frames, second save"
    ;;
  consume)
    IN="${4:?IN}"
    WORK="${5:?WORK}"
    for f in "$IN/first/autosave.sav" "$IN/second/autosave.sav"; do
      [ -s "$f" ] || { echo "save-roundtrip: missing $f (run produce first)" >&2; exit 1; }
    done
    rm -rf "$WORK/second"
    continue_from "$IN/first/autosave.sav" "$WORK/second" "other build's save loads and the race continues 300 frames"
    if [ -s "$WORK/second/autosave.sav" ]; then
      loads "$WORK/second/autosave.sav" "this build's second save"
      loads "$IN/second/autosave.sav" "other build's second save"
      if cmp -s "$IN/second/autosave.sav" "$WORK/second/autosave.sav"; then
        echo "info - second saves are byte-identical"
      else
        echo "info - second saves differ (report only, R2):"
        cmp "$IN/second/autosave.sav" "$WORK/second/autosave.sav" | head -1 | sed 's/^/     /'
        diff "$IN/second/autosave.sav" "$WORK/second/autosave.sav" 2>/dev/null | head -10 | sed 's/^/     /'
      fi
    fi
    ;;
  *) echo "save-roundtrip: mode is produce or consume" >&2; exit 1 ;;
esac

if [ "$FAILS" = 0 ]; then echo "save-roundtrip $MODE: PASS"; else echo "save-roundtrip $MODE: FAIL ($FAILS)"; exit 1; fi
