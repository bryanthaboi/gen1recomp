# - Find PulseAudio includes and libraries
#
#   PULSEAUDIO_FOUND        - True if PULSEAUDIO_INCLUDE_DIR &
#                             PULSEAUDIO_LIBRARY are found
#
#   PULSEAUDIO_INCLUDE_DIR - where to find pulse/pulseaudio.h, etc.
#   PULSEAUDIO_LIBRARY     - the pulse library
#   PULSEAUDIO_VERSION_STRING - the version of PulseAudio found
#

find_path(PULSEAUDIO_INCLUDE_DIR
          NAMES pulse/pulseaudio.h
          DOC "The PulseAudio include directory"
)

find_library(PULSEAUDIO_LIBRARY
             NAMES pulse
             DOC "The PulseAudio library"
)

if(PULSEAUDIO_INCLUDE_DIR AND EXISTS "${PULSEAUDIO_INCLUDE_DIR}/pulse/version.h")
    file(STRINGS "${PULSEAUDIO_INCLUDE_DIR}/pulse/version.h" pulse_version_str
         REGEX "^#define[\t ]+pa_get_headers_version\\(\\)[\t ]+\\(\".*\"\\)")

    string(REGEX REPLACE "^.*pa_get_headers_version\\(\\)[\t ]+\\(\"([^\"]*)\"\\).*$" "\\1"
           PULSEAUDIO_VERSION_STRING "${pulse_version_str}")
    unset(pulse_version_str)
endif()

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(PulseAudio
    REQUIRED_VARS PULSEAUDIO_LIBRARY PULSEAUDIO_INCLUDE_DIR
    VERSION_VAR PULSEAUDIO_VERSION_STRING
)
