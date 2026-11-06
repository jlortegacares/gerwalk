# Pilot progression: level, stats and a saved run

Branch: `main`. Delivery: unreviewed (runtime ineligible for immutable review).
Tests: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . tests/smoke_test.tscn`.

## Specs

S1. **The pilot has a persistent level from 1 to 100, driven by kills.** Every
   enemy destroyed adds one kill. The level is derived from the total, never
   stored separately: `kills_for_level(L) = ceil(0.045 * (L - 1)^2 + 0.55 * (L - 1))`,
   capped at 100, so level 100 is 496 kills and level 1 is zero kills.

S2. **Each level improves the ship automatically, across five tracks.** There are
   no points to spend and no upgrade menu; the bonuses are distributed at every
   level and reach these caps at level 100:
   - THRUSTERS: +20% top speed (GERWALK 26.8 -> 32.2, still below the interceptor's 34).
   - ARMOR: +8 maximum HP (6 -> 14).
   - REACTOR: +80% turbo capacity and +60% recharge.
   - AUTOLOADER: -15% primary interval (vulcan, laser tick and plasma).
   - GUNNERY: -20% vulcan spread, +20% plasma lock cone, +20% laser range.
   Weapon damage is **not** scaled: the enemies do not scale either, so damage
   growth would turn every fight into a formality.

S3. **The pilot can save a run and resume it later.** The save keeps
   `total_kills`, `last_scenario` and a `version`, in `user://progress.cfg`. The
   level and every stat are derived from `total_kills`, so there is one source of
   truth. A missing or corrupt file reads as level 1 and is never deleted.

S4. **The menu offers the saved run.** CONTINUE appears only when a save exists
   and opens `last_scenario`. A read-only PILOT panel shows the level, the kills
   and the five track values. RESET PROGRESS clears the save from that panel.

S5. **The HUD shows the level and the progress to the next one.** Both come from
   the event bus, like every other readout, and a kill updates them live.

S6. **Stats apply at the start of a run.** A level-up in the middle of a fight
   only shows in the HUD; the ship keeps the stats it started with until the next
   run, so a lucky kill never changes the fight in progress.

S7. **Nothing regresses.** The missile contract (8 missiles, 1.8 s load,
   nearest-first, 44 degree fan), the city, the audio palette and the
   death/restart loop are untouched. The smoke suite runs at level 1 with zero
   bonuses and never reads or writes the real `user://progress.cfg`.

## Tasks

| ID | Spec | Status | Evidence |
|----|------|--------|----------|
| T1 | S1, S3 | done | `common/game_progress.gd`: curve, save/load, cache, injectable path |
| T2 | S2 | done | `common/pilot_stats.gd`: five track multipliers from the level |
| T3 | S1, S5 | done | `entities/enemy/turret.gd` `_die` -> `GameProgress.register_kill`; `pilot_progress_changed` on the bus |
| T4 | S2, S6 | done | `entities/player/player.gd`: `_apply_pilot_stats()` captures speed, HP, turbo, recharge and derived drag once in `_ready` |
| T5 | S2 | done | `entities/player/weapon_system.gd`: cadence, spread, cone and range from `PilotStats`; damage untouched |
| T6 | S5 | done | `ui/hud/hud.gd`, `ui/hud/hud.tscn`, `ui/hud/level_bar.gd`: label plus progress bar, fed by the bus |
| T7 | S3, S4 | done | `ui/menu/main_menu.gd` + `.tscn`: CONTINUE, PILOT panel, two-press RESET; both levels call `remember_scenario` |
| T8 | S1-S7 | done | `tests/smoke_test.gd`: `TEST_PROGRESS` isolation, curve, save round trip, corrupt fallback, kill hook, stats, HUD, menu |
| T9 | S7 | done | `docs/combat-prototype.md`: progression section, three tuning rows, architecture map, checks comment |
| T10 | S7 | done | suite green twice: 550 `PASS`, `SMOKE TEST PASSED` on both runs |

## Log

