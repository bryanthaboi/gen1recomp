# Native application localization

This document defines the design and contribution rules for localizing
Gen1Recomp's own application UI. It is deliberately separate from cartridge
content and from translation mods.

## Current support

The application interface supports English (`en`) and Spanish for Spain
(`es-ES`). The implementation includes early locale startup, immediate
language switching, persistence, launcher Settings, ROM/save/mod import
surfaces, save-slot management, mod manager/browser chrome, notices,
confirmations, application-owned errors, responsive controls, and ROM-free
regression coverage.

Automated tests cover the locale boundary and the main ROM-free application
surfaces.

## Goal

Gen1Recomp should present its own user-facing interface in more than one
language through a normal application setting:

`Settings -> Interface Language -> English / Español / ...`

The selected language is an application preference. It does **not** change the
language of the imported Pokémon ROM, cartridge-derived dialogue, species,
items, moves, maps, Pokédex, battle script, or other gameplay content.

The first built-in locales are English (`en`) and Spanish (`es-ES`). The
architecture must let upstream add further built-in locales by contributing
metadata and a catalog, without introducing an external language-pack system.

Locale identifiers use canonical BCP 47 tags. The English source locale uses
the language-only `en` tag because the application does not define a regional
English variant. Spanish uses the regional `es-ES` tag for the built-in Spain
catalog.

## Upstream context

The localization design builds on the translation work already present on
`dev`, but does not treat translation mods as the application-locale UX.

Relevant upstream work includes:

- `Strings` source-as-key translation registry and context support;
- launcher literals routed through `Strings` and pre-boot mod catalog loading;
- translation-mod scaffolding/refresh tooling and format-arity validation;
- launcher font fallback work for non-Latin scripts;
- the bundled `spanish_ui` LANGUAGE-profile mod, merged in PR #974.

That work proves that the existing `Strings` seam is useful and should remain
compatible. It also exposes the architectural boundary this feature must add:
`Strings()` currently spans both Gen1Recomp-authored application UI and
Gen1Recomp-authored gameplay text. A built-in application locale therefore
must **not** simply become another global `Strings` catalog, because that would
translate battle/gameplay strings together with the launcher.

The native locale layer is consequently an application-domain overlay rather
than a replacement for the current translation-mod system.

## Scope

Application localization covers text authored by Gen1Recomp and presented as
part of the host application, including surfaces shown while a game is running:

- launcher navigation and controls;
- Settings;
- ROM import UI and user-facing import errors;
- save-slot/profile management and the save editor shell;
- mod browser/manager chrome;
- controls and host configuration;
- Gen1Recomp overlays and host-owned internal menus;
- update UI;
- confirmations, notices, and other user-facing host messages;
- user-facing host errors.

A host overlay opened over a running game is still application UI and uses the
selected interface locale.

## Application/game boundary

The native application locale does not translate:

- cartridge dialogue;
- cartridge/game menus;
- battle content;
- Pokémon names;
- move names;
- item names;
- Pokédex content;
- ROM-derived text;
- gameplay content;
- textual content supplied by third-party mods.

A user may run an English ROM with a Spanish Gen1Recomp interface, or the
reverse. `Interface Language` must never become a selector for the Pokémon ROM
language.

Some current `Strings()` calls live in gameplay code. Their existence does not
make them application-localizable. Domain classification is based on ownership
of the surface, not merely on whether a literal was authored in Lua.

## Logs and diagnostics

Developer-facing logs, diagnostics, traces, internal error details, assertions,
and support/debugging text remain in English. This preserves one stable,
searchable diagnostic form regardless of interface locale.

When a failure has both user presentation and technical detail, split them:

- localized application UI: `Could not import the ROM.`;
- English log: the detailed path/error/cause used for debugging.

A technical log call must not pass through the application locale layer. If a
single string is currently reused for both UI and logging, the presentation and
diagnostic messages should be separated instead of translating the log.

## Mods

