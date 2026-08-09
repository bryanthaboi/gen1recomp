# Contributing interface translations

Gen1Recomp can include more interface languages alongside English and Spanish.
Contributions are welcome from fluent translators and reviewers.

Interface translations cover the launcher, Settings, ROM and save import,
save slots, the mod browser, notices, and other text written by Gen1Recomp.
They do not translate a Pokémon ROM, gameplay dialogue, names, moves, Pokédex
entries, or text supplied by a mod. Never upload or share a ROM as part of a
translation contribution.

## Before you start

- Check whether somebody is already working on the language. Opening an issue
  or a draft pull request early helps contributors avoid doing the same work
  twice.
- State the language and regional variant you intend to translate, such as
  French for France (`fr-FR`). Some languages need more than one regional or
  writing-system variant.
- A translation must be written or reviewed by a fluent speaker.
  Machine-generated or word-for-word text is not ready for inclusion without
  fluent human review. If that review is still pending, say so clearly when
  submitting the work.

## Translate the catalog

The Spanish catalog at [`src/locales/es_es.lua`](../src/locales/es_es.lua) is a
complete example. Copy it to a file named for the new language, update its
`id` and `name`, and translate the values on the right:

```lua
return {
  id = "fr-FR",
  name = "Français",
  strings = {
    ["Delete"] = "Supprimer",
  },
}
```

The English text inside square brackets is the catalog key and must stay
unchanged. Translate only the value after `=`. Use natural wording rather than
translating each word literally.

Keep formatting markers such as `%s`, `%d`, and `\n` in every translated value.
They are replaced with names, numbers, or line breaks while the application is
running. Save the file as UTF-8 so accents and other characters are preserved.

A translation-only contribution may be submitted as a plain-text catalog in an
issue. The application integration and validation can then be completed as a
separate step. Do not submit a ROM, save file, or mod.

## Submit and review

A complete language contribution should include:

1. the translated catalog;
2. the language added to the interface-language list;
3. automated catalog checks;
4. a manual check at desktop and narrow window sizes;
5. confirmation that switching languages works immediately and after a
   restart;
6. a note identifying the fluent-language reviewer, or stating that review is
   still needed.

Languages using a new writing system may need additional font work. For
example, Chinese, Japanese, or Korean must be checked for missing glyphs and
readability throughout the interface. A translated catalog alone cannot prove
that those languages render correctly.

The technical architecture, boundaries, and validation rules are described in
[Native application localization](localization.md).
