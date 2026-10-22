# Planet: bigger world, islands and cities

Branch: `main`. Delivery: unreviewed (runtime ineligible for immutable review).
Tests: `./run.sh --headless tests/smoke_test.tscn`.

## Specs

S1. **The planet is much larger.** `PLANET_RADIUS` goes from 400 to 1600 (4x).
A lap (`2 * PI * PLANET_RADIUS`) goes from ~2513 to ~10053 units, about 6.3
minutes at GERWALK cruise and 3.5 at FIGHTER cruise. Nothing else about travel
changes: the surface still passes under the ship at exactly the distance flown.

S2. **Tessellation tracks the radius.** The facets are chords, so the surface
sags below the true sphere by about `(vertex spacing)^2 / (8 * radius)` at each
triangle's centre. At 400/96 segments that is 0.21 units; at 1600 with the same
count it would be 0.86 and the ground would visibly rise and fall under the ship
as facets rolled past. `PLANET_SEGMENTS` / `PLANET_RINGS` go to 192 / 96, which
holds the sag at 0.21 units.

S3. **There are islands.** The surface has a sea level: below it, deep and
shallow water; above it, a narrow sand beach, vegetation and high ground. Islands
are 30-80 units across so a whole one fits on screen, with a ragged shoreline
and a foam line at the waterline. Water is painted scenery: no collision, no
nodes, the play plane is untouched.

S4. **There are cities, painted from above.** Per the user's choice ("Pintadas
desde arriba"), a city is a district painted into the shader: an opaque asphalt
square with a street grid and scattered amber-lit roofs, placed on dry land only.
No 3D blocks, no collision, no gameplay change.

S5. **Nothing regresses.** All smoke assertions stay green, and the planet still
turns `distance / radius` with the ship always at its pole.

## Tasks

| ID | Spec | Status | Evidence |
|----|------|--------|----------|
| T1 | S1 | done | `PLANET_RADIUS = 1600`, lap comment updated |
| T2 | S2 | done | `PLANET_SEGMENTS = 192`, `PLANET_RINGS = 96`, sag comment |
| T3 | S3 | done | `planet_surface.gdshader` land field, sea palette, foam |
| T4 | S4 | done | cube-sphere district chart, per-district tangent plane |
| T5 | S5 | done | smoke green twice, captures reviewed |
| T6 | S5 | done | `_test_planet_rolls_with_the_player` tolerance scaled to the expected angle |

## Log

L1. Request, verbatim: "ahora quiero que agrandes el planeta mucho mas y en el
crea islas y ciudades".

L2. City style, decided by the user before implementation, because the camera
makes it a product fork: at 50 units up a building tall enough to read would have
to cross the play plane at y = 0. Chosen: "Pintadas desde arriba" - painted
districts with lit windows in the shader, over the islands.

L3. Design. Islands are a land field with a sea level, three octaves: continents
~1800 units, islands ~48, shoreline ~12. Each octave is recentred and stretched
first, because `fbm3` averages 0.4375 and a raw field sits on the sea level.
Cities need a pole-free placement scheme: a per-point tangent frame degenerates
at two poles and the rolling planet carries the ship over them, so districts are
placed on a cube-sphere chart, and each district then draws on its own tangent
plane because the chart is not conformal and a grid drawn in it bends.

L4. Iteration from captures, all found by looking at the frame:
- First pass was ~70% ocean with no visible coastline: the field sat on the sea
  level. Fixed with per-octave recentring and a stretch.
- `step(0.30, hash)` lit 70% of roofs, not 30%. Inverted the comparison.
- The city was a ghost with terrain contours through the asphalt: `city` was
  `district * inside * land` and `land` is a `smoothstep`, so it never reached 1.
  Made the land gate binary and the city opaque.
- Terrain accents were added after the city mix, so contour lines ran across the
  blocks. Masked them by `1 - city`.
- Windows 0.34 units wide (4 px) aliased into white noise; a lit roof of 1.05
  units is what reads from 50 units up.
- Lit roofs came out cream because the sunlit grey albedo washed the emission;
  lit roofs now carry almost no albedo and the emission is saturated amber.

L5. Verification. `./run.sh --headless tests/smoke_test.tscn` passed twice; the
roll assertion reads 0.0249 rad against an expected 0.0249 with a 10% tolerance.
Captures: `/tmp/gw-m75.png` (GERWALK, two districts and a coastline) and
`/tmp/gw-mfighter.png` (FIGHTER). The shader constants are named (`SEA_LEVEL`,
`REGION_SCALE`, `ISLAND_SCALE`, `COAST_SCALE`, `CITY_CELL`, `CITY_HALF`,
`CITY_BLOCK`, `CITY_ROAD`, `CITY_ROOF`, `CITY_LIT`) and the docs table points at
them.

L6. Risk: item 6 - a painted shader has no test that can pin the look, so the
captured frames are the check. No data, security, contract, concurrency or
delivery surface is touched; gameplay stays planar.
