# ShaderFX: runtime slang shader presets

ShaderFX plays real libretro `.slangp` shader presets over the finished frame.
It replaced `src/render/GBCFX.lua`, a hand-ported fixed four-level effect, with
a picker: any preset the player drops in a folder, or any preset pulled from
the RetroArch buildbot, can be selected and run. Engine:
`src/render/ShaderFX.lua` (discovery, download, translation call, pass-graph
runtime, render entry point), `src/render/ShaderFixup.lua` (GLSL rewrites),
`src/render/ShaderSourcePatches.lua` (pre-translation source patches),
`src/core/Sensors.lua` (accelerometer and gyroscope), `src/ui/ShaderFXScreen.lua`
(the picker), `src/ui/ShaderFXParamsScreen.lua` (per-preset parameter editor),
`tools/shaderfx-bridge/` (the Rust translator). Call sites:
`src/render/Renderer.lua` (Gen 1) and `src/core/Game2.lua` (Gen 2), both at the
end of the frame. Drivers: `tests/drivers/gold_shaderfx_zoom_sizing_test.lua`,
`tests/drivers/gold_shaderfx_menu_black_crop_test.lua`.

This is first-party engine code, not a mod. It calls the native translator
directly through `ffi.load`, with no `Sandbox.lua`, no `native` permission
declaration, and no mod boundary. Mods do not get that, and the distinction is
deliberate: the upstream maintainer will not accept `native` in mods.

## What a player sees

**OPTIONS** carries two rows, `SHADER FX` and `SHADER FX 2`. Each opens the
same pushed list screen (`ShaderFXScreen`) on a different slot. The list is
`OFF`, then every `.slangp` found on disk, then a permanent `DOWNLOAD SHADERS`
action row at the bottom.

A preset that has never been translated draws muted with a `CONVERT` hint on
the right. `A` on that row translates it in place and stays open: converting is
a preparation step, not a selection. `A` on a converted row activates it,
persists the choice, and closes. `SELECT` on a converted row opens
`ShaderFXParamsScreen`, which lists every `#pragma parameter` the preset
declares and lets the player step each one (`A` wraps, Left/Right clamp,
`SELECT` resets one row, `START` resets all behind a confirm).

Presets live in a plain OS folder, `shaders/` under the portable base directory
when running portable (`SaveData.portableBaseDir()`, the SD-card convention the
Anbernic pack uses, see `docs/anbernic-rg34xxsp.md`) and otherwise under LOVE's
save directory. `ShaderFX.list()` scans it recursively, so a shader pack keeps
whatever nested layout it shipped with. These are real filesystem paths rather
than `love.filesystem` virtual paths on purpose: the native translator does
plain `std::fs` reads and knows nothing about LOVE's mounts, and neither do the
LUT loads.

Persisted state, all in `save.options`:

| Key | Meaning |
| --- | --- |
| `shaderfx` | main slot's preset name, or absent for OFF |
| `shaderfxSecondary` | secondary slot's preset name |
| `shaderfxParams[name][paramId]` | one preset's edited pragma values |

`POKEPORT_SHADERFX=<name>` activates a preset in the main slot for scratch
harnesses that never call `ShaderFX.applyOptions`. It is a stand-in that
predates the real OPTIONS row; `applyOptions` marks itself as having run so the
env var can never later override a real player choice, including a real choice
of OFF.

One quiet behavior worth knowing about: if a slot wants a real preset while
PERFORMANCE is still on AUTO, and AUTO would resolve to a tier that caps
ShaderFX off, `ShaderFX.applyOptions` pins PERFORMANCE to `HIGH`. Without it
the saved choice was force-deactivated a few lines later on every boot, which
looks identical to "the setting does not save" from the player's side. On
Android and iOS that is the common case, because AUTO always resolves to
`balanced` there. It never touches an already-explicit performance choice and
never un-escalates.

## The five stages

| Stage | Owner |
| --- | --- |
| Fetch | `ShaderFX.list`, `ShaderFX.downloadPresets`, `ShaderFX.installDownloaded` |
| Translate | `tools/shaderfx-bridge/` via `ShaderFX.translate` |
| Fixup | `src/render/ShaderFixup.lua` |
| Cache | `ShaderFX.convert` writes, `ShaderFX.load` reads |
| Run | `ShaderFX.runChain` / `runPass` / `ShaderFX.render` |

### Fetch

