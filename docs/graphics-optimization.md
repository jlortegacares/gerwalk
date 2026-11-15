# Graphics cost: where the frame goes, and what to do about it

Every number below was measured on this machine with `tools/perf_probe.tscn`;
estimates say so. O2, O1, O1b, O4 and O5 are implemented; O6 was measured and
closed without a change. The table below is the state before any of it, and each
option records what it moved.

## Why this exists

The planet reads well and costs too much. Rather than guessing which knob to
turn, the arena is booted, parked over one patch of terrain, and timed with one
thing removed at a time. What follows is that measurement, then the options it
supports, ranked by measured effect.

## Method

`tools/perf_probe.tscn` instantiates `arena.tscn`, waits 30 frames, then times
60 frames per configuration with vsync asked off and no frame cap. Each row
removes exactly one thing the arena draws, so a row's delta is that thing's
cost.

Two things had to be worked around:

- **The refresh rate hides everything.** At 1280 x 720 every configuration
  reports 16.7 ms, on this machine, because macOS still paces the loop to the
  screen even with vsync disabled. A frame that fits in one refresh measures the
  display, not the shader.
- **So the shader is also timed at a supersampled resolution**, where the frame
  falls below the refresh rate and the number becomes real. Two pixel counts
  give a line, and the line separates the cost that scales with pixels from the
  cost that does not.

Machine: Apple M2 (10-core GPU), macOS 27.2, Godot 4.7.2, Metal, Forward+.
Window 1280 x 720 unless noted. Shipping project settings: MSAA off, no FXAA,
no TAA, no debanding, filmic tonemap, no SSAO/SSIL/SDFGI/glow/fog.

## The measurement

| Row | Render size | Frame time | FPS |
| --- | --- | --- | --- |
| baseline | 1280 x 720 | 16.70 ms (capped) | 59.9 |
| baseline | 2560 x 1440 | 27.21 ms | 36.8 |
| full shader | 5120 x 2880 | 98.19 ms | 10.2 |
| relief synthesis stubbed | 5120 x 2880 | 55.99 ms | 17.9 |
| no clouds | 2560 x 1440 | 26.67 ms | 37.5 |
| no stars | 2560 x 1440 | 26.88 ms | 37.2 |
| no sun shadow | 2560 x 1440 | 23.81 ms | 42.0 |
| cheap shadow settings | 2560 x 1440 | 26.64 ms | 37.5 |
| backface culling on | 2560 x 1440 | 27.23 ms | 36.7 |
| seven of ten relief samples removed | 2560 x 1440 | 21.35 ms | 46.8 |
| half resolution | 2560 x 1440 (= 640 x 360) | 16.64 ms | 60.1 |
| cloud rebuild, opening clearing | 384 puffs | 0.60 ms | - |
| cloud rebuild, densest bank | 696 puffs | 0.98 ms | - |

"Relief synthesis stubbed" is a runtime rewrite of the surface shader's
`terrain_detail` body to `return 0.33`: the bake, the palette, the water and the
city chart all still run, only the four-octave detail field disappears.

## The model

Fitting the two full-shader points (3.69 and 14.75 megapixels):

```
frame_ms  =  2.9  +  6.46 * megapixels        # full shader, before O2
frame_ms  =  2.9  +  3.60 * megapixels        # relief synthesis stubbed
frame_ms  =  2.9  +  5.30 * megapixels        # full shader, after O2
```

- **6.46 ms/Mpx is the whole terrain fragment.** At the shipping 1280 x 720
  (0.92 Mpx) that is about **5.9 ms** of a **8.8 ms** frame.
- **2.9 ms is the fixed floor**: CPU, submission, UI, the cloud deck, the star
  shell, everything that does not scale with pixels.
- **The relief synthesis is 2.86 ms/Mpx — 44 % of the terrain fragment**, and
  about 2.6 ms (30 %) of a 1280 x 720 frame. O2 recovered 1.16 of those 2.86
  (see O2 below); what remains is the base height and the two normal samples,
  which are the terrain itself.

The rest of the picture, all measured:

