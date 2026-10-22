# Fighter flight model: stall speed, skid and wind

Branch: `main`. Delivery: unreviewed (runtime ineligible for immutable review).
Tests: `./run.sh --headless tests/smoke_test.tscn`.

## Specs

S1. **The fighter never stalls to zero.** "En Modo Caza, la aceleración no decae
a 0. Si el jugador no presiona el acelerador, la nave sigue planeando hacia
adelante a una velocidad crucero base." The coasting target is
`FIGHTER_STALL_SPEED = 0.4 * FIGHTER_SPEED` = 19.3 u/s, the same number as the
throttle's own floor, so no input and the lightest touch give the same speed.
Airspeed falls from cruise to that floor in the old 0.35 s.

S2. **The course lags the nose.** "Cuando la nave rota su morro, el vector de
velocidad tarda en alinear la nueva orientación, provocando derrape lateral
(skidding)." The nose turns at 400 deg/s; the course follows at
`FIGHTER_GRIP / airspeed` (about 226 deg/s at cruise, faster than the nose at
stall speed). A commanded reversal must show more than 20 u/s across the nose
after 0.2 s and settle under 3 u/s within a second.

S3. **A constant wind moves the ship.** "Un vector global de viento ambiental"
that "desplaza pasivamente a la nave y opone resistencia frontal si intentas
volar contra él." Chosen constant, not gusting. `WIND = (7, 0, 0)` u/s enters as
the frame airspeed is measured in: the same glide covers 26.3 u/s downwind and
12.3 upwind, and the wind is never a free constant push.

S4. **The scope is FIGHTER.** GERWALK keeps its 0.050 s brake, no drift and no
wind, because it is a ground-effect hover that holds station. The barrel roll
stays a scripted lateral step (-7.0 units) and is not airspeed.

S5. **Nothing else regresses.** The 91 pre-existing assertions stay green, and the
one that described the old stop is replaced by the stall contract.

## Tasks

| ID | Spec | Status | Evidence |
|----|------|--------|----------|
| T1 | S1 | done | `FIGHTER_STALL_SPEED`, `FIGHTER_DRAG` derived from the same 0.35 s |
| T2 | S2 | done | `FIGHTER_GRIP`, course-plus-magnitude state in `_move_fighter` |
| T3 | S3 | done | `WIND`, airspeed measured relative to it |
| T4 | S4 | done | `_roll_velocity` keeps the jink out of the air model |
| T5 | S5 | done | 98 checks, green twice |
| T6 | S5 | done | `FIGHTER_STOP_TIME` still drives the transform via `TRANSFORM_DRAG` |

## Log

L1. Request, verbatim: "El modelo debe simular tres fuerzas vectoriales clave:
velocidad mínima de sustentación (el caza nunca se frena por completo), arrastre
aerodinámico dependiente del ángulo (deriva/resistencia al cambiar de dirección)
y un vector global de viento ambiental." With the three numbered requirements for
stall speed, drift and wind, the last one offering "un vector constante o
turbulento".

L2. Wind behaviour, decided by the user before implementation: **constant**. A
changing wind makes a graze that looked fair feel unfair in a bullet-hell, and a
constant vector is the only version a test can pin with exact numbers.

L3. Design. Airspeed is tracked as a course plus a magnitude, and the throttle
owns the magnitude while the airframe owns how fast the course may follow the
nose. The obvious alternative - forward and lateral as independent axes with
their own targets - manufactures airspeed out of a turn; a twelve-frame test of it
reached 390 u/s sideways. Wind is the frame airspeed is measured in, not a vector
added to the position, so it produces frontal resistance instead of a free push.

L4. Bug found by the tests. The barrel roll's lateral push was added to the
velocity and then read back as airspeed the next frame, so every jink topped up
the previous one: a measured 393 u/s sideways and a 46-unit step instead of 7.
Fixed by holding the push in `_roll_velocity` and subtracting it before the air is
read. The roll is back to -7.0 units, the exact old number.

L5. Verification. 98 assertions, green twice; the capture still frames the ship.
The changed numbers are all in the smoke test: stall in 0.35 s, glide floor
26.3 u/s over ground, 13.1 units covered in 0.5 s, 27.5 u/s of skid at 0.2 s that
settles to 0.0, 26.3 downwind against -12.3 upwind, and the hover unmoved by the
wind.

L6. Docs. `docs/combat-prototype.md` gains the three-force model, the table rows
and two known gaps (no wind readout, no airspeed cue); `docs/requirements.md`
FR-21 is updated; S3 of `odd/tasks/transformation-modes.md` is marked superseded.

L7. Risk: none. FIGHTER-only, no data, security, contract, concurrency or
delivery surface, and the behaviour change is the one that was requested. GERWALK,
the barrel roll and the transform feel are asserted unchanged.
