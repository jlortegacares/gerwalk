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
  run earns a kill threshold, spawned ahead of the ship. The stream keeps running
  through the fight (see S16), so the arrival escalates the run instead of resetting
  it.
- **S5 — The player cannot fly through it.** The hull is solid against the
  player, unlike the small enemies, because a 96-unit ship is a wall and flying
  through it breaks the scale the boss exists to sell. The collision is six
  solid target points, two per third of the keel, so the wall covers the hull
  exactly and a shot always lands on a point.
- **S6 — It has a boss bar.** The HUD shows the ship's name and a single health
  bar while it is alive, fed only by bus events, hidden again when it dies. The bar
  reads the sum of the six points, so the fight still reads as one hull.
- **S7 — Its fire is telegraphed and dodgeable.** Every gun announces the line it
  will fire along before the shot leaves, so a death is attributable and the dodge
  is stepping off the line.
- **S8 — It has two phases.** Below 60% health the ship turns and fires faster
  and adds a radial burst, so the fight escalates instead of flattening.
- **S9 — Killing it pays and ends the encounter.** The hull breaks up in a
  twelve-blast cascade plus one detonation sized to the ship, pays a large score,
  and the planet keeps going.
- **S10 — The suite covers it.** Appearance, the solid hull, the six target
  points, the bar, the phase change, damage, and death are asserted in the smoke
  test.
- **S11 — Each section burns as its own pool drains.** Two fire stations per
  section ignite at 90 and 55 percent of that section's pool and grow as it keeps
  taking damage, with smoke plumes in world space, so shooting the bow sets the bow
  alight. A destroyed section burns at full intensity. The fire is recomputed from
  the pools on every hit, so the blaze cannot drift out of step with the bar. User:
  *"necesito que el el boss se valla incendiando progresivamente se le agote la
  vida"*.
- **S12 — Player fire reaches the hull, and the hit is visible.** A real player
  dart or missile takes health off the boss, and every hit opens a flash on the
  upper deck of the point it crossed. User: *"que las balas y misiles del player
  toquen al boss"*.
- **S13 — Three independently attackable sections.** The hull is fought as bow,
  middle and stern; a shot wears down the third it crosses and nothing else, and
  each section can be destroyed on its own. Destroying one does not open the hull:
  it stops taking damage, stops firing its own gun and burns at full intensity. When
  the third falls the ship explodes with a blast scaled to its size. User: *"quiero
  que el boss tenga 3 areas que se puedan atacar, la delantera, la tracera y la
  media. cada una atacable independientemente. cuando se destruyen las 3 partes la
  nave boss explota con una gran explocion acorde a su tamaño"*.
- **S14 — Each section fires a different weapon, and the lock is visible.** The
  stern answers with a laser, the bow with a vulcan burst and the middle with
  guided missiles; each runs on its own clock and a destroyed section silences
  exactly its own gun. The missile lock mark on the boss is visible and sits on the
  ship: a small box on the hull, drawn over the model, instead of a hull-sized frame
  whose corners hang in the air. User: *"quiero que la
  parte tracera el boss ataque con lacer, la delantera con vulcan y la parte media
  con misiles. tambien el target de misiles al boss debe ser visible"*.
- **S15 — Three target points, one per section.** The hull is fought as three
  independently damageable points: one on the bow, one on the middle and one on the
  stern. Each point owns its own pool, and a section is finished when its point is;
  the section's gun and fires read it, so a destroyed third stops answering and burns
  at full intensity. The 6-point split was dropped in L9 at the user's request.
  Original user text: *"quiero que apliques 6 puntos para targear al boss 2 adelante,
  2 al medio y 2 atras"*; revised by *"deja los principales 3"*.
- **S16 — The fighters stay when the boss arrives.** The arrival must not clear the
  field: the enemies already fighting stay, and the normal stream keeps producing
  through the set piece. User: *"a su vez quiero que los figther enemigos no
  desaparezcan al aparecer el boss"*.
