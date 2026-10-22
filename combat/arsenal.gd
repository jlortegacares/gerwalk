class_name Arsenal
extends RefCounted
## Weapon catalogue. Every number the player feels lives here, so tuning a weapon
## never means hunting through firing code, and the HUD can name a weapon the same
## way the system does.
##
## Archetypes are taken from Raiden: a wide vulcan, a concentrated laser and a
## flexible plasma that leans on lock-on. Switching is a player choice, not a
## pickup economy: keys 1/2/3 and the D-pad select directly (decided 2026-10-21).

enum Kind {
	VULCAN,
	LASER,
	PLASMA,
}

const NAMES: Dictionary = {
	Kind.VULCAN: "VULCAN",
	Kind.LASER: "LASER",
	Kind.PLASMA: "PLASMA",
}

## Vulcan: three pellets per shot in a fan wide enough to catch a turret that is
## drifting off the crosshair. Cheap damage, forgiving aim, no travel tricks.
const VULCAN_INTERVAL: float = 0.085
const VULCAN_PELLETS: int = 3
const VULCAN_SPREAD_DEGREES: float = 16.0
const VULCAN_SPEED: float = 95.0
const VULCAN_DAMAGE: int = 1
const VULCAN_SIZE: Vector3 = Vector3(0.42, 0.34, 1.6)
const VULCAN_COLOR: Color = Color(0.55, 0.98, 0.9, 1.0)

## Laser: hit-scan. The tick is the damage cadence, not the visual one, so a
## continuous beam pays out in steady bites instead of one burst frame, and the
## beam itself can be redrawn every frame without touching the damage rate.
const LASER_TICK: float = 0.05
const LASER_DAMAGE: int = 1
const LASER_RANGE: float = 40.0
const LASER_GLOW: float = 0.55
const LASER_CORE: float = 0.20
const LASER_COLOR: Color = Color(0.42, 0.95, 1.0, 1.0)

## Plasma: a slow bolt that locks the nearest turret inside a narrow cone and then
## curves onto it. Semi-automatic on purpose: the lock needs the aim, the flight
## does not, so a shot that leaves badly still arrives.
const PLASMA_INTERVAL: float = 0.11
const PLASMA_SPEED: float = 58.0
const PLASMA_DAMAGE: int = 3
const PLASMA_SIZE: Vector3 = Vector3(0.80, 0.62, 2.3)
const PLASMA_TURN_RATE: float = 3.4
const PLASMA_LOCK_RANGE: float = 34.0
const PLASMA_LOCK_CONE_DEGREES: float = 30.0
const PLASMA_COLOR: Color = Color(0.72, 0.82, 1.0, 1.0)

## Missiles: automatic, one launch per interval, alternating wings. The launch
## angle matters as much as the turn rate: a missile that leaves straight ahead
## has no visible curve, and the curve is what sells the guidance.
const MISSILE_INTERVAL: float = 1.6
const MISSILE_SPEED: float = 34.0
const MISSILE_DAMAGE: int = 4
const MISSILE_SIZE: Vector3 = Vector3(0.46, 0.38, 1.9)
const MISSILE_TURN_RATE: float = 2.8
const MISSILE_RANGE: float = 48.0
const MISSILE_LAUNCH_AHEAD: float = 0.3
const MISSILE_LAUNCH_SIDE: float = 0.9
const MISSILE_LAUNCH_ANGLE_DEGREES: float = 14.0
const MISSILE_COLOR: Color = Color(1.0, 0.8, 0.42, 1.0)

## Bomb: the panic button. It cancels enemy fire around the ship and pays a flat
## lump of damage, then charges back up on kills rather than on a timer, so it
## rewards the risk of staying in the fight.
const BOMB_START_CHARGES: int = 3
const BOMB_MAX_CHARGES: int = 5
const BOMB_KILLS_PER_CHARGE: int = 12
const BOMB_RADIUS: float = 40.0
const BOMB_DAMAGE: int = 8
const BOMB_WAVE_TIME: float = 0.45
