#!/bin/sh
# Tests for port/launch.sh: data finding (Review Focus 5) and the missing or
# partial data paths (Review Focus 1).
#
# Strictly POSIX sh: Onion runs launch.sh under BusyBox ash, so these tests run
# it under dash (debian:bookworm) and BusyBox ash (alpine), both local images.
#
#   verify-launch.sh            run everything (host: needs Docker)
#   verify-launch.sh --cases    find_data / no-data cases, in the current sh
#   verify-launch.sh --game EXE partial-data case with a built x86 opena2,
#                               in the current sh (needs python3)
#
# The game case runs inside the cached opena2mini-hosttest:gcc13 image, after
# host-test.sh --game --miyoo has built the game. It uses truncated synthetic
# data from tests/generate_data.py; no original game data is involved.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
LAUNCH="$HERE/port/launch.sh"
FAILS=0
PASSES=0

pass() {
  PASSES=$((PASSES + 1))
  echo "ok   - $1"
}
fail() {
  FAILS=$((FAILS + 1))
  echo "FAIL - $1"
}
# expect NAME EXPECTED ACTUAL
expect() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected '$2', got '$3')"; fi
}

# fresh_port: a new empty port directory with launch.sh; prints its path.
fresh_port() {
  dir=$(mktemp -d "${TMPDIR:-/tmp}/a2launch.XXXXXX")
  cp "$LAUNCH" "$dir/launch.sh"
  mkdir -p "$dir/data"
  echo "$dir"
}

# run_find PORT: find_data on PORT/data from inside PORT, sourcing launch.sh
# as a library. Prints "<status>:<output>".
run_find() {
  out=$(cd "$1" && LAUNCH_SH_LIB=1 sh -c '. ./launch.sh && find_data data')
  echo "$?:$out"
}

