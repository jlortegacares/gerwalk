# Planet cloud deck: weather that breaks a missile lock

Branch: `main`. Delivery: unreviewed (runtime ineligible for immutable review).
Tests: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . tests/smoke_test.tscn`.

## Specs

S1. **The planet scenario has a cloud effect.** The arena carries a cloud deck the
   ship flies through. The deck is scenery the player can enter, not a skybox and
   not a flat overlay. The city scenario is untouched.

S2. **Dense clouds let the player shake an enemy missile.** When the ship is inside
   a bank dense enough to count as cover, an enemy homing missile loses its lock
   and flies straight for the rest of its life. The loss is permanent: the cloud
   is cover the player spends, not a shield that re-acquires when the ship leaves.

S3. **Thin clouds do not break the lock.** A visible but thin bank is a warning,
   not cover. Only the core hides the ship, so the player can read a bank before
   committing to it.

S4. **One field drives the visuals and the rule.** The same density value decides
   how many puffs a cell draws and whether a point counts as cover. A bank that
   looks dense is a bank that actually breaks a lock; there is no second,
   invisible rule to drift out of sync.

S5. **The opening fight stays readable.** The deck starts clear around the origin,
   so the first contact happens in open sky and the run never starts inside a
   wall of white.

S6. **Nothing regresses.** The missile contract is untouched: eight missiles, 1.8 s
   load, nearest-first, 44° fan. Decoys, player missiles, non-homing enemy shots
   and levels without a cloud field keep their behaviour. Audio stays synthesized
   on the 17-key palette. The smoke suite stays green.

S7. **The deck reads as natural cloud, not a repeated pixelated stamp.** The
   silhouettes are irregular, the textures are mipmapped so distant puffs do not
   alias, several variants break the repetition, and a faint haze layer binds the
   detail puffs into one volume. The dense core still reads as cover and the ship
   stays visible inside it.

## Tasks

| ID | Spec | Status | Evidence |
|----|------|--------|----------|
| T1 | S1, S4 | done | `levels/arena/cloud_field.gd`: `FastNoiseLite` density field, cell-streamed `MultiMesh` of billboarded quads, procedural puff texture |
| T2 | S1 | done | `levels/arena/arena.gd` `_build_clouds()` after `_build_planet()`; smoke: the planet carries a cloud field |
| T3 | S2, S3 | done | `combat/projectile.gd` `_cloud_hides_target()` + the drop in `_steer()`; smoke: a dense bank breaks the lock, the shot flies straight, a thin cloud leaves the lock alone |
| T4 | S5 | done | `CloudField.CLEAR_INNER/CLEAR_OUTER`; smoke: the opening patch is clear of dense cloud |
| T5 | S4 | done | `CloudField.density_at()` is the single source; smoke: density is deterministic, the deck has dense banks and thin gaps, a dense point draws 839 puffs |
| T6 | S6 | done | 560 `PASS`, `SMOKE TEST PASSED` (baseline 550); existing missile, decoy and lock tests unchanged |
| T7 | S6 | done | `docs/combat-prototype.md`: cloud section, tuning rows, architecture map, capture commands, checks |
| T8 | S1, S7 | done | reviewed frames: `/tmp/cloud_v3_core.png`, `/tmp/cloud_v3_fringe.png`, `/tmp/cloud_v3_close.png`, `/tmp/cloud_v3_clear.png` |
| T9 | S7 | done | four domain-warped texture variants with mipmaps and anisotropic filtering, a faint haze layer, per-instance opacity and a baked vertical light falloff; `_test_clouds` still green |

## Log

L1. Request, verbatim: "quiero que el escenario planet tenga un efecto de nubes
las cuales cuando el usuario pasa por las partes mas densas sea capas de perder el
rastro de los misiles enemigos".

L2. Ambiguity resolved with the user: "perder el rastro de los misiles enemigos"
means **the cloud cuts the lock**. The missiles do not merely disappear from the
HUD; they stop tracking the ship and fly straight.

L3. Design. The cloud has to be both a visual and a rule, so one `FastNoiseLite`
field owns both. `density_at()` is pure and deterministic; the streaming rebuild
reads it for the puff count and `Projectile` reads it for the cover check. The
alternative, a visual-only deck plus a separate gameplay volume, would let the
two drift and make a bank that looks solid fail to hide the ship.

L4. Lock semantics. The lock is dropped, not suspended: `_steer()` sets
`_target = null` and the existing "no target, no steering" path takes over. A
temporary suspension would need a re-acquire rule and a timer, and it would turn
the cloud into a shield instead of a read. Only a `Player` target is covered: a
flare burns in the open, and a shot already chasing one keeps chasing it.

L5. Opening clearing. The first turret spawns 30 units out, so the deck fades in
between `CLEAR_INNER = 45` and `CLEAR_OUTER = 120`. The planet is
circumnavigable, so this is a clearing, not a hole: the field comes back past the
ring.

L6. Visual tuning. The first pass read as a white-out: `CLOUD_ALPHA = 0.40`,
`MAX_PUFFS_PER_CELL = 5` at 24-unit cells. The deck now uses 18-unit cells, up to
ten puffs per cell, 12–24-unit quads and `CLOUD_ALPHA = 0.22`, so a dense core
reads as a layer with the ship still visible. Per-instance colour carries RGB
variation only; alpha stays 1.0 because `vertex_color_use_as_albedo` would
multiply the material alpha a second time.

L7. Godot 4.7 trap: a spatial shader does not accept `billboard` or
`billboard_keep_scale` as `render_mode`. The first shader failed to compile; the
deck uses `StandardMaterial3D.billboard_mode` and `billboard_keep_scale`
instead, which also keeps the whole deck in one draw call.

L8. Risk: item 3 — `Projectile._steer` is the guidance path shared by player
missiles, decoy-chasing enemy shots and every homing enemy shot. The new branch
is guarded by `_team == Team.ENEMY` and `_target is Player`, so the other callers
are untouched, and the existing missile and decoy tests still pass.

L9. Follow-up request, verbatim: "quiero que mejores los efectos de las nubes,
actualmente parecen pixelados en cierta forma y necesito que se vea mas natural".

L10. Visual pass. The pixelation came from a 96x96 texture without mipmaps and
one repeated circular stamp: distant puffs aliased and the deck read as a pattern
of discs. The deck now uses four 256x256 domain-warped variants with mipmaps and
anisotropic filtering, a wide faint haze quad per cell, per-instance opacity, and
a baked vertical light falloff so an unshaded billboard still reads as a volume.
Dense cells draw up to 16 detail puffs plus two haze quads; the opening ring and
the cover rule are unchanged. The smoke test still reports 560 `PASS`, and the
dense point now draws 1519 puffs.

L11. Follow-up request, verbatim: "baja la cantidad de nubes en el escenario a la
mitad". The lever is coverage, not density: thinning the banks themselves would
also thin the cover the missiles read. `VISUAL_MIN_DENSITY` went from 0.32 to 0.50,
the field's median, so the deck covered about half the map instead of almost all of
it, and the detail, haze and brightness ramps were re-anchored at 0.70-0.75 so a
dense core kept its mass. The density field and the lock rule did not change.

L12. Follow-up request, verbatim: "bajalo aun mas". `VISUAL_MIN_DENSITY` moved to
0.58, well above the field's median: measured coverage fell to 28.4% of the map
while the dense area stayed at 19.45%, because the cover threshold never moved. The
three ramp tops collapsed into `VISUAL_FULL_DENSITY = 0.66`, just above
`DENSE_THRESHOLD`, so a core at the threshold still reads at half weight and
anything denser is saturated: the deck lost sky, not cores. The fringe capture point
moved to (230, 0, 390), density 0.620, because the old (150, 0, 0) at 0.489 is now
clear sky. Reviewed frames: `/tmp/cloud_low_core.png`, `/tmp/cloud_low_thin.png`,
`/tmp/cloud_low_mid.png`, `/tmp/cloud_low_clear.png`. The streamed count at the
dense probe fell from 1519 to 839 puffs, which is the coverage cut showing up in the
total; the probe cell itself still draws a full core, and the smoke test still
reports 560 `PASS` with `SMOKE TEST PASSED`.

L13. Follow-up request, verbatim: "baja el porcentaje de nubes en PLANET un 50%".
Measured first, with a probe that samples `density_at` on a 2000x2000 patch: the
deck covered 29.6% of the map at `VISUAL_MIN_DENSITY = 0.58` and the cover was
20.7% at `DENSE_THRESHOLD = 0.62`. Halving the deck while keeping the cover was
impossible by construction, because cover has to stay inside the visible deck: a
14.8% deck cannot contain a 20.7% cover. So both thresholds moved up the field's
distribution, which halves the deck *and* the cover it carries:
`VISUAL_MIN_DENSITY` 0.58 -> 0.65, `DENSE_THRESHOLD` 0.62 -> 0.68,
`VISUAL_FULL_DENSITY` 0.66 -> 0.71 (the midpoint of the new band, so a core at the
cover threshold still reads at half mass). Re-measured: the deck covers 14.9% (a
49.7% cut) and the cover is 10.0%. The fringe band is 4.9 points wide, so there is
still thin weather between open sky and a lock-breaking core. Consequence worth
knowing: guided missiles can be shaken in half as much of the map as before, which
is what "half the clouds" means when the clouds are the cover. The alternate lever
-- leave the footprint and halve the puffs per cell -- was rejected because the
deck would then look thinner than the rule it advertises. The streamed count at the
dense probe fell 839 -> 357. The smoke test now also asserts the "thin" probe is
visible cloud rather than open sky, so a future retune cannot leave that check
proving nothing. Frames: `/tmp/cloud_half_core.png`, `/tmp/cloud_half_fringe.png`,
`/tmp/cloud_half_clear.png`. 770 `PASS`, `SMOKE TEST PASSED`.
