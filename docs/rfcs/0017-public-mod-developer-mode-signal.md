# RFC 0017: Public mod developer-mode signal

## Status

Proposed.

## Motivation

The engine already has one fixed developer-mode decision per boot, enabled by
`POKEPORT_DEV=1` or `--developer`, but a sandboxed mod cannot observe that
decision through the public API. Commands, screens, and exports can expose a
diagnostic surface, but none can make it developer-only. `force_enable_env`
controls whether a mod is enabled rather than explaining the boot mode, and
the legacy `os.getenv` compatibility shim deliberately hides arbitrary host
environment values and reports compatibility usage.

The concrete consumer is **Adaptive Trainers**. Its approved Chapter 30
diagnostics must expose trainer, boss, Rival, and League projections and log
random-choice seed labels only while `POKEPORT_DEV` is active; a production
boot must emit only normal errors and warnings. Without a public signal the mod
must either ship an ungated diagnostic surface, use a legacy environment shim,
or leave the required runtime tooling disconnected.

## Decision and plan extended

This implements **D-AT-005: developer diagnostics follow the engine's fixed
developer-mode authority**. The consuming work is tracked in Adaptive Trainers
Task 9:
[`docs/superpowers/plans/2026-08-14-adaptive-trainers.md`](https://github.com/MaxTomahawk/gen1recomp-adaptive-trainers/blob/main/docs/superpowers/plans/2026-08-14-adaptive-trainers.md).

The engine delta is generic. It contains no trainer state, diagnostic schema,
seed labels, commands, screens, or Adaptive Trainers policy.

## Exact API delta

Every sandboxed mod API object receives:

```lua
if mod.dev then
  mod.commands:register("diagnose", function(ctx)
    -- mod-owned developer tooling
  end)
end
```

`mod.dev` is a strict boolean snapshot of the loader's existing developer-mode
decision. It is fixed for the engine boot. Assigning another value on a mod's
private API table cannot change the loader, another mod, or engine developer
mode. The signal grants no permission and exposes no environment value, command
line, path, or host API.

## Migration and compatibility

Existing mods change nothing. The field is additive, requires no manifest
permission, and is allocated only as part of an API object for a loaded mod.
With no mods, no API object or export table is created and developer mode keeps
its existing engine behavior. Existing developer console and hot-reload
behavior is unchanged.

## Verification

- `tests/modkit/cases/dev_mode.lua` loads a sandboxed public mod with the
  injected developer tripwire disabled and enabled, proves a strict boolean,
  and proves no legacy environment report is produced.
- `tests/engine/dev_mode_no_mod_parity.lua` is the separate no-mod parity test;
  it proves both tripwire states allocate no mod or export object, preserve the
  active dataset object, and retain the same deterministic link fingerprint.

## Deprecation etiquette

Nothing is removed, renamed, superseded, or deprecated.
