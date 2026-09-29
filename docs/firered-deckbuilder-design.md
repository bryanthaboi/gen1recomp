# FireRed Deckbuilder: Initial System Design

Status: Initial design; incomplete and not yet an implementation specification.
Last updated: 2026-09-29.

## Project Goal

Replace FireRed's conventional battle mechanics and movesets with a turn-based
deckbuilding combat system. Each Pokemon has its own deck and grows that deck
through level-up card rewards. Rework items to support the new combat system.

Development takes place in the `imp-tea/gen1recomp` fork, initially on
`codex/firered-deckbuilder`. The target is the Lua/LOVE application, not a
modified GBA ROM.

This document records the decisions made so far. Sections marked as open
questions do not establish rules. Further design conversations will refine this
document before implementation.

## Combat Baseline

Use near one-to-one parity with the general combat components and flow of
Slay the Spire 2 as the starting design reference: a five-card hand, draw pile,
discard pile, exhaust pile, attacks, block, and energy spent to play cards.
Specific cards, character features, and unique character mechanics are not the
intended reference.

This is a statement of design intent, not a verified inventory of that game's
rules. Exact resource values, draw and discard timing, and effect lifetimes
still need to be specified. The confirmed departures below take precedence
over the reference, especially simultaneous turns and individual Pokemon decks.

## Confirmed Rules

### Active Pokemon and Parties

- Battles are strictly one active Pokemon versus one active Pokemon.
- All other Pokemon in each party remain on the bench.
- Each Pokemon has its own deck, rather than contributing to a shared party deck.
- Opposing Pokemon also have individual decks and use the same general combat
  system as the player.

### Card Pools and Progression

- Each type has a pool of cards.
- Each Pokemon has access to a subset of cards from the relevant pools.
- Each time a Pokemon levels up, it receives a card reward to add to its deck
  instead of learning a conventional move.
- Reward choice structure, skipping rewards, starting decks, and deck editing
  rules remain undecided.

### Voluntary Switching

- Switching is allowed at the beginning of a turn, after drawing cards.
- A side may voluntarily switch only once per turn.
- Switching must happen before any cards are played that turn.
- Switching costs no energy.
- Switching is therefore a decision the player can make with knowledge of the
  current active Pokemon's drawn hand.

The meaning of "before any cards are played" must be made precise when the
simultaneous-turn planning and resolution rules are defined. Forced replacement
after fainting is not yet specified by these voluntary-switch rules.

### Deck State While Benched

- A benched Pokemon preserves its draw, discard, and exhaust piles throughout
  the battle.
- If a Pokemon switches out with a drawn hand, it retains that hand when it
  returns to the field.
- Status cards remain in the deck of the Pokemon that acquired them; they do not
  transfer to the incoming Pokemon when switching.

For example, if Pokemon A draws a hand and switches to Pokemon B without playing
any cards, A's hand is preserved on the bench. When A returns, it still has that
hand. Whether returning also triggers any additional draw is an open question.
Persistence of status cards between separate battles is also undecided.

### Simultaneous Turns and Card Order

- Both combatants play their full turns simultaneously, rather than using a
  player turn followed by an enemy intent being executed.
- Enemy intents are not displayed.
- Card play order depends on both the acting Pokemon's Speed stat and the
  priority level of the card.
- Cards have priority levels, with the priority concept inspired by moves in
  TemTem.

The exact priority model is not yet selected. In particular, no additive,
multiplicative, or priority-bracket formula has been approved. The relationship
between selecting cards and resolving their effects remains open; simultaneous
turns do not yet imply a particular queue, lock-in, or reveal implementation.

### Opponent AI

- Opponents play cards from their Pokemon's decks, rather than executing a
  separate scripted intent system.
- Build a general-purpose AI capable of playing hands effectively within the
  new combat rules.
- The intended outcome is satisfying opposition; the AI architecture and
  difficulty controls have not yet been selected.

### Items

- Rework items to fit the new battle system.
- Specific item effects, use costs, timing, and limits remain open.

## Questions for the Next Design Rounds

### Simultaneous Selection and Resolution

- Do both sides select and commit an entire ordered sequence before resolution,
  or are cards selected in smaller steps?
- How much of the opponent's hand, selected cards, and resource state is visible,
  given that intents are not displayed?
- Is a player's chosen sequence preserved, or can priority reorder their own
  cards as well as interleave cards from the opposing side?
- How do card priority and Pokemon Speed combine? How are ties resolved?
- When are energy costs paid, targets validated, and effects applied?
- How do draws, generated cards, energy gains, and conditional effects work
  during a turn whose other actions may already be selected?
- What happens to a queued card when its user faints, its target changes, or its
  requirements are no longer met?

### Switching and Drawing

- Does an incoming Pokemon with a retained hand use that hand without drawing?
- What does a Pokemon draw on its first entry into battle?
- What happens when an incoming Pokemon's retained hand has fewer or more than
  five cards? Is five a draw amount, target hand size, or hand limit?
- When do both sides declare and reveal switches relative to card selection?
- How does forced replacement after fainting interact with the once-per-turn
  voluntary-switch limit and unresolved cards?

### Resources and Persistence

- How much energy is available each turn, when does it refresh, and is it tracked
  per side or per Pokemon?
- When are unplayed cards discarded, and how does that timing interact with a
  hand preserved on the bench?
- When is the discard pile shuffled into the draw pile?
- When does block expire? Does it persist while benched?
- Which buffs, debuffs, and status effects tick or expire on the bench?
- Which state persists between battles, including HP and status cards?

### Pokemon Identity and Progression

- How do Pokemon stats other than Speed affect cards, damage, and defense?
- How do type effectiveness, dual types, and abilities work?
- What determines a species' card access and starting deck?
- How many card choices appear on level-up, and may rewards be skipped?
- How do evolution, card upgrades, duplicate cards, and card removal work?
- How are decks generated for wild Pokemon, trainers, and newly caught Pokemon?

### Encounter Rules, Items, and AI

- How do catching, fleeing, victory, defeat, and experience awards work?
- When can items be used, and do they consume energy or another resource?
- What information may the AI use when choosing cards and switches?
- How should difficulty vary across wild Pokemon, ordinary trainers, and bosses?

## Implementation Scope to Revisit After Design

The design will require card definitions and effects, per-Pokemon deck storage,
combat piles and hands, simultaneous-turn resolution, switching, opponent AI,
card rewards, item behavior, battle UI, and save-data support.

The intended integration is to enter the new combat system from FireRed's
existing encounters and return the results to the overworld. Exact integration
points and the division between engine changes and mod APIs require a code
review once the mechanics are sufficiently defined.

No combat implementation, final balance values, or AI algorithm is approved by
this initial document. The next milestone is a coherent system overview that
resolves the questions above, followed by a small playable battle prototype.
