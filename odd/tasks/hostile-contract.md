# Hostile contract: move `Enemy` out of `turret.gd`

Branch: `main` (work-unit commit pending).
Test runner: `/Applications/Godot.app/Contents/MacOS/Godot --headless tests/smoke_test.tscn`

## Specs

**S1.** `Enemy` is the hostile contract, not a behaviour, and it lives in
`entities/enemy/enemy.gd`: the `enemy` group, the pool (`max_hp()`, `_hp`,
`current_hp()`), the hit flash, the `killed` signal, the standard death (hide the
hull, spawn the blast, feed `GameProgress` and `GlobalEventBus.enemy_killed`), the
`_aim_beam` mesh and the three lock-mark defaults.

**S2.** The hierarchy states what each hull is: `Turret extends Enemy`,
`MissileEnemy extends Turret`, `FighterEnemy extends Enemy`, `Boss extends Enemy`.
`Turret` keeps only the turret's hull, roam/engage state machine and ring/fan
patterns.

**S3.** No behaviour changes. Hull sizes (turret 10, interceptor 8, launcher 12,
mothership 1200), score values (100/200/250/5000), the death sequence, the blast
kick (`DEATH_SHAKE`) and the lock-mark answers are identical to the pre-change tree.

**S4.** No `.tscn` changes. `class_name` is global, so the four enemy scenes keep
their script paths and the suite keeps instantiating them by path.

**S5.** The suite is green on the final tree.

## Tasks

| ID | Spec | Status | Evidence |
|----|------|--------|----------|
| T1 | S1 | done | new `entities/enemy/enemy.gd` (195 lines) + generated `enemy.gd.uid` |
| T2 | S2 | done | `turret.gd` 427 → 302 lines, `class_name Turret extends Enemy`; `missile_enemy.gd` `extends Turret` + `max_hp()`; `fighter_enemy.gd` / `boss.gd` call `super._ready()` + `max_hp()` |
| T3 | S3 | done | suite green; no constant value edited |
| T4 | S4 | done | no `.tscn` touched; `--headless --import` registers `Enemy` and `Turret` |
| T5 | S5 | done | `SMOKE TEST PASSED`, 0 failures |
| T6 | — | done | `docs/architecture.md` (new), `docs/combat-prototype.md` architecture table |

## Log

**L1.** Request, verbatim:

> analiza el codigo de este pruyecto y propone una arquitectura de software

Followed by approval of the proposal: "si" to *write `docs/architecture.md` and
start with P0*.

**L2.** Constraint found while reading: `FighterEnemy` inherits `_aim_beam` and
`_build_aim_beam()` from the old `Enemy` (= turret), and `MissileEnemy` calls
`super()` from both `_ready` and `_build_visual`. Those pieces therefore belong to
the base, not to `Turret`, and `MissileEnemy` becomes a `Turret` subclass instead of
copying the movement.

**L3.** `_hp` is set by a virtual `max_hp()` called from the base `_ready`, not by
each subclass writing `_hp` before `super()`. Reason: `MissileEnemy` must repaint
and re-time itself *before* the inherited `_ready` builds the visual, so a subclass
assignment would be clobbered by the base.

**L4.** `Boss` keeps its own `_die()`: the break-up is twelve blasts and a deferred
`queue_free`, which is a genuinely different death, not a copy of the base.
