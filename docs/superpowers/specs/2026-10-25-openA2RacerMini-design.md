# OpenA2RacerMini: design

Date: 2026-10-25
Status: ready for owner review

## What this is

OpenA2RacerMini is a fork of [openA2Racer](https://github.com/3dutchie/openA2Racer)
(the open-source reimplementation of Davilex's A2 Racer, 1997, Dutch release)
that runs natively on the **Miyoo Mini Plus under Onion OS**.

It is for two audiences, in this order:

1. The owner, who plays it on their own Mini Plus.
2. Other A2 Racer fans, who install it from the
   [MiyooMini-Ports](https://github.com/Producdevity/MiyooMini-Ports) catalog.

So it must be a real, finished Onion port: extract a release to the SD card,
add your own game data, run `~Import ports`, play. Nobody installing it should
need to know how it was built.

## Why it matters, and what failure looks like

It is a racing game. **Smooth frame rate and immediate control response come
first.** Frame drops or sluggish steering make it a failure even if everything
else works. Picture quality is second: the best image possible *without*
compromising smoothness.

## Goals

- Full game on the device: menus, all six stages, cars, traffic, police,
  HUD, music, sound, Smacker movies, profiles and saves. No cut-down race-only
  build.
- **Frame rate: aim for 60 fps during races, with 30 fps as a hard floor.**
  "Hard floor" means no sustained dips below 30 fps on any stage with the
  release default settings, measured on a real Mini Plus with real game data.
- Responsive input: button press to visible reaction within one or two frames;
  no buffering/vsync setup that adds latency.
- Best possible image within that budget (see Rendering).
- Installs and behaves like other good Onion ports (see Packaging and Onion
  integration).
- Listed in MiyooMini-Ports as category Racing, assets "Owned data".

## Non-goals

- Shipping any original A2 Racer data (art, audio, movies, executables).
  Users supply their own copy, exactly like the Half-Life, Fallout and
  Mario Kart 64 ports.
- The desktop "enhanced" graphics mode (1280×960, edge AA, shadows, 2×
  textures). It is removed or compiled out on the device.
- Supporting other handhelds (Miyoo Flip RK3566, A30, etc.). The Miyoo Mini
  v1–v4 and Mini Flip share the same SoC and will likely work, but only the
  Mini Plus is tested.
- Becoming upstream openA2Racer. This is a separate fork.
- Importing original Windows saves (upstream doesn't either).

## Anti-goals

- A build that runs but stutters in races, or has steering that feels laggy
  or twitchy on the D-pad.
- Device changes outside the port folder: no firmware mods, no system-wide
  libraries, no forced overclock/swap.
- Hard-to-merge divergence from upstream: Miyoo changes must stay isolated so
  upstream fixes can keep flowing in.

## Constraints

**Hardware.** SigmaStar SSD202D: 2× Cortex-A7 @ ~1.2 GHz, ARMv7-A hard-float +
NEON-VFPv4, 128 MB RAM shared with Onion, 640×480 screen, no usable GPU for 3D.
A 2D blit engine (MI_GFX) exists and can scale/copy surfaces.

**The engine already fits well.** openA2Racer renders entirely on the CPU into
a 640×480 ARGB8888 buffer and uploads one SDL streaming texture per frame
(`src/main.cpp`). It depends only on SDL2 (window, input, audio) plus vendored
libsmacker and stb. It reads game files on demand from an extracted CD folder
or ISO (`readExtent` in `src/assets.cpp`), never loading the whole disc into
RAM. Steering is already ramped (`moveTowards` in `src/simulation.cpp`, full
lock in ~0.12 s). It has a 320×200 low-res mode and a headless
`--demo --frames N` mode for repeatable measurement.

**Toolchain.** The Onion ecosystem builds with GCC 8.x against glibc 2.28
(`ghcr.io/onionui/miyoomini-toolchain`). openA2Racer targets C++20; the only
C++20 library feature found so far is `std::bit_cast` in `src/assets.cpp`.
GCC 8 also needs `-lstdc++fs` for `<filesystem>`. Exact remaining
incompatibilities are only known after a first compile.

**Data size.** A CD image is ~700–800 MB; trivial on typical 32–128 GB cards
and under FAT32's 4 GB limit.

**Licensing.** New code MIT. libsmacker is LGPL-2.1 and statically linked
upstream; releases must keep shipping its source/relink archive (upstream's
CMake already produces one). The Miyoo SDL2 backends are GPL-3.0 or zlib
depending on the fork used; their license goes in the release.

**Builder's machine.** Windows 11 with Docker Desktop and git; no host CMake.
The owner has a Mini Plus with Onion OS and will obtain a copy of the Dutch
release for real-data testing.

## Decided by the owner

- **Name:** OpenA2RacerMini.
- **Separate fork** of openA2Racer with its own repo and GitHub releases.
- **Smoothness over looks**, but the best looks the budget allows.
- **60 fps target, 30 fps hard floor.**
- **Controls** (follows the Mario Kart 64 Miyoo port's conventions):

  | Button | Action |
  |---|---|
  | D-pad | Steer / navigate menus |
  | A | Gas / confirm / dismiss fine / skip movie |
  | B | Brake and reverse / back |
  | R1 | Handbrake |
  | Y | Cycle camera (cockpit → chase → helicopter) |
  | X | Toggle radar |
  | Start | Pause / resume |
  | Select + Start | Restart stage |
  | Menu | Quick save, then return to Onion |
  | Menu + R2 / Menu + L2 | Quick save / quick load |
  | L1, L2, R2 | Unassigned by default |

  The in-game BEDIENING (controls) menu keeps working for remapping.
- **Full game**, not a race-only build.
- **Distribution as "owned data"**: no game files in releases.
- **Device access:** the builder may use FTP, SSH or USB to the owner's Mini
  Plus (Onion's Wi-Fi FTP/SSH), so device runs can be a tight
  build → push → measure loop. The builder picks the method. When the real
  game data arrives is not yet known; until then work proceeds on
  synthetic data.
- **Gameplay never changes for performance.** Traffic, rivals, police,
  physics, pickups and collidable objects stay exactly as upstream. Only
  presentation may be reduced.
- **Publishing:** the fork, its releases and the MiyooMini-Ports PR are under
  the owner's GitHub account. The builder prepares everything (CI, release
  notes, `ports.json` entry); the owner presses publish and opens the PR.

## Calls made by Claude (check these)

- **Repo layout like OpenRCT2mini:** a `Packaging/miyoo_mini/` folder with
  `Dockerfile`, `build-deps.sh`, `toolchainfile.cmake`, `build.sh`,
  `package.sh` and the launch script, next to the upstream source.
- **Miyoo changes behind a CMake option** (e.g. `-DA2_MIYOO=ON`) and `#if`
  guards, so the desktop build stays identical to upstream.
- **Stay on the Onion GCC 8 toolchain** and backport the few C++20 bits
  (e.g. a `memcpy`-based `bit_cast` helper), rather than introducing a newer
  compiler. If backporting turns out to be large, a newer cross-GCC with
  static libstdc++ is the fallback; that switch should be flagged, not made
  silently.
- **Static libstdc++/libgcc**, flags
  `-marm -mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard`, Release/O2 or
  O3 (whichever measures faster).
- **SDL2 from a Miyoo fork**, bundled in the port's `libs/` folder.
  OpenRCT2mini uses `XK9274/sdl2_miyoo` (MI_GFX video backend); Half-Life
  uses the steward-fu `mmiyoo` backend. Either is acceptable; pin a specific
  commit. Choose the one with lower input latency and working audio.
- **Working dir and saves on the SD card:** the launcher sets `HOME` and
  XDG paths to the port folder so SDL's pref dir (profiles, settings, save
  slots) lives under `Roms/PORTS/Games/OpenA2RacerMini/`.
- **Render threads capped at 2** on the device.
- **CPU governor:** `launch.sh` may set the `performance` governor at the
  stock clock for the session and must restore the previous governor on exit.
  No overclock by default (users can still use Onion's own overclock tools).
- **Fallback order if 30 fps isn't held:** (1) dynamic/lower internal
  resolution, (2) shorter view distance, (3) dropping or simplifying distant
  *non-collidable* scenery only. Nothing that touches gameplay. If the floor
  still can't be held on some stage, that blocks a 1.0 release; earlier
  releases may ship as "prerelease" with the stage documented as a known
  issue.
- **The floor holds in all three cameras** (cockpit, chase, helicopter) and in
  busy moments (start grid, police chases, heavy traffic). Dynamic resolution
  exists to absorb exactly these peaks.
- **Shared vs. Miyoo-only code:** portable speedups that leave desktop output
  unchanged may go into shared code (and can be offered upstream).
  Device-only changes that alter output (fixed-point, NEON paths, lower
  precision) sit behind the Miyoo option. Device rendering does **not** need
  to be pixel-identical to upstream's screenshot tests, but the
  **simulation must stay identical**: same results from the same inputs, so
  saves move between desktop and device.
- **Menu-button save:** goes into a dedicated autosave slot, never one of the
  ten manual slots or the quick-save slot. The next launch starts normally
  (intro skippable, then menu), with the autosave loadable from the load
  menu; Game Switcher-style auto-resume is the nice-to-have below. Outside a
  race (menus, movies) Menu just exits. Menu acts on release so Menu+R2/L2
  combos don't trigger an exit.

## Rendering

The guiding principle, taken from the Mario Kart 64 port: render as sharply as
the frame budget allows, and drop resolution only when needed.

Required behaviour:

- **Internal resolution is adjustable**, with at least 640×480 and 320×240
  (4:3, matching the screen; the existing 320×200 mode can serve as the low
  end if simpler). Output is scaled to 640×480, preferably with the MI_GFX
  blitter so scaling costs no CPU.
- **Dynamic resolution in races (my call, strongly suggested by MK64):**
  while a frame wouldn't fit in 1/60 s, render smaller; return to full size
  when there is headroom. Menus and movies always at full size.
- **View distance** stays at the original 2,600 units or less; reduce it only
  if measurement shows it is needed to hold the floor.
- Release defaults are picked from real-device measurements so every stage
  holds ≥ 30 fps and as close to 60 as possible. Users can change them with
  launch arguments in the `.port` file (like MK64's `Arguments` line).

How to make the software renderer faster (fixed-point, NEON, span
optimisations, texture cache size, etc.) is left to the builder, guided by
profiling.

## Input

- Map the Miyoo buttons (which arrive as keyboard keys or joystick events
  depending on the SDL fork) to the actions above.
- D-pad steering must feel analogue-smooth: keep the existing ramp, tune
  rates on the device. Gas/brake are digital.
- No latency added by triple buffering or queued presents; target ≤ 2 frames
  from press to screen.

## Onion integration

Minimum for release:

- Launch from Ports; the shortcut stays hidden until game data is present
  (`GameDataFile` in the `.port` file).
- Menu returns cleanly to Onion after an automatic quick save.
- Clean exit with `sync`, no corrupted saves when quitting.
- Logs to a file in the port folder; no log spam on the SD card in release
  builds unless a debug flag is set.

Nice to have, in this order (builder decides how far to go): Onion Game
Switcher resume (MK64 does this), save on power-off with resume, low-battery
warning.

## Packaging

Release archive (7z or zip), extracted at the SD card root:

```
Roms/PORTS/
  Games/OpenA2RacerMini/
    opena2              stripped ARM binary
    launch.sh
    libs/               bundled SDL2 (and anything else non-system)
    data/               user puts the CD folder or CD.iso here
    README / INSTALL.txt, licenses, LGPL relink source archive
  Imgs/OpenA2RacerMini.png    box art
  Shortcuts/Racing/OpenA2RacerMini.port
```

`launch.sh` sets library path, `HOME`, SDL driver variables, checks the data
is present (writes a clear message to the log if not), runs the game with
`--data data/...`, logs, and `sync`s on exit.

The README explains where to put the data (an extracted CD folder or a
`CD.iso`/raw MODE2 image) and that the Dutch release is the supported one.

## Build

- One command on Windows (Docker Desktop) or Linux produces the binary and
  the release archive. It runs in a container based on the Onion toolchain
  image; first run may build SDL2 and cache it.
- A GitHub Actions workflow builds the same archive on push/tag (nice to
  have before the first public release).
- The desktop build and upstream's synthetic tests (`ctest`, `A2_BUILD_GAME=OFF`
  core tests) keep passing.

## Testing and acceptance

Three stages:

1. **Synthetic data (no game needed):** build passes; upstream core tests pass
   on the host; the ARM binary runs headless under `qemu-arm-static` with the
   synthetic data (OpenRCT2mini does this); on the Mini Plus it launches from
   Onion, every button does its job, sound plays, Menu returns to Onion.
2. **Real data on the Mini Plus:** for each of the six stages and all three
   cameras, run a repeatable measurement (headless `--demo` for raw render
   fps, plus a scripted or recorded drive the builder defines so rounds are
   comparable) and record average fps, 1% low, worst frame, and memory use,
   written to a CSV in the port folder. Use these numbers to pick release
   defaults.
3. **Release:** fresh SD-card install from the archive following only the
   README, play stage 1 through to the finish, save/quit/resume. The builder
   then prepares the GitHub release and the MiyooMini-Ports `ports.json`
   entry; the owner publishes and opens the PR.

**Done means:** every stage holds ≥ 30 fps with release defaults (aim 60);
controls feel immediate; all goals above work; clean install works from the
README alone.

## Left to the builder

- Choice of SDL2 Miyoo fork (within the criteria above).
- All renderer optimisation techniques and dynamic-resolution heuristics.
- How the Miyoo code is structured inside the fork (as long as it is isolated
  and the desktop build is unchanged).
- Exact launch arguments and their names.
- How far to go with the "nice to have" Onion integration.
- Box art (an original design; don't copy Davilex's cover art).

## Prior art

- **Mario Kart 64** (cacuracaptors/mk64-miyoomini): controls, dynamic
  resolution, 640×480 at up to 60 fps, deep Onion integration.
- **OpenRCT2mini** (scheeseman486): Docker toolchain, CMake toolchain file,
  SDL2 fork build, qemu testing, Onion packaging.
- **Half-Life** (IC-0n417): owned-data model, launcher checks, 320×240
  software rendering at a 30 fps cap as a performance reference.