Two acquisition paths, and they land in the same place. A player can copy a
shader pack into `shaders/` by hand, or press `DOWNLOAD SHADERS`, which fetches
`https://buildbot.libretro.com/assets/frontend/shaders_slang.zip` (the same
~54 MB archive RetroArch's own "Update Shaders" entry pulls) through
`src/net/Fetch.lua`, the curl-on-a-`love.thread` transport the self-updater and
mod index already use.

Downloaded presets are *not* pre-converted. The buildbot is RetroArch's asset
mirror and has no notion of this project's cache format, so a downloaded preset
goes through the same `CONVERT` row a hand-copied one does. Every platform
ships both convert and use; there is no asymmetry to work around.

Repeat downloads are conditional. The zip itself is deleted right after
extraction, so what is cached instead is the buildbot's own ETag
(`shaderfx_buildbot.etag`), replayed as `If-None-Match`. The server answers a
match with 304 and no body, and curl writes no file at all in that case, so
`installDownloaded(notModified)` short-circuits before touching the filesystem
and reports "already up to date" rather than "FAILED".

The interesting part is what gets extracted. `handheld/` is not self-contained:
its 78 presets carry 101 references that escape the folder (color-mod LUTs
into `../shaders/color/`, console-border helpers into `../../reshade/`, shared
motion-blur and misc helpers, a shared `stock.slang`) across roughly 40 of
them. Extracting `handheld/` alone silently breaks about a third of its own
list; extracting the whole zip drags in ~5600 files of CRT, arcade and console
content nobody asked for. So `extractClosure` walks the real file-level
dependency closure in Lua before a single file is copied, the same
`#reference`-closure idea librashader applies internally, done up front because
deciding what to copy has to happen before the translator ever sees these
files. Against this zip that is 207 files and about 9.5 MB with zero broken
references. The closure seeds from `KEPT_PRESETS`, a curated shortlist rather
than all 78, after most of `color-mod/` and `console-border/` turned out either
irrelevant (color-only, no LCD effect) or broken for this project. That list
is a temporary trim pending wider testing and is expected to change.

Two mechanical details in that walk that are easy to get wrong a second time.
`extractRefs` tries a quoted `key = "path"` match per line first, with an
unrestricted `[^"]+` capture, because the closing quote is an unambiguous
delimiter and real packs ship paths with spaces and parentheses in them
(`"shaders/handheld/color-mod/Game Boy (Color).slang"`); only a line with no
quoted match falls back to a conservative character class, since an unquoted
path has no delimiter to trust past. And `love.filesystem.write` does not
create intermediate directories, so each destination directory is created once
before anything is written into it; without that, every file under a subfolder
`handheld/` never had before was silently dropped while flat writes succeeded.
Cleanup is equally literal: `love.filesystem.unmount()` takes the archive path
originally passed to `mount()`, not the mountpoint. Called with the mountpoint
it returns false, leaves the zip's handle open, and the following `remove()`
silently fails too, so every download used to leave 54 MB on disk forever.

### Translate: the native bridge

`tools/shaderfx-bridge/` is a small Rust crate (`spike`) that builds a cdylib
named `librashader_bridge`. It wraps `librashader-presets`,
`librashader-preprocess` and `librashader-reflect` behind a two-function C ABI:

```
char* librashader_translate_preset(const char* preset_path, int es);
void  librashader_free_string(char* s);
```

It returns a JSON `TranslateResult`: `pass_count`, a `passes` array (each with
its emitted `vertex`/`fragment` GLSL, `filter`, `wrap_mode`, `scale_x`/
`scale_y`, its own `#pragma parameter` declarations, a classified `samplers`
list and a classified `size_uniforms` list), the preset's `textures` (LUTs,
with resolved absolute paths and filter/wrap settings), its
`parameter_overrides`, and an `error` field.

**What the bridge is not.** No librashader runtime backend is linked in, for
any API: no GL, Vulkan, D3D or Metal crate is a dependency, and no live
graphics context is ever touched. It is the translation step only. LOVE still
owns every draw call, every canvas and every shader object. The bridge hands
back text and metadata and nothing else.

**When it is called.** Only from `ShaderFX.convert()`. Translation is ahead of
time, not just in time. `ShaderFX.load()`, `ShaderFX.activate()`, boot-time
reactivation of a saved choice and every frame of `ShaderFX.render()` read the
cached artifact and never call the library. An entry with no cached artifact
fails `activate()` loudly instead of silently live-translating.

The classification is done with librashader's real semantics resolution rather
than name matching on the Lua side, and that matters for correctness, not just
tidiness. Sampler classification uses `ShaderSemantics::create_pass_semantics`
plus the `TextureSemanticMap` lookup (explicit alias and LUT-name entries
first, then the built-in `Source`/`Original`/`OriginalHistoryN`/`PassOutputN`/
`PassFeedbackN` conventions), so a pass reachable only by its real `.slangp`
alias resolves. The per-pass convenience API only registers the alias of the
pass being compiled, so the bridge mirrors upstream's `insert_pass_semantics`
loop and builds a preset-wide alias map first; without that,
`ds-hybrid-scalefx.slangp`'s pass 2 sampling `scalefx_pass0` by alias, with no
`PassOutput1`-shaped name anywhere, can never resolve. Size-uniform
classification runs the same resolution over the pass's `uniform_semantics`
map, which also covers shapes (`PassFeedbackSizeN`, `UserSizeN`) that no
present preset uses but that the convention allows.