- **Cloud deck: about 1 ms.** Hiding it recovers 1.1 ms at 2.5K (5 %), 0.5 ms
  before O2 made the rest cheaper. It is alpha-blended billboards over the whole
  sky, and there is nothing to win without changing how they are drawn.
- **Star shell: free.**
- **Backface culling: free.** The sphere is closed, and the occluded hemisphere
  is rejected before shading. Leave `cull_disabled` alone.
- **Sun shadow: 0.79 ms/Mpx (2.9 ms, 11 %, at 2.5K).** But the three obvious
  ways to make it cheaper all bought nothing: two cascades instead of four, a
  60-unit far plane instead of 100, blur 2.0 -> 1.0, angular distance 1.8 ->
  1.0 = **0.07 ms**. A 2048 shadow map with a cheaper soft filter = **0.23 ms,
  inside the noise**. What costs is the per-pixel lookup into the shadow map,
  not how it is rendered.
- **Pixels are the dominant axis.** 75 % of a 1280 x 720 frame is per-pixel
  shading, and the cost is linear in pixels. Nothing else in the scene has that
  property.

## What this means for the target hardware

This is an M2. A 2017-class integrated GPU is roughly four times slower per
pixel, so the same 1280 x 720 frame is around 35 ms (28 fps) there, and a Retina
fullscreen window — four times the pixels — is around 107 ms (9 fps). That is
the complaint, and the model points at two things: the relief fragment, and the
fact that the render resolution is whatever the window happens to be.

## Options

### O1. A render-resolution governor — implemented, -49 % at 2560 x 1440

`common/render_scale.gd`, registered as the `RenderScale` autoload.

The game does not choose how many pixels it renders: `canvas_items` stretch hands
the 3D viewport whatever window the OS provides. On a Retina display that is two
to four times the pixels of a 720p target, and a weak GPU pays for all of them.
The governor caps the bill:

- `scaling_3d_scale = min(1.0, 1600 / window_width)`, recomputed whenever the
  window changes size, so a resize or a fullscreen toggle lands on the right
  number instead of a stale one.
- A floor of 0.5, so a 4K window renders 1920 px wide rather than something the
  terrain cannot survive.
- `scaling_3d_mode = FSR` (spatial). FSR2 would be sharper but it is temporal,
  and a planet rolling under a fast ship is exactly what makes temporal
  upscalers ghost.
- Only the 3D pass scales. The UI canvas keeps the window's own resolution,
  because text is already sharp and no upscaler improves it.

**Measured**, window 2560 x 1440:

| | Render size | Frame time |
| --- | --- | --- |
| before | 2560 x 1440 | 21.6 ms (46 fps) |
| after | 1600 x 900 | 11.1 ms (90 fps) |
| before, 4K-ish window | 3200 x 1560 | 29.8 ms (34 fps) |
| after, 4K-ish window | 1920 x 780 (the floor) | ~16.5 ms (60 fps) |

The 11.1 ms figure was taken in the one run where the display pacing lifted and
the frame dropped below the refresh rate; most runs read 16.7 ms there, which is
the screen, not the renderer.

**Look:** at 1:1, the ocean gradient and the hull edges are very slightly softer
and there is no ringing. The HUD is pixel-identical, by construction.

The numeric A/B is not evidence: two runs of *identical* capture arguments differ
by a mean of 0.98 of 255 per channel around the ship, and the upscaled-versus-
native pair differs by 0.86 — less than the run-to-run noise. Gameplay captures are
not bit-reproducible, so the judgment rests on the crops and on the arithmetic
(a 1280 x 720 window renders at exactly 1.0, which the suite asserts), not on a
difference number.

**What it does not do.** The cap alone does nothing at 1280 x 720 — the shipping
window is already below 1600 px — which is where the 4x-slower-than-an-M2 case
lands. That gap is closed by the adaptive half below, not by the cap.

#### O1b. The adaptive half — implemented

The cap is a constant; the hardware is not. The same 1280 x 720 window that costs
7.8 ms here costs about 31 ms on a GPU four times slower, and the cap can do
nothing there because the window is already under it.

So there is a second, inner budget: a ladder of five rungs, each multiplying the
capped render width — 1.0, 0.85, 0.72, 0.6, 0.5, floored at 640 px wide. At 720p
that is 1280x720 down to 640x360. The governor starts at the top and only walks
down when frames are actually being missed.

