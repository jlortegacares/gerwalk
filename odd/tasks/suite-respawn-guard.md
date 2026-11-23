# Suite respawn guard: a death mid-run must not restart the run

Branch: `main`.
Test runner: `/Applications/Godot.app/Contents/MacOS/Godot --headless tests/smoke_test.tscn`

## Specs

**S1.** A death during the suite may not navigate. The runner detaches
`GameOver.respawn_requested` and `GameOver.menu_requested` from the HUD's scene
changes at boot, so neither the respawn countdown nor the death screen's own button
can reload the scene the suite runs in.

**S2.** The ship may not die between checks. The runner parks it under a sentinel
`_invulnerable` (`SmokeSuite.SUITE_INVULNERABLE`), and every test that clears the
frames for a real hit puts the hull back at full health under the sentinel when it
is done (`_park_ship()`).

**S3.** The death test keeps its own behaviour: it still drains the hull to zero,
still expects the blast and the shockwave, and still drives the two answers through
its own recorder.

**S4.** No assertion changes. The suite prints the same 775 PASS, one boot, exit 0.

## Tasks

| ID | Spec | Status | Evidence |
|----|------|--------|----------|
| T1 | S1 | done | `tests/smoke_test.gd`: both signal connections dropped right after the ship is resolved |
| T2 | S2 | done | `SmokeSuite.SUITE_INVULNERABLE` + `_park_ship()`; boot parking in the runner |
| T3 | S2 | done | `_park_ship()` at the end of `_test_audio`, `_test_maneuverability`'s glide block, `_test_dash_evasion`, `_test_damage_and_iframes`, `_test_boss` |
| T4 | S3, S4 | pending | awaiting the suite run |

## Log

**L1.** Discovered while validating the pad panel: the suite printed 1,456 PASS with
12 failures and still exited 0. The run had booted twice — `arena exposes a Player`
appears at line 3 and again at 696 — and the second boot was fully green.

**L2.** Root cause: a stray enemy shot killed the ship mid-suite. `_dead` then gates
`hud._unhandled_input`, so the pause test could not open the menu, and the ship's
own physics stopped, so the vapour, the leg pose, the engine hum and the hull impact
all went quiet. Five seconds later the death screen's countdown fired
`respawn_requested` and `hud._restart_run()` reloaded the scene, restarting the whole
suite from a fresh world.

**L3.** Not the refactor. The same double boot reproduces on `HEAD` with the working
tree stashed: 1,283 PASS, 4 FAIL, two boots. The suite already knew it could happen —
`_test_death` carries the comment "an earlier encounter is allowed to have landed a
killing hit in another test" — but nothing stopped it.

**L4.** Two layers, because either one alone leaves a hole: the sentinel prevents the
death, and the detached signals stop a death from silently doubling the run. A future
stray death now shows up as the single run of failures it is.

**L5.** The sentinel is a number, not a new player flag: the gameplay code keeps its
own rules, and the tests already use `_invulnerable` for exactly this. `_park_ship()`
restores health as well as frames, so a check that measured a real hit does not leave
the next test one point from death.
