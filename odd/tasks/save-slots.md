# Multiple save cards

Branch: `main`. Delivery: `single-pr`. Tests:
`/Applications/Godot.app/Contents/MacOS/Godot --headless tests/smoke_test.tscn`.

Objective: turn the single pilot record into six save cards, like a console memory
card, and make CONTINUE the door to picking one.

## Specs

S1. **Multiple saves.** Requested verbatim: "necesito que el juego guarde
multiples partidas como una memorycard ps5. analiza y proponeme como aplicarlo".
The game keeps several independent pilots instead of one file.

S2. **CONTINUE opens the list.** Answered verbatim: "CONTINUE abre la lista y
elegís qué partida cargar". CONTINUE is always offered at boot (an empty card is
how a second pilot is created), it opens a card list, and the chosen card is the
one that loads. On the pause screen CONTINUE stays hidden: a run already belongs
to a card and is not swapped in flight.

S3. **A card is a pilot.** Each card stores exactly what the record stores today:
`total_kills` and `last_scenario`, plus `last_played` (unix seconds). The level
and every bonus stay derived from the kills. Version rises to 2; a version-1 file
reads unchanged because everything it lacks has a default.

S4. **Six cards, one file each.** `user://saves/pilot_1.cfg` .. `pilot_6.cfg`.
The active card lives in `settings.cfg` under `[save] active_slot`, a section
that file already preserves alongside `[display]`, `[livery]` and `[pad]`.
Instructions outside the active card (livery, pad, fullscreen) stay global.

S5. **The old save migrates once.** If `user://progress.cfg` exists and no card
exists, it is copied to card 1 and the original is renamed to
`user://progress.cfg.imported`. The backup blocks any second import, so erasing
card 1 later cannot resurrect the old file. The original is renamed, never
deleted, so it can be inspected.

S6. **The card panel.** Opened from CONTINUE, it shows a 3x2 grid of cards naming
slot, level, kills, scenario and date, or `EMPTY SLOT`. Pressing a card selects
it; the action row then offers `LOAD` + `DELETE` for an occupied card and
`START PLANET` + `START CITY` for an empty one. DELETE asks twice. BACK, Escape
and the pad's cancel close the panel. The active card is marked on its card and
on a line under the menu tagline.

## Tasks

| ID | Spec | Route | Status | Evidence |
| --- | --- | --- | --- | --- |
| T1 | S1, S3, S4, S5 | inline | done | `common/save_slots.gd`, `GameProgress` version 2 + `last_played`; `_test_save_slots` covers two cards, the pointer, delete, clamping and the one-shot import |
| T2 | S2, S6 | inline | done | `%Saves` panel, `%SlotLine`, `%Slots`/`%SlotPrimary`/`%SlotSecondary`/`%SavesBackButton`; CONTINUE opens the list at boot and stays hidden in pause |
| T3 | S1–S6 | inline | done | smoke suite: 767 PASS / 0 FAIL |
| T4 | — | inline | done | `docs/combat-prototype.md`: Run it, Pause, Pilot progression, Save cards, Architecture, Tuning knobs, Checks |

## Log

L1. User request, verbatim: "necesito que el juego guarde multiples partidas como
una memorycard ps5. analiza y propone como aplicarlo". Analysis only; no
implementation was authorized yet.

L2. Analysis delivered. The game has no mission state to serialize: the arena is
regenerated and enemies stream, so a "save" is the pilot record, not a midpoint.
Proposed six cards, one file each, the active card in `settings.cfg`, and a
migration that renames rather than deletes.

L3. Flow decision, verbatim: "CONTINUE abre la lista y elegís qué partida
cargar". CONTINUE stops hiding itself and becomes the way into the card list.

L4. Implementation authorized, verbatim: "arranca".

L5. Pressing a card only selects it; `LOAD`/`START` is what marks it active and
opens the scene. This keeps DELETE reachable: a one-press load would leave no
moment in which a card is chosen but not yet opened. The deviation from the
sketch is one extra press, not a different contract.

L6. A card's directory is created when a card is selected, not only when the old
save is imported. Without it the first write to an install that never had an old
save went to a missing directory, `ConfigFile.save()` failed silently and every
card read back empty; the suite caught it as a card that would not delete.

L7. The pause screen skips `SaveSlots.ensure()` because a run in flight already
owns a record: re-pointing the file underneath it would swap the pilot the HUD is
showing.

L8. Verified: 767 PASS / 0 FAIL in the headless suite (+32 over the 735 baseline).
Panel rendered at 1280x720 and reviewed: three columns of cards, the active card
in the accent colour, LOAD/DELETE switching to START PLANET/START CITY on an
empty card, BACK below. Rendering the panel alone touches `user://`; the shot was
taken with `SaveSlots.configure()` pointed at scratch cards.

