# Missile radar: hold to load, release to salvo

Branch: `main`. Delivery: unreviewed (runtime ineligible for immutable review).
Tests: `./run.sh --headless tests/smoke_test.tscn`.

## Specs

S1. **The radar looks forward only.** "necesito que el player tenga un radar
delantero". A contact exists only for enemies inside `MISSILE_RANGE` and inside a
forward cone around the aim direction. An enemy behind the nose is never a contact,
no matter how close it is.

S2. **The rack never fires on its own.** "cuando un enemigo este en su rango
pueda marcarlo manteniendo apretado el boton del misil apretado (no se lanza
automaticamente)". With the button up, the load decays and nothing launches, contact
in range or not. The old automatic clock is removed, not merely gated.

S3. **Hold time loads missiles, up to six.** "por cada 0.3 seg agrega otro misil y
al soltar el boton se lanzan todos los acumulados" plus "dependiendo del tiempo que
mantenga apretado el boton podra lanzar como maximo 6 misiles cuando se suelte".
Each `MISSILE_SALVO_INTERVAL = 0.3` s of held time loads one missile, and the rack
holds at `MISSILE_MAX_SALVO = 6`. The number of contacts never changes how fast the
load grows; releasing fires the whole load in the same frame. A hold shorter than
one interval loads nothing at all.

S4. **The salvo is spread over the radar.** "pero si hay mas target se reparten".
On release the missiles are dealt round-robin over the contacts the radar holds,
nearest first, so three missiles over two turrets land 2/1 and never 3/0. Held time
still decides how many: a lone contact takes the whole load.

S5. **Tapping must not beat holding.** A salvo arms `MISSILE_SALVO_COOLDOWN = 0.45`
s, so hold-release spam cannot outrun the held time that loads the salvo, and the
rack stays shut for the cooldown even with contacts in the radar.

S6. **The salvo follows reality.** Contacts are re-read every frame: a turret that
dies or slips out of the cone stops being a target, and the reticle goes with it. The
load only grows while at least one contact is held, so a salvo can never be
pre-charged in empty sky.

S7. **The player can see the radar and the load.** Every contact carries a reticle
in the world while the button is down, and the HUD shows the loaded count as
`SALVO n / 6`. A mechanic that depends on hold time cannot be invisible.

S8. **The shot's flight profile does not change.** Missile model, smoke trail,
speed, turn rate, damage and lifetime stay as they are. This change owns when a
missile launches, where it comes from, which heading it leaves on and which contact
it chases, not how fast or how tightly it flies. Superseded by S12.

S9. **The button is discoverable.** A `missile` action (right mouse button, gamepad
X, key F) appears in the on-screen control hint and in the docs. Nothing else in the
game may be bound to it.

S10. **The salvo leaves as a fan.** "quiero que los misiles acumulados del player
salgan en distintas direcciones del avion". Missiles are numbered in pairs outwards,
so a load of n leaves on n distinct headings: 11, -11, 22, -22, up to 33 degrees.
Each missile holds its launch heading for `MISSILE_GUIDANCE_DELAY = 0.22` s before
the guidance engages, because guidance on the launch frame folds the spread into one
column. A six-missile load must read as six lines, not as three shots fired twice.

S11. **The mark is a lock, not a decal.** Requested verbatim: "a su vez mejora la
animacion de targear a un enemigo". The mark is the anime lock, not a ring: four
corner brackets pointing inwards plus a diamond pip on the centre, so the target
stays visible inside its own mark. It arrives 1.9x wide and snaps down onto the
contact in 0.22 s while it fades in, and the snap is an ease-out-back, so the box
passes its resting size and squeezes before it settles. Once settled it breathes on
its emission rather than spinning: the box is not symmetric, but rotating it with the
turret would tilt a marker that has to stay level with the play plane. It still dies
with its target and follows it while it moves.

