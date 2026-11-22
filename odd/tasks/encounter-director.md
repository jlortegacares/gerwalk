# Encounter director: one stream loop, two scenarios

Branch: `main`.
Test runner: `/Applications/Godot.app/Contents/MacOS/Godot --headless tests/smoke_test.tscn`

## Specs

**S1.** The stream loop exists once. Population cap, spawn distance band, heading
bias, despawn radius and the retry that keeps a contact off the ship live in
`levels/director/encounter_director.gd`. `arena.gd` and `city.gd` configure it
instead of implementing it.

**S2.** Only roster and placement differ. The planet streams interceptors and
nothing else; the city streams turret, launcher and interceptor at the same shares
as before. The planet spawns at a polar offset; the city snaps to a street
crossing and keeps its separation retry.

**S3.** The run's counters exist once. Score and kills live in
`levels/director/run_state.gd`; a hull kill and a tower demolition both pay
through it, and the boss threshold reads the same counter it read before.

**S4.** No behaviour change. The seeded sequence produces the same spawns in the
same order, the mothership still arrives on the same kill count and is still
exempt from the despawn, and the opening contact of each scenario is the hull it
was forced to be.

**S5.** The private-state hacks are gone. The suite and the capture tool no longer
write `_spawn_timer` or `_run_kills` by name; they call `director().park()`,
`director().spawn_now()`, `director().resume()` and `run_state().kills`.

**S6.** The suite is green on the final tree: 775 PASS, 0 FAIL, exit 0.

## Tasks

| ID | Spec | Status | Evidence |
|----|------|--------|----------|
| T1 | S1, S3 | done | new `levels/director/encounter_director.gd`, `levels/director/run_state.gd` |
| T2 | S2 | done | arena: single-entry roster, no placer, `keeper` exempts `Boss`; city: three-entry roster with shares, `placer = _street_spawn`, 6 attempts at 40 u |
| T3 | S3 | done | arena `_on_enemy_killed` → `_run.add_kill`; city kills and demolitions → `_run.add_score` |
| T4 | S4 | done | hull is rolled before the bearing, so the seeded order is unchanged |
| T5 | S5 | done | 7 call sites moved off private fields: `smoke_test.gd`, `enemies_suite.gd` ×2, `world_suite.gd` ×2, `ui_suite.gd` ×2, `capture_frame.gd` |
| T6 | S6 | done | `SMOKE TEST PASSED`, 775 PASS, 0 FAIL |

## Log

**L1.** Request, verbatim: "sigue" — continuing the architecture plan. P2 (suite
split) was done first on purpose: it is the net this refactor is checked with.

**L2.** The two directors were **not** identical, and the differences are real:
the planet has no roster roll, no geometry to snap to, and a hull that must never
be despawned; the city has three archetypes, snaps to streets and retries six
bearings to avoid landing on the ship. Those became configuration (roster +
shares, a `placer` callable, `min_spawn_separation` / `spawn_attempts`, a `keeper`
predicate) instead of subclassing, because neither level is a variant of the other:
they are two arrangements of the same rules.

**L3.** RNG order is part of the contract. The city rolled the hull **before** the
bearing (`_pick_enemy_scene()` then `_spawn_point()` in argument order), so
`spawn_next()` rolls the hull first too. Reversing it would have produced a
different seeded layout with identical code paths, which is the kind of change that
never shows up in a test and always shows up in a capture.

**L4.** `spawn_opening()` exists because a scenario's first contact is a lesson,
not a roll: the planet forces an interceptor, the city forces a turret, and neither
consumes randomness, exactly as before.

**L5.** `park()` stops production but not the cull, which is what
`_spawn_timer = 1e9` actually did. A test that parks the stream still wants strays
cleaned up.

**L6.** Not done here: the boss arrival itself stays in `arena.gd`. It is a set
piece with a HUD contract, a lock-anchor contract and a bar, not a stream rule.
Only its heading comes from the director now.
