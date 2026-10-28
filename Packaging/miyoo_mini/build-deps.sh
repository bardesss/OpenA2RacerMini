#!/usr/bin/env bash
# Build the Miyoo SDL2 fork (mmiyoo / MI_GFX video, MI_AO audio) as a shared
# library into the cross sysroot. Runs inside the toolchain image build.
#
# Source: XK9274's sdl2_miyoo, the fork OpenRCT2mini ships. XK9274's GitHub
# account no longer exists (checked 2026-10-26), so the pinned commit is
# fetched from a mirror fork that still carries it. The commit is the last
# one with the sdl2/ subdirectory layout (main before the 2026-08 flattening,
# whose newer code needs XK9274's now-deleted neon helper library):
#   bf1aba2de04ed8c3401cf45919e0ae63e58d2cec  (2025-09-23)
# Any fork in the steward-fu/sdl2 network serves it; the URLs below are tried
# in order. Only sdl2/ (SDL itself) and mmiyoo/ (SigmaStar headers and the
# stub libs the fork links against) are checked out; swiftshader/ is skipped.
# This runs on CI (GitHub Actions) only: see ruling R13, no local pull.
#
# Patches (same as OpenRCT2mini's build-deps.sh, minus its input remaps,
# which OpenA2RacerMini does not want: it reads the stock evdev keys):
#  - drop the unused SDL_ttf/SDL_image/SDL_mixer/SDL2_gfx includes
#  - link MI_SYS/MI_GFX instead of SwiftShader's EGL/GLESv2, and replace the
#    EGL context wrapper with a no-op stub (no GL is used)
#  - export HOST=arm-linux so configure takes the MI_AO audio branch
#  - fix the [2]/[1] texture-format designator typo in the render driver
#  - SDL_revision.h stub
# OpenA2RacerMini's own patches (found on the Mini Plus):
#  - render: always blit synchronously in RenderCopy. The fork's threaded
#    path keeps only a pointer to the caller's pixels (UpdateTexture does not
#    copy) and blits them later from a thread, while the game already draws
#    the next frame into the same buffer: the screen flickers.
#  - render: skip the MI_GFX blit and flip unless the mmiyoo video driver
#    runs. The mmiyoo renderer is the fork's only one, so SDL uses it under
#    the dummy driver too (qemu tests), where the now synchronous blit would
#    crash in the MI_GFX ioctls.
#  - audio: the MI_AO driver always plays 16-bit samples but leaves the
#    requested format in the spec; set S16 so SDL converts (the game asks
#    for float32, which came out as silence).
# Unlike OpenRCT2mini the dummy video/audio drivers stay enabled: SDL only
# picks them when SDL_VIDEODRIVER/SDL_AUDIODRIVER=dummy is set, and the
# qemu tests need them.
set -euo pipefail

SDL2_COMMIT=bf1aba2de04ed8c3401cf45919e0ae63e58d2cec
SDL2_REMOTES=(
  https://github.com/Producdevity/sdl2_miyoo.git
  https://github.com/tailtwo/sdl2_miyoo.git
  https://github.com/steward-fu/sdl2.git
)
HOST_TRIPLE=arm-linux-gnueabihf
SYSROOT="$("$HOST_TRIPLE-gcc" -print-sysroot)"
PREFIX="$SYSROOT/usr"
WORK=/tmp/build-deps
NPROC="$(nproc)"
echo "== sysroot: $SYSROOT =="

rm -rf "$WORK"
mkdir -p "$WORK/sdl2_miyoo"
cd "$WORK/sdl2_miyoo"
git init -q
fetched=0
for remote in "${SDL2_REMOTES[@]}"; do
  echo "== fetching $SDL2_COMMIT from $remote =="
  # Full depth-1 fetch (swiftshader/ included, CI bandwidth): buster's git 2.20
  # only allows --filter on a configured partial-clone remote.
  if timeout 1800 git fetch -q --depth 1 "$remote" "$SDL2_COMMIT"; then
    fetched=1
    break
  fi
done
[ "$fetched" = 1 ] || { echo "could not fetch SDL2 commit $SDL2_COMMIT" >&2; exit 1; }
# Buster's git (2.20) predates `git sparse-checkout`; use the config switch.
git config core.sparseCheckout true
printf '/sdl2/\n/mmiyoo/\n' > .git/info/sparse-checkout
git -c advice.detachedHead=false checkout -q FETCH_HEAD
[ "$(git rev-parse HEAD)" = "$SDL2_COMMIT" ] || { echo "checked out the wrong commit" >&2; exit 1; }
test -f sdl2/src/video/mmiyoo/SDL_video_mmiyoo.h
test -d mmiyoo/inc && test -d mmiyoo/lib

