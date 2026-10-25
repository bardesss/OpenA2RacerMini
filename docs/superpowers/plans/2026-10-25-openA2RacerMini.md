# OpenA2RacerMini Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A fork of openA2Racer that builds in Docker on Windows and ships one Onion OS port archive running the full game on the Miyoo Mini Plus and Miyoo Mini Flip at 60 fps target / 30 fps hard floor.

**Architecture:** Upstream source stays as-is except for small, guarded changes. Device-only code sits behind a CMake option `A2_MIYOO` (`#if A2_MIYOO`), and testable logic (button handling, save-slot paths, dynamic resolution, perf stats) lives in new SDL-free files in `a2core` with their own test executables. Everything Miyoo-specific for building and packaging lives in `Packaging/miyoo_mini/`, modelled on OpenRCT2mini.

**Tech Stack:** C++ (C++20 on desktop, compatible with GCC 8.3 on device), CMake ≥ 3.24 inside Docker, Onion toolchain image `ghcr.io/onionui/miyoomini-toolchain` (GCC 8.3, glibc 2.28), Miyoo SDL2 fork (mmiyoo / MI_GFX backend), qemu-arm-static, Onion `launch_standalone.sh`.

**Spec:** `docs/superpowers/specs/2026-10-25-openA2RacerMini-design.md`

## Global Constraints

- Name: **OpenA2RacerMini**. Port folder: `Roms/PORTS/Games/OpenA2RacerMini/`.
- Devices: **Miyoo Mini Plus and Miyoo Mini Flip**, one build (same SSD202D SoC). Mini Plus is tested by the owner; Mini Flip is "expected to work, untested" until a volunteer confirms it. Device differences are handled at runtime, never with a second build.
- Fork base: `3dutchie/openA2Racer` commit `6a9ad018f1a9995c92e9a0d65f9da7edc3952514` (main, 2026-10-22).
- Frame rate: **aim for 60 fps in races; 30 fps hard floor** (no sustained dips below 30) on every stage, in **all three cameras**, including the start grid, police chases and heavy traffic, with release defaults, on a real Mini Plus with real data.
- **Gameplay never changes for performance**: traffic, rivals, police, physics, pickups and collidable objects stay as upstream. Only presentation may be reduced, in this order: (1) internal resolution, (2) view distance (never above the original 2,600 units), (3) distant *non-collidable* scenery.
- **The simulation stays identical** to upstream: no `-ffast-math`, no changes to `src/simulation.cpp` behaviour. Saves must move between desktop and device.
- Desktop build (`A2_MIYOO=OFF`) output stays unchanged; upstream tests keep passing. Portable speedups that leave desktop output identical may go in shared code.
- Enhanced graphics mode is unavailable on the device.
- No original A2 Racer data in the repo, the tests or the release archive.
- Device compile flags: `-marm -mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard`, `-static-libstdc++ -static-libgcc`; render threads capped at 2.
- No overclock by default; performance governor at stock clock only, via Onion's `PerformanceMode=1` (restored by Onion on exit).
- Controls (owner-approved):

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
  | Menu (on release) | In race: autosave, then exit to Onion. Elsewhere: exit. |
  | Menu + R2 / Menu + L2 | Quick save / quick load (slot 1), no exit |
  | L1, L2, R2 | Unassigned |
- Menu-button save goes to a dedicated **autosave** slot, never a manual slot or the quick-save slot. Next launch starts normally; the autosave is loadable from the load (slots) menu.
- Licences in the release: MIT (OpenA2), LGPL-2.1 libsmacker plus the relink source archive, SDL2 fork licence, Liberation OFL, stb MIT.
- Publishing (GitHub repo, releases, MiyooMini-Ports PR) is done by the owner. The builder only prepares it.

## Review Focus

1. **Game data missing, partial or wrong edition.** The launcher writes a clear reason to `logs/latest.log`, the game shows its error page instead of crashing, and Onion gets control back. Owner: Task 10 (`verify-launch.sh` cases).
2. **Profile creation with buttons only.** The device has no keyboard and no `SDL_TEXTINPUT`, so a new player must be creatable with the D-pad and A, with a default name. Owner: Task 6 (`miyoo_controls_test` name-page case plus device check).
3. **Menu pressed mid-movie, mid-loading, on the fine dialog or while paused.** Outside a race it exits cleanly without saving. In a race it autosaves a consistent state, and an autosave written while paused or on a fine loads back correctly. Owner: Task 5 (`autosave_on_exit` headless tests) and Task 6.
4. **SD card full or read-only during autosave.** An error message, the previous autosave left intact, and the game still exits. Owner: Task 5 (`save_slots_test` failing-write case).
5. **Data dropped in different shapes.** The CD folder itself, the CD's contents directly in `data/`, `CD.iso`, any `*.iso`, or upper/lower-case names from FAT32 all need to be found. Owner: Task 10 (`find_data` cases in `verify-launch.sh`).

---

## File Structure