The `es` flag picks the emitted dialect: 1 for GLSL ES 1.00 (mobile, LOVE's ES
dialect), 0 for GLSL 1.20 (LOVE's desktop dialect). `ShaderFX` picks it from
`love.system.getOS()`, and the same function decides which dialect
`validateShader` is asked about at run time, so the two always agree. Convert
and render always happen on the same device; **artifacts are not portable
across platforms**.

One class of fixup has to happen in the bridge rather than in `ShaderFixup.lua`,
on the raw `.slang` text before SPIR-V compilation: `textureSize`,
`texelFetchOffset` and `textureOffset` are all ES 3.00+ only, and spirv-cross
refuses to *emit* them for an ES 1.00 target, failing the whole pass with
`UnsupportedSpirv("textureSize is not supported in ESSL 100.")`. No GLSL text
is ever produced for a later pass to patch, so `rewrite_essl100_gaps` rewrites
the source first, and only for the ES target:

- `textureSize(Tex, lod)` becomes a literal `ivec2(w, h)` when `Tex` is one of
  the preset's declared static textures, with dimensions read straight out of
  each PNG's IHDR chunk. A texture that is not one of those, or a non-literal
  `lod`, is left alone so it fails as loudly as before instead of guessing.
- `texelFetchOffset` and `textureOffset` become ordinary `texture()` calls at
  the equivalent texel-centre UV, using the texture's own `<Tex>Size.zw`
  reciprocal-size uniform. The containing block instance (`params`, `global`,
  whatever) is discovered by scanning the source's own uniform block bodies,
  never assumed. When a pass samples another pass purely through these calls it
  may never declare that `<Tex>Size` uniform at all, so one is injected first,
  before any byte offsets are computed.

That last rewrite has an honest limit: `texture()` honours the sampler's wrap
mode at out-of-range coordinates, which is not necessarily identical to
`texelFetch`'s implementation-defined out-of-bounds behavior. Any edge-of-image
discrepancy for passes whose offsets can leave the image is unmeasured.

**Building it.** `cargo build --release` inside `tools/shaderfx-bridge/`.
`ShaderFX` looks for the library, most specific first: the
`LIBRASHADER_BRIDGE_DLL` environment variable, the source directory,
`<source>/tools/shaderfx-bridge/target/release/`, the save directory, and
finally the bare name handed to the system loader. Per-OS names are
`librashader_bridge.dll` (Windows), `liblibrashader_bridge.dylib` or
`librashader_bridge.dylib` (macOS), and `liblibrashader_bridge.so` or
`librashader_bridge.so` (Linux and Android). Android resolves the bare name
because the `.so` ships as an ordinary `jniLibs` entry, so `dlopen` finds it
without a path. The desktop path is still a developer build sitting in cargo's
output directory; nothing packages it next to a shipped game yet.
`ShaderFX.canConvert()` reports whether the library resolved on this machine,
and `ShaderFX.bridgeError()` says why not. Activating an already-converted
preset never needs any of this.

**Statically linked bridges.** On iOS there is no loadable library at all:
the bridge is linked straight into the app binary, so its symbols live in the
main image and are reachable only through `ffi.C`. The candidate list is empty
on iOS and, on every platform, a failed candidate walk falls back to probing
`ffi.C` for `librashader_translate_preset` after the `ffi.cdef`. If the symbol
is there, `ffi.C` becomes the library handle and `ShaderFX.translate` uses it
unchanged. If it is not, `ShaderFX.bridgeError()` reports that `ffi.C` was
probed as well, followed by the file paths that were tried (omitted on iOS,
where none are).

**Android ships the bridge inside the APK.** `scripts/build_android.sh`
stages `liblibrashader_bridge.so` into
`mobile/android/app/src/main/jniLibs/<abi>/` for the two ABIs the APK ships,
arm64-v8a and armeabi-v7a, so `ffi.load("liblibrashader_bridge.so")` finds it
by bare name in the app's native library directory. The build cross-compiles
the crate with `cargo ndk` against the same NDK the gradle project uses
(25.2.9519653), which needs `cargo install cargo-ndk` and
`rustup target add aarch64-linux-android armv7-linux-androideabi`; the script
names the exact command for any target that is missing. Set
`SHADERFX_BRIDGE_ANDROID_DIR` to a directory holding
`<abi>/liblibrashader_bridge.so` to bundle prebuilt libraries instead. As on
desktop, the bridge is only needed to CONVERT a preset: a build without it
still runs presets converted elsewhere, and the packager warns and continues
rather than failing.

**iOS links the bridge instead of loading it.** An iOS app cannot `dlopen` a
dylib shipped beside its binary, so `tools/shaderfx-bridge` also builds as a
`staticlib` and `scripts/build_ios.sh` links it into the app executable
(`bundle_shader_bridge_ios`, mirroring `bundle_shader_bridge` in
`scripts/build.sh`). `SHADERFX_BRIDGE_IOS` points at a prebuilt archive;
otherwise cargo builds `aarch64-apple-ios` for device builds and every
installed simulator target (`aarch64-apple-ios-sim`, `x86_64-apple-ios`) for
the Simulator, with `IPHONEOS_DEPLOYMENT_TARGET=15.0`, and `ARCHS` is pinned to
what got built. The archive is never linked directly: LÖVE 12 carries its own
glslang for shader validation and the crate drags in a second, incompatible
one, and linking both crashed inside `Shader::validateInternal` at startup.
Each slice is therefore prelinked with `ld -r -all_load
-exported_symbols_list` so only `_librashader_translate_preset` and
`_librashader_free_string` stay external and every other symbol (glslang,
spirv-cross, Rust std) becomes private to the object, then `rust-objcopy`
drops the `__LLVM` bitcode sections rustup's prebuilt std carries, since
Apple's `nm` cannot read them. `OTHER_LDFLAGS` adds `-Wl,-u` on both entry
points to keep them past dead-stripping and `-lc++` for the C++ the crate
needs; no Objective-C framework is involved. A build that linked the object
fails if `nm` cannot find `_librashader_translate_preset` in the finished
binary; a build that could not produce one only warns and lands where the
desktop packages without cargo land: converted presets run, CONVERT does not.

### Fixup

`ShaderFixup.lua` mechanically rewrites the emitted GLSL into something LOVE
will accept. librashader emits a standalone `void main()` /`gl_FragData[0]` /
`gl_Position` shape (translated Vulkan GLSL); LOVE requires the `effect()` and
`position()` convention and refuses a raw `main()`-shaped source outright. This
is a targeted rewriter, not a GLSL parser, and every rule below exists because a
real preset in the corpus failed without it. This list is the least guessable
part of the whole feature.

**`#version` line.** Stripped; LOVE prepends its own.

**Array constructors.** SPIR-V Cross emits ES 3.0 array-constructor syntax
(`const float _17[5] = float[](0.0, 1.0, ...)`) for compile-time array
literals, which validation rejects with "arrayed constructor: not supported for
this version". GLSL ES 1.00 has no array-constructor syntax at all. There are
three real shapes in the corpus and each is handled: a `const` global (declared
without an initializer at global scope, with per-element assignments relocated
to the top of `main()`), a non-const local declaration with initializer
(rewritten in place, since a function body can hold assignment statements where
the literal was), and a bare reassignment of an array declared elsewhere (also
in place). Splitting the element list needs `splitTopLevelCommas`, because a
naive comma split breaks on any element containing its own parentheses
(`vec2(-1.0, 0.0)`), and the outer capture needs `%b()` rather than a
`[^%)]-` class for the same reason: the class stops at the first inner `)`, the
whole match fails, and the literal passes through completely untouched.

**Whole-array copies.** `float param_1[7] = coeffs;` is how SPIR-V Cross clones
a function-parameter array before passing it on, since GLSL array arguments are
by value. ES 1.00 has no whole-array assignment either, so it becomes a bare
declaration plus an element-by-element copy. The size is known from the
declaration, so no comma splitting is involved. This one only became reachable
once the other array shapes stopped masking it in the same file.

**Integer modulo.** ES 1.00 has no `%` operator, and SPIR-V Cross emits it
anyway for an upstream integer-modulo op. `%` in GLSL is only defined for
integer operands, so routing through float `mod()` and back is exact for the
non-negative operands this shader family uses (rotation and orientation enum
indices). Four patterns are tried in order (paren/paren, paren/bare,
bare/paren, bare/bare) because SPIR-V Cross fully parenthesizes a compound
operand and leaves a simple one bare, and the balanced form must be tried
before a plain identifier can partially match. Seen live on
`authentic_gbc`'s subpixel-rotation math.

**Precision.** SPIR-V Cross hardcodes an unguarded `precision highp float;` /
`precision highp int;` pair with no toggle. That is removed and replaced with
the same guard the old hand-written `DotMatrix` port used: claim `highp` only
where `GL_FRAGMENT_PRECISION_HIGH` says the driver actually offers fragment
highp, and fall through to the stage default otherwise.

**Struct flattening.** This is the big one. LOVE's `Shader:send` cannot address
a member of a custom struct-typed uniform: neither an `INSTANCE.member` dot path
nor sending the whole struct as a table works, both raise "Shader uniform '...'
does not exist." librashader emits every pass's `#pragma parameter`s and size
uniforms as exactly that kind of struct, so as shipped the output is unusable
from LOVE, not merely inefficient. `flattenStruct` deletes the struct and its
instance uniform and re-declares the members at top level. Scalar members are
*packed* four at a time into synthetic `uniform vec4 LIBRA_PACKED_N;` slots,
because GLSL ES 1.00 guarantees only 16 fragment uniform *vectors* and every
scalar costs a whole one; `gb-pass4`'s pass 0 alone has 14 scalars, already over
budget unpacked. Non-scalar members keep their own uniform, since packing an
existing `vec4` saves nothing. Every `instance.member` reference is rewritten to
`LIBRA_PACKED_N.x` (or `.y`/`.z`/`.w`), and a member whose original declared
type was `int` or `bool` gets an explicit cast back on every read, since a
packed slot only stores floats. Vertex and fragment declare identically ordered
structs for the same parameters, so packing both with the same prefix assigns
the same slot and component to the same parameter in both stages, and one
`shader:send` reaches whichever stage uses it.

Two ordering constraints inside that function are load bearing and look
arbitrary from the outside. Packing must walk the members in the struct's own
declaration order, because that order is what keeps the scalars in one
contiguous run; an earlier version sorted them longest-name-first before
packing and produced six packed vec4s instead of four on `gb-pass4`, blowing the
budget. Substitution, separately, must go longest-name-first, so a replacement
can never land as a substring inside a still-pending member name that shares a
prefix. The two orders are separate copies of the list for exactly that reason.

`Fixup.packValues` turns a flat `{name = value}` table back into the
`{uniform = value_or_vec4}` shape the packed shader expects, per the manifest
`flattenStruct` returned. `Fixup.countUniformSlots` counts declared uniform
slots against that same 16-vector budget, samplers excluded. Its pattern uses
`[%w_]+` rather than `%w+` because Lua's `%w` does not include underscore
unlike regex `\w`, and every generated name here is full of underscores.

**UBO blocks.** `LIBRA_UBO_FRAGMENT` and `LIBRA_UBO_VERTEX` have the identical
problem and are flattened the same way, under a distinct `LIBRA_UBO_PACKED_`
prefix so their groups cannot collide with the push block's numbering. `MVP` is
the one special member: it is substituted directly to `transform_projection`
instead of becoming a uniform, because "multiply the incoming vertex by it" is
exactly what LOVE's `transform_projection` already is on a full-screen draw, and
nothing would ever supply a value for it. An earlier version assumed the UBO
block only ever carried `MVP` and deleted the whole declaration after
substituting it. That is true only for presets that declare their parameters in
a push-constant block; presets that use a UBO instead (many real handheld and
console-border presets do) had every other member reference left dangling, and
the driver then read `INSTANCE.PAR` as a swizzle, which is where the "undeclared
identifier" and "unknown swizzle selection" errors on real Android hardware came
from.

**Fragment entry point.** `void main()` becomes LOVE's `effect()` signature.
The parameter list is qualified by an `EFFECT_PREC` define rather than a literal
precision, because LOVE forward-declares `effect()`'s prototype under its own
header's precision default before this source runs, which can mismatch whatever
the precision guard above raises the default to. `Fixup.PREC_HEADS` holds the
two variants (`mediump`, then unqualified) and the caller tries them in order
against `validateShader`, taking the first that passes.

**Fragment output.** `gl_FragData` does not exist in LOVE's `effect()`
convention, so every `gl_FragData[0]` occurrence is rewritten to a local
`gbFragColor`, declared at the top of the function, with a single `return`
appended before the closing brace. Rewriting *every* occurrence regardless of
the operator that follows is necessary, not just symmetric with the vertex side:
an earlier assign-then-return pair assumed one write at the very end of
`main()`, which holds for most presets but not for ones like `ds-hybrid-sabr`
that write once with `=` and later accumulate with `+=`. The `+=` statement
passed through unconverted and collided with LOVE's own `gl_FragColor` write
("Cannot use both gl_FragColor and gl_FragData"). A bare early `return;` is
rewritten to `return gbFragColor;`, which holds the value assigned just before
it on every real shape seen.

**Vertex entry point.** `void main()` becomes `position(mat4
transform_projection, vec4 vertex_position)`, the source's own `attribute`
redeclarations of `Position`/`TexCoord` are dropped since LOVE supplies them,
`gl_Position = X;` becomes `gbClipPos = X;` (named to share no substring with
`Position`, or the next step would mangle it), and a `return gbClipPos;` is
appended. The `Position` and `TexCoord` substitutions are frontier-matched
whole identifiers (`%f[%w]...%f[%W]`), not blind substring replacements: real
presets declare their own unrelated locals such as `vec2 vTexCoord;`, and a
blind `gsub` turned that declaration into the invalid `vec2 vVertexTexCoord.xy;`
(`dot.slangp` pass 0, a real driver "unexpected DOT" error).

### Cache

`ShaderFX.convert(entry)` is the only path that calls the bridge. It runs
`ShaderSourcePatches.apply` first, translates, then serializes the decoded
result to `ShaderFX.artifactPath(entry)`: the source `.slangp`'s own absolute
path with the extension swapped to `.lua`, so the artifact sits next to the
preset it came from. The file is a plain `return { ... }` chunk written by
`serializeLua`, which handles the string/number/boolean/nested-table shape
`Json.decode` produces. Array detection walks every key rather than trusting
`#t`, since `#t` counts a trailing nil as absent and a sparse table can pass a
naive length check by accident.

`ShaderFX.load(entry)` `loadfile`s that chunk and builds a chain state. On
failure it says "convert this preset first" rather than falling back to a live
translation.

**AOT rather than JIT** is the whole point of this stage. Translation is a rare,
explicit, user-initiated action whose result is stable for a given preset and
dialect, so paying for it once and writing the answer to disk keeps `ffi.load`
and the native call off every activation, every boot and every frame. The cost
is a staleness gap: `ShaderFX.isConverted()` is a plain "does the artifact file
exist" check with no version or content stamp, and there is no explicit
"reconvert" action in the UI. A preset converted by an older build never picks
up a later translator fix on its own. This was seen on a real device, where
`sunlight_shimmer.slangp`'s `Accelerometer` uniform never reached the shader
because that device's cache predated the fix while `pixel_transparency`'s
happened to be fresher. Two places compensate by reconverting unconditionally:
`ShaderFXScreen`'s explicit selection of an already-converted row, and
`ShaderFX.applyOptions` on every boot and options save. Both are human-paced,
CPU-only work with no GPU compile, and neither is on the per-frame path.

`ShaderSourcePatches.lua` sits just before translation and patches the raw
`.slang`/`.inc` files *on disk*, because only librashader's own preset parser,
reading the real files, discovers `#pragma parameter` lines and struct members;
nothing downstream can add one. Patches are small, explicit, per-preset literal
find/replace pairs (plain `find`, not `gsub`, since GLSL source is full of Lua
pattern magic), re-applied idempotently on every convert so a buildbot
re-download that replaces the upstream file wholesale does not quietly undo
them. **The patch table ships empty on purpose and nothing registers one.** Its
original use case, wiring gyroscope yaw into `sunlight_shimmer.slangp` as new
`PT_YAW_*` pragma parameters, was reverted precisely because of the staleness
gap above: a new pragma can only reach an artifact that gets reconverted, and at
the time nothing forced one. The mechanism is kept for a future preset that
genuinely needs a new declaration, but an already-wired engine-side channel is
preferred whenever one exists.

### Run: the pass graph

`ShaderFX.activate(slot, entry, paramOverrides)` loads the artifact, layers the
player's edited parameters over the artifact's own defaults, loads the preset's
LUTs once, and snapshots the accelerometer rest pose. `ShaderFX.render` then
runs the chain each frame.

`newChainState` builds one instance of chain-local state per loaded preset,
never module-global, so switching presets cannot leak a previous preset's
canvases or dimensions. `ALL_DEFAULTS` is built in layers: each pass's declared
`initial`, then the preset's own `parameter_overrides`, then (in `activate`) the
player's `shaderfxParams` edits.

Sizes resolve through `resolveScale`, which handles all four slang scale types
(`absolute`, `viewport`, `source`, `original`) against the viewport, the pass's
input dimensions and the original frame. Size uniforms are packed as
`{w, h, 1/w, 1/h}`, the slang convention.

`runPass` caches two things per `(state, pass index)`. The **shader** is
compiled once for the state's lifetime, along with the fragment manifest it was
compiled against, since a pass's GLSL depends only on the preset and never on
per-frame input. The **canvas** is reallocated only when the pass's resolved
size actually changes, a window resize or a different preset. Every harness this
runtime was ported from ran the chain once and quit, so allocating a fresh
canvas and compiling a fresh shader on every call was invisible there. On a real
per-frame render path it is one GPU allocation per pass per frame, and a shader
recompile on top. The same discipline applies to the crop canvas in
`cropToGbSource`, which is called once per frame and whose size grows with the
world canvas as the player zooms out; leaving it uncached was a real cost that
scaled with zoom level even with a single preset active.

Sampler binding is by semantic, from the bridge's classification, never by a
hardcoded per-preset name check: `Source` is the previous pass's output (or the
input frame for pass 0), `Original` and `OriginalHistory` are the input frame,
`PassOutput` indexes an earlier pass's canvas, and `User` resolves a LUT by the
real name the translation reported. A sampler that resolves to nothing asserts
rather than drawing garbage.

