# Missile radar: hold to mark, release to salvo

Branch: `main`. Delivery: unreviewed (runtime ineligible for immutable review).
Tests: `./run.sh --headless tests/smoke_test.tscn`.

## Specs

S1. **The radar looks forward only.** "necesito que el player tenga un radar
delantero". A firing solution exists only for enemies inside `MISSILE_RANGE` and
inside a forward cone around the aim direction. An enemy behind the nose is never
markable, no matter how close it is.

S2. **The rack never fires on its own.** "cuando un enemigo este en su rango
pueda marcarlo manteniendo apretado el boton del misil apretado (no se lanza
automaticamente)". With the button up, no mark and no launch happens, target in
range or not. The old automatic clock is removed, not merely gated.

S3. **Hold time buys marks, up to six.** "dependiendo del tiempo que mantenga
apretado el boton podra lanzar como maximo 6 misiles cuando se suelte". Each
`MISSILE_LOCK_INTERVAL` of held time marks the nearest still-unmarked enemy in the
radar, and the rack holds at `MISSILE_MAX_LOCKS = 6`. Releasing fires one missile
per mark, in marking order, each guided to its own target. Multi-lock rather than
a salvo on a single target (decided with the user, 2026-10-22).

S4. **Tapping must not beat holding.** A salvo arms `MISSILE_SALVO_COOLDOWN`, so
six quick taps cannot outrun six marks of held time. Without it the hold would be
a strictly worse way to fire.

S5. **Marks follow reality.** A mark dies with its enemy and drops when the enemy
leaves the radar. A launch never pays out a target that is gone, and a dead
target never keeps its reticle.

S6. **The player can see the lock.** Every marked enemy carries a reticle in the
world, and the HUD shows how many marks the rack holds. A mechanic that depends on
hold time cannot be invisible.

S7. **The shot itself does not change.** Missile model, smoke trail, speed, turn
rate, damage and lifetime stay as they are: this change owns when a missile
launches and where it comes from, not how it flies.

S8. **The button is discoverable.** A new `missile` action (right mouse button,
gamepad X, key F) appears in the on-screen control hint and in the docs. Nothing
else in the game may be bound to it.

## Tasks

| ID | Spec | Route | Status |
|----|------|-------|--------|
| T1 | S1, S3 | inline | done |
| T2 | S2, S3, S4 | inline | done |
| T3 | S5 | inline | done |
| T4 | S6 | inline | done |
| T5 | S8 | inline | done |
| T6 | S1-S5 | inline | done |
| T7 | S6, S8 | inline | done |

## Log

L1 (verbatim): "modifiquemos como se ejecutan y actuan los misiles: necesito que
el player tenga un radar delantero y cuando un enemigo este en su rango pueda
marcarlo manteniendo apretado el boton del misil apretado (no se lanza
automaticamente), dependiendo del tiempo que mantenga apretado el boton podra
lanzar como maximo 6 misiles cuando se suelte"

L2: Asked whether the hold accumulates marks on several enemies or a single salvo
count on one target. User chose multi-lock: one missile per marked enemy.

L3: Radar cone at 55 degrees half-angle around the aim, mark interval 0.16 s,
salvo cooldown 0.45 s. The cooldown is the piece that makes holding worth
anything; without it six taps win.
