class_name PilotStats
extends RefCounted
## The five tracks a pilot's level buys, as pure numbers. The level is the only
## input; the ship and the weapons read the multipliers and never know why they
## changed.
##
## Every track is one multiplier or one integer on top of the base the game already
## tuned, which preserves the relationships those bases encode: the dash stays
## 3.17x cruise, FIGHTER stays 1.8x GERWALK, and GERWALK at level 100 stays slower
## than the interceptor. Damage is deliberately absent: enemies do not scale, so
## raising damage would turn every fight into a formality.

const MAX_LEVEL: int = GameProgress.MAX_LEVEL

## Caps at level 100. The percentages are the design's whole budget per track.
const SPEED_GAIN: float = 0.20
const HP_GAIN: int = 8
const TURBO_CAPACITY_GAIN: float = 0.80
const TURBO_RECHARGE_GAIN: float = 0.60
const INTERVAL_GAIN: float = -0.15
const VULCAN_SPREAD_GAIN: float = -0.20
const PLASMA_CONE_GAIN: float = 0.20
const LASER_RANGE_GAIN: float = 0.20

var level: int = 1


func _init(pilot_level: int = 1) -> void:
	level = clampi(pilot_level, 1, MAX_LEVEL)


## 0 at level 1, 1 at level 100: every track interpolates on this one number.
func progress() -> float:
	return float(level - 1) / float(MAX_LEVEL - 1)


## THRUSTERS. Scales cruise, afterburner, dash and both fighter speeds together.
func speed_multiplier() -> float:
	return 1.0 + SPEED_GAIN * progress()


## ARMOR. An integer because the HUD's segments and every damage source are whole
## hit points.
func max_hp(base: int) -> int:
	return base + roundi(HP_GAIN * progress())


## REACTOR. A bigger tank and a faster refill, so the burner lasts longer and comes
## back sooner; the drain rate stays put.
func turbo_capacity_multiplier() -> float:
	return 1.0 + TURBO_CAPACITY_GAIN * progress()


func turbo_recharge_multiplier() -> float:
	return 1.0 + TURBO_RECHARGE_GAIN * progress()


## AUTOLOADER. One factor for every primary cadence, so the three weapons keep
## their relative rate.
func primary_interval_multiplier() -> float:
	return 1.0 + INTERVAL_GAIN * progress()


## GUNNERY. Tighter fan, wider lock, longer beam: handling, not damage.
func vulcan_spread_multiplier() -> float:
	return 1.0 + VULCAN_SPREAD_GAIN * progress()


func plasma_cone_multiplier() -> float:
	return 1.0 + PLASMA_CONE_GAIN * progress()


func laser_range_multiplier() -> float:
	return 1.0 + LASER_RANGE_GAIN * progress()