- **S17 — The rack can lock the bow, the middle and the stern separately.** Besides
  the existing centre, the ship exposes two more places a missile can be locked on:
  one toward the bow and one toward the stern. A salvo splits over the three, and a
  missile aimed at a third steers to that third so the damage lands on its points.
  User: *"quiero que na nave boss tenga otros 2 lugares para targearle misiles. en
  la parte delantera y en la tracera aparte del centro"*.

### Assumptions

- The run keeps going after the boss dies; there is no victory screen in the
  prototype, and inventing one is out of scope. The kill pays score and the
  planet resumes.
- The middle section's guided pair reuses the launcher enemy's tuning rather than
  introducing a second missile model: the counterplay (turn, dash, transform,
  decoy) must not change because the shot came from a capital ship.
- Audio reuses the existing 17-key palette. No new synthesized key: the stern's
  laser is the player's `laser` at a lower pitch.

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
| T9 | S13 | inline | done | `entities/enemy/boss_part.gd`, `boss.gd` three-section build, `ship_explosion.gd` `scale_multiplier`, suite |
| T10 | S7 S13 S14 | inline | done | `entities/enemy/boss_weapon.gd`, `boss.gd` `_build_weapons`/`lock_mark`, `lock_reticle.gd` `set_mark_size`, `turret.gd` `lock_mark`, `weapon_system.gd` `_sync_marks`, suite |
| T11 | S15 S16 | inline | done | `boss_part.gd` `section_id`, `boss.gd` six-point build and section helpers, `boss_weapon.gd` section silence, `arena.gd` live stream, suite |
| T12 | S17 | inline | done | `turret.gd` `lock_mark_anchors`, `boss.gd` `_build_lock_anchors`, `weapon_system.gd` `LockSlot` radar pool, suite |
| T13 | S15 | inline | done | `boss.gd` `PARTS_PER_SECTION` removed, `PART_COUNT` 3, `PART_HP` 400, one box per section; `boss_part.gd` doc; suite |

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
- **L4 (user, verbatim):** "quiero que el boss tenga 3 areas que se puedan atacar,
  la delantera, la tracera y la media. cada una atacable independientemente. cuando
  se destruyen las 3 partes la nave boss explota con una gran explocion acorde a su
  tamaño".
- The hull is now three `BossPart` nodes (`entities/enemy/boss_part.gd`), each an
  equal third of the keel: index 0 is the bow (`+X`), 1 the middle, 2 the stern
  (`-X`). Each owns `PART_HP = BOSS_HP / 3 = 400`, reports through `damaged` and
  `destroyed`, and carries the hull's collision. `Boss` keeps no shape at all, so a
  shot always lands on a section; `Projectile` routes player fire to `BossPart`
  before the `Enemy` branch.
- `Boss.take_damage()` survives as the hull-wide helper the capture tool and the
  suite use. It drains bow to stern and never spills past a section, so `--boss-hp
  N` still lands the ship at N. `BOSS_HP` stays 1,200 as the total: the bar, the
  60 percent phase threshold and the score keep one meaning, and the bar reads the
  sum of the three pools.
- A destroyed section stays solid (no hole in the hull), stops taking damage, stops
  firing its muzzle stations (`MUZZLE_PART = [2, 1, 1, 0]`) and burns at full
  intensity. Fires moved from six hull-wide stations to two per section at 90 and
  55 percent of that section's pool, so the blaze names the third that is wearing
  down. The hit flash now lands on the section that took the hit instead of toward
  the player.
- The body no longer calls `move_and_slide()`: with no shape it would have nothing
  to slide against, so `_drive(delta)` integrates `global_position` directly.
- **The first version of the sections drifted off the hull.** They were
  `AnimatableBody3D` with the default `sync_to_physics`, and a probe showed their
  local positions growing frame after frame inside the moving hull: `Part0` should
  sit at local `x = 15.97` and had walked to `x = 5.20, z = -13.01` while the
  physics-server transform lagged the node. The read-back that `AnimatableBody3D`
  performs each step accumulates against a parent that moves every physics frame.
  They are `StaticBody3D` now, which follows the parent's transform exactly; the
  probe then showed node and server transforms identical and a real dart taking the
  bow from 400 to 399 with the other two sections untouched.
