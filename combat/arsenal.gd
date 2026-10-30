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

## Fighter mode: the gun is bolted to the airframe, so the same three archetypes
## tighten into a nose-first battery. Range is the headline (+40%), speed keeps the
## shots readable at 1.8x cruise, and the fan closes from 16 to 4 degrees.
const FIGHTER_RANGE_MULTIPLIER: float = 1.4
const FIGHTER_SPEED_MULTIPLIER: float = 1.35
const FIGHTER_VULCAN_SPREAD_DEGREES: float = 4.0

## Missiles: a forward radar and a charged salvo, not a clock. The radar holds the
## enemies inside the forward cone; holding the missile button loads one missile every
## MISSILE_SALVO_INTERVAL and releasing fires the whole load, spread over those
## contacts. The launch angle matters as much as the turn rate: a missile that leaves
## straight ahead has no visible curve, and the curve is what sells the guidance.
## Fast enough to catch a running turret before the rack's salvo cooldown matters,
## and fast enough that the guidance curve is a short, legible flick instead of a
## long arc the target can walk out of.
const MISSILE_SPEED: float = 42.0
const MISSILE_DAMAGE: int = 4
const MISSILE_SIZE: Vector3 = Vector3(0.46, 0.38, 1.9)
const MISSILE_TURN_RATE: float = 2.8
const MISSILE_RANGE: float = 48.0
## Half-angle of the forward radar around the aim. Wide enough to sweep a turning
## fight, narrow enough that the lock is still a forward decision.
const MISSILE_RADAR_CONE_DEGREES: float = 55.0
## Held time per loaded missile. A full rack of six is 1.8 s of commitment, and a
## tap shorter than one interval fires nothing at all: the hold is the weapon.
const MISSILE_SALVO_INTERVAL: float = 0.3
const MISSILE_MAX_SALVO: int = 6
## After a salvo the rack is empty for a moment, so hold-release spam cannot chain
## salvos faster than the hold that loads them.
const MISSILE_SALVO_COOLDOWN: float = 0.45
const MISSILE_LAUNCH_AHEAD: float = 0.3
const MISSILE_LAUNCH_SIDE: float = 0.9
## The salvo leaves as a fan, not as a line. Missiles are numbered in pairs
## outwards, so a load of n uses n distinct headings: 11, -11, 22, -22, 33, -33.
## Without that, a six-missile load reads as three shots fired twice.
const MISSILE_LAUNCH_ANGLE_STEP_DEGREES: float = 11.0
const MISSILE_LAUNCH_ANGLE_MAX_DEGREES: float = 33.0
## Seconds of straight flight before a player missile starts guiding. The fan has to
## be readable before the shots commit, or the salvo collapses into one column on
## the launch frame and the spread is invisible.
const MISSILE_GUIDANCE_DELAY: float = 0.22
const MISSILE_COLOR: Color = Color(1.0, 0.8, 0.42, 1.0)

## Decoy: the countermeasure against guided fire. A flare burns where it was
## dropped and takes the lock of every enemy missile close enough to be fooled,
## which leaves that missile flying straight once the flare burns out. The
## cooldown is the whole cost: a countermeasure you can spam is a dodge, not a
## read.
const DECOY_COOLDOWN: float = 4.0

## Bomb: the panic button. It cancels enemy fire around the ship and pays a flat
## lump of damage, then charges back up on kills rather than on a timer, so it
## rewards the risk of staying in the fight.
const BOMB_START_CHARGES: int = 3
const BOMB_MAX_CHARGES: int = 5
const BOMB_KILLS_PER_CHARGE: int = 12
const BOMB_RADIUS: float = 40.0
const BOMB_DAMAGE: int = 8
const BOMB_WAVE_TIME: float = 0.45
