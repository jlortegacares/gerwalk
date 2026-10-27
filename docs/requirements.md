# Gerwalk — Product Requirements

**Status:** Draft v0.3
**Owner:** — (to be assigned)
**Engine:** Godot Engine
**Genre:** Top-down twin-stick shooter (360°) with a real-time 3D scenario

## 1. Vision

Gerwalk is a top-down twin-stick shooter set in a 3D scenario: the player flies
over a planet, moves and fires independently in any direction, and stays locked
to the centre of the screen. It draws its aesthetic intensity and bullet patterns
from classic bullet-hell shoot 'em ups.

## 2. Design Pillars

| ID | Pillar | Implication |
|----|--------|-------------|
| P1 | Full 360° control | Movement uses the left stick, aiming and firing use the right stick. Neither axis restricts the other. |
| P2 | Accessibility with challenge | Instant death (one hit = death) is replaced by a segmented HP bar. A margin of error exists without removing bullet-hell tension. |
| P3 | Godot Engine | Chosen for 3D scene rendering and particle performance on PC and consoles. |
| P4 | Visual style | Pre-rendered 3D models, rendered offline to 2D sprites. The arena itself is real-time 3D. See D-02 and D-03. |

## 3. Scope

### 3.1 In scope for MVP

- One playable arena with a repeating wave loop.
- One player character with dual-stick movement and aiming.
- Segmented HP system with damage feedback and death state.
- A small enemy roster (minimum three distinct behaviors).
- At least three distinct weapons or fire modes.
- HUD: HP segments, current weapon, score or run state.
- Game over and restart without leaving the app.
- Gamepad and keyboard + mouse input parity.

### 3.2 Out of scope for MVP

- Online multiplayer, co-op, or networked play.
- Persistent progression across sessions (meta-progression store).
- Localization beyond English.
- Level editor or user-generated content.

## 4. Functional Requirements

### Explicit (derived directly from the brief)

