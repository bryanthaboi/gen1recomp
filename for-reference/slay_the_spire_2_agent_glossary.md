# Slay the Spire 2: terminology guide for agents

Scope: the 580-card repository snapshot for game version **0.107.1**, database version **2**. This is a reading guide to terms occurring in card metadata, English descriptions, and keyword/upgrade fields. It is not a complete combat simulator specification.

Terms were collected from explicit keyword arrays, highlighted text, and a scan of the resolved descriptions. Ordinary card titles are not automatically mechanics. Definitions absent from the repository are explanatory context; external references may describe newer patches. Verify exact timing, stacking, and numeric rules against the matching game version before simulating combat.

## 1. Explicit card keywords

Counts are distinct source records with the keyword in base keywords, added keywords, or removed keywords. They include upgrade-only occurrences; they do not count every prose mention.

| Keyword | Records | Meaning |
|---|---:|---|
| Exhaust | 99 | Leaves normal circulation for this combat; an Exhaust card normally exhausts when played. |
| Unplayable | 26 | Cannot be played normally. |
| Innate | 24 | Starts combat in your opening hand. |
| Retain | 23 | Avoids the normal end-of-turn discard. |
| Ethereal | 18 | Exhausts if still in hand at turn end. |
| Sly | 8 | Discarding it before turn end plays it free. |
| Eternal | 7 | Cannot be removed or transformed from the deck. |