**LUTs** are loaded once per `activate`. `ShaderFX.loadImageFromPath` reads the
bytes with plain `io.open` and goes through `love.data.newByteData` and
`love.image.newImageData`, because a preset's texture paths are arbitrary
absolute OS paths outside any LOVE mount and `love.graphics.newImage` refuses
those outright ("Could not open file ... Does not exist") even when the file is
real. Wrap modes are mapped from librashader's names to LOVE's
(`clamp_to_border` to `clampzero`, `clamp_to_edge` to `clamp`, `repeat`,
`mirrored_repeat` to `mirroredrepeat`). A LUT that fails to load is logged and
left nil; the fail-loud point is the sampler assertion in `runPass` that
actually needed it, not the loader.

**History ring.** `OriginalHistoryN` currently resolves to a steady state: every
history slot reads the current frame, both for the sampler binding and for the
size uniform. Real per-frame history rotation has been proven out in a desktop
harness but is not wired into this path.

**Feedback.** `PassFeedback` is not implemented. A `PassFeedback` or `User` size
uniform raises an explicit "not yet supported" error, and a `PassFeedback`
sampler resolves to nothing and trips the binding assertion. No preset in the
shipped shortlist uses it.

**Blending.** Every pass draws with `replace`, and the chain's final pass uses
`replace, premultiplied`. Intermediate canvases are `nearest` filtered.