- Death is a twelve-blast cascade (`DEATH_STEP` 0.11, scale 2.2, shake 0.5) plus
  one detonation at the hull's centre (`FINAL_SCALE` 6.0, shake 3.0).
  `ShipExplosion` gained `scale_multiplier` (default 1.0, so every existing caller
  is unchanged) which scales each layer and stretches the lifetime by
  `clampf(sqrt(scale), 1.0, 1.6)`.
- Suite: **618 PASS / 0 FAIL** (was 589). The boss test now asserts the three
  sections, their layers and boxes, their bow-to-stern order, a real dart wearing
  down only the bow, each section falling on its own, the bar reading the sum, and
  the final blast's scale.
- **L5 (user, verbatim):** "quiero que la parte tracera el boss ataque con lacer, la
  delantera con vulcan y la parte media con misiles. tambien el target de misiles al
  boss debe ser visible".
- Each section now owns a `BossWeapon` (`entities/enemy/boss_weapon.gd`): the bow a
  four-volley vulcan of three amber pellets, the middle a guided pair tuned like
  `MissileEnemy`, the stern a laser that rakes from the deck top down to the play
  plane. The guns are parented to the **Boss** at `y = 0`, not to the section body:
  the body sits at deck height (local `y = 10.78`), so a shot born there would fly
  over the player forever. Each gun reads its own `BossPart` every tick, so a
  destroyed third goes silent without a second bookkeeping path.
- Every gun telegraphs with the same line it fires along, and the aim locks when the
  windup opens, so the line is a promise. The laser keeps its line lit while it
  burns. The old hull-wide `_aim_beam`, the four muzzle stations and the shared
  attack state machine are gone; the phase-two radial ring stays as the ship's own
  no-telegraph escalation.
- `Boss._state` became `_dead`: only `DEAD` was ever read, and the three guns own
  their clocks now.
- The lock mark was a 2.6-unit box on the hull's centre, which on a 96-unit ship
  reads as no lock at all. `Enemy.lock_mark()` returns `Vector3.ZERO` by default and
  `Boss` overrides it. The first version framed the whole keel and the capture
  showed why that fails: a 95.8-unit box is longer than the camera sees, so its
  corners were never on screen. It now frames the middle third (17.6 x 9.4), which
  is where a homing missile steers and fits in one glance. `LockReticle` gained
  `set_mark_size(half, lift)`, called before `add_child`, and scales its bracket
  arms, line weight, pip and tally with the smaller side.
- The boss test makes the player untouchable for its duration: three guns now fire
  a laser and homing missiles, and the test is about the ship's state, not about
  surviving it.