**The signal.** The obvious one is the GPU frame time, and the engine can report it
(`RenderingServer.viewport_get_measured_render_time_gpu`). On Metal it reports 0.00
at every render scale (`tools/gpu_time_probe.tscn`), so it is not available here.
The frame delta is, but vsync pins it at the refresh interval: it cannot tell a GPU
with three times the headroom from one that just scrapes by. What it *can* tell is
a missed refresh — a frame that needs 17 ms arrives as two intervals, and a GPU with
headroom never produces one. So:

- **Down** when more than 8 % of the last second of frames miss the interval. The
  test is the miss ratio only, with no average-frame-time test beside it: one 33 ms
  frame in twenty pulls a 16.67 ms average to 17.5 and would soften the image for a
  machine that is fine.
- **Up** only after 2.5 s with no misses at all, one rung at a time. This accepts
  that "no misses" is evidence of headroom rather than a measurement of it.
- Every rung change drops the frame history and discards the next 0.5–1.0 s, because
  every sample in it describes a resolution that no longer exists.
- A climb that has to come back down takes that rung off the ladder: 20 s, doubling
  each time it fails again, up to ten minutes. Without it, a machine sitting exactly
  on the boundary would flicker between two rungs forever.

**Measured** with the cap raised out of the way, so the ladder is the only thing
acting (`tools/governor_probe.tscn -- --live 1`, window 3200 x 1560, a full
25.9 ms frame at native):

| | Render size | Frame time |
| --- | --- | --- |
| start | 2720 x 1326 | 25.9 ms (37 fps) |
| settled | 1920 x 936 | 16.67 ms (60 fps) |

It took one step in the first second, tried one rung back up, measured 17.77 ms,
returned, and held 60 fps. The scripted profiles in the same tool cover what this
machine cannot reproduce: a comfortable machine is left alone, a single hitch in
twenty frames does not count, a 4x-slower GPU settles on a rung two below full, and
it climbs back to full quality within about 20 s once the frames are cheap again.

**At 1280 x 720 on this machine the governor never moves**: 7.8 ms is well inside
the budget, so the image is bit-for-bit what it was. The adaptive half is for the
machine that is not this one.

`tools/gpu_time_probe.tscn` exists to record why the GPU-time signal is not used,
rather than leaving the next person to rediscover that it reads zero.

### O2. Terrain relief: ten evaluations per fragment down to three — implemented, -22 %

**Measured:** 27.2 -> 21.2 ms at 2560 x 1440 (**-6.0 ms, -22 %**), and 98.2 ->
80.2 ms at 5120 x 2880 (-18 %). The per-pixel slope goes from 6.46 to
5.3 ms/Mpx; the fixed floor is unchanged. Repeat runs spread about ±0.5 ms, so
the honest number is -22 %, not -22.8.

Where the ten evaluations went, and what each was worth:

| Sample | Count | Outcome |
| --- | --- | --- |
| base height | 1 | kept |
| normal, +/- tangent | 2 | kept |
| cavity, +/- tangent at 6 units | 2 | folded into the two normal samples |
| shadow blocker, 5 march steps | 5 | reads the bake only |

The cavity is a finite difference of the same field at a wider step:
`h(+d) + h(-d) - 2h(0)`, which is `d^2 * laplacian(h)`. A second difference
grows with the square of the step, so the six-unit curvature is the
one-and-a-half-unit curvature times `(6.0 / 1.5)^2 = 16` — the normal samples
the shader already pays for, one constant, no extra evaluations.

The amplification pushed the widest hollows past the range, and a hard clamp
turned them into flat patches with a visible contour. Soft saturation
(`x / (1 + |x|)`) approaches the same limit with no edge anywhere.

The shadow march probes the field five times to ask "is something taller than me
between me and the sun". Reading only the bake keeps ridge-to-ridge shadowing and
loses sub-30-unit casters, which at 10 pixels per world unit land inside the
shadow of the ridge that made them. That is the one visible cost of O2: the
terrain loses its finest cast shadows, and the landscape reads slightly softer
than before. Measured against the pre-change frame the mean absolute difference
is about 2 of 255 per channel, with every landform and coastline preserved.