`ShaderFX.render(canvas, rect, source, dpiX, dpiY)` is the entry point
`Renderer:endFrame` and `Game2` call. `canvas` is the finished window-sized
composite (world, UI, and any post-process pipeline that already ran); `rect` is
this frame's real playfield rectangle in physical framebuffer pixels and
`source` is the real pixel size of the content it frames. The sequence is: crop
`rect` out of the composite, run whichever slots are active over that crop, draw
the untouched composite, then stretch the chain output back over `rect`. UI and
letterbox bars outside the playfield pass through untouched. If the chain throws,
the frame still shows the unprocessed composite; a broken preset degrades to
"shader off", never to a crash or a blank frame.

Three details in that path are non-obvious:

- **DPI.** `love.graphics.newCanvas` and `draw` work in LOVE's DPI-aware
  logical units, not raw pixels, so the viewport handed to the pass graph and
  the final draw-back position are both converted from `rect`'s physical pixels
  first. On a `dpiscale = 1` desktop the two are numerically identical and the
  bug is invisible; at dpiscale 3 on real Android hardware the chain output
  rendered about three times too large and at a pixel-valued offset in unit
  space.
- **Draw color.** `cropToGbSource` sets `setColor(1, 1, 1, 1)` explicitly. The
  caller can leave the draw color dirty (a menu's black text leaves it at
  `(0,0,0,x)`), the crop draw multiplies the canvas texels by the active color,
  and `push("all")` saves state for `pop()` without resetting it. That was the
  root cause of the Gen 2 blank-menu bug, confirmed on a desktop repro where
  `getColor()` read `0,0,0,1` here exactly when a menu was on the stack.
  `flushBatch()` on the line above is cheap insurance against a read-after-write
  ordering hazard between this draw and whatever last rendered into the canvas;
  it was never confirmed to fix anything on its own.
