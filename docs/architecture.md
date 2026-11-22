# Architecture

How the codebase is organised, where its seams are, and the order in which the
weak ones should be moved. This is a working document: it records the target and
the migration, not an ideal to reach in one pass.

Measured on the tree: 58 `.gd` files, 21,859 lines, three autoloads.

## 1. What is there today

The layers already exist; most of them are just not named as such.

```
common/    contracts and services   event bus, progress, save cards, stats, audio, render scale
combat/    weapons and effects      projectiles, arsenal, bomb, decoy, lock reticle
entities/  actors                   player, enemies, city props
levels/    scenario shells          arena (planet), city, cloud field
ui/        presentation             hud, menu panels
tools/     offline work             terrain bake, sfx synthesis, model probes
tests/     smoke suite              one file
```

Four ownership rules are already in force, and they are the reason the game behaves
consistently despite the size of a few files:

1. **The event bus carries lifecycle only.** `common/global_event_bus.gd` is a
   one-way feed into presentation: the HUD and the menu listen, nothing in
   gameplay listens back. Presentation never mutates gameplay.
2. **The weapon facade is the seam for shooting.** `Player` owns the input;
   `WeaponSystem` exposes `select`, `cycle`, `fire_bomb` and `drop_decoy`; every
   number a player feels lives in `combat/arsenal.gd`.
3. **The level owns the run.** An enemy emits `enemy_killed(value)` on the bus; the
   level sums it and republishes the total. Score is not a player property.
4. **Entities are built in code.** Scenes are thin (`1`–`5` nodes); hulls, meshes
   and materials are assembled in `_build_visual()`. This is deliberate and stays.

## 2. Where it hurts

Each item is a measurement, not an opinion.

### 2.1 The base class lived in the wrong file

`class_name Enemy` was declared inside `entities/enemy/turret.gd`. Every hostile —
turret, launcher, interceptor, mothership — inherited *that file*, which meant a
capital ship inherited a turret's roam/orbit state machine and overrode almost all
of it.

**Resolved in P0.** See §4.

### 2.2 The two directors were duplicated

`levels/arena/arena.gd` and `levels/city/city.gd` shared nine functions by name:

```
_ready  _physics_process  _build_environment  _maintain_population
_spawn_enemy  _spawn_angle  _planar_distance  _on_enemy_killed  score
```

Streaming rules and score accounting were written twice and kept in sync by hand.

**Resolved in P1.** See §5.1. The loop is `EncounterDirector`; the counters are
`RunState`; the levels configure both.

### 2.3 Three god objects

| File | Lines | What it holds |
| --- | --- | --- |
| `entities/player/player.gd` | 1,556 | input, both flight models, transformation state machine, dash and double-tap, aim, bank, thrusters, smoke, wingtip ribbons, materials, audio |
| `ui/menu/main_menu.gd` | 832 | navigation, options, livery preview, pad remap, save cards, pause |
| `entities/player/weapon_system.gd` | 809 | three primaries, missile radar, salvo, bomb, decoy |

### 2.4 The test was a monolith

`tests/smoke_test.gd` was 6,115 lines, 65 `_test_` functions, 714 assertions, one
process, one mutable world. It parked the encounter stream by writing
`_run_kills = -1000` and `_spawn_timer = 1e9` from the outside — a rehearsed run,
not isolated units.

**Resolved in P2.** See §5.3. The run order and every assertion are unchanged.

### 2.5 Static state cannot be injected

`GameProgress.instance().use_path()`, `SaveSlots.configure()`, `PadBindings`,
`GameSettings`: static singletons that the suite has to reconfigure before boot.

## 3. Target architecture

One sentence: **name the seams that already exist, and move the god objects down
into components.** This is a reframe, not a rewrite.

```
┌── Composition root ── main_menu.tscn / arena.tscn / city.tscn ─┐  wiring only
│                                                               │
│  Presentation      ui/hud, ui/menu panels                     │  reads events
│  Directing         EncounterDirector, RunState, BossPhase     │  spawns, scores
│  Actors            Player*, Enemy*, Projectile, BossPart      │  nodes with behaviour
│  Rules (pure)      Tuning, kill curve, spawn curve, damage    │  no nodes
│  Adapters          SaveStore, Audio, InputMap, RenderScale    │  side effects
└───────────────────────────────────────────────────────────────┘
```