```
(repo root = fork of openA2Racer, in D:\Dev\miyoo-a2-racer)
CMakeLists.txt                      modify: A2_MIYOO option, new core files/tests, stdc++fs, emulator
src/compat.hpp                      create: a2::bitCast (GCC 8 replacement for std::bit_cast)
src/assets.cpp                      modify: std::bit_cast -> a2::bitCast
src/miyoo_controls.hpp/.cpp         create: button state machine -> commands (SDL-free)
src/save_slots.hpp/.cpp             create: slot path rules incl. autosave, atomic write helper
src/dynamic_resolution.hpp/.cpp     create: frame-time -> world scale controller
src/perf_stats.hpp/.cpp             create: frame-time stats (avg, 1% low, worst) + CSV line
src/renderer.hpp/.cpp               modify: world scale (render world smaller, upscale before HUD)
src/render_workers.cpp              modify: cap threads at 2 under A2_MIYOO
src/main.cpp                        modify: Miyoo glue (input, autosave, flags, present, perf)
tests/compat_test.cpp, miyoo_controls_test.cpp, save_slots_test.cpp,
tests/dynamic_resolution_test.cpp, perf_stats_test.cpp      create
tests/renderer_test.cpp             modify: world-scale cases
Packaging/miyoo_mini/
  Dockerfile                        toolchain image (Onion image + cmake, qemu, SDL2 fork)
  build-deps.sh                     builds pinned SDL2 fork into the sysroot
  toolchainfile.cmake               cross settings + CMAKE_CROSSCOMPILING_EMULATOR
  build.sh                          one-command cross build -> build-arm/opena2
  host-test.sh                      host build + ctest in gcc:8 and gcc:13 containers
  qemu-test.sh                      ARM ctest + headless synthetic demo under qemu
  package.sh                        stages Roms/PORTS tree -> dist/*.7z
  verify-package.sh                 checks archive contents, no game data, ELF/glibc limits
  verify-launch.sh                  tests launch.sh data-finding and error paths
  deploy.sh                         push build to device over FTP/SSH
  bench.sh                          on-device stage x camera benchmark -> CSV
  port/launch.sh, port/OpenA2RacerMini.port, port/INSTALL.txt, port/box_art.png
.github/workflows/miyoo.yml         CI: build, test, package, upload artifact
README-MIYOO.md                     user-facing install / controls / options
```

---

### Task 1: Fork setup and host test harness

**Files:**
- Create: repo at `D:\Dev\miyoo-a2-racer` (keep existing `docs/superpowers/`)
- Create: `Packaging/miyoo_mini/host-test.sh`

**Interfaces:**
- Produces: `Packaging/miyoo_mini/host-test.sh [gcc-version]`. It runs `cmake -DA2_BUILD_GAME=OFF` + build + `ctest` in a `gcc:<ver>` container (default 13) with CMake installed, exits non-zero on failure. Later tasks use it as their test runner.

- [ ] **Step 1:** Initialise git in the folder, add remote `upstream` = `https://github.com/3dutchie/openA2Racer.git`, fetch, create branch `main` at commit `6a9ad018…`, keeping `docs/superpowers/` (commit it on top).
- [ ] **Step 2:** Write `host-test.sh`. Mount the repo read-only at `/src`, build in `/tmp/build` inside the container, install cmake ≥ 3.24 (pip `cmake==3.30.*` or the Kitware tarball, because `gcc:8` ships an older CMake).
- [ ] **Step 3:** Run `bash Packaging/miyoo_mini/host-test.sh 13`. Expected: all upstream core tests pass (`100% tests passed`).
- [ ] **Step 4:** Commit: `chore: fork openA2Racer at 6a9ad01 and add host test harness`.

### Task 2: GCC 8 compatibility

**Files:**
- Create: `src/compat.hpp`, `tests/compat_test.cpp`
- Modify: `src/assets.cpp` (lines using `std::bit_cast`: ~56, 395, 420, 421), `CMakeLists.txt`

**Interfaces:**
- Produces: `template <class To, class From> To a2::bitCast(const From &)` (memcpy-based, `static_assert(sizeof(To)==sizeof(From))`, trivially copyable). Header-only, in `src/compat.hpp`.

- [ ] **Step 1: Write the failing test** `tests/compat_test.cpp` using the same `check()` style as `tests/renderer_test.cpp`:
  - `bitCast<float>(uint32_t(0x3f800000)) == 1.0f`
  - `bitCast<int16_t>(uint16_t(0xffff)) == -1`
  - `bitCast<uint32_t>(-0.0f) == 0x80000000u`
- [ ] **Step 2:** Add `compat` to the test list in `CMakeLists.txt`, then run `host-test.sh 13`. Expected: FAIL (compat.hpp missing).
- [ ] **Step 3:** Implement `src/compat.hpp` and replace every `std::bit_cast` in `src/` with `a2::bitCast`. In CMake, when `CMAKE_CXX_COMPILER_ID STREQUAL GNU AND CMAKE_CXX_COMPILER_VERSION VERSION_LESS 9`, link `a2core` against `stdc++fs`. Use `CMAKE_CXX_STANDARD 20` when the compiler supports it, else `17` (GCC 8 only gets `-std=c++2a` partially; compile with 17 + fixes if 2a fails).
- [ ] **Step 4:** Run `host-test.sh 13` and `host-test.sh 8`. Expected: both pass. Fix any further GCC 8 errors in the smallest way that keeps desktop behaviour identical (for example designated initialisers, `std::span`, `contains()`, `<=>`). List each fix in the commit message.
- [ ] **Step 5:** Commit: `build: compile with GCC 8 (bitCast, stdc++fs)`.