- **The final blit stretches.** A slang chain's last pass is not required to
  land on the viewport size, and most presets (21 of the 78 in the corpus)
  declare their last pass `scale_type = "source"` and stay at native Game Boy
  resolution, relying on the frontend's blit exactly as RetroArch does.
  Requiring an exact size match here used to skip the draw outright for every
  such preset on every frame, which is a silent total no-op rather than a sizing
  quirk. The stretch uses the last-run chain's own final-pass `filter` to pick
  nearest or linear.

### What this engine feeds shaders that a libretro core does not

A stock libretro core hands its frontend a raw framebuffer and a frame count.
This engine has more context available and passes some of it through.

| Context | How it reaches the shader |
| --- | --- |
| Playfield rect and true source size | `rect`/`source` per frame from `Renderer:endFrame` or `Game2`, so the chain sees real on-screen geometry at any survey zoom or Faithful Ratio state rather than a fixed 160x144 assumption that then gets stretched |
| Blit scale | `rect.scale`, the crisp integer scale the composite was built at, used to derive the crop's own draw scale |
| SGB zone coloring and palette | Baked into the input frame. `PaletteFX` zone passes run before the composite reaches ShaderFX, so a preset shades an already-zone-tinted image |
| Performance tier | `chainRenderScale()` reads `Performance.CAPS[tier].shaderfx`, a chain-resolution multiplier; the viewport and the cropped source both shrink by it and the final blit upscales |
| Accelerometer | `Sensors.read("accelerometer")`, bound to the `Accelerometer` unique semantic |
| Gyroscope | `Sensors.read("gyroscope")`, bound to `Gyroscope`, plus the integrated yaw twist below |