S12. **The salvo braids like the anime.** Requested verbatim: "quiero que el efecto
de los misiles y el target se inspiren en el anime marcross". A player missile swings
its aim direction off the line of sight by `MISSILE_WEAVE_AMPLITUDE` radians at
`MISSILE_WEAVE_RATE` radians per second, so it crabs sideways and swings back and the
smoke trail draws a wave instead of a straight line. Each missile of a salvo carries
its own phase, so a full rack braids rather than moving in lockstep. The swing is
applied to the desired heading, never to the per-frame turn step, and it fades to
zero inside `MISSILE_WEAVE_HIT_RANGE` so the shot still hits what it locked onto.
`MISSILE_TURN_RATE` rises to 5.2 because the turn radius must be small enough for the
weave to bend more than once per flight. Enemy missiles keep their straight track:
their weave would change how the fight reads without buying the player anything.

## Tasks

| ID | Spec | Route | Status |
|----|------|-------|--------|
| T1 | S1, S3, S4 | inline | done |
| T2 | S2, S3, S5 | inline | done |
| T3 | S6 | inline | done |
| T4 | S7 | inline | done |
| T5 | S9 | inline | done |
| T6 | S1-S6 | inline | done |
| T7 | S7, S9 | inline | done |
| T8 | S8, S10 | inline | done |
| T9 | S11 | inline | done |
| T10 | S12 | inline | done |
| T11 | S11, S12 | inline | done |

## Log

L1 (verbatim): "modifiquemos como se ejecutan y actuan los misiles: necesito que
el player tenga un radar delantero y cuando un enemigo este en su rango pueda
marcarlo manteniendo apretado el boton del misil apretado (no se lanza
automaticamente), dependiendo del tiempo que mantenga apretado el boton podra
lanzar como maximo 6 misiles cuando se suelte"

L2: Asked whether the hold accumulates marks on several enemies or a single salvo
count on one target. User chose multi-lock: one missile per marked enemy. Superseded
by L4.

L3: Radar cone at 55 degrees half-angle around the aim, mark interval 0.16 s,
salvo cooldown 0.45 s. The cooldown is the piece that makes holding worth
anything; without it six taps win.

L4 (verbatim): "pero necesito que al mantener apretado salga el total de los
misiles aunque sea a un solo target (ej: mantengo apretado y por cada 0.3 seg agrega
otro misil y al soltar el boton se lanzan todos los acumulados)"

L5 (verbatim): "pero si hay mas target se reparten"

L6: L4 and L5 together settle the mechanic: held time is the count (0.3 s per
missile, six max), the radar is the distribution. One mark per contact is gone, so a
lone target takes six missiles instead of one, and the mark interval is replaced by
`MISSILE_SALVO_INTERVAL`. The old multi-lock commits (`61a7a87`, `94dbe4a`) stay in
history.

L7: The load only grows while a contact is held. Without that rule a player could
charge six missiles in empty sky and dump them the frame a turret appears, which
turns the radar back into a clock.

L8: Distribution is round-robin from the nearest contact, so the closest turret
takes the odd missile. With more contacts than missiles the nearest ones take the
hits: the pool is capped at `MISSILE_MAX_SALVO` and dealt from its head.

L9: Feedback is one reticle per contact while the button is down, and `SALVO n / 6`
on the HUD. The rings answer "who", the label answers "how many"; both are needed
once the load and the spread are independent.

L10: Tests rewritten for the load-and-spread version: 27 missile assertions
covering no auto-fire, one interval loads one, growth to three, a lone contact taking
every missile, a 2/1 split over two contacts, forward-cone exclusion, the six cap,
the cooldown right after a salvo, and a tap firing nothing. Three consecutive green
runs. Visual check: three contacts ringed, `SALVO 3 / 6`, and the salvo leaving with
its trails.

