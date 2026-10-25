# Headless autosave round trip on synthetic data (Review Focus 3 and 4).
# Usage: cmake -DOPENA2=<exe> -DDATA=<dir> -DPREFS=<dir> -DMODE=<mode> -P autosave_test.cmake
#   on_exit      autosave when --frames ends, then --load-autosave
#   paused       the same, paused at frame 200
#   fine         the same, at a frame where the demo car is being fined (FRAMES)
#   write_error  the autosave cannot be written: error, old autosave kept, exit
if(NOT FRAMES)
  set(FRAMES 300)
endif()
file(REMOVE_RECURSE "${PREFS}")
file(MAKE_DIRECTORY "${PREFS}")
set(extra)
if(MODE STREQUAL "paused")
  set(extra --pause-at 200)
elseif(MODE STREQUAL "write_error")
  # A non-empty directory where the temporary file must go: the write fails
  # even for root, like a full or read-only SD card.
  file(WRITE "${PREFS}/autosave.sav" "previous autosave\n")
  file(WRITE "${PREFS}/autosave.sav.tmp/blocker" "x")
endif()

execute_process(
  COMMAND "${OPENA2}" --data "${DATA}" --headless --demo --frames ${FRAMES} --autosave-on-exit
          --prefs "${PREFS}" ${extra}
  RESULT_VARIABLE result OUTPUT_VARIABLE out ERROR_VARIABLE err)
message(STATUS "save run: ${result}\n${out}${err}")

if(MODE STREQUAL "write_error")
  if(result EQUAL 0)
    message(FATAL_ERROR "A failed autosave must be reported in the exit status")
  endif()
  if(NOT err MATCHES "SAVE ERROR")
    message(FATAL_ERROR "A failed autosave must print an error")
  endif()
  file(READ "${PREFS}/autosave.sav" previous)
  if(NOT previous STREQUAL "previous autosave\n")
    message(FATAL_ERROR "A failed autosave must leave the previous autosave intact")
  endif()
  return()
endif()

if(NOT result EQUAL 0)
  message(FATAL_ERROR "Autosave run failed")
endif()
if(NOT EXISTS "${PREFS}/autosave.sav")
  message(FATAL_ERROR "autosave.sav was not written")
endif()
if(EXISTS "${PREFS}/slot0.sav" OR EXISTS "${PREFS}/autosave.sav.tmp")
  message(FATAL_ERROR "Autosave touched the quick-save slot or left a temporary file")
endif()
if(MODE STREQUAL "paused" AND NOT out MATCHES "paused 1")
  message(FATAL_ERROR "Expected the autosave to be written while paused")
endif()
if(MODE STREQUAL "fine" AND NOT out MATCHES "fine (0\\.[0-9]+|1)\\)")
  message(FATAL_ERROR "Expected the autosave to be written during a fine")
endif()

execute_process(
  COMMAND "${OPENA2}" --data "${DATA}" --headless --load-autosave --frames 60 --prefs "${PREFS}"
  RESULT_VARIABLE result OUTPUT_VARIABLE out ERROR_VARIABLE err)
message(STATUS "load run: ${result}\n${out}${err}")
if(NOT result EQUAL 0 OR NOT out MATCHES "Autosave loaded")
  message(FATAL_ERROR "The autosave did not load back")
endif()
if(EXISTS "${PREFS}/slot0.sav")
  message(FATAL_ERROR "Loading the autosave wrote the quick-save slot")
endif()