Two motion semantics are deliberately pinned rather than guessed. `Rotation` is
bound to 0 because librashader's own documentation is explicit that it is
`retroarch_get_rotation()`, the *content's* requested rotation (a vertically
oriented arcade core, say), not device orientation. Nothing here ever rotates
Game Boy content, so 0 is the correct answer, not a placeholder.
`AccelerometerRest` is bound to `{0, 0, 0}`: it is librashader's "reading at
rest" calibration reference, no preset in the corpus reads it, and a fixed
placeholder beats an invented value.

`src/core/Sensors.lua` is what makes the two real motion semantics work.
`love.sensor` does not exist in LOVE 11.5, the version this project ships, on
any platform including Android; it is a LOVE 12 addition. The working path is
raw FFI into the SDL2 that LOVE already links, the same technique
`src/core/Orientation.lua` uses, opening the first `SDL_SENSOR_ACCEL` or
`SDL_SENSOR_GYRO` device via `SDL_NumSensors`/`SDL_SensorGetDeviceType`/
`SDL_SensorOpen`. The `love.sensor` path is kept above it and simply stops being
dead code after a future LOVE 12 upgrade. Loading order matters:
`ffi.load("SDL2")` first, needed on desktop where SDL2 is a separate DLL, then
bare `ffi.C`, needed on Android where love-android links SDL2 statically into
`libmain.so` and there is no `libSDL2.so` for `ffi.load` to find by name. A
device with no sensor is probed once and then permanently reports zeros, so a
desktop run does not pay for it every frame.

SDL keeps sensor readings in the device's fixed chassis frame regardless of
screen orientation, so `rotateForScreen` remaps x and y into
"as currently displayed" terms using `SDL_GetDisplayOrientation`. That
compensation is mobile-only: a desktop monitor is legitimately and permanently
"landscape" to that query, which says something about the monitor's shape and
nothing about how a player is holding anything.

The accelerometer path in `sizeTable` does three things to the raw reading
before it becomes a uniform, all of them driven by real on-device data:

