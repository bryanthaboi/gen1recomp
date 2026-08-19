# - Find SndIO includes and libraries
#
#   SNDIO_FOUND        - True if SNDIO_INCLUDE_DIR & SNDIO_LIBRARY are found
#   SNDIO_LIBRARIES    - Set when SNDIO_LIBRARY is found
#   SNDIO_INCLUDE_DIRS - Set when SNDIO_INCLUDE_DIR is found
#
#   SNDIO_INCLUDE_DIR - where to find sndio.h, etc.
#   SNDIO_LIBRARY     - the sndio library
#

find_path(SNDIO_INCLUDE_DIR
          NAMES sndio.h
          DOC "The SndIO include directory"
)

find_library(SNDIO_LIBRARY
             NAMES sndio
             DOC "The SndIO library"
)

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(SndIO
    REQUIRED_VARS SNDIO_LIBRARY SNDIO_INCLUDE_DIR
)

if(SNDIO_FOUND)
    set(SNDIO_LIBRARIES ${SNDIO_LIBRARY})
    set(SNDIO_INCLUDE_DIRS ${SNDIO_INCLUDE_DIR})
endif()

mark_as_advanced(SNDIO_INCLUDE_DIR SNDIO_LIBRARY)
