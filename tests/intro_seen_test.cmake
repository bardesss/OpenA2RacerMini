# --skip-intro-if-seen: the first launch plays the intro and leaves a marker in
# the preferences directory; the second launch skips the intro.
# Runs the windowed game under SDL's dummy video/audio drivers (no display),
# because --headless always starts a race and never reaches the intro.
# Usage: cmake -DOPENA2=<exe> -DDATA=<dir> -DPREFS=<dir> -P intro_seen_test.cmake
file(REMOVE_RECURSE "${PREFS}")
file(MAKE_DIRECTORY "${PREFS}")
set(ENV{SDL_VIDEODRIVER} dummy)
set(ENV{SDL_AUDIODRIVER} dummy)

foreach(run IN ITEMS first second)
  execute_process(
    COMMAND "${OPENA2}" --data "${DATA}" --prefs "${PREFS}" --frames 5 --skip-intro-if-seen
    RESULT_VARIABLE result OUTPUT_VARIABLE out ERROR_VARIABLE err)
  message(STATUS "${run} run: ${result}\n${out}${err}")
  if(NOT result EQUAL 0)
    message(FATAL_ERROR "The ${run} run failed")
  endif()
  set(out_${run} "${out}")
endforeach()

if(NOT out_first MATCHES "Intro: first launch")
  message(FATAL_ERROR "The first launch must play the intro")
endif()
if(NOT EXISTS "${PREFS}/intro-seen")
  message(FATAL_ERROR "The first launch must write the intro-seen marker")
endif()
if(NOT out_second MATCHES "Intro: already seen, skipped")
  message(FATAL_ERROR "The second launch must skip the intro")
endif()

# Without the flag the marker is ignored: upstream behaviour, nothing printed.
execute_process(
  COMMAND "${OPENA2}" --data "${DATA}" --prefs "${PREFS}" --frames 5
  RESULT_VARIABLE result OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT result EQUAL 0 OR out MATCHES "Intro:")
  message(FATAL_ERROR "Without --skip-intro-if-seen the run must be unchanged\n${out}${err}")
endif()