1. **Rest-pose subtraction.** `activate()` snapshots whatever pose the player is
   actually holding the device in and every later reading is measured relative
   to that, rather than to an assumed idealized vertical. The shipped tilt maths
   (`pt_base.inc`'s `getOrientedTilt`) was authored assuming gravity sits almost
   entirely on one axis at rest; a natural, comfortable hold already puts 56 to
   66 percent of gravity's magnitude on the axis the shader reads as tilt, so
   the effect sat near-saturated all the time instead of starting near neutral.
2. **Axis swap.** The tilt maths assumes a device resting flat, with gravity
   dominant on Z, the one axis it never reads. This engine's rest pose is
   upright portrait, where Y is gravity-dominant, so y and z are swapped to put
   gravity back on the ignored axis.
3. **Denominator stabilization.** `getOrientedTilt` normalizes by the full
   vector's magnitude. Before calibration that magnitude was a stable ~9.8 that
   quietly damped tilt and noise alike by the same factor; calibration correctly
   zeroes x and y at neutral but also shrinks the magnitude near rest, and real
   logs showed it swinging between 0.65 and 11.4 second to second on ordinary
   hand jitter, which reads as wildly bouncing. A fixed constant is re-injected
   on the ignored axis to keep the denominator stable, but only when there is a
   genuine live reading to calibrate against. An all-zero raw read is
   `Sensors.lua`'s explicit "no hardware at all" sentinel, never a real value on
   Earth, and injecting into that case would make the shader believe it had
   sensor data and silently replace its own static fallback with fake motion.

Yaw is a separate mechanism. A raw gyroscope reading is angular velocity, not an
angle, so it only becomes a usable on-screen offset by integrating over time,
and only the per-slot state persists frame to frame to do that. `updateYawTwist`
is deliberately a decaying spring rather than a true integrated heading:
gyro-only integration drifts without a magnetometer to correct it, so this
settles back toward neutral and stays bounded by construction. It is folded onto
the accelerometer's x component before the shader's own normalize and clamp,
because that is the only already-compiled channel the stock upstream maths
reads, and reaching an already-converted artifact with no reconvert was worth
the tradeoff that the twist reads as an added simulated tilt rather than a
cleanly separate motion. It applies to `sunlight_shimmer.slangp` only, the one
preset in the shortlist with a twist-reactive channel. `YAW_GAIN = 0.6` and a
clamp of +/-2 were tuned against real device data (a moderate real yaw turn
peaks around 1.5 to 1.7 rad/s); a much larger gain was tried on-device and
looked worse, because overshooting a comfortable range reads worse than being
subtle. Retune in small steps with real device checks, not big jumps.

## Two slots

`ShaderFX.SLOTS` is `{"main", "secondary"}` and `ShaderFX.OPTION_KEY` maps each
to its save key. The slots are activated and persisted independently, and the
same `ShaderFXScreen` serves both, opened with the slot as its argument. Pragma
parameter edits are keyed by *preset name*, not by slot, because a preset's
values are a property of the preset the same way its cached artifact is;
editing them re-activates every slot currently showing that preset and persists
for the next load in either.

When both slots are active, `render` runs main's chain first and hands its
finished output to secondary as secondary's own input frame, along with its
dimensions, so a secondary preset that scales off its input sees main's real
output size rather than the original crop. Either slot alone behaves exactly as
a single-preset path; neither active is a plain passthrough.

**This is not how RetroArch composes multiple presets.** RetroArch merges
presets into a *single* pass list through `#reference` and `Append`, producing
one pass graph with one shared semantics map, where a later pass can reference
an earlier one's output by alias and the whole thing resolves as one unit. Two
slots here are two independent librashader chains run back to back, which is
what stacking two separate preset chains would give you, not what merging them
gives you. Presets that assume merged semantics will not behave the same way.

## Test seams

`ShaderFX` exposes a few fields purely so a headless harness can assert on real
per-frame values without taking a screenshot: `_lastRect` and `_lastSource`
(the rect and source dimensions a caller handed in), `_lastCrop` (the exact crop
canvas, which the later unconditional draw-back would otherwise mask),
`_lastYawTwist` and `_lastAccelPacked` (the integrated twist and the values that
actually reached the packed uniform, per slot). `Sensors.setOverride`,
`Sensors.clearOverride` and `Sensors.setOrientationOverride` inject synthetic
readings on a machine with no hardware.

## Limitations

None of these are theoretical.

- **Tested on very little real hardware.** Essentially one Android phone, one
  desktop, and the automated harnesses. Anything about how a preset actually
  looks or performs elsewhere is unverified.
- **No performance tier is actually tuned.** The chain-resolution multiplier in
  `Performance.CAPS` is a working mechanism, but every tier that permits
  ShaderFX at all sets it to 1.0. Nothing runs at reduced chain resolution
  today. Picking a real value for weak hardware needs a device this project does
  not have.
- **The dual-slot design does not match RetroArch.** See above. Two chains in
  sequence is not one merged pass list.
- **`OriginalHistoryN` is a steady state.** Real per-frame history rotation
  falls back to "every slot is the current frame" in the live render path, and
  is unverified there.
- **`PassFeedback` is unimplemented.** Its size uniform raises an explicit
  error and its sampler trips an assertion.
- **`ShaderFXScreen` has a known text-overlap bug on long preset names.**
  `ListMenu`'s `fitLabel` truncation covers the ordinary case, but a long enough
  player-supplied filename still collides with the row's right-hand hint.
- **`ShaderSourcePatches` ships with an empty patch table and nothing uses it.**
  Intentional, for the reason given above, but it means the mechanism has no
  live coverage.
- **Cached artifacts have no staleness detection.** Existence is the only check.
  The two unconditional reconvert points paper over it; anything that does not
  go through them can be running a stale translation.
- **Artifacts are per-device.** The GLSL dialect is baked in at convert time.
  Copying a converted preset folder between a phone and a desktop copies a
  wrong artifact along with it.
- **The bundled bridge is only as good as the build machine.**
  `scripts/build.sh` bundles the cdylib for mac, win and linux via
  `bundle_shader_bridge`, building it with cargo when a prebuilt one is not
  supplied through `SHADERFX_BRIDGE`. A build host without cargo produces a
  package that can run converted presets but cannot CONVERT new ones, and says
  so rather than failing. `scripts/build_android.sh` and `scripts/build_ios.sh`
  follow the same rule with `cargo ndk` and the iOS static archive.
- **The buildbot shortlist is a temporary trim.** `KEPT_PRESETS` reflects one
  manual pass over `handheld/` and is expected to change, most likely to shrink.
- **Tilt direction is unverified.** Which way forward and back rocking moves the
  effect was never confirmed on a device; if it feels backwards the fix is a
  sign flip on the swapped axis, not a deeper bug. Likewise, whether the
  landscape rotation compensation matches real RetroArch is genuinely unknown:
  RetroArch's Android input driver computes a screen rotation but does not
  visibly apply it to the accelerometer values that reach shader uniforms, so
  this project's compensation may be an improvement over upstream rather than a
  match to it.
- **`texelFetch` wrap behavior at image edges may differ.** The ES 1.00 rewrite
  in the bridge turns those calls into `texture()`, which honours the sampler's
  wrap mode out of range where `texelFetch`'s out-of-bounds behavior is
  implementation defined. Unmeasured.
