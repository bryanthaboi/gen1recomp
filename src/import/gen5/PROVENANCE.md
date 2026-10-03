Nds.lua, Narc.lua, Lz.lua, Graphics.lua, Cells.lua, Animation.lua and Composer.lua adapt container, decoding and rasterization algorithms from AnimaEngine v1.0.0, copyright (c) 2026 AnimaEngine contributors, under its MIT license. The complete permission notice is preserved in ANIMAENGINE_LICENSE.

Pinned reference: https://github.com/KillDaWill/AnimaEngine/tree/v1.0.0
Release commit prefix: 70547df. Locally inspected C source digests and URLs are recorded in the task-private native-reference/provenance.json.

Relevant files: source/nanr.c, nmcr.c, nmar.c, sprite_composer.c, ncgr.c, nclr.c, ncer.c and include/nanr.h. No GUI, screenshots, ROM data, extracted assets or reference pixels are included here. The adapted Lua modules use no third-party native runtime.

Differences from the reference: strict byte/section/resource validation; unknown NMAR section heuristics are rejected; rasterization uses bounded sparse indexed buffers; rendering targets LÖVE ImageData. Symmetric nearest-neighbor rounding matches the reference for both positive and negative coordinates. Timeline periods account for ping-pong playback and loop prefixes instead of assuming summed forward durations. Optional cycleTicks reports a cap explicitly. It does not claim every combined loop is complete when capped. Source keys/indices remain zero-based; Lua arrays are one-based.

Reference metadata's coordinate-offset adjustment hook is intentionally inert because source NMCR placement and NANR transformations already incorporate those offsets. Native import coverage and real-pixel parity require separate verification; passing synthetic tests alone does not prove Quest behavior.