L11: Reported from play: `Invalid type in function '_drop_reticle' ... (previously
freed)`. A turret killed while ringed leaves a freed reference in `_marked`, and
passing it to a parameter typed `Enemy` fails the type check before the function body
runs, so `_sync_marks` and `_discharge` aborted mid-cleanup: the rack never emptied
and the error repeated every frame. Reproduced first with a new sub-test (kill a
ringed contact mid-hold, keep holding, release), which failed "the rack empties" and
printed the error every frame. Fix: both loops walk the list backwards, drop a freed
mark without calling into it, and only call `_drop_reticle` on a live enemy.

L12 (verbatim): "quiero que los misiles acumulados del player salgan en distintas
direcciones del avion, a su vez mejora la animacion de targear a un enemigo"

L13: The fan is a pair counter, not a side counter. `_missiles_fired` is gone: the
salvo index already says both which wing and which pair, so `index / 2 + 1` gives
11, -11, 22, -22, 33, -33 and the rack reads as a spread instead of a stream. The
first capture showed the problem the angle alone cannot fix: with guidance on the
launch frame the spread folds into a column before it is a few frames old, so
`Projectile.set_guidance_delay()` holds the shot on its heading for
`MISSILE_GUIDANCE_DELAY = 0.22` s first. The test reads the heading two frames after
the release and asserts every missile lands in its own 5-degree bucket.

L14: The reticle was a torus, and a torus spinning on its own axis is invisible, so
the "pulsing ring" read as painted on. It is now four arcs (`ImmediateMesh`) with a
lock-in: born 1.9x wide, closing to 1.0 in 0.24 s while it fades in, spinning fast
and settling into an idle turn, with the emission pulsing. `transparency` needs a
`TRANSPARENCY_ALPHA` material, so the material is built before the fade is set.
Evidence: 361 PASS / 0 FAIL; `--missile 100 --salvo-delay 10` shows five separate
lines; `--lock 4` and `--lock 40` show the lock-in and the settled ring.

L15 (verbatim): "quiero que el efecto de los misiles y el target se inspiren en el
anime marcross"

L16: Read the request as two things: the Itano Circus (missiles that weave, leaving
braided smoke) and the anime lock (a bracket box, not a ring). The weave is applied
only to player missiles, because enemy guidance is gameplay the player reads.

L17: The first weave offset the *aim point* sideways, and the shot orbited its target
without closing: a lateral aim offset at 2.8 rad/s turn rate is a spiral, not a weave.
The second attempt added the swing to the per-frame `step`, which is already an angle,
so the missile turned at roughly 25 rad/s. The shape that works swings the *desired
heading* by `sin(age * rate + phase) * amplitude * weight` before the turn-rate clamp.
Evidence: the first version reported `widest = 0.01` and never arrived.

L18: `MISSILE_TURN_RATE` went 2.8 -> 5.2. A turn rate is a turn radius: 15 units at
42 u/s cannot bend a path more than once before the shot arrives, so the weave had
nowhere to draw. Final tuning: amplitude 0.62 rad, rate 11 rad/s, hit range 9,
fade 9. Phase is `index * 2.1`, which over six missiles gives three opposed pairs.

L19: The reticle became four corner brackets plus a diamond pip, and the spin was
replaced by an emission breath: the box is no longer symmetric, but rotating it with
the turret would tilt a marker that has to stay level with the play plane. The
lock-in is an ease-out-back (`OVERSHOOT = 1.70158`), so the box overshoots to 0.91x
of its resting scale and squeezes before it settles.

L20: The reticle test drives `_process(1.0 / 60.0)` fourteen times by hand. In
headless, `process_frame` is not tied to the clock, so a wall-clock wait would sample
past the squeeze and the overshoot assertion would pass for the wrong reason. The
weave test flies at `Vector3(400, 0, 400)`: a turret freed in the previous test is
still in the tree for the tick it frees, and it killed the missile 1.4 units from the
origin.

L21: Evidence: 365 PASS / 0 FAIL. Captures `--missile 100 --salvo-delay 26` (the
braid), `--missile 100 --close 1 --zoom 1.7 --salvo-delay 20` (the fan), and
`--lock 30` (the settled bracket box) all reviewed.