cd sdl2
echo "== patching =="
for f in src/video/mmiyoo/SDL_video_mmiyoo.h src/video/mmiyoo/SDL_video_mmiyoo.c \
  src/render/mmiyoo/SDL_render_mmiyoo.c; do
  [ -f "$f" ] || continue
  sed -i \
    -e 's|^#include "SDL_ttf.h"|#include "SDL_render.h" /* SDL_ttf.h removed: unused */|' \
    -e 's|^#include "SDL_image.h"|/* SDL_image.h removed: unused */|' \
    -e 's|^#include "SDL_mixer.h"|/* SDL_mixer.h removed: unused */|' \
    -e 's|^#include "SDL2_gfxPrimitives.h"|/* SDL2_gfx removed: unused */|' \
    -e 's|^#include "SDL2_rotozoom.h"|/* SDL2_rotozoom removed: unused */|' \
    "$f"
done
grep -q -- '-L\. -lEGL -lGLESv2' configure.ac
sed -i 's|-L\. -lEGL -lGLESv2|-L../mmiyoo/lib -lmi_sys -lmi_gfx -lmi_common|' configure.ac
if grep -q '\[2\] *= *SDL_PIXELFORMAT_ARGB8888' src/render/mmiyoo/SDL_render_mmiyoo.c; then
  sed -i 's|\[2\] *= *SDL_PIXELFORMAT_ARGB8888|[1] = SDL_PIXELFORMAT_ARGB8888|' \
    src/render/mmiyoo/SDL_render_mmiyoo.c
fi
cat > src/video/mmiyoo/SDL_opengles_mmiyoo.c <<'EOF'
/* OpenA2RacerMini: no-op replacement for the SwiftShader EGL wrapper (the
   game renders in software and ships no libEGL/libGLESv2). */
#include "../../SDL_internal.h"
#if SDL_VIDEO_DRIVER_MMIYOO
#include "SDL_video_mmiyoo.h"
#include "SDL_opengles_mmiyoo.h"

int glLoadLibrary(_THIS, const char *name) { return 0; }
void *glGetProcAddress(_THIS, const char *proc) { return NULL; }
void glUnloadLibrary(_THIS) {}
SDL_GLContext glCreateContext(_THIS, SDL_Window *window) { return NULL; }
int glSetSwapInterval(_THIS, int interval) { return 0; }
int glUpdateBufferSettings(void *pFunc, void *fb_idx, void *fb_vaddr) { return 0; }
int glSwapWindow(_THIS, SDL_Window *window) { return 0; }
int glMakeCurrent(_THIS, SDL_Window *window, SDL_GLContext context) { return 0; }
void glDeleteContext(_THIS, SDL_GLContext context) {}
#endif
EOF
grep -q 'if ((evt.mode == MMIYOO_MOUSE_MODE) || (srcrect->w == 800)) {' \
  src/render/mmiyoo/SDL_render_mmiyoo.c
sed -i 's|if ((evt.mode == MMIYOO_MOUSE_MODE) \|\| (srcrect->w == 800)) {|if (1 /* OpenA2RacerMini: synchronous blit */) {|' \
  src/render/mmiyoo/SDL_render_mmiyoo.c
grep -q 'OpenA2RacerMini: synchronous blit' src/render/mmiyoo/SDL_render_mmiyoo.c
grep -q '^    GFX_Copy(pixels, src, dst, pitch, 0, E_MI_GFX_ROTATE_180);$' \
  src/render/mmiyoo/SDL_render_mmiyoo.c
grep -q '^        GFX_Flip();$' src/render/mmiyoo/SDL_render_mmiyoo.c
sed -i \
  -e 's|^    GFX_Copy(pixels, src, dst, pitch, 0, E_MI_GFX_ROTATE_180);$|    if (oa2_mi_gfx()) /* OpenA2RacerMini: MI_GFX only */\n    &|' \
  -e 's|^        GFX_Flip();$|        if (oa2_mi_gfx())\n    &|' \
  -e 's|^int My_QueueCopy(SDL_Texture \*texture, const void \*pixels, const SDL_Rect \*srcrect, const SDL_FRect \*dstrect)$|/* OpenA2RacerMini: true when the mmiyoo video driver runs (not dummy). */\nstatic int oa2_mi_gfx(void)\n{\n    const char *driver = SDL_GetCurrentVideoDriver();\n    return driver \&\& (SDL_strcmp(driver, MMIYOO_DRIVER_NAME) == 0);\n}\n\n&|' \
  src/render/mmiyoo/SDL_render_mmiyoo.c
