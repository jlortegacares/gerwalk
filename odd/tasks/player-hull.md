# Player hull: the airframe build leaves the ship

Branch: `main`.
Test runner: `/Applications/Godot.app/Contents/MacOS/Godot --headless tests/smoke_test.tscn`

## Specs

**S1.** The airframe construction lives in `entities/player/player_hull.gd`
(`class_name PlayerHull extends RefCounted`): the visual root, the two hand-built
gunpod materials, the imported model wearing the saved livery, the camera-axis fill
light and the GU-11 itself.

**S2.** `player.gd` keeps the handles (`_visual`, `_model`, `_accent_material`,
`_gunmetal_material`, `_gunpod`) and reads them back from the builder, because the
mode pose moves the root, the i-frame blink hides it and the pod follows the hand
every frame.

**S3.** The builder owns no scene graph of its own. It is a step, not a resident,
like `PlayerEffects` and `PadPanel`. The fill light's parent arrives as an argument,
so the hull never reads the camera rig.

**S4.** No behaviour change: same node names, same transforms, same material values,
same livery source and same render layer for the fill.

**S5.** The suite is green on the final tree: 775 PASS, 0 FAIL, one boot, exit 0.

## Tasks

| ID | Spec | Status | Evidence |
|----|------|--------|----------|
| T1 | S1 | done | `entities/player/player_hull.gd`, 144 lines: `build()` plus `_build_fill_light`, `_ship_material`, `_build_gunpod`, `_block`, `_mesh_node` moved verbatim |
| T2 | S2 | done | `_build_visual()` is now six lines: construct, build, read the five handles back |
| T3 | S3 | done | `build(ship, light_parent)`; the ship passes `camera.get_parent()` |
| T4 | S4 | done | six constants moved with their comments; `GERWALK_LIFT` and `GUNPOD_STOWED` stayed, because the mode pose reads them |
| T5 | S5 | done | one clean run: 775 PASS, 0 FAIL, one boot, exit 0; only timing numbers drift from the previous baseline |

## Log

**L1.** Request: continue the `player.gd` split after the effects node and the menu's
pad panel.

**L2.** The cuts considered and rejected: `player_audio.gd` would wrap eight `Sfx`
calls and no decision, so it would add a layer without buying anything;
`player_flight.gd` and `player_actions.gd` own the state the suite drives through
`_player.set/_get` (66 + 61 sites), so they are the last moves, not the next ones.

**L3.** The hull build is the clean seam in between: ~130 lines that run once, read
the livery, and are never touched by a test assertion. The ship keeps every handle,
so nothing that reads `_visual` or `_gunpod` changes.

**L4.** `player.gd` 1,103 → 993 lines. Small on its own, but it takes the material
and geometry policy out of the flight script: what the ship is made of stops being
mixed into what the ship does.