| ID | Requirement | Acceptance criteria |
|----|-------------|---------------------|
| FR-01 | The player moves in any direction independently of aim direction. | Holding movement input at any angle moves the character along that vector while aim stays fixed on the right-stick vector. |
| FR-02 | The player aims and fires in any direction independently of movement. | Aim vector follows the right stick / mouse with full 360° resolution; character may move opposite to the fire direction. |
| FR-03 | Firing is decoupled from facing: the character can shoot while retreating. | No state in which firing forces a movement direction change. |
| FR-04 | The player has a segmented HP bar instead of one-hit death. | HP is displayed as discrete segments; a bullet impact removes exactly one segment (or a defined damage value); the player survives until all segments are gone. |
| FR-05 | Losing all HP ends the run. | At zero segments the run enters a game-over state and can be restarted. |
| FR-06 | Enemies and bullets follow bullet-hell style patterns. | Enemies emit patterned projectile groups (spread, ring, aimed) that are individually dodgeable at the intended movement speed. |
| FR-07 | The game runs on Godot with a real-time 3D scenario. | Projectile and impact effects render in the 3D scene without dropping the NFR-01 frame target. |
| FR-08 | The visual style is pre-rendered 3D models. | Every character, enemy, prop, and effect ships as a 3D source model rendered offline to 2D sprites; no mixed-source or pixel-art assets in MVP. The scenario (planet surface and limb) is real-time 3D geometry (D-03). |
| FR-15 | The player stays framed on screen and can travel the whole planet surface. | The camera follows the player: at rest the player projects within 1 px of the screen centre, and under thrust it leads the frame by a bounded handful of pixels (measured 8 px at cruise, and the lead saturates at 0.6 world units so every mode, including FIGHTER at 180% speed and its burner, stays under 16). The planet rotates under the ship as it travels, so there is no boundary and no direction is blocked; covering one circumference brings the original terrain back under the ship, which makes the surface finite and fully traversable. |
| FR-12 | Primary fire is continuous and three archetypes differ in behaviour. | Holding fire sustains the selected weapon: vulcan fires a wide spread fan, laser fires a concentrated straight ray of high DPS, plasma fires a flexible shot with semi-automatic lock-on. Firing never reduces translation speed. |
| FR-17 | The player selects a primary weapon directly, with no pickup economy. | Keys 1/2/3 select vulcan, laser or plasma immediately; the D-pad left/right cycles them; the HUD names the active weapon. |
| FR-18 | Homing missiles fire automatically at a fixed interval. | With a target inside 48 units the ship launches one guided missile every 1.6 s from alternating wings, with no player input; with no target it does not fire. |
| FR-19 | A limited bomb cancels enemy fire and damages nearby enemies. | One charge detonates a 40-unit blast that frees enemy projectiles and deals heavy damage in the same frame; the rack starts at 3, caps at 5 and gains one charge per 12 kills. |
| FR-20 | Ship maneuverability is snappy arcade response with aviation presentation. | Rest to cruise in 0.05–0.08 s and cruise to a full stop in 0.06 s or less; a 15–30% stick deflection moves the ship at tap speed; the shot direction is instant while the hull turns at 1800 deg/s; the dash is 3.0–3.5x cruise, injected flat on frame one with prior inertia cancelled, aimed along the stick when deflected and along the nose when not; the hull banks 20–35 deg while drifting or turning and levels out when it stops; thruster trails are subtle at constant speed and flash on a dash or a launch from rest; the camera trails the body by a spring so the ship leads a few pixels under thrust. |
| FR-21 | The ship transforms in real time between a twin-stick hover (GERWALK) and a nose-first interceptor (FIGHTER). | Q or LB switches both ways over 0.28 s, with weapons locked, no invulnerability and momentum preserved; entry into FIGHTER points the hull where the ship was already going. GERWALK keeps the 360° twin-stick behaviour unchanged. FIGHTER turns the left stick into a heading request followed at a capped 400 °/s, thrusts along the nose at 180% of the hover cruise and never stalls to zero: releasing the stick settles the airspeed at 40% of cruise in 0.35 s. The course follows the nose only through a lateral grip, so a hard turn skids sideways instead of pivoting, and every heading flies the same speed — the model carries no world-space wind, so the wings sweep from the throttle and not from the compass; the right stick becomes yaw trim instead of aim, the dash becomes a 0.20 s barrel roll that keeps the heading, every primary fires at 0° with 1.4x range, tighter dispersion and higher muzzle speed (plasma loses its lock), and while the afterburner is lit a drawn 7-unit, ±30° cone destroys enemy projectiles. The HUD names the active mode. |
| FR-16 | The ship has a sustained afterburner fed by a turbo reserve. | Holding the afterburner with movement input moves the ship faster than normal top speed while the reserve lasts; the reserve drains only while burning and refills while at normal thrust; at zero the ship falls back to normal speed and does not re-arm until the burner is released. |

### Recommended baseline (needs product confirmation)

These are conventional for the genre and make FR-01..FR-08 testable, but were
not stated in the brief.

| ID | Requirement | Why it is proposed |
|----|-------------|--------------------|
| FR-09 | Damage grants brief invulnerability frames and a visual/haptic cue. | Without i-frames, overlapping bullet clusters delete the whole HP bar in one frame, contradicting P2. |
| FR-10 | Difficulty escalates across waves (enemy count, pattern density, speed). | Bullet-hell tension requires a rising curve; a flat loop loses P2's "tension". |
| FR-11 | A dodge/dash or equivalent evasion tool with cooldown. | Gives the player agency against dense patterns; supports P2. |
| FR-13 | Score or run-progress readout persists across the run. | Needed so wave escalation has a visible stake. |
| FR-14 | Input rebinding and pause menu. | Standard accessibility baseline for PC and console release. |

## 5. Non-Functional Requirements