**What the measurement taught, and it is the most useful part of this
document.** Removing evaluations does not reliably make this shader faster:

| `terrain_detail` sites | Frame time at 2560 x 1440 |
| --- | --- |
| 10 (original) | 26.7 ms |
| 5 (cavity stubbed, march still detailed) | 29.8 ms |
| 3 (cavity stubbed, march on the bake) | 21.4 ms |

The middle row has half the sites of the first and is *slower*. A shader this
size is decided by how many live values the fragment can hold — register pressure
and spilling — not by how much arithmetic is written. The cavity pair, which is
four taps of a four-octave field, turned out to be the expensive ones; the five
march steps were not. Every variant here had to be measured, and two of the three
"obviously cheaper" versions were not.

Two other dead ends worth recording:

- **Cavity from the bake instead of the detail field** (`texture()` at the
  cavity step, two taps): 21.4 ms, the same as deriving it, but visibly coarser
  and it needed a 30x weight to read at all. The derived version keeps the detail
  field's own curvature and looks closer to the original.
- **Restoring the march's detail term** with the cavity already folded: 29.8 ms
  against 22.2 ms. The shadows it buys back cost a third of the whole saving.

### O3. The sun's shadow map: an on/off decision, not a tuning problem

**Measured:** turning it off recovers 2.4 ms at 2.5K (11 %). Every attempt to keep
it but make it cheaper came back inside the noise, because the cost is the
per-pixel lookup, not the cascade setup.

So the honest options are:

- keep it and pay it, or
- drop engine shadows and paint a soft blob under the hull, the turrets and the
  missiles — a decal or a vertex-coloured quad — which costs a fraction of a
  millisecond and keeps the "something is above the ground" cue.

Recommendation: keep it for now. 8 % is not where the money is, and shadows
under the hulls are load-bearing for the sense of altitude. Revisit only if O1
and O2 are not enough.

### O4. Small shader trims — two of four kept, -4.5 % at 2.5K

Four candidate trims, each measured on its own against the shipping shader. The
noise band on this machine is +/- 0.2 ms, so the kept pair is real and the rejected
pair is not close.

| Change | 2x (2560 x 1440) | 4k (5120 x 2880) | Verdict |
| --- | --- | --- | --- |
| before | 21.59 / 21.77 | 80.96 / 81.09 | |
| **A.** drop the fourth terrain octave | 21.10 / 21.32 | 78.74 / 79.05 | **kept** |
| **B.** water ripple 3 octaves -> 2 | 20.81 / 20.55 | 76.90 / 76.83 | **kept** |
| **C.** `pow` folds -> `sqrt` chains | 21.28 / 21.06 | 78.58 / 78.60 | rejected |
| **D.** baked field repacked to RGBA8 | 20.64 / 20.67 | 76.62 / 76.11 | rejected |

**A** removed the 7-world-unit chain (weight 0.04). It cost a twelfth of the
field's arithmetic per call and sits at the resolution of the detail bake that O5
would later introduce, so it was the cheapest thing to give up. The three
remaining chains are reweighted 0.52 / 0.26 / 0.10; land, coast, city and mountain
crops against the pre-O4 shader are indistinguishable at this zoom.

**B** removed the finest ripple octave and renormalised the survivors to
0.625 / 0.375. The ocean block is not branched and cannot be -- its colour is one
side of the final `mix` -- so every octave removed there is paid back across the
whole planet, including the 58 % that is land.

**C was slower**, which is the interesting one. `pow(x, k)` compiles to
`exp2(k * log2(x))`, two special-function operations; `sqrt` is *also* a
special-function operation, not a multiplication. A `sqrt(sqrt(n))` chain needs two
of them for `n^1.25` and three for the crest, so the substitution trades a `log2`
plus an `exp2` for three `sqrt`s. It measured 20.81 -> 21.28 at 2x.

