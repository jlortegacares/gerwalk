# Planet boss: the mothership

Feature: a final boss for the planet scenario. One capital ship, built from the
`models/boss-1` GLB, that flies slowly over the surface and is fought as a set
piece. Branch: `main`. Delivery: `ask-on-risk`, single slice while under budget.
Test runner: `./run.sh --headless tests/smoke_test.tscn`.

## Specs

- **S1 — The asset is the boss.** The planet scenario gains a final boss built
  from `models/boss-1/capital_mother_ship_class_two..glb`. User: *"para ello usa
  el archivo glb en la carpeta modelo/boss-1"*.
- **S2 — It flies, slowly.** The ship is not parked: it moves over the planet on
  its own heading. User: *"volando lentamente sobre el planeta"*.
- **S3 — Surprising size.** The hull reads as a capital ship, not as a large
  fighter: an order of magnitude longer than the player's 4.15-unit airframe.
  User: *"es de un tamaño sorprendente"*.
- **S4 — It is one final encounter per run.** The boss arrives once, after the
  run earns a kill threshold, spawned ahead of the ship. Normal streaming stops
  while it is alive so the fight is readable and the boss is the only threat.
- **S5 — The player cannot fly through it.** The hull is solid against the
  player, unlike the small enemies, because a 96-unit ship is a wall and flying
  through it breaks the scale the boss exists to sell.
- **S6 — It has a boss bar.** The HUD shows the ship's name and a single health
  bar while it is alive, fed only by bus events, hidden again when it dies.
- **S7 — Its fire is telegraphed and dodgeable.** Every burst is announced before
  it lands, from muzzles spread along the hull, so a death is attributable.
- **S8 — It has two phases.** Below 60% health the ship turns and fires faster
  and adds a radial burst, so the fight escalates instead of flattening.
- **S9 — Killing it pays and ends the encounter.** The hull breaks up in a
  cascade of blasts, pays a large score, and normal streaming resumes.
- **S10 — The suite covers it.** Appearance, the solid hull, the bar, the phase
  change, damage, and death are asserted in the smoke test.
- **S11 — The hull burns as its pool drains.** Six fire stations, walked bow to
  stern, ignite at 90, 78, 66, 54, 42 and 30 percent of the pool and grow as the
  ship keeps taking damage, with smoke plumes in world space. The fire is
  recomputed from the pool on every hit, so the blaze cannot drift out of step
  with the bar. User: *"necesito que el el boss se valla incendiando
  progresivamente se le agote la vida"*.
- **S12 — Player fire reaches the hull, and the hit is visible.** A real player
  dart or missile takes health off the boss, and every hit opens a flash on the
  upper deck the camera can see. User: *"que las balas y misiles del player toquen
  al boss"*.

### Assumptions

- The run keeps going after the boss dies; there is no victory screen in the
  prototype, and inventing one is out of scope. The kill pays score and the
  planet resumes.
- The boss does not fire guided missiles in this slice. The launcher enemy already
  owns that pattern; a second implementation would be a second tuning surface.
- Audio reuses the existing 17-key palette. No new synthesized key.

## Tasks

| ID | Specs | Route | Status | Evidence |
| --- | --- | --- | --- | --- |
| T1 | S1 | inline | done | GLB imported, measured, rendered |
| T2 | S6 | inline | done | bus signals + `ui/hud/boss_bar.gd` + `hud.tscn` |
| T3 | S1 S2 S3 S5 S7 S8 | inline | done | `entities/enemy/boss.gd`, `entities/enemy/boss.tscn` |
| T4 | S4 S9 | inline | done | `levels/arena/arena.gd` |
| T5 | S10 | inline | done | `tests/smoke_test.gd` `_test_boss()` |
| T6 | S1 S3 | inline | done | `docs/combat-prototype.md` |
| T7 | S3 | inline | done | `tools/capture_frame.gd` `--boss` flag + captures |
| T8 | S11 S12 | inline | done | `entities/enemy/hull_fire.gd`, box collider, hit flash, suite |

## Log

- **L1 (user, verbatim):** "ahora necesito que crees un jefe final para el
  escenario planeta. esta es una nave gigante, para ello usa el archivo glb en la
  carpeta modelo/boss-1."
