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

S8. **The shot itself does not change.** Missile model, smoke trail, speed, turn
rate, damage and lifetime stay as they are: this change owns when a missile
launches, where it comes from, and which contact it chases, not how it flies.

S9. **The button is discoverable.** A `missile` action (right mouse button, gamepad
X, key F) appears in the on-screen control hint and in the docs. Nothing else in the
game may be bound to it.

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