**D was bandwidth, not precision, that failed.** R is *signed* elevation, so a
UNORM repack needs `elev * 0.5 + 0.5` and then steps by 0.47 world units -- against
a shadow `smoothstep` that softens over 1.2 units and a waterline foam drawn at
+/- 0.006. The repack halved the file to 6.29 MB and changed the frame by nothing
(20.64 / 20.67 at 2x), because field traffic is about 13 GB/s of roughly 100
available. It did visibly move the coastline: the land-site search in
`tools/terrain_study.gd` picked different sites on the same planet afterwards.
Halving VRAM is not worth a shoreline that shifts by half a world unit.

O4 total: 21.68 -> 20.68 ms at 2x (**-4.5 %**), 81.04 -> 76.86 at 4k (**-5.2 %**).

### O5. Bake the relief instead of synthesising it — implemented, -16.9 % at 4k

This was the ceiling, and it was measured before it was built. `tools/perf_probe`
carried a `flat detail` row that rewrote the surface shader with `terrain_detail`
stubbed to a constant: **61.7 ms at 5120 x 2880 against 76.5**, or a fifth of the
frame. That number is the most this option could ever return, and nothing was
built until it was known.

The plan as first written was wrong, in a way worth recording. It proposed baking
the detail *height* at 2048 per face and taking finite differences at runtime. At
2048 a texel is 1.22 world units against a 1.5-unit sample offset, so the bilinear
gradient would be near-constant per texel and the relief would facet like a mesh of
squares -- and RGBAH at that size is 100 MB.

What the fragment actually consumes is smaller than it looks. `detail`, the
synthesised height, feeds exactly three things: two finite differences and one
curvature term. Nothing displaces geometry and the palette never reads it. So the
field is differentiated offline, at exactly the offsets the shader used, and the
fragment reads the answers.

**The channel layout is a tangent-plane vector, not two components.** Channels
R, G, B hold the detail rise as a vector in object space, mapped from
-2.0 .. 2.0 slope onto 0 .. 1; A holds the cavity. Two frame-relative scalars
would have been the obvious encoding and would have baked a defect: the tangent
frame the shader builds (`cross(up, |up.y| < 0.9 ? Y : X)`) flips ninety degrees
along a circle of the planet, and a cubemap blends neighbouring texels. Every texel
on that circle would average two values measured in different frames. Stored as a
vector the field is frame-free, and the shader projects it onto its own frame with
two dots.

Cavity is baked rather than rederived from `rise_u + rise_v`. The identity is
exact -- `detail_u + detail_v - 2 * relief` is literally the sum of the two
differences -- but it only holds while the gain and the offsets in two files agree,
and the fourth channel was already being read.

`DETAIL_SLOPE_RANGE = 2.0` was read off the data with a `--detail-stats` pass, not
guessed: `|g|` has a p99 of 1.14 and only 0.012 % of texels pass 2.0, so 2.0 spends
the byte where the slopes are and clips only the sharpest crests. A byte resolves
0.0157 of slope, under a degree of facet at `RELIEF_BOOST`.

| | 2x (2560 x 1440) | 4k (5120 x 2880) |
| --- | --- | --- |
| after O4 | 20.81 / 20.55 | 76.90 / 76.83 |
| **after O5** | **17.36 / 17.38** | **63.94 / 64.13** |

**-15.5 % at 2.5K, -16.9 % at 4K**, and 2.2 ms off the 61.7 ms ceiling at 4k --
which is the price of the cubemap tap replacing the arithmetic. The fragment went
from 5.49 to 4.35 ms/Mpx at 4k.

Costs, all of them real:

- **33.6 MB of VRAM** at 1024 per face with mipmaps, 3.1 world units per texel
  against the 1.5-unit sample offset. `FLAG_COMPRESS` makes the file 8.8 MB on
  disk; the runtime upload is the same either way. Applying the same flag to the
  older field takes it from 12.6 MB to 5.6 MB, so the two artifacts together are
  14.4 MB in the repository instead of 45.2.
- **A 72-second bake** instead of 7.4, almost all of it the detail pass. The
  shader's `hash31` / `value_noise3` / crease functions are transcribed into
  GDScript in `tools/bake_planet.gd`, so the bake needs no window and runs
  headless.
