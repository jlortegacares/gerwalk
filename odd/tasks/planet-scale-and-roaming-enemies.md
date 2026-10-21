# Planet scale and roaming enemies

Branch: `main` (work-unit commits)
Work unit: `ea84898` — feat: enlarge the planet and let enemies roam it
Delivery: `ask-on-risk` default, no chain forecast (about 350 authored lines)
Test runner: `./run.sh --headless tests/smoke_test.tscn`

## Specs

**S1.** The planet is much larger. `PLANET_RADIUS` goes from 80 to 400 units, so a
lap (`2 * PI * PLANET_RADIUS`) goes from ~503 to ~2513 units. The ship keeps the
same top speed, so a lap takes about 94 s of uninterrupted flight instead of 19 s.
The terrain feature size does not change: the shader samples object space, where
one unit is one world unit, so 14-unit features stay 14 units at any radius.

**S2.** Enemies are not attached to the ship. The turret keeps a world position
and roams the planet surface on its own (random waypoints, 12-38 units per leg,
7.5 u/s), so travelling leaves it behind and it is met again only if the ship
comes back. When it has no ship nearby it does not fire.

**S3.** Enemies engage when the ship is close and disengage when it escapes. Aggro
at 46 units, leash at 78. While engaged the turret pursues to a 22-unit ring and
strafes it at 7 u/s; pursuit speed (24) is below the ship's top speed (26.8), so
the player can always break away. The existing telegraph -> pattern -> recover
combat keeps working unchanged.

**S4.** The arena keeps a population of up to 3 turrets. New ones spawn 85-110
units from the ship, biased to the heading, so they appear ahead and off screen.
Turrets farther than 190 units are freed. Killing one is replaced by the ordinary
population top-up instead of a dedicated respawn timer.

**S5.** Checks: the smoke test covers the population, the engaged ring distance,
that an enemy does not follow the ship and does roam, and the existing rolling
assertions keep using `Arena.PLANET_RADIUS`. Visual check with
`tools/capture_frame.gd -- --travel N`.

## Tasks

| ID | Spec | Route | Status |
|----|------|-------|--------|
| T1 | S1, S5 | inline | done |
| T2 | S2, S3, S5 | inline | done |
| T3 | S4, S5 | inline | done |
| T4 | S5 | inline | done |

## Log

**L1.** User request, verbatim:

> quiero que el planeta sea mucho mas grande (para tener mucho que recorrer), los enemigos tambien deben recorrer el planeta como el player.

**L2.** Design notes.

- A bigger radius is what makes a bigger planet here: lap length is `2 * PI * R`,
  and the roll angle per unit travelled is `1 / R`, so the ground still scrolls at
  exactly the ship's speed. Nothing else in the roll model changes.
- Trade-off accepted: at R = 400 the limb leaves the frame. The camera looks 75
  degrees down from 51.5 units above the surface, so the top of the screen meets
  the ground at ~41 units instead of escaping into space. The planet stops reading
  as a globe from the cockpit; it reads as a continuous surface, which is the
  price of a planet that is actually large.
- The alternative (raise the camera until the limb fits again) needs a camera
  about 0.54 * R above the ground, which shrinks the ship and the fight to nothing.
- Enemies keep world-space positions instead of planet-object-space anchors. A
  true terrain anchor would drag them under the play plane as the surface curves
  (the sagitta at 40 units is 2 units even at R = 400) and would make the ship
  collide with anything it flies over. World positions preserve planar hitboxes
  and are visually indistinguishable on a hovering enemy.

**L3. Evidence.** `./run.sh --headless tests/smoke_test.tscn` passes 26
assertions: population, engaged ring distance, turret does not follow the ship
(114.3 units behind), turret roams on its own (11.1 units in 1.5 s), and the roll
assertions still turn `distance / PLANET_RADIUS`. Captures at 1280x720 with
`tools/capture_frame.gd`: the resting frame shows the surface filling the frame
(no limb, as documented) with the first turret engaging, and `--travel 300`
leaves that turret behind while a streamed one appears ahead.
