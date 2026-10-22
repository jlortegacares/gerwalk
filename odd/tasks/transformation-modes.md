# Transformation modes: Fighter / GERWALK

Branch: `main`. Delivery: unreviewed (runtime ineligible for immutable review).
Tests: `./run.sh --headless tests/smoke_test.tscn`.

## Specs

S1. **Two modes, switched in real time.** A dedicated `transform` action (Q /
gamepad L1) toggles between `GERWALK` and `FIGHTER` in either direction. The
switch takes 0.28 s, locks weapons for its duration, grants no invulnerability,
and preserves the current velocity. Double-tapping during the switch is ignored.

S2. **GERWALK is the current ship, unchanged.** Twin-stick 360: cruise in
0.067 s, full stop in 0.050 s, instant aim with a 1800 deg/s hull, dash at 3.17x
cruise, 32 deg bank, camera spring. No regression in the 71 existing assertions.

S3. **FIGHTER flies like a fighter.** The left stick requests a heading, not a
translation: the hull turns toward the requested heading at a capped 400 deg/s
(spec band 360-450), and thrust follows the nose. Cruise is 48.2 u/s (180% of
the 26.8 GERWALK cruise, inside the requested 160-180% band); the ship always
carries a 40% minimum throttle while the stick is held, and full deflection gives
full speed. Releasing the stick decelerates by drag to a full stop in 0.35 s.
No lateral translation: the ship cannot strafe across its nose and cannot turn on
its own axis instantly.

S4. **FIGHTER fires down the nose.** Firing angle is locked to the longitudinal
axis (0 deg) for every primary: dispersion tightens (vulcan 16 -> 4 deg), muzzle
speed rises 1.35x, effective range rises 40% (projectile lifetime scaled), and
plasma loses its lock-on cone. Automatic missiles and the bomb keep working
unchanged, because both are independent systems rather than the main gun.

S5. **The right stick stops aiming in FIGHTER.** Its horizontal axis becomes yaw
trim (+/-60 deg/s of course correction, still under the 400 deg/s cap), and the
dash button becomes a barrel roll: 0.20 s, lateral displacement of 55 u/s,
heading preserved, i-frames as today. The roll is presentation only; the capsule
stays flat on y = 0.

S6. **Supersonic burst.** While boosting in FIGHTER, a frontal shockwave destroys
enemy projectiles inside a 7-unit cone of +/-30 deg off the nose, and draws that
cone. Enemy shots outside the cone still hit. GERWALK boosting does not do this.

S7. **The silhouette changes.** FIGHTER sweeps both wings fully aft, pitches the
nose down 6 deg and sits lower; GERWALK holds the wings forward and the hover
stance. The transition interpolates over the 0.28 s switch and fires one impact
flash plus a light camera shake.

S8. **The HUD names the mode.** `player_mode_changed` drives a label that reads
`FIGHTER` or `GERWALK`, and the controls hint lists the transform key.

## Tasks

| ID | Spec | Route | Status |
|----|------|-------|--------|
| T1 | S1, S2, S3, S5, S8: mode state, transform input, fighter kinematics, yaw trim, barrel roll, HUD label | inline | |
| T2 | S4, S6: fighter weapon profile, 40% range, no plasma lock, shockwave cone | inline | |
| T3 | S7: silhouette morph and transition flash | inline | |
| T4 | Tests and docs | inline | |

## Log

L1 (user, verbatim excerpt): "El jugador controla una nave de combate de
geometría variable ... capaz de alternar en tiempo real entre dos modos operativos
claramente diferenciados: a. Modo Caza (Fighter Mode): Alta velocidad,
desplazamiento vectorial orientado al frente, inercia aerodinámica y fuego frontal
concentrado de largo alcance ... b. Modo Guardián (GERWALK Mode): (comportamiento
actual) Maniobrabilidad Twin-Stick omnidireccional en 360°, capacidad de vuelo
estacionario (hover)."

L2 (decision): the stick is a *heading request*, not a translation and not a raw
yaw-rate input. Only that reading satisfies the three constraints at once: thrust
follows the nose, the turn rate is capped, and releasing the stick coasts to a
stop in 0.35 s. A constant-thrust model would never decelerate on release.

L3 (decision): FIGHTER cruise is pinned at the top of the requested band (180%)
because the mode's whole value is repositioning; the afterburner tops it at 60
u/s instead of scaling the GERWALK ratio, which would have reached 75 u/s and
made the play plane unreadable at this camera distance.

L4 (decision): transformation grants no i-frames. A free dodge on the core
mechanic would make every other defensive tool optional, and the spec asks for a
mode, not an escape.
