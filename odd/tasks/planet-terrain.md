# Planet terrain: baked relief, rivers and city sites

Objective: replace the flat-lit, height-colour-only planet surface with a terrain
whose macro structure is baked on the CPU and shaded as relief.
Branch: `main` (working tree, uncommitted). Test runner: `./run.sh --headless tests/smoke_test.tscn`.

## Specs

- **S1** The surface must show hills, mountains, rivers and cities that read as
  places. Verbatim request: "ahora quiero que plantees una mejora en el terreno,
  que tenga cerros, montañas, rios y siluetas de ciudades mas realistas".
- **S2** The macro field is baked on the CPU offline and shipped as a resource.
  Verbatim choice: "horneado en CPU". Runtime cost is a texture fetch, not a
  terrain generation pass.
- **S3** Relief is painted, not geometric. `entities/player/player.gd` pins the
  hull to `y = 0`; `Arena.GROUND_Y = -1.5`; the sphere's vertices are ~52 units
  apart. Nothing may rise above the play plane, so the mesh stays a sphere and
  every landform is a shading effect.
- **S4** The accepted sea is untouched: four noise layers, the
  `deep_water`/`reef_water`/`shallow_water` palette, `EMISSION` glare and
  ripple-driven roughness. The sea stays flat and at sea level.
- **S5** Gameplay contracts are unchanged: no terrain collision, planar hitboxes,
  the missile contract (8 / 1.8 s / nearest-first / 55 deg cone / 48 range) and the
  cloud deck's single density field.
- **S6** The bake is reproducible: same seed and constants produce byte-identical
  output. The tool is checked in and rerun by hand.
- **S7** The smoke suite stays green.

## Tasks

- T1 Probe the engine APIs the design depends on. Done: `Cubemap.create_from_images`
  works, `Cubemap` does **not** serialize its images, a `Resource` holding
  `Array[Image]` does, and RGBAH survives the round trip.
- T2 Write `tools/bake_planet.gd`: cube-face encoder, noise field matching the
  current land/sea layout, drainage, river distance field, city suitability, save.
- T3 Prove the cube-map orientation convention with an analytic diff (bake the
  direction ramps, render the cube and the analytic formula, compare).
- T4 Bake the field and inspect it visually.
- T5 Load the field in `arena.gd`, build the `Cubemap`, feed the shader, and update
  the object-space sun direction every physics frame for cast shadows.
- T6 Rewrite the surface shader's terrain half: elevation from the field, normals
  from its gradient, sun-marched shadows, rivers, snow/rock palette, city sites.
- T7 Iterate on captures.
- T8 Update `docs/combat-prototype.md`.
- T9 Run the smoke suite.

## Log

- **L1** "ahora quiero que plantees una mejora en el terreno, que tenga cerros,
  montañas, rios y siluetas de ciudades mas realistas"
- **L2** "horneado en CPU"
- **L3** Constraint established while planning: the hull is at `y = 0`, the ground
  at `y = -1.5`, and the sphere's vertices are 52 units apart, so real geometry
  cannot produce mountains. Relief must be painted, like the cities already are.
- **L4** The bake cannot be a start-up cost: 6 faces at usable resolution is
  millions of cells. It runs offline and ships as `levels/arena/planet_field.res`.

## Log

- L5 (2026-11-14). Relief pass. The look read as poured wax, and the cause was a
  sign error in intent: `(1 - |n|)^2` smooths the ridged fold into a dome, because
  the square of a V has zero slope at its point. Replaced by `pow(n, 1.35)` for the
  short chains and `pow(n, 1.10)` for the two long ones, which keeps the crease.
  Also: curvature measured at a 6-unit step instead of the 1.5-unit shading step
  (a summit is a landform property, not local grain); cast shadows sharpened from a
  5-unit to a 1.2-unit softness; `RELIEF_BOOST = 1.55` on the shading normal only,
  because a 52-degree sun swings its term by a tenth on a 20-degree flank; albedo
  grain at 2.4 and 1.0 units plus scree on the steepest faces, which was the missing
  texture everywhere; palette rebalanced (rock 0.135, grass 0.026/0.072/0.040,
  snowline 0.62).
- L6. Cube seams. `_stitch()` feathers the outer two texels of every face across the
  neighbour graph before drainage; half a texel of phase between two faces was
  enough to draw a crease where a face boundary crosses the view.
- L7. Cities. `_build_city_sites` scored "low, flat, near water", which selects
  sandbars: the best sites on the planet were fifty-unit islands. Added a
  `hinterland` term (`coast > 45..85`) so a district of twenty units has land around
  it. The shader no longer exempts cities from relief shadow, cavity and cast
  shadow, and the lights are gated by a downtown mask instead of spread evenly.
- L8 (2026-11-15). Performance pass over the same shader; the numbers live in
  `docs/graphics-optimization.md`. Two trims kept (the 7-unit chain and the finest
  water ripple, -4.5 % at 2.5K); two rejected on measurement (`sqrt` chains are
  slower than `pow`, and an RGBA8 field repack bought nothing because bandwidth is
  not the limit). Then the detail layer stopped being synthesised at all: its
  gradient and cavity are baked into `planet_detail.res` at 1024 per face, stored
  as an object-space tangent vector so the cubemap can blend across the frame's
  discontinuity ring. -16.9 % at 4K, 2.2 ms short of the measured ceiling. The look
  is unchanged in character and the creases move, because GDScript is 64-bit and
  the transcribed hash is a different instance of the same noise.
- Open: a straight low-contrast line still crosses the view at one orientation. It
  is not the cubemap (the field renders clean) and not the city (disabling it keeps
  the line), and it survives a constant-emission probe only when emission is real,
  so it lives in `color`. Not yet isolated.
- Open: snow almost never appears -- 0.8% of land is above 0.6 -- so the peaks have
  no summit colour.
