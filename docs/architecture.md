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

### 2.2 The two directors are duplicated

`levels/arena/arena.gd` and `levels/city/city.gd` share nine functions by name:

```
_ready  _physics_process  _build_environment  _maintain_population
_spawn_enemy  _spawn_angle  _planar_distance  _on_enemy_killed  score
```

Streaming rules and score accounting are written twice and kept in sync by hand.

### 2.3 Three god objects

| File | Lines | What it holds |
| --- | --- | --- |
| `entities/player/player.gd` | 1,556 | input, both flight models, transformation state machine, dash and double-tap, aim, bank, thrusters, smoke, wingtip ribbons, materials, audio |
| `ui/menu/main_menu.gd` | 832 | navigation, options, livery preview, pad remap, save cards, pause |
| `entities/player/weapon_system.gd` | 809 | three primaries, missile radar, salvo, bomb, decoy |

### 2.4 The test is a monolith and it is the only safety net

`tests/smoke_test.gd`: 6,115 lines, 65 `_test_` functions, 714 assertions, one
process, one mutable world. The suite parks the encounter stream by writing
`_run_kills = -1000` and `_spawn_timer = 1e9` from the outside — it drives a
rehearsed run, not isolated units. It works, and it is what protects every change,
which is exactly why it must be split before the god objects are.

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

### 5.1 EncounterDirector and RunState

Extract from arena and city into `levels/director/`:

```
EncounterDirector   population, spawn distance/heading, despawn, spawn-ahead,
                    the roster and its shares               (configured per level)
RunState            score, kills, boss_spawned, boss ref   (one owner)
```

Arena and city become data plus geometry: roster, distances, and a `spawn_point`
hook (the city snaps to a street crossing, the planet does not). This deletes the
nine duplicated functions and makes score live in one place.

### 5.2 Splitting the god objects

```
player.gd            ~250  orchestrator: input, state, timers
├ player_flight.gd         gerwalk / fighter
├ player_actions.gd        dash, double-tap, transform, roll, i-frames
├ player_visuals.gd        thrusters, smoke, wingtip ribbons, aim beam, bank
└ player_audio.gd          hum and cues

main_menu.gd         ~150  panel router
├ options_panel / livery_panel / pad_panel / save_panel

weapon_system.gd     ~350  facade
├ primary_fire.gd          vulcan / laser / plasma
├ missile_radar.gd         pool, marks, salvo, launch
└ beam_visual.gd
```

`PlayerModel` already proves the split works: the airframe left `player.gd` and
nothing hurt.

### 5.3 Splitting the suite

```
tests/smoke_test.tscn       runner: order, exit code
tests/world_fixture.gd      boots the arena, exposes clear(), park_stream(), spawn_turret()
tests/suites/movement.gd
tests/suites/weapons.gd
tests/suites/enemies.gd
tests/suites/ui.gd
tests/suites/persistence.gd
```

Same integration value, no 6k-line file, and `park_stream()` becomes fixture API
instead of a hidden hack.

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
| P0 | Hostile contract (`enemy.gd`, `Turret`) | High | Low | 3 h |
| P1 | `EncounterDirector` + `RunState` | High | Medium | 1 d |
| P1 | Split `player.gd` | High | Medium | 1 d |
| P1 | Split `weapon_system.gd` | Medium | Low | 4 h |
| P1 | Split `main_menu.gd` into panels | Medium | Low | 4 h |
| P2 | Suite split + fixture | High | Medium | 1 d |
| P2 | `SaveStore` injection | Medium | Low | 3 h |
| P3 | Typed payloads | Low | Low | 2 h |
| P3 | Separated tuning | Low | Low | 3 h |

P0 first because it unblocks the rest and changes no behaviour. P2 before P1 when
the time comes: secure the net, then cut.

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
