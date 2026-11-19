# Planet roster: interceptors and the mothership, nothing else

Branch: `main` (work-unit commit pending).
Test runner: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . tests/smoke_test.tscn`

## Specs

**S1.** The PLANET scenario streams one archetype. Every contact the arena spawns is
an interceptor (`entities/enemy/fighter_enemy.tscn`); the turret and the missile
launcher do not appear in the planet's sky.

**S2.** The mothership is untouched. It arrives once per run on its kill trigger
(`BOSS_KILL_THRESHOLD`), and the interceptors already on the field stay when it
does.

**S3.** Nothing else changes. CITY keeps all three archetypes and its share
constants, the missile contract is untouched (8 missiles, 1.8 s load, nearest-first,
44°/55° cone), and the audio stays on the 17-key palette.

**S4.** The opening contact is not an ambush. The first contact spawns outside the
interceptor's chase and attack radii, so it does not fire on a player who has not
moved the stick yet.

**S5.** The roster is pinned by the suite. The opening child of the arena's
`Enemies` node is a `FighterEnemy`, and driving the population spawner produces only
interceptors.

## Tasks

| ID | Spec | Status | Evidence |
|----|------|--------|----------|
| T1 | S1 | done | `levels/arena/arena.gd`: `FIGHTER_ENEMY_SCENE` is the only streamed scene; `ENEMY_SCENE`, `MISSILE_ENEMY_SCENE`, `MISSILE_ENEMY_SHARE`, `FIGHTER_ENEMY_SHARE` and `_pick_enemy_scene()` removed |
| T2 | S4 | done | `FIRST_SPAWN_DISTANCE` 30 → 70, outside `CHASE_RADIUS` (62) and `ATTACK_RANGE` (46) |
| T3 | S5 | done | `tests/smoke_test.gd`: `_test_planet_roster`; the turret's own tests spawn their own turret now |
| T4 | S1-S3 | done | `docs/combat-prototype.md`: interceptor section, tuning rows, planet question, known gaps |

## Log

**L1.** Request, verbatim:

> quiero que en la etapa planet solo aparezcan figthers enemigos y el boss final, el
> resto de enemigos sacalos de PLANET.

**L2.** Why the turret and the launcher leave with it. Both are ground-holding
enemies: the turret roams a leg, leashes to a ring and waits for the ship to come to
it, and the launcher telegraphs a salvo from a fixed post. That works in a district
because the district gives them streets to sit on. The planet is open air, and the
only encounter that space can stage is the chase — which is the interceptor. Keeping
them as a minority share would have kept two encounters the planet cannot frame.

**L3.** The opening contact moved from 30 to 70 units. At 30 it spawned inside
`ATTACK_RANGE` (46) and inside `CHASE_RADIUS` (62), so it fired roughly 1.6 s after
the load (`FIRST_PASS_TIME` 0.9 + `WARNING_TIME` 0.72) whether or not the player had
moved. At 70 the interceptor has to close first, and the player gets the first
decision. The cloud deck's `CLEAR_INNER`/`CLEAR_OUTER` ring already leaves 70 in
clear sky (the fade gives it at most 0.25 density), so the first fight still happens
in open air.

**L4.** Two suite problems surfaced and were fixed rather than worked around. Three
interceptors chasing the stationary test player killed it mid-run and dragged ten
unrelated checks down with it, so the stream is parked after `_test_planet_roster`
(the same trick `_test_radar` already used). And `_test_enemy_patterns` plus
`_test_turret_roams_on_its_own` took "the first enemy on the field", which is an
interceptor now and chases by design; both spawn their own turret instead, because
the turret's rule (it patrols, it does not follow) is still a rule the city relies
on.

**L5.** Evidence: 769 `PASS`, 0 `FAIL`, `SMOKE TEST PASSED` (baseline 767).

**L6.** Risk: item 3 — the arena's spawn behaviour is a contract that other code and
docs describe. Mitigated by pinning the roster in the suite and by leaving the city
path untouched.