### Task 3: Cross toolchain image and ARM build

**Files:**
- Create: `Packaging/miyoo_mini/Dockerfile`, `build-deps.sh`, `toolchainfile.cmake`, `build.sh`
- Modify: `CMakeLists.txt` (option `A2_MIYOO`, default OFF, adds `A2_MIYOO=1` compile definition to `a2core` and `opena2`; when ON, `A2_BUILD_GAME` uses SDL2 from the sysroot, never `FetchContent`)

**Interfaces:**
- Produces: image tag `opena2mini-toolchain:latest`; `bash Packaging/miyoo_mini/build.sh [--debug] [--rebuild-toolchain]` → `build-arm/opena2` plus `build-arm/` test binaries; the sysroot contains `libSDL2-2.0.so.0` at `$SYSROOT/usr/lib`.

- [ ] **Step 1:** Dockerfile `FROM ghcr.io/onionui/miyoomini-toolchain:latest`. Repoint Buster apt to archive.debian.org (as OpenRCT2mini's Dockerfile does), install `pkg-config cmake(≥3.24 via pip or tarball) qemu-user-static p7zip-full python3`, bake `PATH` into `ENV`, and run `build-deps.sh`.
- [ ] **Step 2:** `build-deps.sh` builds SDL2 from `XK9274/sdl2_miyoo`, pinned to an explicit commit SHA recorded in the script (resolve `main` once when writing it), `sdl2/` subdir only, shared library. Apply the same header scrubs OpenRCT2mini's `build-deps.sh` needs (SDL_ttf/SDL_image/SDL_mixer/SDL2_gfx includes). This is the first candidate fork; Task 9 may switch to steward-fu's `mmiyoo` SDL2 on measured latency or audio problems.
- [ ] **Step 3:** `toolchainfile.cmake` copies OpenRCT2mini's structure: sysroot from `-print-sysroot`, `CMAKE_NO_SYSTEM_FROM_IMPORTED TRUE`, the Global Constraints flags, `-static-libstdc++ -static-libgcc -Wl,--gc-sections`, `-Wl,-rpath,'$ORIGIN/libs'`, and `CMAKE_CROSSCOMPILING_EMULATOR` = `qemu-arm-static;-L;<sysroot>`. Default `CMAKE_BUILD_TYPE=Release`.
- [ ] **Step 4:** `build.sh` builds the image if missing or older than Dockerfile/build-deps.sh, then runs cmake with `-DA2_MIYOO=ON -DA2_USE_SYSTEM_SDL2=ON -DA2_FETCH_SDL2=OFF` and builds in `build-arm/`. It must work from Git Bash on Windows (use `MSYS_NO_PATHCONV=1` for `docker run -v`).
- [ ] **Step 5:** Run `bash Packaging/miyoo_mini/build.sh`. Verify inside the container:
  - `file build-arm/opena2` → `ELF 32-bit LSB … ARM, EABI5 … hard-float`
  - `arm-linux-gnueabihf-objdump -T build-arm/opena2 | grep -o 'GLIBC_[0-9.]*' | sort -Vu | tail -1` → ≤ `GLIBC_2.28`
  - `readelf -d build-arm/opena2` shows no `libstdc++` NEEDED entry.
- [ ] **Step 6:** Commit: `build: Miyoo Mini cross toolchain and ARM build`.

### Task 4: ARM tests and synthetic smoke run under qemu

**Files:**
- Create: `Packaging/miyoo_mini/qemu-test.sh`

**Interfaces:**
- Consumes: Task 3 image and `build-arm/`.
- Produces: `bash Packaging/miyoo_mini/qemu-test.sh`, which exits 0 when ARM ctest passes and the ARM `opena2 --headless --demo --frames 480` on synthetic data writes a BMP.

- [ ] **Step 1:** In the container, run `ctest --test-dir build-arm --output-on-failure` (the emulator from the toolchain file makes the ARM test binaries run). Expected: all core tests pass, `simulation` included, which shows that the GCC 8 ARM build simulates like the desktop one.
- [ ] **Step 2:** Generate synthetic data with `python3 tests/generate_data.py /tmp/synthetic`, run `qemu-arm-static -L $SYSROOT build-arm/opena2 --data /tmp/synthetic --headless --demo --frames 480 --screenshot /tmp/smoke.bmp`, and assert the BMP exists and is non-empty.
- [ ] **Step 3: Cross-platform save test.** Add a ctest (host and ARM) `save_roundtrip_fixture`: a save made by the x86 headless build after `--demo --frames 300` loads in the ARM build, and both continue 300 frames to a byte-identical second save. Implement it as `--save-after N PATH` / `--load PATH` debug flags in `main.cpp` (available in all builds, documented in `--help`).
- [ ] **Step 4:** Commit: `test: ARM ctest, synthetic smoke run and x86↔ARM save round trip under qemu`.

### Task 5: Save slots with a dedicated autosave

**Files:**
- Create: `src/save_slots.hpp`, `src/save_slots.cpp`, `tests/save_slots_test.cpp`
- Modify: `src/main.cpp` (`saveFile`, `saveSlot`, `loadSlot`, Slots page), `CMakeLists.txt`

**Interfaces:**
- Produces:
  - `enum class SlotKind { Manual, Autosave };`
  - `struct SlotId { SlotKind kind; int index = 0; };` (index 0–9 for Manual; quick save is Manual 0, as upstream)
  - `std::filesystem::path a2::slotPath(const std::filesystem::path &saveDir, SlotId)` returns `slot<N>.sav` for Manual (upstream naming kept) and `autosave.sav` for Autosave.
  - `bool a2::writeAtomically(const std::filesystem::path &target, const std::function<void(std::ostream &)> &write, std::string &error)` writes `target.tmp` then renames over target. On any failure it returns false, leaves `target` untouched and removes the temp file.
  - CLI: `--autosave-on-exit` (headless: write the autosave when `--frames` ends, emulating Menu) and `--load-autosave`.

- [ ] **Step 1: Write failing tests** in `save_slots_test.cpp`:
  - `slotPath(d,{Manual,0}) == d/"slot0.sav"`, `slotPath(d,{Autosave}) == d/"autosave.sav"`, and Autosave differs from every Manual 0–9
  - `writeAtomically` into a fresh temp dir writes the content
  - `writeAtomically` whose writer throws leaves an existing target byte-identical and no `.tmp` behind
  - `writeAtomically` into a read-only/nonexistent unwritable directory returns false with non-empty error (Review Focus 4)
- [ ] **Step 2:** Run `host-test.sh 13`. Expected: FAIL (no `save_slots`).
- [ ] **Step 3:** Implement. Move `App::saveSlot`'s temp/rename logic onto `writeAtomically`. Add `saveAutosave()` and `loadAutosave()` to `App`. On the Slots page add an `AUTOSAVE` entry above the ten slots, shown only when `autosave.sav` exists, loading via `loadSlot`'s path.
- [ ] **Step 4:** Add CMake headless tests on synthetic data:
  - `autosave_on_exit`: `--demo --frames 300 --autosave-on-exit --prefs DIR`, then `autosave.sav` exists and `slot0.sav` doesn't
  - `autosave_paused`: same while paused (`--pause-at 200`, new debug flag) and on an active fine where the synthetic data allows it; then `--load-autosave --frames 60` exits 0 (Review Focus 3)
- [ ] **Step 5:** Run `host-test.sh 13` and `qemu-test.sh`. Expected: PASS.
- [ ] **Step 6:** Commit: `feat: dedicated autosave slot with atomic writes`.

### Task 6: Miyoo button handling

**Files:**
- Create: `src/miyoo_controls.hpp`, `src/miyoo_controls.cpp`, `tests/miyoo_controls_test.cpp`
- Modify: `src/main.cpp` (inside `#if A2_MIYOO`: `events()`, the drive-input function near line 559, `Settings` defaults), `CMakeLists.txt`

**Interfaces:**
- Produces:
  - `enum class MiyooButton { Up, Down, Left, Right, A, B, X, Y, L1, L2, R1, R2, Start, Select, Menu };`
  - `enum class MiyooContext { Race, Menu, Movie };` (`Race` = Page::Playing incl. paused and fine dialog)
  - `enum class MiyooCommand { Up, Down, Left, Right, Confirm, Back, Pause, CycleCamera, ToggleRadar, RestartStage, QuickSave, QuickLoad, AutosaveAndExit, Exit };`
  - `class MiyooControls { public: std::vector<MiyooCommand> press(MiyooButton, MiyooContext); std::vector<MiyooCommand> release(MiyooButton, MiyooContext); bool held(MiyooButton) const; };`
  - `std::optional<MiyooButton> a2::miyooButtonFromScancode(int sdlScancode)`, a table from the Miyoo evdev keys as SDL scancodes: arrows→D-pad, SPACE→A, LCTRL→B, LSHIFT→X, LALT→Y, E→L1, T→R1, TAB→L2, BACKSPACE→R2, RETURN→Start, RCTRL→Select, ESCAPE→Menu. Declared with plain `int` so core stays SDL-free; the values are SDL2's `SDL_SCANCODE_*` numbers (written as constants in the .cpp with a comment).
- Driving (gas, brake, steer, handbrake) is **not** in `MiyooControls`. It keeps upstream's held-key polling so BEDIENING remapping works. Under `A2_MIYOO`, the `Settings::keys` defaults become `{LEFT, RIGHT, LCTRL (B), SPACE (A)}` and handbrake reads `SDL_SCANCODE_T` (R1) instead of SPACE.

- [ ] **Step 1: Write failing tests** in `miyoo_controls_test.cpp`, one function per rule, asserting the exact command vectors:
  - Race: press A → `{}` (gas is polled, no command); Y → `{CycleCamera}`; X → `{ToggleRadar}`; Start → `{Pause}`
  - Race: hold Select, press Start → `{RestartStage}` and no `Pause`
  - Race: press+release Menu alone → `{}` on press, `{AutosaveAndExit}` on release
  - Race: press Menu, press R2, release R2, release Menu → `{QuickSave}` once and **no** exit; same with L2 → `{QuickLoad}`
  - Menu context: A → `{Confirm}`, B → `{Back}`, D-pad → direction commands, Menu release → `{Exit}`
  - Movie context: A or B → `{Confirm}` (skip), Menu release → `{Exit}`
  - Race with fine dialog: A → `{Confirm}` (upstream dismiss). Since `MiyooControls` doesn't know about fines, the glue passes `MiyooContext::Menu` while `race_->fineDelay() > 0`. Test it as a Menu-context A press and document that in the header.
  - `miyooButtonFromScancode` maps every table entry and returns `nullopt` for an unrelated scancode
- [ ] **Step 2:** Run `host-test.sh 13`. Expected: FAIL.
- [ ] **Step 3:** Implement `MiyooControls`, then the `main.cpp` glue under `#if A2_MIYOO`. In `events()`, `SDL_KEYDOWN`/`SDL_KEYUP` (non-repeat) → `miyooButtonFromScancode` → `press`/`release` with the current context, then dispatch: Up/Down/Left/Right/Confirm/Back → the existing `key(SDLK_*)` calls; Pause → `key(SDLK_p)`; CycleCamera → `settings_.camera = (settings_.camera + 1) % 3`; ToggleRadar → existing radar toggle; RestartStage → existing `R` path; QuickSave/QuickLoad → `saveSlot(0)` / `loadSlot(0)`; AutosaveAndExit → `saveAutosave()` then `quit_ = true` (exit even if the save failed, showing nothing); Exit → `quit_ = true`. If the SDL fork turns out to deliver joystick events instead (Task 9), add a second `int → MiyooButton` table for joystick buttons. Leave the rest unchanged.
- [ ] **Step 4: Name page (Review Focus 2).** Under `A2_MIYOO`, entering the new-player Name page pre-fills a unique default name (`SPELER`, then `SPELER 2`, `SPELER 3`, … within `ProfileStore::maxNameCharacters`), and Confirm accepts it. Add a test in `tests/profiles_test.cpp` for the helper `std::string a2::defaultPlayerName(const std::vector<std::string> &existing)`: `{}`→`"SPELER"`, `{"SPELER"}`→`"SPELER 2"`, `{"SPELER","SPELER 2"}`→`"SPELER 3"`.
- [ ] **Step 5:** Run `host-test.sh 13`, `host-test.sh 8` and `qemu-test.sh`. Expected: PASS, and the desktop build is unchanged (no `A2_MIYOO` code compiled).
- [ ] **Step 6:** Commit: `feat(miyoo): button mapping, menu/exit combos and button-only player names`.

### Task 7: World resolution scaling in the renderer

**Files:**
- Modify: `src/renderer.hpp`, `src/renderer.cpp`, `tests/renderer_test.cpp`

**Interfaces:**
- Produces on `a2::Renderer`:
  - `void setWorldScale(float scale)`, clamped to `[0.5, 1.0]` and ignored (kept 1.0) while `enhanced()`
  - `float worldScale() const`
  - `int worldWidth() const` / `int worldHeight() const` = `round(640*scale)` / `round(480*scale)`
- Behaviour: `clear`, `background`, `triangle`, `quad`, `mesh` and `shadow` draw into a world buffer of `worldWidth×worldHeight`. `finishWorld()` upscales it bilinearly into the 640×480 `color_` buffer. HUD calls after that (`rect`, `line`, `text`, `blit`, `blitKey`, `sprite`, `dim`) draw at full 640×480 as now. At scale 1.0 no copy happens and output is **byte-identical** to upstream.

- [ ] **Step 1: Write failing tests** in `renderer_test.cpp`:
  - `worldScaleOneIsIdentical`: render the existing depth scene at default and after `setWorldScale(1.0f)`; `pixels()` equal element-wise
  - `worldScaleHalfCoversSameArea`: at `setWorldScale(0.5f)`, the red `screenTriangle` (100,100)-(500,100)-(100,400) still covers pixel (200,200) and leaves (600,450) background after `finishWorld()`; the covered-pixel count is within 2% of the scale-1 count
  - `hudSharpAfterScaledWorld`: at 0.5, `rect(10,10,1,1,green)` after `finishWorld()` sets exactly pixel (10,10) and not (11,10)
  - `scaleClamped`: `setWorldScale(0.1f)` → `worldScale()==0.5f`; with `setEnhanced(true)` → `1.0f`
- [ ] **Step 2:** Run `host-test.sh 13`. Expected: FAIL.
- [ ] **Step 3:** Implement. Projection uses the world size and `focal * (worldWidth/640)`. Rasterisation bands use world height. The upscale is fixed-point bilinear and row-parallel through `parallelRenderRows`. The existing `lowResolution` (320×200) present path stays for desktop; on `A2_MIYOO` the Options display choice maps to world scale instead (Task 8).
- [ ] **Step 4:** Run `host-test.sh 13`, then the existing `graphics` and `headless_game` tests. Expected: PASS, and upstream screenshots unchanged at scale 1.
- [ ] **Step 5:** Commit: `feat(renderer): optional reduced world resolution with full-res HUD`.

### Task 8: Dynamic resolution, perf stats and device runtime defaults

**Files:**
- Create: `src/dynamic_resolution.hpp/.cpp`, `src/perf_stats.hpp/.cpp`, `tests/dynamic_resolution_test.cpp`, `tests/perf_stats_test.cpp`
- Modify: `src/main.cpp`, `src/render_workers.cpp`, `CMakeLists.txt`

**Interfaces:**
- Produces:
  - `class DynamicResolution { public: explicit DynamicResolution(std::vector<float> steps = {1.0f, 0.75f, 0.5f}, double budget = 1.0/60); float update(double frameSeconds); float scale() const; void reset(); };` Initial rule (tunable in Task 11): step down one level after 2 consecutive frames over `budget`; step up one level after 30 consecutive frames under `0.7 * budget`; never below the last step.
  - `struct PerfSummary { int frames; double avgFps, low1Fps, worstMs; };` `class PerfStats { public: void add(double frameSeconds); PerfSummary summary() const; };` where `low1Fps` is the fps of the slowest 1% of frames (mean of the worst `ceil(frames/100)` frame times).
  - `std::string a2::perfCsvLine(int stage, int camera, float scale, double frameMs, long rssKb)`
  - CLI (all builds): `--perf FILE` appends one CSV row per frame (header `stage,camera,scale,frame_ms,rss_kb` when creating the file) and prints the `PerfSummary` on exit; `--world-scale S` fixes the scale (disables dynamic); `--dynamic-resolution on|off`; `--view-distance UNITS` (≤ 2600, applied to `Camera::farPlane`); `--vsync on|off`.
- Device defaults under `A2_MIYOO`: dynamic resolution **on** in races, scale 1.0 in menus and movies, enhanced unavailable (F4/left-shoulder ignored, the Options GRAFISCH choice hides "Verbeterd" and the 640×480/320×200 choices map to world scale 1.0/0.5), fullscreen 640×480, frame cap 60, render workers capped at 2 (`std::min(count, 2u)` in `render_workers.cpp` under `A2_MIYOO`). The default for `--vsync` is decided in Task 9 by latency measurement.

- [ ] **Step 1: Write failing tests**:
  - DynamicResolution: starts at 1.0; one slow frame (0.020) stays 1.0; two → 0.75; two more → 0.5; more slow frames stay 0.5; 29 fast (0.010) frames stay, the 30th → 0.75; a slow frame in the middle resets the fast counter
  - PerfStats: 99 frames of 1/60 plus 1 frame of 0.1 → `avgFps` ≈ 100/(99/60+0.1) within 0.01, `low1Fps == 10`, `worstMs == 100`
  - `perfCsvLine(2,1,0.75f,16.5,40000) == "2,1,0.75,16.50,40000"`
- [ ] **Step 2:** Run `host-test.sh 13`. Expected: FAIL.
- [ ] **Step 3:** Implement the classes, then wire them into the main loop. Time each frame with `SDL_GetPerformanceCounter` (headless: wall clock around simulate+render), call `dyn.update()` in races, then `renderer_.setWorldScale(dyn.scale())` before the next frame. RSS comes from `/proc/self/statm` on Linux, 0 elsewhere.
- [ ] **Step 4:** Add a CMake headless test `perf_csv` on synthetic data: `--demo --frames 120 --perf out.csv`, then the file has 121 lines and the header matches.
- [ ] **Step 5:** Run `host-test.sh 13`, `host-test.sh 8` and `qemu-test.sh`. Expected: PASS.
- [ ] **Step 6:** Commit: `feat: dynamic resolution, perf CSV and Miyoo runtime defaults`.

### Task 9: Device bring-up on synthetic data

Manual, on the owner's Mini Plus. The owner enables Onion's FTP/SSH (or connects USB) and gives the device IP.

**Files:**
- Create: `Packaging/miyoo_mini/deploy.sh`, `Packaging/miyoo_mini/bench.sh`, `docs/miyoo/bringup-notes.md`

**Interfaces:**
- Produces: `deploy.sh <device-ip>` copies `dist/stage/Roms/PORTS/...` (from Task 10's `package.sh --stage-only`; until then the binary and libs into the same folder layout) to `/mnt/SDCARD/Roms/PORTS/Games/OpenA2RacerMini/` over SSH (`scp`), falling back to FTP (`curl -T`). `bench.sh` runs on the device over SSH: for stage 1–6 × camera 0–2, `opena2 --data <data> --headless --demo --stage S --camera C --frames 900 --perf bench.csv`, then prints one summary line per run.

- [ ] **Step 1:** Write `deploy.sh` and `bench.sh`, then deploy a synthetic-data build.
- [ ] **Step 2:** On the device, check: it launches from Ports, the picture fills the screen, sound effects and music play, the intro movie plays and A skips it, every button in the Global Constraints table does its action, Menu returns to Onion, a new player can be created with buttons only, and `autosave.sav` appears after Menu in a race. Record results in `bringup-notes.md`.
- [ ] **Step 3:** Measure input latency for the SDL fork and `--vsync on|off`: film the screen and the A press at 240 fps on a phone, or log event→present timestamps. Pick the fork (XK9274 vs steward-fu `mmiyoo`) and the vsync default with ≤ 2 frames latency and working audio. Record the measurements and decision in `bringup-notes.md`; if switching fork, change `build-deps.sh` and rerun Tasks 3–4.
- [ ] **Step 4:** Commit: `chore(miyoo): device deploy/bench scripts and bring-up notes`.

### Task 10: Onion port package and launcher

**Files:**
- Create: `Packaging/miyoo_mini/package.sh`, `verify-package.sh`, `verify-launch.sh`, `port/launch.sh`, `port/OpenA2RacerMini.port`, `port/INSTALL.txt`, `port/box_art.png`, `README-MIYOO.md`

**Interfaces:**
- Produces: `package.sh [--stage-only] [--debug]` → `dist/OpenA2RacerMini-onion-<version>-<gitshort>.7z` with:
  ```
  Roms/PORTS/Games/OpenA2RacerMini/{opena2, launch.sh, libs/libSDL2-2.0.so.0, data/PUT_A2_RACER_CD_HERE.txt, INSTALL.txt, README.md, licenses/…, source/OpenA2-<ver>-source.zip}
  Roms/PORTS/Imgs/OpenA2RacerMini.png
  Roms/PORTS/Shortcuts/Racing/OpenA2RacerMini.port
  ```
- `.port` follows Onion's standalone template (see `OnionUI/Ports-Collection`, e.g. `openjazz.port`): `GameName="OpenA2RacerMini"`, `GameDir="OpenA2RacerMini"`, `GameExecutable="launch.sh"`, `GameDataFile` set to a file that exists only when data is present (decide after checking `launch_standalone.sh`'s GameDataFile semantics; fall back to `data/.ready`, which launch.sh creates on first successful data detection, if it doesn't support globs), `KillAudioserver=1`, `PerformanceMode=1`, `Arguments=""` (users add options such as `--world-scale 0.75` here), plus the SDL driver exports chosen in Task 9.
- `launch.sh` defines `find_data <dir>`, which prints the data path or exits 2. Accepted shapes, in order: `<dir>/CD/` folder, `<dir>` itself containing the CD files, `<dir>/CD.iso`, the first `<dir>/*.iso` / `*.ISO`. Matching is case-insensitive for the marker file openA2Racer validates (the implementer reads `src/assets.cpp` for the required top-level names). Then: `cd` to the port dir; `mkdir -p logs`; `HOME`/`XDG_*` to the port dir; `LD_LIBRARY_PATH=libs`; if no data, write the reason (what was looked for, where) to `logs/latest.log` and exit 2; run `./opena2 --data "$DATA" --skip-intro-if-seen $Arguments > logs/latest.log 2>&1` (intro plays on the first launch only; add `--skip-intro-if-seen` flag storing a marker in prefs); `sync`; exit with the game's status.

- [ ] **Step 1: Write failing launcher tests** in `verify-launch.sh` (runs in the toolchain container with `sh`, sourcing `launch.sh` functions via `LAUNCH_SH_LIB=1`, which skips the run part):
  - empty `data/` → exit 2 and the log mentions `data/`
  - `data/CD/<marker>` → prints `data/CD`
  - `data/<marker>` directly → prints `data`
  - `data/CD.iso` and `data/a2racer.ISO` → prints that file
  - lowercase `data/cd/<marker-lowercase>` → found (Review Focus 5)
  - partial copy (marker present, a required track file missing): launcher passes it on; `opena2 --validate`-style check at startup makes the game show its error page and exit non-zero, not crash. Assert on the ARM build under qemu with a truncated synthetic data dir (Review Focus 1)
- [ ] **Step 2:** Run `verify-launch.sh`. Expected: FAIL.
- [ ] **Step 3:** Implement `launch.sh`, `.port`, `package.sh` (strip the binary, copy libs, licences, run `tools/package_source.py` for the LGPL source zip, original box art: a simple title card, no Davilex cover art), `INSTALL.txt` and `README-MIYOO.md` (install steps, where data goes, Dutch release only, controls table, `Arguments` options).
- [ ] **Step 4:** `verify-package.sh`: the archive contains exactly the tree above; no file in the archive has an extension from upstream's original-data list (`.PCX .SMK .WAV .MOD .A2R`, plus any `.iso`); the binary passes Task 3's ELF/glibc checks. Run `verify-launch.sh` and `verify-package.sh`. Expected: PASS.
- [ ] **Step 5:** Deploy with `deploy.sh`, run `~Import ports` on the device: the shortcut is hidden without data and appears once data is present.
- [ ] **Step 6:** Commit: `feat(miyoo): Onion port package, launcher and install docs`.

### Task 11: Real-data performance loop

Manual plus code, on the owner's device with their own Dutch A2 Racer data. Starts when the owner has the data. The loop: measure → profile → optimise → measure.

**Files:**
- Modify: renderer/texture/scene code as the profile dictates (`src/renderer.cpp`, `src/texture.cpp`, `src/scene.cpp`); device-only output-changing paths go under `#if A2_MIYOO`
- Create: `docs/miyoo/performance.md` (measurement log)

**Interfaces:**
- Consumes: `bench.sh`, `--perf`, `--world-scale`, `--view-distance`, `--dynamic-resolution`.

- [ ] **Step 1: Baseline.** Run `bench.sh` with `--world-scale 1.0 --dynamic-resolution off`, then `0.75` and `0.5`, across 6 stages × 3 cameras. Record avg fps, 1% low, worst ms and peak RSS in `performance.md`.
- [ ] **Step 2: Real drive.** For each stage, run the non-headless `--demo --race --stage S --perf drive.csv --frames 3600` on the device in each camera (this covers start grid, traffic and police, as the demo drives the full route). Record results the same way.
- [ ] **Step 3: Profile** the worst runs. Build `--debug` with `-pg` or add scoped timers (simulate / world raster / upscale / HUD / present) printed in the perf summary, then rank the hotspots.
- [ ] **Step 4: Optimise** hotspots one at a time. After each change: `host-test.sh 13`, `qemu-test.sh` (simulation and save round trip must still pass), then rerun the affected bench rows and record before/after. Shared-code changes must keep desktop output byte-identical (renderer tests and screenshots). Output-changing device paths (fixed-point, NEON) go behind `A2_MIYOO`.
- [ ] **Step 5: Fallbacks, only if needed and in this order:** tune the DynamicResolution steps/thresholds (a lower step such as 0.4 is allowed), then `--view-distance` below 2600, then distance-culling non-collidable scenery under `A2_MIYOO`. Never change traffic, police or collidable objects.
- [ ] **Step 6: Exit criterion.** With release defaults, every stage × camera run shows no sustained dip below 30 fps (1% low ≥ 30) in `performance.md`, plus peak RSS that leaves Onion headroom (target ≤ 80 MB). If a stage can't meet it, document it as a known issue; that blocks 1.0 but allows a prerelease.
- [ ] **Step 7:** Set the release defaults in `main.cpp`'s `A2_MIYOO` block, then commit per optimisation: `perf(miyoo): <what> (<stage/camera> X→Y fps)`.

### Task 12: Onion extras (nice to have, in order)

Do these only after Task 11 meets its exit criterion. Each one is its own commit, tested on the device and noted in `bringup-notes.md`.

- [ ] Game Switcher resume: on launch from the Game Switcher, load `autosave.sav` straight away (follow MK64's mechanism; read `cacuracaptors/mk64-miyoomini` `port/savestate_miyoo.c` / launch script for how Onion signals it).
- [ ] Save on power-off: handle SIGTERM/SIGUSR from Onion's shutdown with `saveAutosave()` then exit.
- [ ] Low-battery warning: read the battery level the way MK64's `port/battery_miyoo.c` does and show the in-game message line.

### Task 13: CI and release preparation

**Files:**
- Create: `.github/workflows/miyoo.yml`, `docs/miyoo/release-checklist.md`, `docs/miyoo/ports-json-entry.json`

- [ ] **Step 1:** Workflow on push and tag `v*`: `host-test.sh 13`, `host-test.sh 8`, `build.sh`, `qemu-test.sh`, `package.sh`, `verify-package.sh`, `verify-launch.sh`, then upload the 7z as an artifact. On a tag, create a **draft** release with the 7z attached (the owner publishes).
- [ ] **Step 2:** Push to a branch of the owner's fork (the owner creates the GitHub repo `OpenA2RacerMini`) and confirm the workflow is green.
- [ ] **Step 2b: Mini Flip check.** Before Task 9, confirm the Flip's screen resolution, button keycodes and lid/sleep behaviour from Onion's source (`OnionUI/Onion`, device detection and keymap files) and record any differences in `bringup-notes.md`; add runtime handling if needed. For the release, find a volunteer Flip tester (catalog/Discord). Release notes say "Mini Flip: expected to work, untested" until one reports back.
- [ ] **Step 3: Release checklist.** Fresh SD card install from the archive using only `README-MIYOO.md`, play stage 1 to the finish, Menu-exit, relaunch, load the autosave, quit. Record the result.
- [ ] **Step 4:** Write `ports-json-entry.json` matching MiyooMini-Ports `ports.schema.json` (category Racing, assets "Owned data", status Prerelease until Task 11's criterion holds on every stage, then Playable; porter = owner) and hand it to the owner with the PR text.
- [ ] **Step 5:** Commit: `ci: build, test and package the Miyoo port; release prep`.
