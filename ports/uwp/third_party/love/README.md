# LÖVE UWP binaries

These x64 UWP Release binaries were built from [`caorthann-celt/love-xbox-uwp`](https://github.com/caorthann-celt/love-xbox-uwp) at commit `3f51bf0be5f3f86e5934da3893caba2b817f82c1`.

The build uses LÖVE 11.5, LuaJIT, SDL2, and ANGLE. Keep the DLLs and import libraries together; they are one binary interface.

The normal package build consumes these files directly. Rebuilding the backend is a separate dependency maintenance task.
