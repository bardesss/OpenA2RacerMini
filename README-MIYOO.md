# OpenA2RacerMini

A2 Racer (Davilex, 1997, Dutch release) on the **Miyoo Mini Plus** and
**Miyoo Mini Flip** with **Onion OS**, using the open-source OpenA2 engine.

The Mini Plus is tested. The Mini Flip uses the same chip and the same build,
and is expected to work, but nobody has confirmed that yet.

## What you need

- A Miyoo Mini Plus or Mini Flip with Onion OS.
- Your own copy of the **Dutch A2 Racer CD**. Other editions have not been
  verified. This port contains no game files.

## Install

1. Extract the release archive to the root of the SD card. It adds
   `Roms/PORTS/Games/OpenA2RacerMini/`, the box art in `Roms/PORTS/Imgs/` and
   the shortcut `Roms/PORTS/Shortcuts/Racing/OpenA2RacerMini.port`.
2. Copy the CD to `Roms/PORTS/Games/OpenA2RacerMini/data/`, in any of these
   forms (upper or lower case names both work):

   | Put in `data/` | What it is |
   |---|---|
   | `CD/` | the whole CD folder, with `RCS.IND`, `RCS.IMG`, `ETAPPE1.TRK`, ... inside |
   | the CD's files | copied straight into `data/` |
   | `CD.iso` or any `*.iso` | an ISO disc image |
   | `track.bin` (any `*.bin`) | a raw MODE2/2352 image from a BIN/CUE pair; keep the `.cue` next to it |

   The data is about 114 MB.
3. On the device, open **Games > Ports** and run **~Import ports**.
4. Start **OpenA2RacerMini**. The intro movie plays on the first launch only.

If the game does not start, read
`Roms/PORTS/Games/OpenA2RacerMini/logs/latest.log`. Without game data it lists
what was looked for and where; with broken or incomplete data the game shows an
error page (press Menu to return to Onion) and the log names the missing file.

Saves, profiles and settings live in
`Roms/PORTS/Games/OpenA2RacerMini/saves/`. The save files are the same as on
the desktop OpenA2, so you can copy them between the two.

## Controls

| Button | Action |
|---|---|
| D-pad | Steer / navigate menus |
| A | Gas / confirm / dismiss fine / skip movie |
| B | Brake and reverse / back |
| R1 | Handbrake |
| Y | Cycle camera (cockpit → chase → helicopter) |
| X | Toggle radar |
| Start | Pause / resume (in menus it also confirms) |
| Select + Start | Restart stage |
| Menu (on release) | In a race: autosave, then return to Onion. Elsewhere: return to Onion. |
| Menu + R2 / Menu + L2 | Quick save / quick load (slot 1), without leaving |
| L1, L2, R2 | Unassigned |

The Menu button always writes to its own **autosave** slot, never to a manual
slot or the quick-save slot. The next launch starts normally; load the
autosave from the load (slots) menu.

## Options

Extra game options go in the `Arguments` line of
`Roms/PORTS/Shortcuts/Racing/OpenA2RacerMini.port`, for example
`Arguments="--world-scale 0.75"`. Run `~Import ports` again after editing it.

| Option | Effect |
|---|---|
| `--world-scale S` | Fixed race resolution scale from 0.5 to 1 (turns off the automatic scaling). The HUD stays sharp. |
| `--dynamic-resolution on\|off` | Lower the race resolution automatically when a frame is slow (on by default). |
| `--view-distance N` | Race view distance in units, at most 2600 (the original). |
| `--vsync on\|off` | Wait for the display refresh. |
| `--camera 1..3` | Start in cockpit, chase or helicopter view. |
| `--skip-intro` | Never play the intro movie. |
| `--mute` | No sound. |
| `--perf FILE` | Write one CSV row per frame (stage, camera, scale, frame time, memory) and print fps stats to the log on exit. |

Lowering the resolution or view distance only changes how the game looks;
traffic, police, physics and everything else play as on the desktop.

## Licences

The release folder `licenses/` holds every licence: OpenA2 (MIT),
libsmacker (LGPL-2.1, statically linked; the complete source to rebuild and
relink is in `source/`), the SDL2 Miyoo fork (zlib), Liberation fonts (OFL)
and stb (MIT). A2 Racer itself and its data belong to their owners and are
not part of this port.

## Building

See `Packaging/miyoo_mini/` in the source: `build.sh` cross-builds the ARM
binary, `package.sh` stages the port tree and packs the release, and
`verify-package.sh` / `verify-launch.sh` check the archive and the launcher.
