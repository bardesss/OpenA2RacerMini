#!/bin/sh
# OpenA2RacerMini launcher for Onion OS (Miyoo Mini Plus / Mini Flip).
# Started by Onion's launch_standalone.sh from Roms/PORTS/Games/OpenA2RacerMini
# with the .port file's Arguments. Plain POSIX sh: Onion runs BusyBox ash.
#
# Sourcing this file with LAUNCH_SH_LIB=1 only defines the functions (tests).

PORT_DIR=$(cd "$(dirname "$0")" && pwd)

# upper TEXT: TEXT in upper case.
upper() {
  printf '%s\n' "$1" | tr '[:lower:]' '[:upper:]'
}

# has_marker DIR: true when DIR holds RCS.IND, the file openA2Racer requires
# at the top level of the CD (any case: FAT32 keeps whatever case was copied).
# POSIX sh has no local variables, so each function uses its own names.
has_marker() {
  for marker_file in "$1"/*; do
    [ -f "$marker_file" ] || continue
    [ "$(upper "${marker_file##*/}")" = RCS.IND ] && return 0
  done
  return 1
}

# find_data DIR: prints the path to hand to opena2 --data, or returns 2.
# Accepted, in this order:
#   DIR/CD/        the CD folder (any case) with RCS.IND inside
#   DIR/<any>/     any other folder with RCS.IND inside (a copy named after
#                  the volume label, such as A2RACER); the first one wins
#   DIR            the CD's files copied straight into DIR
#   DIR/CD.iso     (any case)
#   DIR/*.iso      the first ISO image
#   DIR/*.bin      the first raw MODE2/2352 image of a BIN/CUE pair (track.bin);
#                  openA2Racer tells image formats apart by content
find_data() {
  for f in "$1"/*; do
    [ -d "$f" ] && [ "$(upper "${f##*/}")" = CD ] && has_marker "$f" && {
      echo "$f"
      return 0
    }
  done
  for f in "$1"/*; do
    [ -d "$f" ] && has_marker "$f" && {
      echo "$f"
      return 0
    }
  done
  has_marker "$1" && {
    echo "$1"
    return 0
  }
  for pattern in CD.ISO '*.ISO' '*.BIN'; do
    for f in "$1"/*; do
      [ -f "$f" ] || continue
      # shellcheck disable=SC2254 # the pattern is meant to match
      case "$(upper "${f##*/}")" in
      $pattern)
        echo "$f"
        return 0
        ;;
      esac
    done
  done
  return 2
}

# no_data_reason DIR: what was looked for, and where.
no_data_reason() {
  cat <<EOF
OpenA2RacerMini: A2 Racer game data not found.
Looked in: $1/ (the port's data/ folder)
Looked for, in this order:
  data/CD/       a copy of the CD folder (any folder name), with RCS.IND inside
  data/RCS.IND   the CD's files copied straight into data/
  data/CD.iso    or any other data/*.iso disc image
  data/*.bin     a raw BIN/CUE disc image (for example track.bin)
Copy your own Dutch A2 Racer CD there and start the game again.
EOF
}

main() {
  cd "$PORT_DIR" || exit 1
  mkdir -p logs
  export HOME="$PORT_DIR"
  export XDG_CONFIG_HOME="$PORT_DIR" XDG_DATA_HOME="$PORT_DIR" XDG_CACHE_HOME="$PORT_DIR"
  export LD_LIBRARY_PATH="$PORT_DIR/libs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  # The Miyoo SDL2 fork's drivers (MI_GFX video, MI_AO audio) only come up
  # when named here; without them SDL reports "No available video device".
  # Onion stops its audioserver first (KillAudioserver=1 in the .port file).
  export SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-mmiyoo}"
  export SDL_AUDIODRIVER="${SDL_AUDIODRIVER:-mmiyoo}"

  if ! DATA=$(find_data "$PORT_DIR/data"); then
    no_data_reason "$PORT_DIR/data" >logs/latest.log
    # Still start the game: given data/ without game files it shows its error
    # page (copy your CD to data/), so the player sees why; Menu returns to
    # Onion. The exit status stays 2 for "no data".
    # shellcheck disable=SC2048,SC2086
    ./opena2 --data "$PORT_DIR/data" --prefs "$PORT_DIR/saves" $* >>logs/latest.log 2>&1
    sync
    exit 2
  fi
  echo "OpenA2RacerMini: data $DATA" >logs/latest.log
  # Onion may hand over the .port Arguments as one word; split them on purpose.
  # shellcheck disable=SC2048,SC2086
  ./opena2 --data "$DATA" --prefs "$PORT_DIR/saves" --skip-intro-if-seen $* >>logs/latest.log 2>&1
  status=$?
  sync
  exit "$status"
}

if [ "${LAUNCH_SH_LIB:-0}" != 1 ]; then
  main "$@"
fi
