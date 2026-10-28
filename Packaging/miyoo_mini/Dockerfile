# OpenA2RacerMini cross toolchain: the Onion toolchain image (GCC 8.3,
# glibc 2.28, SigmaStar SDK sysroot) plus a recent CMake, Ninja, qemu-user,
# and the Miyoo SDL2 fork built into the sysroot by build-deps.sh.
#
# Built by build.sh (tag opena2mini-toolchain:latest) or by CI with a layer
# cache. The image is labelled with a hash of this file and build-deps.sh;
# build.sh rebuilds when the label no longer matches.
# Pinned by digest (the :latest of 2026-10-27) so builds are reproducible;
# Dependabot proposes new digests.
FROM ghcr.io/onionui/miyoomini-toolchain:latest@sha256:5d6d1d1b3b2d5c095edacc8b790874a3f57a5369e0463e2bee2a293a9fbccc67

# Buster is end of life: its apt sources live on archive.debian.org.
RUN set -eux; \
    if [ -f /etc/apt/sources.list ]; then \
      sed -i 's|deb.debian.org|archive.debian.org|g; s|security.debian.org|archive.debian.org|g; /buster-updates/d' \
        /etc/apt/sources.list; \
    fi; \
    echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid-until; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      autoconf automake libtool pkg-config file ca-certificates curl git \
      ninja-build p7zip-full python3 qemu-user-static xz-utils; \
    rm -rf /var/lib/apt/lists/*

# Buster's CMake is 3.13; the project needs >= 3.24.
ARG CMAKE_VER=3.30.5
ARG CMAKE_SHA256=f747d9b23e1a252a8beafb4ed2bc2ddf78cff7f04a8e4de19f4ff88e9b51dc9d
RUN set -eux; \
    curl -fL --retry 5 --max-time 600 -o /tmp/cmake.tgz \
      "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VER}/cmake-${CMAKE_VER}-linux-x86_64.tar.gz"; \
    echo "${CMAKE_SHA256}  /tmp/cmake.tgz" | sha256sum -c -; \
    mkdir -p /opt/cmake; \
    tar xzf /tmp/cmake.tgz --strip-components=1 -C /opt/cmake; \
    rm /tmp/cmake.tgz; \
    ln -sf /opt/cmake/bin/cmake /opt/cmake/bin/ctest /opt/cmake/bin/cpack /usr/local/bin/; \
    cmake --version

# The upstream image only sets PATH in /root/.bashrc; bake it into ENV so
# non-login shells and other users (docker run --user) find the compiler.
ENV PATH=/opt/miyoomini-toolchain/usr/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

COPY build-deps.sh /opt/opena2mini/build-deps.sh
RUN bash /opt/opena2mini/build-deps.sh

WORKDIR /src