| ID | Requirement | Target |
|----|-------------|--------|
| NFR-01 | Frame rate | 60 FPS sustained at 1920x1080 on a mid-range PC (GTX 1650 / Ryzen 5 3600 class) with peak projectile load. |
| NFR-02 | Input latency | Fire input to visible projectile spawn within 2 frames (33 ms at 60 FPS). |
| NFR-03 | Platform targets | PC (Windows + Linux) for MVP; console certification as a later milestone (OPEN-03). |
| NFR-04 | Rendering pipeline | Pre-rendered character and enemy assets: fixed base resolution, fixed light direction, consistent camera angle and scale across all sprites. The arena is runtime 3D and keeps one fixed camera pitch. |
| NFR-05 | Projectile budget | Minimum 400 simultaneous player-visible bullets at NFR-01 frame target. |
| NFR-06 | Engine version | Godot 4.x, pinned and documented in the repo (OPEN-04). |
| NFR-07 | Determinism | Wave and pattern generation reproducible from a seed, so bugs and balance can be reproduced. |
| NFR-08 | Accessibility | Remappable controls, scalable HUD, and no color-only encoding of critical information (e.g. player vs enemy projectiles). |

## 6. Player Experience Targets

- **Time to first shot:** under 10 seconds from launch to firing.
- **First death:** the player should survive at least 60 seconds on a first run.
- **Readability:** player bullets, enemy bullets, and hazards must be visually
  distinguishable within one frame at maximum projectile density.
- **Failure attribution:** after any death, the player can name what hit them.

## 7. Open Questions

| ID | Question | Blocks |
|----|----------|--------|
| OPEN-03 | Which consoles are targets, and in what order? | NFR-03, input and certification work |
| OPEN-04 | Godot version and renderer (Forward+ vs Compatibility / mobile)? | NFR-06, particle performance budget |
| OPEN-05 | Is there a narrative or setting beyond the name "Gerwalk"? | Enemy roster and art direction |
| OPEN-06 | Does the 3D scenario pivot extend to player, enemies, and effects as real-time meshes, or do they still ship as pre-rendered sprites in the 3D scene? | D-02 scope, FR-08, asset pipeline (NFR-04) |

## 7.1 Resolved Decisions

| ID | Decision |
|----|----------|
| D-01 | The brief does not reference an external progression archetype (action RPG, roguelike, arcade). Player advancement inside the MVP is wave-based only, tracked by score and run state. Persistent meta-progression stays out of scope (3.2). |
| D-02 | Visual style is pre-rendered 3D models rendered offline to 2D sprites. Pixel art is out of scope. |
| D-03 | The scenario is real-time 3D, not a 2D backdrop. The arena is a `Node3D` scene where the planet surface is the play field: the ground is a sphere whose centre tracks the ship, so the ship is always at its pole, and the planet rolls under the ship by the distance travelled, so there is no boundary and the whole surface is circumnavigable. A following `Camera3D` keeps the ship centred. Gameplay stays on the y = 0 plane so hitboxes remain planar and bullet patterns keep their twin-stick readability; the third dimension is presentation. The camera is a child of the player and does not rotate with the player's heading: a rotating camera would curve straight bullets on screen. Whether entities also become real-time meshes is OPEN-06. Enemies are part of the planet, not of the ship: they keep world positions on the surface, roam it on their own and are left behind when the ship travels away, so exploring changes what the player meets. |

## 8. Success Criteria for MVP

1. A new player completes at least three escalating waves using only the
   on-screen guidance and default controls.
2. FR-01 through FR-08 pass their acceptance criteria in a recorded playtest.
3. NFR-01 and NFR-05 hold during a stress test with the maximum projectile load.
4. No crash, soft lock, or unrecoverable input state in a 30-minute session.

## 9. Next Steps

1. Initialize the Godot project and pin the engine version (OPEN-04).
2. Convert FR-09..FR-11 and FR-13..FR-14 from "proposed" to confirmed or dropped.
3. Produce a combat feel prototype: one arena, one enemy, one weapon, HP bar.
4. Define the pre-rendered asset pipeline: source DCC, render resolution, light
   rig, and sprite export settings (D-02, NFR-04).