Native application locales are repository-owned data, not LANGUAGE-profile
mods. Thousands of existing mods are outside the scope of this feature.

Third-party mods remain responsible for translating their own UI and text.
Existing mod-provided `strings` catalogs remain supported as a separate API.
Native application localization does not replace or redefine that API.

### Lookup precedence

The intended model is deliberately conservative:

1. application-owned call sites opt into the native application locale;
2. missing native entries fall back to the English source;
3. existing mod `Strings()` behavior remains available and unchanged for mod
   compatibility/gameplay translation.

A native application locale must not be injected globally into `Data.strings`.
That would leak the selected interface language into gameplay.

Where an application surface also intentionally exposes existing mod string
overrides, the exact precedence must be explicit and covered by tests. The
preferred default is native application locale first for base-app strings,
with third-party mod-owned UI handled by the mod itself rather than by the
built-in catalog.

## User experience

The setting is named **Interface Language**, never simply `Language`.

Example English UI:

```text
APPLICATION
  INTERFACE LANGUAGE    < English >
```

Spanish:

```text
APLICACIÓN
  IDIOMA DE LA INTERFAZ < Español >
```

Language names are self-identifying (`English`, `Español`, `Français`, ...),
so a user can recover after accidentally selecting an unfamiliar locale.

English (`en`) is the default. The application does not automatically select
a locale from the host OS.

Changing `Interface Language` updates application UI immediately. Views that
cache rendered text or descriptors must rebuild/refresh themselves; the user
must not be asked to restart Gen1Recomp merely to change interface language.

## Persistence

The locale belongs in the existing global `options.lua` table, alongside other
application-wide preferences. It is shared across Red, Blue, and Yellow and is
not save-game state.

The stored value is a stable BCP 47 locale identifier such as:

- `en` -- English source/default;
- `es-ES` -- Español;
- future examples: `fr-FR`, `de-DE`, `it-IT`, `pt-BR`, `ja-JP`, `zh-CN`.

Unknown, malformed, or removed locale identifiers fall back safely to `en`.
Loading an older `options.lua` with no locale field also yields `en`.

## Catalog architecture

English remains the source language and universal fallback. The existing
source-as-key style is retained unless a concrete ambiguity requires context.

The native application layer exposes a small API equivalent to:

```lua
AppLocale.set("es-ES")
AppLocale.get()                 -- "es-ES"
AppLocale.text("Settings")      -- "Ajustes"
AppLocale.text("%d slots", n)   -- validated formatting
```

Catalogs are data committed to the repository. A locale module contains:

- stable BCP 47 locale id;
- native display name;
- source-string -> translated-string map;
- optional metadata needed later for script/font coverage.

Source keys remain English text. Context-qualified keys may be used only when
one English source has genuinely different meanings. This keeps diffs readable
and stays compatible with the design already established by `Strings`.

The application locale layer is intentionally separate from `Data.strings`.
`Data.strings` remains the translation-mod/gameplay registry.

## Fallback and formatting safety

Fallback is deterministic:

1. selected locale entry, when present and valid;
2. English source text.

A missing translation never displays an internal id or blank string.

Formatting follows the same safety property already implemented by `Strings`:
a translation with incompatible printf-style placeholders is rejected and the
English source is used instead. Invalid translations may produce an English
developer log, but must not crash the UI.

## Source-string changes and stale translations

Source-as-key means an English wording edit can orphan a translation. This is
managed by tooling and CI rather than by replacing readable sources with
hundreds of semantic ids.

Localization checks report:

- application source strings missing from a built-in locale;
- catalog entries whose English source no longer exists;
- formatting-placeholder mismatches;
- malformed/duplicate locale metadata;
- application call sites that introduce new untracked UI literals where a
  localized call is expected.

The native catalog inventory is scoped to **application-owned** sources so
battle/gameplay keys do not become required built-in translations.

## Hot language switching

Locale selection is process-global application state, but translated strings
must be looked up at draw/view-model construction time rather than frozen at
module import time.

Rules:

