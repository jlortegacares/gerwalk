# Second scenario: a city of streets and towers

Branch: `main`. Delivery: unreviewed (runtime ineligible for immutable review).
Tests: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . tests/smoke_test.tscn`.

## Specs

S1. **The game has a second scenario: a city.** The boot menu offers the planet
   and the city as two separate runs. The city is its own scene, not a mode of
   the planet.

S2. **The player must fly the streets between buildings.** A tower is solid: the
   ship's capsule and every projectile stop at it, so the street grid is the only
   way through the district. The ship starts on a street crossing, not inside a
   block.

S3. **Buildings can be destroyed by the player, but it costs a lot.** A tower
   takes sustained fire to bring down and pays a demolition score when it does.
   Demolishing one is a decision, never a shortcut. A destroyed tower stops
   blocking and leaves rubble, so the street opens where the wall was.

S4. **The city reads as a city.** A night district: a street grid with asphalt,
   curbs and centre lines, towers with lit windows, a continuous perimeter of
   buildings that closes the district, and a camera that never loses the ship
   behind a tower.

S5. **Nothing regresses.** The planet arena, the arsenal, the HUD, the score, the
   audio and the death/restart loop keep working, and the smoke suite stays green.

## Tasks

| ID | Spec | Status | Evidence |
|----|------|--------|----------|
| T1 | S1, S4 | done | `ui/menu/main_menu.tscn` `%CityButton` ("CITY"), `MainMenu.CITY_SCENE`, `levels/city/city.tscn`; smoke: both scenes exist, city loads |
| T2 | S2, S3 | done | `entities/city/building.gd` + `building.gdshader`; smoke: solid from above, 300 HP gate, last hit demolishes, street opens |
| T3 | S3 | done | `combat/projectile.gd` `_on_body_entered` damages a `Building` for player fire only; smoke: a player shot leaves 299 HP |
| T4 | S2 | done | `city.gd` `_nearest_street_centre`/`_spawn_point`; `entities/enemy/turret.gd` `_move_step` -> `move_and_slide`; smoke: ship and every encounter start on a street |
| T5 | S4 | done | `city.gd` `occluders_between`/`_update_occlusion`, `building.set_ghosted`; smoke: a tower on the sight line is found and ghosted |
| T6 | S5 | done | `tests/smoke_test.gd` `_test_city_scene` + `_world_hit`; 491 `PASS`, `SMOKE TEST PASSED` twice in a row (baseline 468) |
| T7 | S5 | done | `docs/combat-prototype.md`: run-it, the city section, tuning rows, architecture map, checks |
| T8 | S4 | done | reviewed frames: `/tmp/city_start.png`, `city_travel.png`, `city_mid.png`, `city_ghost.png`, `city_chip.png`, `city_ruin.png` |

## Log

L1. Request, verbatim: "quiero que el juego tenga un segundo escenario, este debe
ser una ciudad en la cual el player deberá manejarse en las calles entre
edificios. los edificios podrán ser destruidos por el player pero costara mucho
derribarlos."

L2. Design. The planet is an open field; the city is the opposite, so it reuses
every rule and changes only what the walls do. A tower is one `StaticBody3D` box
on the world layer, which is the layer the ship's capsule and every bullet already
collide with: the streets are the level because the geometry is real, not because
the level script forbids anything. Encounter streaming is copied from the arena
with one change: a spawn is snapped to the nearest street crossing, because a
turret appearing inside a tower would have to be seen through it.

L3. Scale. The game camera sits 65 units up and 17 behind, and shows about
128 x 72 units of the plane. A 26-unit block is a third of the screen and a
12-unit street a sixth, which is the tightest grid that still lets a 2-unit-wide
ship turn around. Blocks are 8 x 8 with the outer ring filled solid: the ring is
the district edge, and a solid ring has no street-sized gaps to leak through.

L4. Demolition price. `Building.MAX_HP` is 300 against a turret's 10, which is
about eight seconds of sustained vulcan fire (35 dps), fifteen of laser, or nine
full missile salvos. The bar appears on the first hit and lingers, because a cost
that high has to show progress or it reads as an invulnerable wall.

L5. Camera occlusion. The camera is 65 units up, so a tower within roughly ten
units of the ship on the camera side hides it. The sight line is traced every
physics frame and every tower on it is dithered out with a screen-space Bayer
pattern instead of alpha blending: a blended tower would leave the transparent
queue and stop writing depth, which lets one building sort over another.

L6. Risk: item 3 - the world collision layer is shared with the arena's player
collision and every projectile mask, so a mistake here changes existing combat.
No stored data, security surface, concurrency or delivery path is touched.

L7. Bug: bullets passed through towers. In Godot 4.7 a moving `Area3D` with
`monitorable = false` does not detect a `StaticBody3D`; a hand-built probe with
`monitorable = true` and the same layer and mask did. Projectiles are now
monitorable, and the missile keeps its difference in the layer and the
`enemy_missile` group instead. Verified the projectile is the only `Area3D` in the
game, so no new broadphase pairs were added.

L8. Visual fix: the curb was painted inside the block, where the tower's footprint
covered it. The ground shader now paints the sidewalk in the street band hugging
the block, and the block interior is lighter pavement while the street is asphalt,
so a demolished lot reads as a lot instead of a hole.

L9. Visual fix: the hit flash washed a whole tower white. `HIT_FLASH_TIME` went to
0.12 s and the shader parameter is `pow(x, 2.6)`, so the flash snaps instead of
holding a third of the screen at full white.
