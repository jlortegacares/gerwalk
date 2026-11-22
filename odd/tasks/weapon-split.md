# The arsenal split: a facade, a cadence and a rack

Branch: `main`.
Test runner: `/Applications/Godot.app/Contents/MacOS/Godot --headless tests/smoke_test.tscn`

## Specs

**S1.** `weapon_system.gd` is a facade. It keeps what belongs to the ship as a
whole — the loaded bullet scene, the pilot's stats, the one spawn path, the cone
query, the bomb rack and the decoy clock — and delegates the rest.

**S2.** `primary_fire.gd` owns the three primaries: vulcan cadence and spread,
laser tick and hit-scan, plasma lock. `beam_visual.gd` is presentation only: two
nested additive boxes scaled along the holder's Z, so the drawn length is the
raycast's answer and nothing else.

**S3.** `missile_radar.gd` owns the rack: the cone pool, one missile loaded per
interval while the button is held, the round-robin salvo, the marks with their
tally, and the post-salvo cooldown. It is `RefCounted` and owns no tree; the spawn
path and the cone query are `Callable`s the facade assigns.

**S4.** `LockSlot` is a global class instead of an inner class of `WeaponSystem`.
Same two references, same semantics: `contact` takes the damage, `host` is what
the mark hangs from.

**S5.** The contract does not move: 8 missiles, 1.8 s to load, nearest contact
first, 55° radar cone, 48 units of range, one slot per lock anchor so a capital
ship is three targets with the 3/3/2 split, missiles leaving from the pylon they
angle towards, guidance delay and weave per shot, and the bomb and decoy
behaving exactly as before.

**S6.** The suite stops writing private fields. What it used to poke is now a
named surface: `radar().set_cooldown()`, `radar().cooldown()`,
`radar().set_loaded()`, `radar().radar_pool()`, `radar().sync_marks()`,
`radar().marks()`, `radar().active_mark()`, `radar().discharge()`,
`primary().set_cooldown()`, `set_bomb_charges()` and `reset_decoy()`.

**S7.** The suite is green on the final tree: 775 PASS, 0 FAIL, exit 0. Only the
physics-timing numbers may differ from the previous run.

## Tasks

| ID | Spec | Status | Evidence |
|----|------|--------|----------|
| T1 | S4 | done | `entities/player/lock_slot.gd`; `LockSlot` is global, `WeaponSystem.LockSlot` references updated |
| T2 | S2 | done | `entities/player/primary_fire.gd`, `entities/player/beam_visual.gd` |
| T3 | S3 | done | `entities/player/missile_radar.gd` |
| T4 | S1 | done | `entities/player/weapon_system.gd` keeps 22 functions, down from 41 |
| T5 | S6 | done | test call sites migrated in `weapons_suite`, `audio_suite`, `movement_suite`, `enemies_suite` |
| T6 | S5 | done | function bodies compared line by line against `HEAD`; only renames and callables differ |
| T7 | S7 | done | 775 PASS, 0 FAIL, exit 0; three physics-timing numbers differ, as in every run |

## Log

**L1.** Request, verbatim: "sigue" — continuing the P1 movements.

**L2.** The file was three engines wearing one coat: a cadence, a rack and a
ship-level service. Only the last one needs a node in the tree; the rack is a
clock plus a picture and the primaries are a cadence, so both moved to objects
that own state instead of scene graph.

**L3.** `LockSlot` became global because the suite types the pool
(`Array[LockSlot]`) and reading it through `WeaponSystem.LockSlot` was a
reach-through that only existed because the class was declared inside the file.

**L4.** The rack is `RefCounted` on purpose. A lock reticle hangs from the contact
it marks, not from the rack, so the rack never needed a parent. That also means
`discharge()` cannot assume its marks are alive — the original code already
handled that, and the extraction keeps it.

**L5.** Callables instead of a back-reference to the facade: `spawn` and
`enemies_in_cone` flow one way, so the muzzle and the team cannot drift between
weapons. It also keeps `PrimaryFire` and `MissileRadar` testable without a
`WeaponSystem` in between.

**L6.** The fixture API is the same principle as the director's: a test names the
action it wants (`park the cooldown`, `load two`, `drop the marks`) instead of
writing the field that happens to implement it today.