- **A different noise instance.** GDScript is 64-bit and the shader is 32-bit, so
  the transcribed `hash31` produces an uncorrelated field of the same statistics,
  not the same field. The macro terrain, the palette, the water and the cities are
  identical -- they come from the unchanged bake -- but the specific creases of
  the detail layer move. Whole-frame captures differ by 1.4 % on average, above
  the 0.8 % run-to-run noise floor; side by side, the character is the same and
  the coastlines match texel for texel. Making it bit-exact would mean emulating
  float32 at four roundings per hash, or moving the bake onto the GPU and giving
  up the headless bake.
- **The unresolved look problem does not move.** Mountains still read softer than
  they should at close range. O5 changes where the relief comes from, not what
  shape it has; the "poured wax" note in `odd/tasks/planet-terrain.md` still stands
  and needs a different fix.

### O6. The cloud streaming hitch — measured, and it is not one

**Measured and closed.** The deck rebuilds whenever the ship crosses an 18-unit
cell, so it never shows up in a frame average; `tools/perf_probe.tscn` now times
the rebuild directly, in isolation:

| Site | Puffs | Rebuild |
| --- | --- | --- |
| the opening clearing | 384 | 0.60 ms |
| the densest bank the search found | 696 | 0.98 ms |

The worst case is one millisecond, once every half second at cruise. That is not
a hitch, and a `density_at` cache would be complexity bought with nothing. The
proposal assumed a rebuild cost an order of magnitude more than it does; the
measurement says leave it alone.

## Recommended sequence

1. ~~**O6**~~ — measured at 0.6-1.0 ms, closed without a change.
2. **O2** — done, -22 % at 2.5K.
3. **O1** — done, -49 % at 2.5K. It protects big windows and fullscreen; it does
   nothing at 720p, which is where weak hardware still hurts.
4. **O1b** — done. The adaptive ladder reaches 720p, at the cost of rendering it at
   a lower resolution. It is the lever that trades sharpness for frame rate.
5. **O4** — done, -4.5 % at 2.5K. Two trims kept, two rejected on measurement.
6. **O5** — done, -16.9 % at 4K. The architectural ceiling, and most of it was
   collected.

Every option on the list has now been either delivered or measured and closed, and
`tools/perf_probe.tscn` carries a row for each so the numbers can be re-derived
rather than trusted.

Delivered, in the order it happened: O2 took the per-pixel slope from 6.46 to
5.3 ms/Mpx, O1 cut the pixel count of a 2560 x 1440 window to 1.44 Mpx, O1b walks
the render width down another ladder when frames are still missed, O4 trimmed 4.5 %
out of the fragment, and O5 replaced the relief synthesis with a baked gradient.
O1 and O2 together take a 2560 x 1440 window from 27.2 ms to 11.1 ms (**-59 %**),
and a 4K window from roughly 40 ms to the 16.7 ms refresh ceiling. On the shader
itself, O2 + O4 + O5 took a 2560 x 1440 *render* from 27.2 ms to 17.4 ms
(**-36 %**) and a 5120 x 2880 render from 98.2 ms to 64.0 ms (**-35 %**), which is
a 5.86 -> 4.35 ms/Mpx slope.

What is left is a machine four times slower than this one at the shipping 1280 x 720:
the adaptive ladder answers it by rendering at 640 x 360, which is a real loss of
sharpness rather than a free win. Nothing on this list buys that back any more --
the next lever is not a shader trim but a decision about what those pixels should
contain.

## How to check it

```
./run.sh tools/perf_probe.tscn                       # full sweep, a few minutes
PERF_ROWS="baseline 2x" ./run.sh tools/perf_probe.tscn   # one row, seconds
```

The tool prints the machine, the render size, and one line per configuration.
Run it before and after each option; the deltas are the receipt. Rows that
report 16.6 ms are measuring the display, not the change — use a larger window
or a supersampled row for those.

## Not worth touching

- **Cloud deck** (~1 ms, 5 %). Do not trade its look for performance; there is
  nothing there.
- **Star shell, backface culling, MSAA, tonemapping, post effects.** All already
  free or already off.
- **Sphere tessellation.** 192 x 96 exists to keep the facet gap at 0.21 units;
  lowering it reintroduces the ground bobbing under the ship.
