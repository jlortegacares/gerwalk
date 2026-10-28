# Feature: fighter enemy VFX parity with player

**Goal**: `FighterEnemy` (`entities/enemy/fighter_enemy.gd`) should show the same visual effects as the player airframe: wingtip vapour trails, thruster plumes/cores, smoke/contrail puffs, and hit-flash glow on the model material. Livery stays enemy-specific (maroon/red/black).

## Scope
- `entities/enemy/fighter_enemy.gd`: add `_build_thrusters`, `_build_smoke`, `_build_wingtip_trails`; add per-frame `_update_thrusters`, `_update_smoke`, `_update_wingtip_trails` calls in `_physics_process`; expose `_hit_flash` glow on the model material (reuse `_ship_material`-style emission or PlayerModel livery).
- `entities/player/player.gd`: replicate constants/material helpers inline (GDScript has no statics; import not needed for material construction).
- No gameplay changes. Only VFX.

## Design note
The fighter already shares `PlayerModel` with the player, so the hull/shape/glow livery is identical — only the paint differs. Missing VFX are purely additive in `fighter_enemy.gd`.

### Hit flash
The player has NO hit-flash glow; it spawns an impact puff instead. The fighter keeps its existing `_hit_flash` scale pulse from `Enemy`, so no extra glow is added — replicating the player means adding trails/smoke/thrusters only.

## Out of scope
- New weapon behaviours for the enemy.
- Transform mode for the enemy (it stays FIGHTER-only, wings folded).
- Particle scenes as `.tscn` — keep GD-side procedural particles like player.

## Tasks
1. Add smoke particles (`GPUParticles3D`) per nozzle anchor on the enemy visual.
2. Add thruster plumes + cores (cone meshes) per nozzle anchor.
3. Add wingtip vapour trails (ImmediateMesh ribbons) from model wing tips.
4. Wire all three into `_physics_process` per frame with `_pose`/`_fly`.
5. Add hit-flash glow emission to the enemy material.
6. Run headless smoke test / open editor to confirm no regressions.
7. Work-unit commit on feature branch.

## Acceptance
- Fighter enemy displays vapour trails behind wingtips when moving.
- Thruster plumes appear behind nozzles under thrust.
- Smoke puffs trail when accelerating.
- `./run.sh --headless` smoke test passes.
