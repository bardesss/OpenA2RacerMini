# Cross toolchain for Miyoo Mini Plus / Mini Flip (SSD202D, Cortex-A7).
# Used inside the opena2mini-toolchain image by build.sh; the compiler and
# sysroot paths only exist in that container. Structure follows
# OpenRCT2mini's Packaging/miyoo_mini/toolchainfile.cmake.
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR arm)

set(A2_TRIPLE arm-linux-gnueabihf)
set(CMAKE_C_COMPILER ${A2_TRIPLE}-gcc)
set(CMAKE_CXX_COMPILER ${A2_TRIPLE}-g++)
set(CMAKE_AR ${A2_TRIPLE}-ar CACHE FILEPATH "")
set(CMAKE_RANLIB ${A2_TRIPLE}-ranlib CACHE FILEPATH "")
set(CMAKE_STRIP ${A2_TRIPLE}-strip CACHE FILEPATH "")

execute_process(
  COMMAND ${CMAKE_C_COMPILER} -print-sysroot
  OUTPUT_VARIABLE A2_SYSROOT
  OUTPUT_STRIP_TRAILING_WHITESPACE)
set(CMAKE_SYSROOT "${A2_SYSROOT}")
set(CMAKE_FIND_ROOT_PATH "${A2_SYSROOT}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# Imported include dirs as -I, not -isystem: -isystem on the sysroot's
# /usr/include breaks libstdc++'s #include_next <stdlib.h>.
set(CMAKE_NO_SYSTEM_FROM_IMPORTED TRUE)

set(A2_DEVICE_FLAGS "-marm -mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard")
set(CMAKE_C_FLAGS_INIT "${A2_DEVICE_FLAGS}")
set(CMAKE_CXX_FLAGS_INIT "${A2_DEVICE_FLAGS}")
# One binary without a libstdc++ dependency; SDL2 comes from ./libs next to it.
set(CMAKE_EXE_LINKER_FLAGS_INIT "-static-libstdc++ -static-libgcc -Wl,--gc-sections")
# RUNPATH $ORIGIN/libs (what -Wl,-rpath,'$ORIGIN/libs' gives), set through
# CMake so the $ is escaped correctly for every generator, and no sysroot
# path leaks into the binary.
set(CMAKE_BUILD_WITH_INSTALL_RPATH ON)
set(CMAKE_INSTALL_RPATH "$ORIGIN/libs")

# ARM test binaries run on the x86 host through qemu (ctest, add_test).
set(CMAKE_CROSSCOMPILING_EMULATOR "qemu-arm-static;-L;${A2_SYSROOT}")

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()
