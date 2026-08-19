OpenAL Soft
===========

`master` branch CI status : [![GitHub Actions Status](https://github.com/kcat/openal-soft/actions/workflows/ci.yml/badge.svg)](https://github.com/kcat/openal-soft/actions) [![Windows Build Status](https://ci.appveyor.com/api/projects/status/github/kcat/openal-soft?branch=master&svg=true)](https://ci.appveyor.com/api/projects/status/github/kcat/openal-soft?branch=master&svg=true)

OpenAL Soft is an LGPL-licensed, cross-platform, software implementation of the OpenAL 3D audio API. It's forked from the open-sourced Windows version available originally from openal.org's SVN repository (now defunct).
OpenAL provides capabilities for playing audio in a virtual 3D environment. Distance attenuation, doppler shift, and directional sound emitters are among the features handled by the API. More advanced effects, including air absorption, occlusion, and environmental reverb, are available through the EFX extension. It also facilitates streaming audio, multi-channel buffers, and audio capture.

More information is available on the [official website](http://openal-soft.org/).

Source Install
-------------
To install OpenAL Soft, use your favorite shell to go into the build/
directory, and run:

```bash
cmake ..
```

Alternatively, you can use any available CMake front-end, like cmake-gui,
ccmake, or your preferred IDE's CMake project parser.

Assuming configuration went well, you can then build it. The command
`cmake --build .` will instruct CMake to build the project with the toolchain
chosen during configuration (often GNU Make or NMake, although others are
possible).

Please Note: Double check that the appropriate backends were detected. Often,
complaints of no sound, crashing, and missing devices can be solved by making
sure the correct backends are being used. CMake's output will identify which
backends were enabled.

For most systems, you will likely want to make sure PipeWire, PulseAudio, and
ALSA were detected (if your target system uses them). For Windows, make sure
WASAPI was detected.


Building openal-soft - Using vcpkg
----------------------------------

You can download and install openal-soft using the [vcpkg](https://github.com/Microsoft/vcpkg) dependency manager:

    git clone https://github.com/Microsoft/vcpkg.git
    cd vcpkg
    ./bootstrap-vcpkg.sh
    ./vcpkg integrate install
    ./vcpkg install openal-soft

The openal-soft port in vcpkg is kept up to date by Microsoft team members and community contributors. If the version is out of date, please [create an issue or pull request](https://github.com/Microsoft/vcpkg) on the vcpkg repository.

Utilities
---------
The source package comes with an informational utility, openal-info, and is
built by default. It prints out information provided by the ALC and AL sub-
systems, including discovered devices, version information, and extensions.


Configuration
-------------

OpenAL Soft can be configured on a per-user and per-system basis. This allows
users and sysadmins to control information provided to applications, as well
as application-agnostic behavior of the library. See alsoftrc.sample for
available settings.


Language Bindings
-----------------

As a C API, OpenAL Soft can be used directly by any language that can use
functions with C linkage. For languages that can't directly use C-style
headers, bindings may be developed to allow code written in that language to
call into the library. Some bindings for some languages are listed here.

C# Bindings:
* [OpenTK](https://opentk.net/) includes low-level C# bindings for the OpenAL
API, including some extensions. It also includes utility libraries for math and
linear algebra, which can be useful for 3D calculations.

Java Bindings:
* [JOAL](https://jogamp.org/joal/www/), part of the JogAmp project, includes
Java bindings for the OpenAL API, usable with OpenAL Soft. It also includes a
higher level Sound3D Toolkit API and utility functions to make easier use of
OpenAL features and capabilities.

Python Bindings:
* [PyOpenAL](https://pypi.org/project/PyOpenAL/). Also includes methods to play
wave files and, with PyOgg, also Vorbis, Opus, and FLAC.

FreePascal/Lazarus Bindings:
* [ALSound](https://github.com/Lulu04/ALSound). Also includes a higher level
API and libsndfile support to simplify loading and playing sounds.

Other bindings for these and other languages also exist. This list will grow as
more bindings are found.


Acknowledgements
----------------

Special thanks go to:

 - Creative Labs for the original source code this is based off of.
 - Christopher Fitzgerald for the current reverb effect implementation, and
helping with the low-pass and HRTF filters.
 - Christian Borss for the 3D panning code previous versions used as a base.
 - Ben Davis for the idea behind a previous version of the click-removal code.
 - Richard Furse for helping with my understanding of Ambisonics that is used by
the various parts of the library.
