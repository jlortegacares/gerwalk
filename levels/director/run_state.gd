class_name RunState
extends RefCounted
## What the run has accumulated: the score on the HUD, and the kills the boss
## threshold counts.
##
## The level owns it because the level IS the run. Reloading the scene on a death
## starts a fresh one at zero, and the pilot's record across sessions must never
## decide when a fresh run meets the mothership.
##
## Deliberately not a node and not an autoload: it is a value with two counters,
## handed to whoever needs to read or add to them.

var score: int = 0
var kills: int = 0


## Every payout goes through here, whether it came from a hull or from a tower, so
## the total the HUD shows does not depend on which path produced it.
func add_score(value: int) -> void:
	score += value
	GlobalEventBus.score_changed.emit(score)


## A hull destroyed. Counts toward the run and pays its value. Kept separate from
## `add_score` because a demolition pays without being a kill, and a kill is what
## the boss threshold counts.
func add_kill(value: int) -> void:
	kills += 1
	add_score(value)