[ "$(grep -c 'oa2_mi_gfx' src/render/mmiyoo/SDL_render_mmiyoo.c)" = 3 ]
grep -q '    SDL_zerop(this->hidden);' src/audio/mmiyoo/SDL_audio_mmiyoo.c
sed -i 's|^    SDL_zerop(this->hidden);$|    SDL_zerop(this->hidden);\n    this->spec.format = AUDIO_S16SYS; /* OpenA2RacerMini: MI_AO plays S16 */\n    SDL_CalculateAudioSpec(\&this->spec);|' \
  src/audio/mmiyoo/SDL_audio_mmiyoo.c
grep -q 'OpenA2RacerMini: MI_AO plays S16' src/audio/mmiyoo/SDL_audio_mmiyoo.c
cat > include/SDL_revision.h <<EOF
#define SDL_REVISION "sdl2_miyoo-${SDL2_COMMIT}"
#define SDL_REVISION_NUMBER 0
EOF

echo "== configure =="
export CC="$HOST_TRIPLE-gcc" CXX="$HOST_TRIPLE-g++" AR="$HOST_TRIPLE-ar" RANLIB="$HOST_TRIPLE-ranlib"
export CFLAGS="-O2 -marm -mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard"
export MOD=mmiyoo
# configure.ac gates the MI_AO audio libs on this literal shell variable.
export HOST=arm-linux
./autogen.sh
./configure \
  --host="$HOST_TRIPLE" --prefix="$PREFIX" \
  --disable-static --enable-shared --disable-rpath \
  --disable-joystick-virtual --disable-jack --disable-alsa --disable-sensor \
  --disable-video-wayland --disable-video-vulkan --disable-power --disable-fcitx \
  --disable-hidapi --disable-sndio --disable-libudev --disable-diskaudio \
  --disable-video-x11 --disable-pulseaudio --disable-video-opengles2 \
  --disable-video-opengles --disable-ime --disable-video-kmsdrm --disable-oss \
  --disable-video-opengl --disable-dbus
make -j"$NPROC"
make install
if [ ! -e "$PREFIX/lib/libSDL2.so" ] && [ -e "$PREFIX/lib/libSDL2-2.0.so.0" ]; then
  ln -sf libSDL2-2.0.so.0 "$PREFIX/lib/libSDL2.so"
fi
test -e "$PREFIX/lib/libSDL2-2.0.so.0"
# The device provides the MI libraries (and libshmvar) in /customer/lib. If
# the sysroot lacks one that libSDL2 needs, put the fork's copy there, so the
# game links (ld checks a shared library's dependencies) and loads under
# qemu. The release archive ships only libSDL2 (package.sh).
"$HOST_TRIPLE-readelf" -d "$PREFIX/lib/libSDL2-2.0.so.0" | grep NEEDED
for lib in $("$HOST_TRIPLE-readelf" -d "$PREFIX/lib/libSDL2-2.0.so.0" |
  sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p'); do
  if [ ! -e "$PREFIX/lib/$lib" ] && [ ! -e "$SYSROOT/lib/$lib" ] && [ -e "../mmiyoo/lib/$lib" ]; then
    echo "== $lib not in the sysroot: installing the fork's copy (build/qemu only) =="
    install -m 755 "../mmiyoo/lib/$lib" "$PREFIX/lib/$lib"
  fi
done
ls "$PREFIX"/lib/cmake/SDL2/*onfig.cmake

# Licence and provenance for the release archive (package.sh).
mkdir -p "$PREFIX/share/licenses/SDL2"
cp LICENSE.txt "$PREFIX/share/licenses/SDL2/LICENSE.txt"
printf 'sdl2_miyoo (XK9274 fork of steward-fu/sdl2) commit %s\n' "$SDL2_COMMIT" \
  > "$PREFIX/share/licenses/SDL2/SOURCE.txt"

rm -rf "$WORK"
echo "== SDL2 installed in $PREFIX =="