- Captures: `/tmp/boss_lock3.png` (the lock box framing the hull), `/tmp/boss_guns.png`
  (the stern laser raking the deck and the bow's vulcan fan). Suite: **632 PASS /
  0 FAIL** (was 618).
- **L6 (user, verbatim):** "quiero que apliques 6 puntos para targear al boss 2
  adelante, 2 al medio y 2 atras. a su vez quiero que los figther enemigos no
  desaparezcan al aparecer el boss".
- The hull's three sections became **six target points**: each third is split port
  and starboard, each point owns `PART_HP = BOSS_HP / 6 = 200`, and a section falls
  when both of its points do. The gun and the fires read the section, so a half-worn
  third keeps answering and keeps burning; a point falling still pays its blast.
  `BossWeapon` no longer holds a `BossPart`: it holds the section id and asks the
  boss, which is what keeps one gun per third while the damage unit is the point.
- The arrival no longer frees the field. `spawn_boss()` used to `queue_free()` every
  non-boss enemy and `_maintain_population()` returned while the hull was alive; both
  are gone. The hull counts against `MAX_ENEMIES`, so the fight keeps a couple of
  escorts and the stream refills when they die.
- Suite: **672 PASS / 0 FAIL** (was 632). It asserts the six points, their pairs, a
  point falling without finishing its section, the gun staying alive until the pair
  falls, and that a fighter in the stream survives the arrival.
- **L7 (user, verbatim):** "los target se desprenden del boss, estos deben ser
  pequeños y deben ser fijados en la nave boss".
- The lock mark was the detached thing: a hull-sized frame (17.6 x 9.4 half
  extents) lifted 2 units above the tallest deck. The camera is nearly top-down and
  angled, so a flat box above a 24-unit hull projects well clear of the silhouette,
  and its corners hang over the water where the ship narrows. It read as a target
  that came off the ship.
- The mark is now a small box on the hull: `LOCK_MARK_HALF` (5.0 x 3.2) at the
  hull's own mid height, so it sits inside the ship's silhouette. `Enemy` gained
  `lock_mark_on_hull()` (default false) and `Boss` returns true; `LockReticle`
  draws an on-hull mark with `no_depth_test`, because at mid height the opaque model
  would otherwise hide the whole box. Turret marks keep the depth test, so a box
  behind a tower stays behind the tower. `LockReticle.set_mark_size()` takes the
  third argument.
- Capture: `/tmp/boss_lock_hull.png` (four brackets and the pip on the deck, tally
  below). Suite: **673 PASS / 0 FAIL** (was 672; the lock assertions were rewritten
  to pin the small size, the on-hull height and the over-hull draw).
- **L8 (user, verbatim):** "quiero que na nave boss tenga otros 2 lugares para
  targearle misiles. en la parte delantera y en la tracera aparte del centro".
- The radar used to hold one slot per contact, so a single hull could only ever take
  one mark. `Enemy` gained `lock_mark_anchors()` (empty by default) and `Boss` hangs
  one `Marker3D` per section at the section's own centre and the hull's mid height
  (`LockAnchor0..2`). `WeaponSystem` now pools `LockSlot`s — a contact plus the node
  its mark hangs from — so one detected ship expands into three slots and a turret
  still contributes exactly one.
- Detection stays per body on purpose: a ship in radar range is in range for the
  whole rack, so all three marks appear even when one anchor sits past
  `MISSILE_RANGE`. Sorting and the 8-slot cap are per slot, which is what makes the
  nearest third take the extra missile.
- The shot steers to `slot.host`, so a missile assigned to the bow crosses the bow's
  points. `Projectile` flattens `y`, so a hull-height anchor still flies on the play
  plane and hits the part under it. Slots survive frames by host node identity, and
  an anchor freed with the wreck takes its reticle with it.
- Captures: `/tmp/boss_lock_three_full.png` (bow and middle marks at ×3 each; the
  stern mark falls outside a 1280-px frame because the camera does not follow a
  `--lock-boss` hull at x=46). Probe measurements at the default framing: the three
  reticles sit on `LockAnchor0/1/2`, half extents 5.0 x 3.2, screen x 297/663/1028 at
  y 333. Suite: **688 PASS / 0 FAIL** (was 673).
- **L9 (user, verbatim):** "quiero que elimines los locks de boss que no sean los 3
  creados ultimamente" / "deja los principales 3".
- Clarified with a measurement first: the boss already exposed exactly three lock
  anchors (one per section) and the radar cannot produce more than one mark per
  anchor, so the extra "locks" the user meant were the **six damage points**. The
  fight drops back to **three target points, one per section**.
- `PARTS_PER_SECTION` is gone: `PART_COUNT = SECTION_COUNT = 3` and `PART_HP =
  BOSS_HP / 3 = 400`. Each `BossPart` now covers its whole third of the beam (18.8
  units) at the hull's mid height, so a section and its point are the same unit:
  the first hit that finishes a point also finishes the section, silences its gun
  and burns it at full intensity. `section_hp()` is now just the point's pool.
- The three lock anchors did not move: they still sit on the section centres and the
  rack still splits a salvo 3/3/2 over them.
- Suite: **659 PASS / 0 FAIL** (was 688; the pair assertions for the port/starboard
  halves were removed with the halves themselves).