**Dependency rule:** downward only. `ui → contracts`, never `ui → entities`.
`entities → rules`, never `entities → levels`. `levels → entities`. Adapters are
injected at the root and never reached for from inside.

The test that keeps the rule honest: *if a change forces you to touch two files
that do not know each other, the seam is in the wrong place.* The nine duplicated
director functions are exactly that.

## 4. Movement P0 — the hostile contract (done)

The base used to be `turret.gd`. It is now `entities/enemy/enemy.gd`, and the
hierarchy states what each hull actually is:

```
Enemy          contract: `enemy` group, `_hp`/`max_hp()`, hit flash, `killed`,
               death + explosion + score feed, lock-mark defaults, alive state
├── Turret     + hull, roam/engage state machine, ring/fan patterns
│   └── MissileEnemy   the turret's body and movement, a guided pair instead
├── FighterEnemy       the player's airframe, a missile pass and a break
└── Boss               the set piece: GLB hull, three sections, own death cascade
```

What the base owns, and why:

- `enemy` group membership, `_player`, `_find_player()`, `_visual` — every hostile
  needs the same identity.
- `max_hp()` — a turret (10), an interceptor (8), a launcher (12) and a capital
  ship (1200) do not share a hull size, so the pool is declared instead of
  inherited and overwritten.
- `take_damage()` / `_die()` — the hit flash, the hidden hull, the blast, the
  `killed` signal, the pilot record and the bus event. One death path for the
  small hulls; `Boss` overrides `_die` because a capital ship comes apart over
  twelve blasts instead of one.
- `lock_mark()`, `lock_mark_on_hull()`, `lock_mark_anchors()` — the missile lock
  contract, duck-typed before, named now.
- `_aim_beam` and `_build_aim_beam()` — the warning bar is the same mesh for a
  turret's fan, a launcher's telegraph and an interceptor's launch warning.

`MissileEnemy` moved from `extends Enemy` to `extends Turret`: its own header said
it keeps the turret's body and movement, and now the declaration says it too.

`class_name` is global, so no `.tscn` changed. The only external references that
moved were four constants in the smoke suite (`ORBIT_RADIUS`, `MAX_HP`,
`SCORE_VALUE` now read from `Turret`).

## 5. Movements P1–P3

### 5.1 EncounterDirector and RunState (done)

Extracted from arena and city into `levels/director/`:

```
EncounterDirector   population cap, spawn distance band, heading bias, despawn,
                    the separation retry, a `placer` hook and a `keeper`
                    predicate                                  (configured per level)
RunState            score, kills                              (one owner)
```

Arena and city are now configuration plus geometry. The planet sets a
single-entry roster, no placer and `keeper = enemy is Boss`; the city sets the
three-entry roster with its shares, `placer = _street_spawn`, and six attempts at
40 units of separation. Nine functions vanished from the pair.

Two things stayed in the levels because they are not stream rules: the boss
arrival (a set piece with a HUD and a lock contract) and the city's geometry.

The bonus is the fixture API the split suite needed: `director().park()`,
`director().spawn_now()`, `director().resume()` and `run_state().kills` replaced
the seven places that wrote `_spawn_timer` and `_run_kills` by name.

### 5.2 Splitting the god objects

`weapon_system.gd` is done:

```
weapon_system.gd     295  facade: bullet scene, stats, one spawn path, cone
│                          query, bomb rack, decoy clock
├ primary_fire.gd    218  vulcan / laser / plasma cadence and the lock
├ missile_radar.gd   414  pool, marks, salvo, launch, cooldown  (RefCounted)
├ beam_visual.gd      47  the drawn line, presentation only
└ lock_slot.gd        19  contact + host, now a global class
```

41 functions became 22 in the facade, and the two new pieces own no scene graph:
the rack is a clock plus a picture and the primaries are a cadence, so neither
needs a parent. `PlayerModel` had already proved the movement works.

Still pending:

```
player.gd           1,556  orchestrator: input, state, timers
├ player_flight.gd         gerwalk / fighter
├ player_actions.gd        dash, double-tap, transform, roll, i-frames
├ player_visuals.gd        thrusters, smoke, wingtip ribbons, aim beam, bank
└ player_audio.gd          hum and cues

main_menu.gd          832  panel router
├ options_panel / livery_panel / pad_panel / save_panel
```

### 5.3 Splitting the suite (done)