- do not translate module-level constants eagerly;
- descriptors that cache labels must be rebuilt or updated after locale change;
- launcher/settings panels invalidate their visible labels immediately;
- host overlays created later naturally observe the current locale;
- gameplay state and ROM-derived data are not reloaded or modified.

`AppLocale` exposes a generation counter for surfaces that need explicit cache
invalidation.

At startup the persisted `interfaceLocale` is applied before the first launcher
frame. `love.load` reads `options.lua` once and passes the same table to
`AppLocale.applyOptions` and `Orientation.applyOptions`, avoiding a second
options parse and any initial English flash.

## Fonts and Unicode

Spanish must use natural `es-ES`, including characters such as `á`, `é`, `í`,
`ó`, `ú`, `ñ`, `ü`, `¿`, and `¡` where the UI font supports them. ASCII-only
Spanish is not acceptable for normal application surfaces.

Upstream already distinguishes two relevant rendering paths:

- the launcher uses real fonts and has fallback-font work for broader Unicode;
- many gameplay/8x8 surfaces use the cartridge-style glyph/charmap system.

That distinction reinforces the application/game boundary. Native app
localization must not depend on the ROM font simply because an overlay appears
while a game is running. Host-owned overlays should use an application-capable
font path or explicit host glyph coverage.

Future locales such as Japanese or Chinese require catalog metadata/tests that
verify font coverage. Adding those locales must not require changing cartridge
text or the imported ROM.

## Architecture summary

- `AppLocale` owns built-in locale metadata and source-as-key catalogs.
- `interfaceLocale` persists in the global `options.lua` file.
- Launcher Settings exposes `Interface Language`.
- Startup applies the persisted locale before the first application frame.
- Launcher views rebuild cached labels immediately after a locale change.
- Application-owned surfaces opt into `AppLocale`; gameplay `Strings()` and
  translation-mod catalogs remain unchanged.
- Automated gates detect stale or missing keys and incompatible format
  directives.

This is intentionally not a Spanish-specific branch in the code. `es-ES` is
only the first non-English catalog.

## Tests and validation

Automated coverage includes:

- `en` by default;
- explicit `es-ES` selection;
- persistence and reload of `interfaceLocale`;
- unknown locale -> `en`;
- missing source -> English;
- formatting/placeholder safety;
- hot locale switching;
- Settings reflects the selected locale and native language names;
- persisted locale is active before the first launcher frame;
- representative launcher/import/mod/save surfaces localize;
- representative gameplay/battle/ROM text does **not** change when only
  `Interface Language` changes;
- logs remain English;
- compatibility with the current mod `Strings()` registry;
- inventory detection for new untranslated application strings;
- stale/orphan detection after an English source key changes;
- UTF-8/font coverage for built-in catalogs.

The catalog gate checks missing and stale entries, placeholder compatibility,
dynamic source markers, and high-confidence bare launcher literals. ROM-free
launcher/import/mod suites cover responsive layouts and application/gameplay
localization boundaries. Desktop and narrow/mobile validation remains useful
because translated labels expose sizing assumptions that English can hide.

## Adding a built-in locale

A contributor should need to:

1. add one locale metadata/catalog module with a canonical BCP 47 id;
2. add the locale to the application locale registry/order;
3. translate the application inventory using natural native wording;
4. preserve required placeholders;
5. ensure required UI-font glyph coverage;
6. run the localization validator and normal test suite;
7. add focused tests only when the locale introduces a new rendering or
   grammar edge case.

No gameplay ROM translation, language mod, or external pack is required.

## Upstream compatibility principles

- keep English behavior identical by default;
- do not change ROMs or save-game data;
- reuse the source-as-key approach already accepted upstream;
- do not replace the translation-mod system;
- do not globally load a native locale into `Data.strings`;
- keep commits small and reviewable;
- avoid a large external i18n dependency;
- prefer targeted application-domain migration over mass-renaming strings to
  semantic ids;
- preserve technical logs in English.