L1. Request (as recorded in this session before the context was compacted; the
original message was in Spanish): persistent pilot progression, player level 1 to
100 driven by enemies killed, automatic growth of speed, HP, turbo, fire rate and
weapons, and a save/resume system.

L2. Design. Progression is automatic: each level spreads its bonus across five
tracks, so there is no upgrade menu and no mid-run pause. One multiplier per track
scales the existing base and keeps every ratio the game already tuned: the dash
stays 3.17x cruise, FIGHTER stays 1.8x GERWALK, and GERWALK at level 100 (32.2)
stays slower than the interceptor (34).

L3. Curve. `kills_for_level(L) = ceil(0.045*(L-1)^2 + 0.55*(L-1))` reaches 496 at
level 100. The linear term makes the first levels arrive quickly, which is what a
prototype wants: the player feels the system working inside the first fight, and
the quadratic term stretches the last third of the ladder.

L4. Save model. Only `total_kills`, `last_scenario` and `version` are stored. The
level, the kills into the level and all five track values are derived, so a save
can never hold a level that disagrees with its kill count. The file is written on
every kill and when a run starts; a corrupt file reads as zero kills and is left
on disk for inspection.

L5. "Save a game" is the persistent pilot plus the last scenario, not a mid-run
snapshot. A snapshot would have to store the arena state, the enemies, the score
and the weapons, and the prototype's runs are short enough that resuming the
scenario is the useful part. CONTINUE therefore reopens the last scenario with the
pilot's earned level.

L6. Risk: item 1 (persisted data: a new `user://` file) and item 3 (the player's
public constants `MAX_SPEED`, `MAX_HP`, `TURBO_MAX` are asserted by the suite and
read by other systems). No security, concurrency or delivery surface is touched.

L7. Implementation. `GameProgress` is a `RefCounted` with a cached static instance
and an injectable path; `PilotStats` turns a level into the five multipliers. The
player captures them once in `_apply_pilot_stats()` and hands the same object to
`WeaponSystem`, so every speed, HP, turbo, cadence and handling site reads a
runtime value while the base constants stay the public contract the suite and the
docs already reference. The kill hook lives in `Enemy._die`, next to the score
event, so it fires for every hull and every spawn path.

L8. The curve is non-decreasing, not strictly increasing: `ceil` makes some
consecutive levels share a threshold (levels 4 and 5 both at 3 kills). The test
therefore asserts the inverse as "the threshold reaches at least this level and one
kill short does not", which is the property `level_for_kills` actually has.

L9. Test isolation. `GameProgress.use_path(TEST_PROGRESS)` runs before the arena
enters the tree, so the suite never reads or writes `user://progress.cfg`; the
scratch file is deleted at the end of the run. Later tests keep killing enemies, so
the record reaches level 6 by the time the transformation checks run, but the
ship's stats were captured at run start and stay at level 1 — which is S6 proven
by the suite itself. The city test resets the record before instantiating, because
that scene captures its own stats in `_ready`.

L10. Menu. CONTINUE is visible only when the save file exists and reopens
`last_scenario`, falling back to the planet for an unknown path. The PILOT panel is
read-only and prints the level, the kills and one line per track; RESET PROGRESS
asks twice, and closing the panel disarms it. Escape closes the pilot panel the same
way it closes the options panel.

L11. Docs. `docs/combat-prototype.md` gained a Pilot progression section, three
tuning rows (`game_progress.gd`, `pilot_stats.gd`, `level_bar.gd`), the two new
files and the CONTINUE/PILOT mention in the architecture map, and the pilot
progression mention in the checks comment.

L12. Verification. The suite ran green twice in a row: 550 `PASS`,
`SMOKE TEST PASSED`, no scratch save left behind. One earlier run printed the
fighter bleed check at 0.45 s instead of 0.35 s; three instrumented runs measured
exactly 21 frames with level 1 runtime stats (`speed 48.20`, `drag 82.63`,
`stall 19.28`), and two further clean runs followed, so the single slow reading was
not reproducible and no ship value differed from the baseline.