cases() {
  echo "== find_data cases ($(readlink /proc/$$/exe 2>/dev/null || echo sh)) =="

  p=$(fresh_port)
  expect "empty data/ -> exit 2, nothing printed" "2:" "$(run_find "$p")"
  # The whole launcher, not just the function: a reason in the log, then the
  # game starts on the empty data/ so it shows its error page; exit 2.
  printf '#!/bin/sh\necho "stand-in game called: $*"\nexit 1\n' >"$p/opena2"
  chmod +x "$p/opena2"
  (cd "$p" && sh ./launch.sh --mute >/dev/null 2>&1)
  status=$?
  expect "launch.sh without data exits 2" 2 "$status"
  if grep -q "stand-in game called: --data $p/data --prefs $p/saves --mute" "$p/logs/latest.log"; then
    pass "without data the game still starts on data/ (error page)"
  else
    fail "without data the game still starts on data/ (log: $(cat "$p/logs/latest.log"))"
  fi
  if grep -q "data/" "$p/logs/latest.log" 2>/dev/null; then
    pass "no-data log mentions data/"
  else
    fail "no-data log mentions data/"
  fi
  if grep -q "RCS.IND" "$p/logs/latest.log" 2>/dev/null; then
    pass "no-data log says what was looked for"
  else
    fail "no-data log says what was looked for"
  fi
  # Only the placeholder file present (the shipped state).
  echo "put the CD here" >"$p/data/PUT_A2_RACER_CD_HERE.txt"
  expect "placeholder only -> exit 2" "2:" "$(run_find "$p")"
  rm -rf "$p"

  p=$(fresh_port)
  mkdir "$p/data/CD" && : >"$p/data/CD/RCS.IND"
  expect "data/CD/RCS.IND -> data/CD" "0:data/CD" "$(run_find "$p")"
  rm -rf "$p"

  p=$(fresh_port)
  : >"$p/data/RCS.IND"
  expect "data/RCS.IND -> data" "0:data" "$(run_find "$p")"
  rm -rf "$p"

  p=$(fresh_port)
  : >"$p/data/CD.iso"
  expect "data/CD.iso -> data/CD.iso" "0:data/CD.iso" "$(run_find "$p")"
  rm -rf "$p"

  p=$(fresh_port)
  : >"$p/data/a2racer.ISO"
  expect "data/a2racer.ISO -> data/a2racer.ISO" "0:data/a2racer.ISO" "$(run_find "$p")"
  rm -rf "$p"

  p=$(fresh_port)
  : >"$p/data/a2racer.iso" && : >"$p/data/CD.iso"
  expect "CD.iso preferred over another *.iso" "0:data/CD.iso" "$(run_find "$p")"
  rm -rf "$p"

  p=$(fresh_port)
  : >"$p/data/track.bin" && : >"$p/data/track.cue"
  expect "data/track.bin + track.cue -> data/track.bin" "0:data/track.bin" "$(run_find "$p")"
  rm -rf "$p"

  p=$(fresh_port)
  : >"$p/data/TRACK.BIN" && : >"$p/data/TRACK.CUE"
  expect "data/TRACK.BIN -> data/TRACK.BIN" "0:data/TRACK.BIN" "$(run_find "$p")"
  rm -rf "$p"

  p=$(fresh_port)
  mkdir "$p/data/cd" && : >"$p/data/cd/rcs.ind"
  expect "lowercase data/cd/rcs.ind -> data/cd" "0:data/cd" "$(run_find "$p")"
  rm -rf "$p"

  p=$(fresh_port)
  : >"$p/data/Rcs.Ind"
  expect "mixed-case data/Rcs.Ind -> data" "0:data" "$(run_find "$p")"
  rm -rf "$p"

  p=$(fresh_port)
  # A CD folder without the marker is not data; the image next to it is.
  mkdir "$p/data/CD" && : >"$p/data/CD/README.TXT" && : >"$p/data/CD.iso"
  expect "data/CD without marker falls through to CD.iso" "0:data/CD.iso" "$(run_find "$p")"
  rm -rf "$p"

  p=$(fresh_port)
  mkdir "$p/data/CD" && : >"$p/data/CD/RCS.IND" && : >"$p/data/CD.iso"
  expect "data/CD folder preferred over CD.iso" "0:data/CD" "$(run_find "$p")"
  rm -rf "$p"

  p=$(fresh_port)
  mkdir "$p/data/My CD" && : >"$p/data/My CD/RCS.IND" && : >"$p/data/my disc.iso"
  expect "folder name with spaces, preferred over an image" "0:data/My CD" "$(run_find "$p")"
  rm -rf "$p"

  p=$(fresh_port)
  : >"$p/data/my disc.iso"
  expect "image name with spaces" "0:data/my disc.iso" "$(run_find "$p")"
  rm -rf "$p"

  p=$(fresh_port)
  mkdir "$p/data/A2RACER" && : >"$p/data/A2RACER/RCS.IND"
  expect "CD folder named after the volume label -> data/A2RACER" "0:data/A2RACER" "$(run_find "$p")"
  rm -rf "$p"

  p=$(fresh_port)
  mkdir "$p/data/a2racer" && : >"$p/data/a2racer/rcs.ind"
  expect "lowercase data/a2racer/rcs.ind -> data/a2racer" "0:data/a2racer" "$(run_find "$p")"
  rm -rf "$p"

  p=$(fresh_port)
  mkdir "$p/data/A2RACER" "$p/data/CD" && : >"$p/data/A2RACER/RCS.IND" && : >"$p/data/CD/RCS.IND"
  expect "a CD folder is preferred over another named folder" "0:data/CD" "$(run_find "$p")"
  rm -rf "$p"

  p=$(fresh_port)
  mkdir "$p/data/A2RACER" && : >"$p/data/A2RACER/RCS.IND" && : >"$p/data/RCS.IND"
  expect "a named CD folder is preferred over files in data/" "0:data/A2RACER" "$(run_find "$p")"
  rm -rf "$p"

  p=$(fresh_port)
  mkdir "$p/data/extras" && : >"$p/data/extras/README.TXT" && : >"$p/data/track.bin"
  expect "a folder without the marker is not data" "0:data/track.bin" "$(run_find "$p")"
  rm -rf "$p"

  # The run part: a stand-in game records its arguments and exit status.
  p=$(fresh_port)
  mkdir "$p/data/CD" && : >"$p/data/CD/RCS.IND"
  cat >"$p/opena2" <<'EOF'
#!/bin/sh
echo "args: $*"
echo "pwd: $(pwd)"
echo "home: $HOME"
echo "ld: $LD_LIBRARY_PATH"
exit 7
EOF
  chmod +x "$p/opena2"
  (cd /tmp && sh "$p/launch.sh" --world-scale 0.75 >/dev/null 2>&1)
  status=$?
  expect "launch.sh returns the game's exit status" 7 "$status"
  log=$(cat "$p/logs/latest.log" 2>/dev/null)
  case "$log" in
  *"args: --data $p/data/CD --prefs $p/saves --skip-intro-if-seen --world-scale 0.75"*)
    pass "game gets --data, --prefs, --skip-intro-if-seen and the Arguments" ;;
  *) fail "game arguments (log: $log)" ;;
  esac
  case "$log" in *"pwd: $p"*) pass "game runs in the port dir" ;; *) fail "game cwd" ;; esac
  case "$log" in *"home: $p"*) pass "HOME is the port dir" ;; *) fail "HOME" ;; esac
  case "$log" in *"ld: $p/libs"*) pass "LD_LIBRARY_PATH starts with libs" ;; *) fail "LD_LIBRARY_PATH" ;; esac
  # Onion may pass the .port Arguments as one word.
  (cd "$p" && sh ./launch.sh "--world-scale 0.5 --mute" >/dev/null 2>&1)
  case "$(cat "$p/logs/latest.log")" in
  *"--skip-intro-if-seen --world-scale 0.5 --mute"*) pass "Arguments given as one word are split" ;;
  *) fail "Arguments given as one word are split" ;;
  esac
  rm -rf "$p"
}

