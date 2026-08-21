# RFC 0008 — Streamed mod imports and installation-scoped generated cache

## Motivation

`required_imports`/`optional_imports` can now describe files up to 2 GiB, but
the existing launcher and public mod API still assume imported bytes are small:

* the Windows desktop picker stages a selected required import through a fixed
  `%TEMP%/pokeport_required_import.bin` path before validation;
* the fallback import path materializes the selected file as one Lua string;
* after validation a mod can only use `mod:read("baseroms/...")`, which also
  materializes the whole file;
* `mod.storage` is intentionally scoped to one Pokémon playthrough, so it is
  not an appropriate home for a one-time generated asset cache shared by every
  save using the same installed mod.

This makes optical-disc-sized user sources impractical even though the manifest
schema already accepts them. A failed temporary staging copy can also turn a
valid large source into a smaller temporary file and produce a misleading
"wrong file size" rejection.

A mod should be able to consume its own already-validated source incrementally
and compile derived runtime data once, without receiving a host path or general
filesystem access.

## Decision being extended

This extends the same legal/sandbox direction as **D11 asset transforms**
(`src/mods/AssetTransform.lua`): mods distribute recipes and derive bytes from
user-owned sources rather than shipping ROM-derived data. It also follows the
**D14 parity-gate** contract referenced by `tests/harness.lua` and
`tests/engine/gate_meta_coverage.lua` (the `21-testing-and-ci` plan): additive
extension points ship public-API coverage, no-mod parity coverage, and docs in
the same change.

The historical D11 plan document is referenced by source comments but is not
present in the current repository tree; this RFC is the checked-in design
record for the new surface.

## Exact API delta

No manifest field changes. Existing `required_imports` and `optional_imports`
remain the declaration/validation authority.

Two additive facades are added to the `mod` object.

### `mod.imports`

```lua
local info, err = mod.imports:info("source_id")
local bytes, err = mod.imports:read("source_id", offset, length)
```

* `source_id` must name an import declared by the calling mod.
* the import is rechecked through `RequiredImports.validateStored` before it is
  exposed, so missing, replaced, or invalid optional imports are not readable;
* `offset` and `length` are zero-based byte coordinates;
* one read is capped at 8 MiB;
* no host path or file handle is returned;
* production reads seek into the engine-owned stored copy instead of reading
  the whole source.

`info()` returns declaration metadata plus stored size. It does not expose a
host path.

### `mod.cache`

```lua
mod.cache:write("extract/v1/model.bin", bytes)
local bytes = mod.cache:read("extract/v1/model.bin")
local info = mod.cache:info("extract/v1/model.bin")
mod.cache:delete("extract/v1/model.bin")
```

The cache is rooted at `mod_cache/<mod-id>/`, follows the engine persistence
backend, and is independent of game version, launcher slot, and playthrough.
Paths are checked with `SafePath`; `..`, absolute paths, drive paths, and other
escapes remain unavailable. A single cache write is capped at 64 MiB so large
generated datasets are naturally split into independently replaceable files.

The engine does not interpret cache bytes. Mods own generated-format versioning,
fingerprints, transactional completion markers, and rebuild policy.

## Launcher/import transport delta

For large raw required imports:

1. desktop pickers return the original selected path instead of staging it
   through a fixed temporary file;
2. the engine opens that source itself;
3. bytes are copied directly to the existing engine-owned
   `mods/<id>/baseroms/<file>` destination in 4 MiB chunks;
4. MD5 is updated incrementally during the copy;
5. the normal size/MD5 validation receipt is written only after the complete
   destination passes validation;
6. partial destinations are removed on short reads, write failure, size
   mismatch, or digest mismatch.

N64 imports stay on the existing canonicalization path because byte-order and
copier-header normalization require transformation rather than a raw copy.

If a validation receipt for an already-stored large raw import is missing, the
engine rebuilds it with streaming MD5 rather than a whole-file read.

## Backward compatibility / migration

**Existing mods do nothing.** This is additive.

* manifest v1/v2 fields are unchanged;
* `mod:read`, `mod.storage`, registries, events, hooks, and legacy compatibility
  retain their existing behavior;
* small required imports retain the existing in-memory validation path;
* N64 imports retain canonicalization and existing accepted byte orders;
* a mod that never touches `mod.imports` or `mod.cache` creates no new cache
  files and observes no new behavior.

The mod API integer is not bumped because no existing member changes meaning or
shape.

## Security and legal posture

The launcher remains the authority that validates user-supplied bytes. The new
facade narrows access rather than widening it: a mod can read only ids declared
in its own manifest, only after validation, and only in bounded ranges. It does
not receive host paths, `io`, or a raw filesystem handle.

`mod.cache` is writable only beneath the calling mod's generated-cache root.
Nothing in this RFC permits packaged ROM-derived bytes; `modkit lint/pack`
continue to enforce the existing legal posture.

## Parity guarantee

The change ships with:

* a no-mod/API-v1 parity test proving an empty load and an existing v1-style
  `mod:read` load do not create cache data or change the old surface;
* a public mod-API test that reaches `mod.imports` and `mod.cache` through a
  real `Loader` load, including bounded reads, undeclared/missing imports,
  cache isolation, and traversal rejection;
* incremental MD5 vectors and a large-import streaming regression test;
* the existing engine suite, required-import suite, and mod lint gates.
