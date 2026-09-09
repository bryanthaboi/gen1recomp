# Proposal: bounded import/cache I/O for `mod.job`

## Summary

Extend the existing sandboxed `mod.job` background-compute API with an **opt-in, narrowly scoped asset-processing capability** that allows a worker to:

- read byte ranges from source imports explicitly declared by the owning mod; and
- read/write only that same mod's private generated-cache namespace.

This is intended for expensive offline preprocessing such as model, texture, animation, audio, or index generation from user-authorized source media. The worker remains sandboxed and does not gain arbitrary filesystem access, engine/game state, `io`, `os`, `ffi`, unrestricted `love.filesystem`, or cross-mod access.

## Motivation

`mod.job` already solves the CPU-bound half of this problem: it runs mod-owned Lua source on engine-managed worker threads behind the `background` permission. Today, however, jobs are deliberately pure compute: plain data in, plain data out, with no import or cache access.

That prevents workloads shaped like:

1. read a bounded range from a user-authorized source import;
2. decompress / parse / transform that data;
3. generate runtime-ready binary artifacts;
4. persist those artifacts in the mod's private cache; and
5. return a small completion/progress record to the main thread.

Without a worker-safe I/O surface, large preprocessors must perform most of this work on the main Lua state. On mobile, that can turn a dedicated loading/pre-cache screen into a long-running frame-loop-bound compiler.

A concrete stress case is a mod that converts user-owned source-media 3D models and authored animation data into reusable private runtime caches. The source media is never redistributed, and generated files remain installation-local.

## Proposed API shape

Exact naming is open to review. The key requirement is that the capability is explicit and narrow.

```lua
local handle, err = mod.job:run("workers/build_asset.lua", {
  assetId = 59,
}, {
  maxSeconds = 300,
  assetIO = true,
})
```

Inside an asset-I/O job, inject a worker-local capability object rather than exposing `love.filesystem`:

```lua
job.imports:info(importId)
job.imports:read(importId, offset, length)

job.cache:info(path)
job.cache:read(path)
job.cache:write(path, bytes)
job.cache:exists(path)
```

The worker should write large generated artifacts directly to the cache and return only small plain-data status/results through the existing job channel:

```lua
return {
  ok = true,
  asset = "pokemon/059",
  filesWritten = 14,
}
```

## Security / sandbox contract

The feature should preserve the current `mod.job` security model:

- no arbitrary filesystem paths;
- no `io`, `os`, `ffi`, `debug`, `package`, or unrestricted `require`;
- no arbitrary `love.filesystem`;
- no game-state / engine-module access from the worker;
- no cross-mod reads or writes;
- no undeclared imports;
- no access outside the owning mod's generated-cache namespace;
- no network access unless separately granted by an existing permission/API;
- only the mod's own shipped worker script may execute;
- existing per-mod/global worker limits remain enforced.

Import reads should use the same manifest authorization and bounded-range validation as main-thread `mod.imports` reads.

Cache operations should use the same safe-path rules, per-write size limits, and mod-private namespace as the existing generated-cache API.

## Why this should extend `mod.job`, not expose `love.thread`

The current sandbox intentionally blocks unrestricted worker Lua states because they are outside the normal mod environment. `mod.job` is already the sanctioned engine-managed replacement for background compute. Extending that existing abstraction with explicit capabilities keeps the security boundary centralized instead of reopening unrestricted threading.

## Why this is separate from ARM JIT policy

The Android/LÖVE runtime has separate ARM JIT policy and stability concerns. Even if that changes in the future, large preprocessing jobs still benefit from running independently of the render/update loop. This proposal does not change JIT defaults.

## Implementation direction

### `src/mods/Job.lua`

- Accept an explicit asset-I/O option/capability.
- Serialize only capability metadata to the worker, never arbitrary host paths supplied by the mod.
- Preserve existing worker-count limits.
- Consider a higher timeout ceiling for explicit foreground preprocessing jobs, while keeping a hard upper bound.

### `src/mods/job_worker.lua`

- Inject worker-local `job.imports` / `job.cache` wrappers only when authorized.
- Keep `require("src.*")`, raw filesystem APIs, and engine state unavailable.
- Route all reads/writes through engine-owned validation helpers.

### Import/cache host helpers

- Provide worker-safe bounded import reads.
- Provide private cache `info/read/write/exists` operations.
- Do not expose physical import/cache paths to the worker.

## Cancellation and atomicity

LÖVE threads cannot be safely force-killed in the current architecture, so cancellation can retain the existing semantics: stop accepting/polling the result while the worker may finish naturally.

Generated output should therefore be transactional. A worker should write temporary/incomplete names first and publish the final completion marker only after all required components succeed, for example:

```text
pokemon/059/model.bin.part
pokemon/059/model.bin
pokemon/059/complete.marker
```

An abandoned/timed-out job must never make partial output appear complete.

## Tests

Add modkit/engine coverage for at least:

- declared import range read succeeds;
- undeclared import is rejected;
- out-of-range import read is rejected;
- private cache write/read/info succeeds;
- `../` and absolute cache paths are rejected;
- one mod cannot access another mod's cache;
- worker still cannot access `io`, `os`, `ffi`, normal `love.filesystem`, or `src.*` modules;
- existing job concurrency limits remain enforced;
- cancelled/timed-out jobs cannot publish a valid completion marker from partial output;
- completed generated output is reusable after a fresh application start;
- existing pure-compute `mod.job` behavior is unchanged when asset I/O is not requested.

## Backwards compatibility

Existing `mod.job` users continue to receive the current pure-compute environment unless they explicitly request the new capability. No save-data, battle, link, or ordinary mod-sandbox behavior needs to change.

## Example use cases

- source-media model/animation conversion;
- texture preprocessing;
- large procedural asset compilation;
- private audio preprocessing;
- data indexing/search tables;
- ROM/source analysis that produces installation-local reusable caches.

## Benchmark target / validation use case

A useful acceptance benchmark is a source-media model/animation preprocessor that currently runs on the main Lua state. Compare:

- main-thread preprocessing time and responsiveness;
- background-job preprocessing time;
- cache output hashes/byte identity;
- restart persistence;
- Android thermal/memory behavior;
- cancellation and partial-output recovery.

The performance goal is not to weaken fidelity or reduce generated content, but to move the same preprocessing workload onto the engine's existing bounded background-job architecture.