- **L2 (user, verbatim, on the boss's nature):** "volando lentamente sobre el
  planeta, y es de un tamaño sorprendente".
- Measured the GLB with `tools/probe_boss.gd`: 259 mesh nodes, 59 unique
  materials, hull AABB `size=(6.945099, 1.779842, 1.358975)` centred at
  `(5.859949, 2.026372, 1.097977)`. Bow on `+X`, stern (engines) on `-X`, up on
  `+Y`, so the asset already matches the game's forward convention.
- Rendered top/side/quarter views with `tools/boss_view.tscn`: the long axis is
  the hull, the tall bridge tower sits near the stern, the rounded prow is `+X`.
- Runtime load of the GLB is under a second, so the boss can be `preload`ed with
  the arena instead of hitting the disk mid-fight. The import step is what was
  slow, and it is already committed.
- Camera at 65 up and 17.42 back, 58 degree vertical FOV: about 75 units of play
  plane are visible vertically. A 96-unit hull is deliberately longer than the
  screen, which is what "surprising" has to mean at this scale.
- Built `Boss` as an `Enemy` subclass with its own flight, attack and break-up,
  and `boss.tscn` with a horizontal `CapsuleShape3D` on layers 9/1. The base
  class already owns `TELEGRAPH_TIME`, `RECOVER_TIME`, `FAN_BULLETS`,
  `RING_BULLETS`, `RING_SPEED` and `DEATH_SHAKE`, so the boss constants are
  prefixed (`BOSS_*`, `CASCADE_SHAKE`) and it uses `_fire_shot()` instead of
  overriding `_spawn_bullet()`, whose signature belongs to `Enemy`.
- The arena counts kills per run (`_run_kills`, not the pilot record), spawns the
  ship at 12 and suppresses the stream while `_boss_alive()`. The bar moved to
  `offset_top = 52` so it does not sit on the hint line.
- First phase-two capture showed the radial burst was invisible: it left from the
  hull centre, under an opaque slab. `_hull_edge()` now spawns every ring shot on
  the hull's silhouette (ray/rectangle hit) and the muzzle stations sit on the
  flank edge, so both patterns are visible the frame they fire.
- Verified with `capture_frame --boss 1`: arrival and scale, the telegraph beam,
  the broadside (`/tmp/boss_fire.png`), and the phase-two ring
  (`/tmp/boss_phase2.png`).
- The suite shares one arena and kills far more than 12 enemies, so the run
  counter is parked at -1000 in the test setup and `_test_boss()` drives the real
  threshold with one kill. `_test_boss()` covers arrival, the solid hull, the
  capsule dimensions, the bar, flight, the first burst, damage, the phase
  threshold, the score and the cascade. Suite: **581 PASS / 0 FAIL** (was 560).
- The first burst was silent on the probe: the hull sits on the world layer to be
  solid, and an enemy bullet's default mask is world + player, so the ship was
  shooting down its own broadside on the frame it spawned. `Boss._fire_shot()`
  now masks its bullets to the player layer; the planet has no world colliders.
  The probe then showed the expected 12-shot broadside, and the phase-two capture
  shows the 24-shot ring leaving the hull edge.
- **L3 (user, verbatim):** "necesito que el el boss se valla incendiando
  progresivamente se le agote la vida y que las balas y misiles del player toquen
  al boss".
- Before changing anything, a probe fired one real player dart and one real player
  missile at the hull: `1200 -> 1199` and `1200 -> 1195`. The layers were already
  right. The real defect was feedback, not collision: one point of damage on a
  1,200 pool moves the bar under half a pixel, and the projectile's own spark is a
  two-unit flash at the impact point that the opaque deck hides from a top-down
  camera.
- The collider was a capsule centred on the body origin while the hull is lifted so
  its belly sits on the surface. The top 13.7 units of the ship were outside the
  shape, so a shot that visibly crossed the upper decks could pass through. It is
  now a `BoxShape3D` built from the same constants as the model, at the hull's
  centre, and a real dart fired at the bow is a regression test.
- Fires were built as billboarded flame quads and stayed invisible through several
  captures. An isolation probe rendered six material variants over an opaque slab
  and settled it: a billboarded instance **ignores its own scale**, so a quad sized
  through `scale` renders at its one-unit mesh size. The flames were one unit wide,
  not seventeen. Size now lives in the `QuadMesh`; the per-frame flicker rides on
  material alpha, and the hit flash uses the same rule. `no_depth_test` keeps a
  flame whose centre sits on the deck from being buried in the hull.
- The fire stations walk **bow to stern** (`FIRE_ANCHORS[0]` is the bow). The first
  version had the list reversed while the comment claimed the walk, so the only
  fire lit at 83 percent sat at the stern and a player looking at the bow saw a
  clean hull. Reordering fixed the comment and put the first flame where the player
  usually shoots.
- Captures: `/tmp/final_light2.png` (one deck alight at 1,000 hp),
  `/tmp/final_heavy.png` (the whole ship at 150 hp), and a magenta flash probe
  confirming the hit flash lands on the deck.
- Suite: **589 PASS / 0 FAIL** (was 587 before the flash assertions).