Keyword definitions: [Spire Codex keyword reference](https://spire-codex.com/guides/keywords-guide). Explicit card effects can create exceptions: Bombardment plays from the Exhaust Pile, for example. Exhausting does not permanently delete a card from the run's deck. Retain and Ethereal are separate properties, not opposite ends of one flag.

## 2. Buffs, debuffs, and effect terminology

| Term | Meaning / interpretation |
|---|---|
| Strength | Adds attack damage, generally per hit. |
| Dexterity | Modifies Block gained from cards. |
| Block | Temporary damage protection; normally expires at the next turn's start. |
| Weak | Reduces attack damage. |
| Vulnerable | Increases attack damage received. |
| Frail | Reduces Block gained from cards. |
| Poison | Periodic HP loss that bypasses Block; its stacks decay. |
| Thorns | Retaliatory damage when attacked. |
| Intangible | Limits incoming damage/HP loss to 1. |
| Vigor | Extra damage for the next Attack. |
| Artifact | Negates a debuff application. |
| Focus | Modifies Orb effectiveness. |
| Plating | End-of-turn Block with a decaying stack count. |
| Doom | Execution threshold checked against current HP at enemy-turn end. |
| Stun | Prevents the enemy's next action. |
| Replay | Additional plays of the affected card. |

For Block, Strength, Dexterity, Weak, Vulnerable, Frail, Poison, and Thorns, see [SpireForge's mechanics reference](https://spireforge.app/guides/keywords-and-mechanics). For Intangible, Vigor, Artifact, Focus, Plating, Doom, Stun, and Replay, see [Spire Codex](https://spire-codex.com/guides/keywords-guide). These sources are context, not a replacement for version-matched rules.

Additional distinctions to explain:

- **Buff / debuff / stack:** an effect and its accumulated amount. Some amounts represent duration, others magnitude or charges; do not assume all stacks decay alike. Rend counts unique debuffs, not their summed amounts.
- **Fatal:** a kill-conditioned bonus, used by Feed, Hand of Greed, and The Hunt. The repo does not define eligibility exceptions; verify those before equating it with every instance of “kills an enemy.”
- **Damage / attack damage / unblocked damage / lose HP:** preserve the wording. These can interact differently with Block and damage modifiers. Capture Spirit explicitly causes HP loss; Envenom requires unblocked Attack damage.
- **Hit versus play:** Twin Strike hits twice within one play. Replay creates extra plays. Trigger counts must preserve that distinction.
- **Power card versus power effect:** `type: Power` classifies a card; an internal variable ending in `Power` can instead represent a buff or debuff. `WeakPower` does not make its card a Power card.
- **Named ongoing effects:** names such as Barricade, Buffer, Accuracy, Afterimage, Corruption, and Wraith Form can denote cards and their associated effects. Use each card's description for its effect; do not treat every Power-card title as a universal keyword.

## 3. Resources and character mechanics

| Term | What an agent needs to know | Dataset examples |
|---|---|---|
| Energy | The ordinary resource used to pay card costs. | Adrenaline, Offering |
| X / X-cost | Variable payment/effect; the CSV represents source cost `-2` as `X`. Evaluate each card's wording, including upgrades such as X+1. | Whirlwind, Multi-Cast, Dirge |
| Free to play / costs 0 | Cost-modifying wording. Preserve its duration and conditions; do not assume all “free” effects rewrite printed cost. | Bullet Time, Void Form |
| Stars / Star | Regent resource separate from Energy. Star icons appear in text. The supplied JSON has no separate star-cost field, so the CSV's Energy Cost is not a complete account of Regent card costs. | Venerate, Crescent Spear |
| Forge | Builds damage on Sovereign Blade; initial creation and subsequent improvements are part of the mechanic. | Bulwark, Furnace |
| Sovereign Blade | Regent's named Attack token. Its baseline row does not include Forge accumulated during combat or modifications from other cards. | Parry, Seeking Edge, Sword Sage |
| Osty | Necrobinder's companion, with its own HP, Max HP, alive/dead state, and attacks. | Poke, Sacrifice, Protector |
| Summon | Brings back or strengthens Osty. Do not interpret it as generic creation of any named “Minion” card. | Bodyguard, Afterlife |
| HP / Max HP / heal | Current health, its upper limit, and restoration. Cards distinguish Osty's current HP from his Max HP. | Unleash, Protector, Spur |
| Gold | Run currency. | Hand of Greed, Royalties |

Forge context: [Spire Codex](https://spire-codex.com/guides/keywords-guide). Summon/Osty context: [Necrobinder guide](https://slayspiredb.com/guides/necrobinder-guide-osty-summon-souls-and-doom-in-slay-the-spire-2). Stars context: [SpireForge](https://spireforge.app/guides/keywords-and-mechanics). Exact companion damage routing and resource retention rules are not supplied by the card JSON files.

## 4. Defect's Orb vocabulary

| Term | Reading guide |
|---|---|
| Orb / Orb Slot | A combat object and the capacity to hold it. |
| Channel / Channeled | Create an Orb in the Orb system. |
| Evoke | Activate an Orb's evoke effect, ordinarily consuming it. |
| Passive ability | An Orb effect that operates without an ordinary Evoke. |
| Rightmost Orb | The position explicitly targeted by Dualcast, Multi-Cast, and Quadcast; preserve positional wording. |
| Lightning | Damage Orb. |
| Frost | Block Orb. |
| Dark | Accumulates damage for an eventual Evoke. |
| Plasma | Energy Orb. |
| Glass | Damage-to-all Orb whose effectiveness declines over time. |

Orb types, passive effects, and evoke effects are separate concepts. The card dataset references them but does not store their full definitions. For context see the [Orb mechanics reference](https://spire-codex.com/mechanics/orb-mechanics). Do not import precise Orb base values or Focus formulas from a different patch without checking.

## 5. Card movement, modification, and timing

| Term | Interpretation |
|---|---|
| Deck | The run's owned card collection; distinguish it from the current Draw Pile. |
| Hand | Cards currently held. |
| Draw Pile | Cards available to be drawn in combat. |
| Discard Pile | Combat discard destination. |
| Exhaust Pile | Combat exhaust destination; some cards explicitly interact with it. |
| Draw | Draw action, which can trigger “whenever you draw” effects. |
| Put / return / add into Hand | Movement or creation; do not silently rewrite these as drawing. |
| Discard | Sends a card from hand to discard; distinguish active discard from end-of-turn discard, especially for Sly. |
| Create / add a card / copy | Produces another card instance; inspect text for destination and duration. Arsenal and Pillar of Creation care about creation. |
| Transform | Replaces a card with another. Several Regent cards specify the replacement; Entropy does not name one. |
| Remove from Deck | Persistent deck removal, unlike ordinary combat Exhaust. |
| Upgrade / Upgraded / + | Uses the upgraded form. Can change cost, keywords, values, or wording—not just damage. |
| Permanently | A lasting change to the card, explicitly used by Genetic Algorithm and The Scythe. |
| This turn / next turn / this combat | Separate effect lifetimes. Preserve them exactly. |
| Start / end of turn or combat | Different trigger windows. Ordering is not fully specified in the dataset. |
| Every N / first / whenever / already | Trigger or counter conditions; card text specifies which event is counted. |
| ALL / random / choose / up to | Scope and selection rules; capitalization emphasizes scope rather than defining a separate keyword. |

Examples and distinctions above are grounded in the local card descriptions. The repository does not supply a complete event-ordering engine.

## 6. Named cards and special modifiers referenced by other cards

These are named card objects or modifiers, rather than interchangeable resource counters. Look up their own card rows when resolving another card's effect.

| Term | Meaning in this dataset |
|---|---|
| Shiv / Shivs / Shiv+ | Attack token; baseline Exhaust and 4 damage. |
| Soul / Souls / Soul+ | Skill token; baseline Exhaust and draw 2. It is a card, not a scalar “soul” resource. |
| Inky | Modifier on the Shivs generated by Blade of Ink. Its effect is not defined in the JSON. |
| Minion Strike | Attack token; Exhaust, damage, and card draw. |
| Minion Dive Bomb | Attack token; Exhaust and damage. |
| Minion Sacrifice | Skill token; Exhaust and Block. |
| Fuel | Skill token; Exhaust, Energy, and card draw. |
| Giant Rock | Named Attack token generated by Primal Force. |
| Sweeping Gaze | Named Osty Attack token generated by Sentry Mode. |
| Debris | Status card generated by Collision Course and Crash Landing. |
| Dazed | Ethereal, Unplayable Status card. |
| Wound / Wounds | Unplayable Status card. |
| Burn | Unplayable Status card with an end-of-turn in-hand damage effect. |
| Slimed | Status card with Exhaust and draw 1 in this snapshot. |
| Void | Unplayable, Ethereal Status card that loses Energy when drawn. |
| Soot, Infection, Wither, Toxic, Beckon | Other Status-card names. Their effects differ; look up the corresponding rows. |
| Disintegration, Mind Rot, Sloth, Waste Away, Luminesce | Other named Token-category records. Token is a category/rarity here, not one uniform effect. |
| Strike / Defend | Shared card names with separate character-specific records. Do not deduplicate by display name. Perfected Strike also checks names containing “Strike.” |

The [Inky reference](https://slaythespire.wiki.gg/wiki/Enchantment) and [Blade of Ink reference](https://slaythespire.wiki.gg/wiki/Slay_the_Spire_2%3ABlade_of_Ink) describe its Weak-related effect, but published damage details vary by patch. **The exact 0.107.1 Inky modifier remains unverified here.** Do not derive it from the ordinary Shiv row.

## 7. Run, event, and multiplayer vocabulary

| Term | What to explain |
|---|---|
| Act | A run segment; Quest-card text can reference the next Act. |
| Rest Site | A map location; Byrdonis Egg can hatch there. |
| Event | A special encounter/context, also used as a repository category and rarity. |
| Potion / procure | Alchemize creates a random potion; the potion definitions are outside this repo. |
| Card reward | A post-combat card-selection reward; The Hunt can add one. |
| Sandpit | Encounter-specific state referenced by Frantic Escape. Its complete rules are absent. |
| Byrdonis Egg / Lantern Key / Spoils Map | Quest-card names, carrying run/event effects rather than normal playable effects. |
| Mad Science | Customizable Event card whose default type and effects are unspecified in the source. |
| Deprecated Card | Placeholder for a removed card, not a normal collectible-card specification. |
| Other player / ally / ALL players / ANYONE | Multiplayer scope. Do not replace every ally reference with Osty or assume “other players” includes self. |
| Redirect / incoming attacks | Changes who receives an attack; used by Intercept. Exact damage-routing rules need game logic. |

## 8. Metadata and parsing vocabulary for a future agent

- **Characters:** Ironclad, Silent, Defect, Necrobinder, Regent. Other values in the Character CSV column preserve source categories: Colorless, Curse, Event, Quest, Status, Token, Deprecated.
- **Types present:** Attack, Skill, Power, Curse, Status, Quest, Unknown. Type and character/category are independent fields.
- **Rarity values present:** Basic, Common, Uncommon, Rare, Ancient, Curse, Status, Quest, Event, Token, Deprecated, Unknown. Several are special classification labels, not positions on an ordinary rarity ladder.
- **Target values:** Self, AnyEnemy, AllEnemies, RandomEnemy, AnyAlly, AllAllies, None, Unknown, and an empty value. Treat empty as missing. `None` does not mean Unplayable. Read the description alongside metadata when determining effect recipients.
- **`key` versus `name_eng`:** the key uniquely identifies a source card; names can repeat across characters.
- **`variables` / `varChange`:** base numeric values and upgrade deltas. Apply a delta once. Some delta names omit `Power` (for example Strength → StrengthPower).
- **`18m`:** C# decimal-literal syntax meaning 18, not a multiplier or unit.
- **`diff()` / `inverseDiff()`:** display-format functions; use the resolved value rather than treating them as gameplay subtraction.
- **`plural`, `show`, `choose`:** template branch/grammar operators.
- **`IfUpgraded`:** selects base versus upgraded text.
- **`InCombat` / `IsTargeting`:** conditional previews that depend on combat state; omitted from default descriptions.
- **`Calculated…` / `CalculationBase`:** dynamic result and its default base. A default CSV value is not a live combat prediction.
- **`energyIcons`, `starIcons`, `singleStarIcon`:** display icons. A single energy icon may follow an already-written number; avoid generating “0 1 Energy.”
- **`[gold]`, `[purple]`, `[blue]`:** presentation markup. Gold text can highlight a mechanic, card name, zone, or other term; it is not itself proof of keyword membership.
- **Negative cost sentinels:** `-2` means X; `-1` is represented as N/A in the CSV. Do not treat either as literal negative Energy payment.
- **Missing rules:** this dataset does not contain full keyword tooltips, Orb definitions, enchantment definitions, enemy logic, or complete resource costs. Preserve uncertainty rather than inventing defaults.

## Suggested handoff instruction

Read this glossary alongside the card CSV. Use the repository's versioned card values as the card-data source. Preserve distinctions among play, hit, draw, movement, creation, discard, Exhaust, and permanent removal. Resolve named generated cards through their own records. Consult version-matched game rules for mechanics not defined by the dataset, especially Inky, Sandpit, Orb effects, Star costs, targeting, and trigger order. Do not assume Slay the Spire 1 mechanics or a newer patch apply unchanged.