```
tests/smoke_test.gd              runner: boots the world, installs the suites, drives the order
tests/smoke_suite.gd             harness: world refs, `_check`, spawn/scan helpers, scratch paths
tests/suites/render_suite.gd     the resolution governor, arithmetic and state machine
tests/suites/ui_suite.gd         menus, HUD, pad panel, livery, pause overlay, radar, score
tests/suites/persistence_suite.gd  save cards and the pilot record
tests/suites/movement_suite.gd   flight, transformation, dash, afterburner, death
tests/suites/weapons_suite.gd    primaries, missile radar and lock, salvo, bomb, decoy
tests/suites/enemies_suite.gd    turret, launcher, interceptor, death blasts, mothership
tests/suites/world_suite.gd      planet roster, cloud deck, city district
tests/suites/audio_suite.gd      the synthesized palette and the mix
```

The split is mechanical and preserves the run exactly: all 65 `_test_` functions
moved verbatim, and the PASS output is byte-identical to the single-file run.

Three mechanics make that possible:

1. **The harness is a class, not a bag of statics.** `SmokeSuite` holds the world
   references, the assertions, the spawn and scan helpers, and the scratch paths.
   The runner and every suite extend it.
2. **A suite is a node in the tree.** It is added as a child of the runner, so it
   inherits `PROCESS_MODE_ALWAYS` and keeps running while the pause menu has the
   tree stopped.
3. **The world references are injected, the failures array is shared.** `_install_suite`
   points each suite at the same arena, the same ship and the same `_failures`
   instance, so `_report` sees every failure. `_died_count` stays per-suite because
   the base connects the bus itself.

Every `add_child` and `get_children()` that implicitly meant "the scene root" while
the harness *was* the scene root had to become explicit: gameplay projectiles are
parented to `get_tree().current_scene`, and the scans had to keep looking there.

Still pending from this movement: turning the hidden world hacks into fixture API.
The director half is done (`director().park()` / `spawn_now()` / `resume()`,
`run_state().kills`); what remains are the suite's spawn helpers, which build the
world through the harness instead of through a level API.

### 5.4 Injectable adapters

`GameProgress` and `SaveSlots` behind a `SaveStore` interface: `FileSaveStore` in
production, `MemorySaveStore` in tests, injected at the root. This removes the
static `configure()` calls the suite depends on today.

### 5.5 Typed payloads and separated tuning

`SlotSummary` instead of `Dictionary` for save cards; `EnemyTuning` /
`BossTuning` next to `Arsenal` so each hull's numbers have one home.

## 6. Order of attack

| Priority | Movement | Impact | Risk | Effort |
| --- | --- | --- | --- | --- |
| P0 | Hostile contract (`enemy.gd`, `Turret`) | High | Low | 3 h — **done** |
| P2 | Suite split (`smoke_suite.gd` + `tests/suites/`) | High | Medium | 1 d — **done** |
| P2 | Fixture API on top of the split | High | Low | 2 h — **done with P1** |
| P1 | `EncounterDirector` + `RunState` | High | Medium | 1 d — **done** |
| P1 | Split `player.gd` | High | Medium | 1 d |
| P1 | Split `weapon_system.gd` | Medium | Low | 4 h — **done** |
| P1 | Split `main_menu.gd` into panels | Medium | Low | 4 h |
| P2 | `SaveStore` injection | Medium | Low | 3 h |
| P3 | Typed payloads | Low | Low | 2 h |
| P3 | Separated tuning | Low | Low | 3 h |

P0 first because it unblocks the rest and changes no behaviour. P2 next, before
P1: secure the net, then cut. The suite is split; the fixture API waits for the
director to have a name to park.

## 7. What this architecture does not do

- **No ECS.** The requirement is 400 projectiles, not 100,000. Node-per-bullet is
  a documented, deliberate decision in `combat/projectile.gd`.
- **No scene explosion.** Entities built in code match the pre-rendered asset
  strategy. Only scripts split; the scene trees stay thin.
- **No DI framework.** One `Services` object on the root with four injected
  fields is enough.
- **No test rewrite.** The assertions stay; the file is split.

## 8. Progress log

| Date | Movement | State | Commit |
| --- | --- | --- | --- |
| 2026-11-21 | P0 hostile contract | Done | see `git log` |
| — | P1 encounter director | Pending | — |