# game_case EXE: a partial copy (marker present, a track file missing, another
# file truncated). launch.sh passes it on; the game shows its error page and
# exits non-zero instead of crashing.
game_case() {
  exe=$1
  echo "== partial data with $exe =="
  p=$(fresh_port)
  cp "$exe" "$p/opena2"
  python3 "$ROOT/tests/generate_data.py" "$p/data/CD" >/dev/null || {
    fail "generate synthetic data"
    return
  }
  rm "$p/data/CD/ETAPPE2.TRK"
  # Truncate a second required file, as an interrupted copy would.
  head -c 100 "$p/data/CD/ETAPPE3.OMP" >"$p/data/CD/ETAPPE3.OMP.part"
  mv "$p/data/CD/ETAPPE3.OMP.part" "$p/data/CD/ETAPPE3.OMP"
  expect "partial copy is still passed on" "0:data/CD" "$(run_find "$p")"
  # Windowed game on SDL's dummy drivers; --frames ends the error page.
  (cd "$p" && SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
    sh ./launch.sh --frames 30 --screenshot "$p/error.bmp" >/dev/null 2>&1)
  status=$?
  if [ "$status" -ne 0 ] && [ "$status" -lt 128 ]; then
    pass "game exits non-zero without crashing (status $status)"
  else
    fail "game exit status $status (want 1..127)"
  fi
  if grep -q "ETAPPE2" "$p/logs/latest.log"; then
    pass "log names the missing file"
  else
    fail "log names the missing file: $(cat "$p/logs/latest.log")"
  fi
  if [ -s "$p/error.bmp" ]; then pass "error page was rendered"; else fail "error page was rendered"; fi
  sed 's/^/     log: /' "$p/logs/latest.log"
  # The same copy, complete: the game starts (control for the case above).
  python3 "$ROOT/tests/generate_data.py" "$p/data/CD" >/dev/null
  (cd "$p" && SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
    sh ./launch.sh --frames 30 >/dev/null 2>&1)
  expect "complete synthetic copy runs and exits 0" 0 "$?"
  rm -rf "$p"

  echo "== no data with $exe =="
  p=$(fresh_port)
  cp "$exe" "$p/opena2"
  echo "put the CD here" >"$p/data/PUT_A2_RACER_CD_HERE.txt"
  (cd "$p" && SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
    sh ./launch.sh --frames 30 --screenshot "$p/nodata.bmp" >/dev/null 2>&1)
  expect "no data: launch.sh exits 2" 2 "$?"
  if grep -q "Looked for" "$p/logs/latest.log" &&
    grep -q "OpenA2: A2 Racer data not found" "$p/logs/latest.log"; then
    pass "no data: log has the launcher reason and the game's error"
  else
    fail "no data: log (got: $(cat "$p/logs/latest.log"))"
  fi
  if [ -s "$p/nodata.bmp" ]; then pass "no data: error page was rendered"; else fail "no data: error page was rendered"; fi
  if [ -n "${A2_KEEP_BMP:-}" ]; then cp "$p/nodata.bmp" "$A2_KEEP_BMP"; fi
  sed 's/^/     log: /' "$p/logs/latest.log"
  rm -rf "$p"
}

summary() {
  echo "== $PASSES passed, $FAILS failed =="
  [ "$FAILS" -eq 0 ]
}

case "${1:-}" in
--cases)
  cases
  summary
  exit $?
  ;;
--game)
  game_case "$2"
  summary
  exit $?
  ;;
esac

# Host driver: dash, BusyBox ash, then the game case in the gcc13 image.
export MSYS_NO_PATHCONV=1
status=0
echo "#### dash (debian:bookworm)"
docker run --rm -v "$ROOT:/src:ro" debian:bookworm sh /src/Packaging/miyoo_mini/verify-launch.sh --cases || status=1
echo "#### BusyBox ash (alpine:3.22)"
docker run --rm -v "$ROOT:/src:ro" alpine:3.22 sh /src/Packaging/miyoo_mini/verify-launch.sh --cases || status=1
echo "#### partial data, x86 game build (opena2mini-hosttest:gcc13, A2_MIYOO=ON)"
bash "$HERE/host-test.sh" --game --miyoo \
  --then "sh /src/Packaging/miyoo_mini/verify-launch.sh --game /tmp/build/opena2" 13 || status=1
[ "$status" -eq 0 ] && echo "verify-launch: PASS" || echo "verify-launch: FAIL"
exit "$status"
