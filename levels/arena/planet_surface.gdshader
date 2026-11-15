shader_type spatial;
render_mode cull_disabled, diffuse_burley;

// Planet surface for the play field.
//
// The macro shape of the planet -- where the ranges run, which way a river drains,
// where a city could plausibly sit -- is baked offline into a six-face cube field
// (see `tools/bake_planet.gd`), because none of it can be answered one pixel at a
// time: a drainage network needs the whole planet at once. What lives here is
// everything smaller than a texel: the palette, the river's water, the city grid,
// and the shading that turns a height field into relief.
//
// Sampled in OBJECT space, not world space. The planet rotates under the ship as
// it travels, so the terrain must be painted onto the sphere: the same vertex has
// to keep the same colour no matter how the planet is oriented. World-space data
// would stay put while the geometry turned, and the ground would look static.
//
// 3D directions instead of spherical UVs: the ship sits at the pole of its own
// local patch, and every UV layout collapses at a pole. A cubemap has no poles.

uniform float planet_radius = 1600.0;

// The baked terrain. R: signed elevation (0 at the waterline, 1 at the highest
// peak, -1 at the deepest trench). G: distance to the nearest river, normalised by
// `river_max_distance`. B: urban suitability. A: moisture.
uniform samplerCube planet_field : filter_linear, repeat_disable;
// The detail relief, baked: the gradient of the layer this file used to
// synthesise per pixel, plus its cavity. One tap instead of three evaluations of a
// three-chain ridged field, which measured a fifth of the frame at 5120 x 2880.
// It carries mipmaps -- unlike the field above -- because a gradient is a
// direction and the right answer at distance is the average one.
uniform samplerCube planet_detail : filter_linear_mipmap, repeat_disable;
// The slope the detail channels saturate at, in world units per world unit. Pushed
// in from the resource that holds the baked bytes, so the two cannot disagree.
uniform float detail_slope_range = 2.0;
// The relief the elevation channel is scaled by, in world units. This is a shading
// scale only: the geometry never moves, so a "60-unit mountain" is a painted slope.
uniform float relief_units = 60.0;
uniform float river_max_distance = 24.0;
// Direction toward the sun, in object space. The planet rolls, so this changes
// every frame; `Arena` pushes it in.
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);

// City layout. One candidate district per CITY_CELL, CITY_HALF is the half-size
// of a district, CITY_BLOCK the street pitch and CITY_ROAD the road width.
const float CITY_CELL = 26.0;
const float CITY_HALF = 10.0;
const float CITY_BLOCK = 2.9;
const float CITY_ROAD = 0.34;
const float CITY_ROOF = 1.05;
const float CITY_LIT = 0.16;

// Relief shading. RELIEF_STEP is how far apart the two samples that measure the
// baked slope sit, in world units.
const float RELIEF_STEP = 7.0;
// The detail layer. A bake texel is 6.25 units and the camera sees 72, so the
// field cannot carry anything shorter than a hundred units: a smooth plain is
// what it looks like from here. That missing scale is its own baked cubemap now
// (`planet_detail`), sampled once; the notes on how it was differentiated are in
// `tools/bake_planet.gd`.
//
// One march step of the painted cast shadow.
const float SHADOW_STEP = 3.0;
// How much the shading normal exaggerates the measured slope. The sun sits 52
// degrees up, so a flank of twenty degrees swings its term by a tenth and the whole
// range reads flat. Exaggerating the normal is the one place where lying is free:
// the geometry never moves, the palette never moves, only the angle the light sees.
const float RELIEF_BOOST = 1.55;
// River half-width, in normalised distance units. The channel is a distance field,
// so this is sub-texel: bilinear sampling reconstructs a river narrower than the
// texel grid that stores it.
const float RIVER_HALF = 0.055;
const float RIVER_BANK = 0.22;

varying vec3 object_position;

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float value_noise3(vec3 p) {
	vec3 cell = floor(p);
	vec3 local = fract(p);
	vec3 smoothed = local * local * (3.0 - 2.0 * local);

	float n000 = hash31(cell);
	float n100 = hash31(cell + vec3(1.0, 0.0, 0.0));
	float n010 = hash31(cell + vec3(0.0, 1.0, 0.0));
	float n110 = hash31(cell + vec3(1.0, 1.0, 0.0));
	float n001 = hash31(cell + vec3(0.0, 0.0, 1.0));
	float n101 = hash31(cell + vec3(1.0, 0.0, 1.0));
	float n011 = hash31(cell + vec3(0.0, 1.0, 1.0));
	float n111 = hash31(cell + vec3(1.0, 1.0, 1.0));

	float x00 = mix(n000, n100, smoothed.x);
	float x10 = mix(n010, n110, smoothed.x);
	float x01 = mix(n001, n101, smoothed.x);
	float x11 = mix(n011, n111, smoothed.x);

	return mix(mix(x00, x10, smoothed.y), mix(x01, x11, smoothed.y), smoothed.z);
}

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Everything the bake cannot resolve used to be synthesised here: a three-chain
// ridged field whose two finite differences and curvature were the most expensive
// arithmetic in the frame. It is baked into `planet_detail` instead, so this file
// no longer carries the crease functions at all. What remains of the noise below
// is the rock scree and the city chart, which need a single octave of grain.

void vertex() {
	object_position = VERTEX;
}

void fragment() {
	vec3 p = object_position;
	vec3 up = normalize(p);

	// --- terrain ---
	// Two layers, and the split is the whole reason this reads as terrain. The bake
	// carries what needs the whole planet: where the coast runs, where the ranges
	// are, which way the water drains. One of its texels is 6.25 world units and
	// the camera sees a 72-unit patch, so anything shorter than about a hundred
	// units is invisible in the field -- which is why a smooth field looks like a
	// flat plain from up here. `planet_detail` carries that missing scale, already
	// differentiated.
	vec4 field = texture(planet_field, up);
	float macro = field.r;

	// Local tangent frame, built from the surface normal we are about to shade.
	vec3 tangent = normalize(
		cross(up, abs(up.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0))
	);
	vec3 bitangent = cross(up, tangent);

	// The detail layer in one tap. Its rise is stored as a tangent-plane vector in
	// object space, so projecting it onto this fragment's frame is all it takes to
	// get the two slopes back. A vector rather than two components in the local
	// frame because this frame has a discontinuity ring, and a cubemap blends
	// neighbours across it; the note in `tools/bake_planet.gd` has the detail.
	vec4 baked = texture(planet_detail, up);
	vec3 detail_rise = (baked.rgb * 2.0 - 1.0) * detail_slope_range;
	float detail_u = dot(detail_rise, tangent);
	float detail_v = dot(detail_rise, bitangent);
	// Curvature is baked too. It was the difference of the same two samples, so it
	// is a function of the detail alone -- not of the macro field -- and the fourth
	// channel was spare.
	float cavity = baked.a * 2.0 - 1.0;

	// `surface` stays equal to the baked elevation. Only the shading below sees the
	// detail, so the coast, the snowline and the sea keep the shape the bake gave
	// them while the light reads a mountain range on top.
	float surface = macro;

	// Slope from two samples of the macro layer, at the width it can resolve. Seven
	// units: the bake is smooth over about that much, and the detail no longer needs
	// a step of its own because its gradient arrives already measured at one.
	float macro_span = RELIEF_STEP / planet_radius;
	float macro_u = texture(planet_field, normalize(up + tangent * macro_span)).r;
	float macro_v = texture(planet_field, normalize(up + bitangent * macro_span)).r;

	// Rise over run, in world units per world unit, so a slope is an angle and not
	// a scale. Dividing by the arc the samples span rather than by the texel size
	// keeps that honest if the bake resolution ever changes.
	float macro_rate = relief_units / RELIEF_STEP;
	float rise_u = (macro_u - macro) * macro_rate + detail_u;
	float rise_v = (macro_v - macro) * macro_rate + detail_v;
	float steepness = length(vec2(rise_u, rise_v));

	// A crest sits above the mean of its neighbours and a valley below it, and that
	// difference is the only thing that distinguishes a summit from a saddle from
	// directly above: both can have identical slope. `cavity` arrives already
	// softened -- the bake applies the same `x / (1 + |x|)` saturation this file
	// used to apply here, which is what kept the tails of a four-octave curvature
	// from banding into the hollows.
	float land = smoothstep(-0.002, 0.006, surface);

	float height = clamp(surface, 0.0, 1.0);

	// How deep the water is, as the distance to the shore: the drop below sea level
	// divided by the seabed's own slope. Measuring the drop alone says nothing
	// here, because a smooth low-frequency field leaves most of the ocean a hair
	// under the cut, and the whole sea then reads as shallows.
	float seabed = max(steepness, 0.02);
	float offshore = -surface * relief_units / seabed;
	float depth = clamp(offshore / 45.0, 0.0, 1.0);

	// Distance to the lens, in world units. The haze and the foam both need it.
	float camera_distance = length(VERTEX);
	float fine_weight = 1.0 - smoothstep(35.0, 95.0, camera_distance);

	// --- palette ---
	// Deep water is nearly black on purpose: from this height the sea is seen
	// through its own thickness, so the colour that reads is the seabed's, not the
	// sky's. The shallow tone is what carries the turquoise.
	vec3 deep_water = vec3(0.004, 0.014, 0.042);
	vec3 reef_water = vec3(0.016, 0.080, 0.108);
	vec3 shallow_water = vec3(0.040, 0.170, 0.178);
	vec3 sand = vec3(0.300, 0.262, 0.176);
	vec3 rock = vec3(0.135, 0.128, 0.118);
	vec3 snow = vec3(0.640, 0.675, 0.710);

	// Two vegetation tones picked by the baked moisture. Without it every landmass
	// is the same flat olive and a planet this size looks like a swatch.
	vec3 grass_cool = vec3(0.026, 0.072, 0.040);
	vec3 grass_warm = vec3(0.062, 0.100, 0.030);
	vec3 grass = mix(grass_cool, grass_warm, field.a);

	// --- ocean ---
	// Four layers, and none of them is a sine wave.
	//
	// A train of sines is what a first pass reaches for and it never works: one
	// wavelength everywhere, perfectly parallel, identical across the whole sea.
	// That is corduroy. Crossing a second train of comparable weight is worse: it
	// modulates the first one's troughs along the crest and turns the sea into a
	// lattice of ovals. Both were built and both were rejected on screen. What is
	// left is noise, and the seabed itself.
	// The coastal band is deliberately narrow. `depth` is a distance to the shore
	// in units of 45, so a quarter of the range is about eleven units: enough for a
	// ring of shallows that hugs each beach, not enough to paint the open sea
	// turquoise.
	float shore = 1.0 - smoothstep(0.0, 0.25, depth);

	// Reefs. The one thing that keeps the open sea from being a flat fill: isolated
	// shoals where the seabed comes up, with a hard enough edge to read as a shape
	// rather than as mush. Static, because a seabed does not move.
	float bank = smoothstep(0.62, 0.70, value_noise3(p * 0.045)) * (1.0 - shore);
	vec3 water = mix(deep_water, reef_water, bank);
	water = mix(water, shallow_water, shore);

	// Weather. A slow tonal wash that never settles, so the open sea has some life
	// instead of a flat fill. Large and low contrast on purpose: this is the sea
	// breathing, not a wave.
	float drift = value_noise3(p * 0.030 + vec3(TIME * 0.013, 0.0, TIME * 0.009));
	water *= 0.96 + drift * 0.08;

	// Ripples. Two octaves of value noise scrolled down one wind direction and
	// mildly stretched across it, which is what wind does to a surface. The octaves
	// share no ratio, so there is no period for the eye to lock onto.
	//
	// There used to be a third at 2.05-3.8 units, the finest chop, for a fifth of
	// the weight. It cost a whole `value_noise3` per fragment over land as well as
	// sea -- the ocean block is not branched and cannot be, because its colour is
	// one side of the final `mix` -- and at this altitude the two that remain carry
	// the sheen. Their weights are renormalised so the field stays centred on zero
	// and the sea keeps its brightness.
	vec3 wind = vec3(0.62, 0.0, 0.78);
	float ripple =
		  value_noise3(p * vec3(0.42, 0.78, 0.42) + wind * (TIME * 0.55)) * 0.625
		+ value_noise3(p * vec3(0.93, 1.72, 0.93) + wind * (TIME * 0.95)) * 0.375
		- 0.5;
	water *= 1.0 + ripple * 0.22;

	// Whitecaps: a sparse threshold on a finer noise, stretched across the normal so a
	// cap is a short streak and not a pebble. Two things had to be tuned on screen.
	// The scale has to be small, or the caps are pebbles; and they have to cluster,
	// because a uniform sprinkling reads as video noise. Real chop opens and closes in
	// patches as the wind gusts, so a broad field gates the flecks and leaves calm
	// water to breathe between them. Kept off the shallows, where the shoreline
	// already has its own foam and two foams read as one mistake.
	float cap_noise = value_noise3(p * vec3(1.10, 2.60, 1.10) + wind * (TIME * 1.05));
	float gust = smoothstep(0.40, 0.72, value_noise3(p * 0.11 + wind * (TIME * 0.22)));
	float caps = smoothstep(0.850, 0.945, cap_noise) * gust * (1.0 - shore);
	water += vec3(0.150, 0.190, 0.200) * caps;

	// --- land ---
	// Sand at the waterline, grass above it, bare rock where the slope wins, snow
	// where the altitude does. The rock and snow bands are what make a peak read as
	// a peak from directly above: a summit is a colour, not a silhouette.
	// The beach is one or two world units wide, so the sand-to-grass ramp is
	// measured against a height of a couple of units and not against a tenth of the
	// range: a wide sand band turns every coast into a desert.
	vec3 ground = mix(sand, grass, smoothstep(0.002, 0.014, height));
	// Bare rock where the slope wins, and again on the high ground where nothing
	// holds soil. On the detail layer the slope is an angle, so these thresholds
	// mean a hillside rather than a whole continent.
	ground = mix(ground, rock, smoothstep(0.45, 1.05, steepness));
	ground = mix(ground, rock, smoothstep(0.58, 0.88, height) * 0.40);
	float snowline = 0.62 - field.a * 0.06;
	ground = mix(ground, snow, smoothstep(snowline, snowline + 0.10, height));

	// Surface grain. Every colour so far is a smooth function of height, slope and
	// moisture, and a smooth function painted over a smooth height field is clay:
	// the eye finds no texture anywhere, so the whole landmass reads as one poured
	// material. Two noise scales at 2.4 and 1.0 units break the albedo up without
	// touching the shape -- nothing in the lighting changes, only what the ground is
	// made of. It is also what keeps the palette from banding between its thresholds.
	float grain = value_noise3(p * 0.42) * 0.60 + value_noise3(p * 0.98) * 0.40;
	ground *= 0.80 + grain * 0.40;
	// Bare scree on the steepest faces, where nothing holds. A little, and patchy:
	// rock everywhere is as flat as grass everywhere.
	float scree = smoothstep(0.55, 1.15, steepness) * smoothstep(0.42, 0.72, value_noise3(p * 0.21));
	ground = mix(ground, rock * 0.92, scree * 0.55);

	// Rivers. The channel is a distance field, so it draws its own banks: a dark
	// cut, then water. Without the bank the line sits on the grass like a painted
	// stroke instead of a valley with water in it.
	float river = 1.0 - smoothstep(0.006, RIVER_HALF, field.g);
	float bank_edge = 1.0 - smoothstep(RIVER_HALF, RIVER_BANK, field.g);
	ground = mix(ground, ground * 0.62, bank_edge * (1.0 - river) * land);
	ground = mix(ground, shallow_water * 0.72, river * land);

	vec3 color = mix(water, ground, land);

	// A thin bright ring at the waterline. From 50 units up a beach is a couple of
	// pixels wide, so the foam is what actually draws the coastline.
	float foam = (1.0 - smoothstep(0.0, 0.006, abs(surface))) * fine_weight;

	// --- cities ---
	// Two steps. A cube-sphere chart decides *where* districts are: a tangent frame
	// has two poles where it degenerates and the rolling planet carries the ship
	// over them constantly, while six faces have no singularity at all. The chart
	// alone cannot draw them, because it is not conformal and a straight grid bends
	// across a district, so every district then gets its own tangent plane.
	vec3 an = abs(up);
	vec2 uv;
	float face;
	if (an.x >= an.y && an.x >= an.z) {
		uv = up.yz / an.x;
		face = up.x > 0.0 ? 0.0 : 1.0;
	} else if (an.y >= an.z) {
		uv = up.xz / an.y;
		face = up.y > 0.0 ? 2.0 : 3.0;
	} else {
		uv = up.xy / an.z;
		face = up.z > 0.0 ? 4.0 : 5.0;
	}

	vec2 chart = uv * planet_radius;
	vec2 cell = floor(chart / CITY_CELL);
	vec2 seed = cell + vec2(face * 71.0, face * 43.0);

	vec2 cell_uv = (cell + 0.5) * CITY_CELL / planet_radius;
	vec3 cn;
	if (face < 0.5) {
		cn = normalize(vec3(1.0, cell_uv.x, cell_uv.y));
	} else if (face < 1.5) {
		cn = normalize(vec3(-1.0, cell_uv.x, cell_uv.y));
	} else if (face < 2.5) {
		cn = normalize(vec3(cell_uv.x, 1.0, cell_uv.y));
	} else if (face < 3.5) {
		cn = normalize(vec3(cell_uv.x, -1.0, cell_uv.y));
	} else if (face < 4.5) {
		cn = normalize(vec3(cell_uv.x, cell_uv.y, 1.0));
	} else {
		cn = normalize(vec3(cell_uv.x, cell_uv.y, -1.0));
	}
	vec3 centre = cn * planet_radius;
	vec3 ref = abs(cn.y) < 0.85 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 t1 = normalize(cross(ref, cn));
	vec3 t2 = cross(cn, t1);
	vec2 local = vec2(dot(p - centre, t1), dot(p - centre, t2));

	// Where a city is is a baked decision: low, flat, near the coast, in a cluster.
	// The shader only asks, once per district, so the district stays whole instead
	// of being sliced by a soft boundary running through its blocks.
	float district = step(0.30, texture(planet_field, cn).b);
	float inside = 1.0 - smoothstep(CITY_HALF - 3.0, CITY_HALF, max(abs(local.x), abs(local.y)));

	// Streets are not axis-aligned to the chart. A district has its own bearing, and
	// a grid that all lines up with the cube face is the single thing that made the
	// cities look printed rather than built.
	float bearing = hash21(seed + vec2(17.0, 3.0)) * 6.2831853;
	vec2 turned = vec2(
		local.x * cos(bearing) - local.y * sin(bearing),
		local.x * sin(bearing) + local.y * cos(bearing)
	);

	vec2 block = abs(mod(turned, CITY_BLOCK) - CITY_BLOCK * 0.5);
	float edge = CITY_BLOCK * 0.5 - max(block.x, block.y);
	float road = 1.0 - smoothstep(CITY_ROAD * 0.5, CITY_ROAD * 0.5 + 0.06, edge);

	// Buildings are roofs from here, and a roof has no silhouette. What sells a city
	// from 65 units up is the shadow tall blocks throw across the short ones, so
	// each block gets a height and its neighbour in the sun's direction decides
	// whether it sits in shade.
	vec2 unit = floor(turned / CITY_ROOF);
	float storey = hash21(unit + seed * 3.0 + face);
	vec2 sun_local = vec2(dot(sun_direction, t1), dot(sun_direction, t2));
	float sun_local_reach = length(sun_local);
	vec2 sun_step = sun_local_reach > 0.001 ? sun_local / sun_local_reach : vec2(1.0, 0.0);
	vec2 shade_unit = floor((turned + sun_step * CITY_ROOF * 1.6) / CITY_ROOF);
	float shade_storey = hash21(shade_unit + seed * 3.0 + face);
	float shade = smoothstep(0.05, 0.55, shade_storey - storey) * (sun_local_reach * 0.6 + 0.4);

	// Lit buildings, not lit windows. A window is 0.3 units wide, which is four
	// pixels from 50 units up and turns into white noise the moment the surface
	// tilts. One block of roof is what actually reads as a city from here.
	// Lights cluster in a downtown and thin out to the edge of the district. Spread
	// evenly they read as confetti on a grey plate, which is the one thing that made
	// these towns look printed instead of lived in.
	float downtown = smoothstep(0.38, 0.82, value_noise3(p * 0.10));
	float lit = step(hash21(unit + seed * 3.0 + face + 7.0), CITY_LIT * (0.20 + downtown * 2.0));

	vec3 city_color = mix(vec3(0.052, 0.055, 0.066), vec3(0.011, 0.012, 0.016), road);
	city_color *= 1.0 - shade * 0.55 * (1.0 - road);
	city_color = mix(city_color, vec3(0.072, 0.070, 0.066), storey * 0.35 * (1.0 - road));
	float city = district * inside * step(0.02, height);
	// A lit building gets almost no albedo: sunlight on a grey roof washes the
	// emission out to cream, and the point is that the lights read as lights.
	city_color = mix(city_color, vec3(0.028, 0.017, 0.010), lit * (1.0 - road));
	float windows = lit * (1.0 - road) * city;

	color = mix(color, city_color, city);

	// --- relief lighting ---
	// The mesh is a sphere, so its normal says nothing about the terrain. The bake's
	// own gradient does, and that is the whole illusion: one flank in sun and one in
	// shade is what makes a painted height field read as a mountain.
	vec3 relief_normal = normalize(up - tangent * rise_u * RELIEF_BOOST - bitangent * rise_v * RELIEF_BOOST);
	relief_normal = mix(up, relief_normal, land);
	// NORMAL is a view-space slot. Handing it an object-space vector aims the
	// lighting at whatever the camera happens to be looking at, which reads as
	// land that is black from some angles and lit from none.
	vec3 relief_view = (VIEW_MATRIX * (MODEL_MATRIX * vec4(relief_normal, 0.0))).xyz;

	// Cast shadows, marched toward the sun along the tangent plane. The sphere
	// neither casts nor receives shadows, so without this every flank of a range is
	// lit and the range reads as one boulder rather than as a wall.
	//
	// The ray is marched at roughly half the sun's real elevation, and that is the
	// one dishonest line in this shader. At 52 degrees a ridge twenty units high
	// throws a shadow shorter than the ridge is wide, which from straight above is
	// invisible -- physically correct and useless as a picture. A hillshade with no
	// shadow is a colour map. Halving the climb paints the shadow the eye expects.
	vec3 sun_tangent = sun_direction - up * dot(sun_direction, up);
	float sun_reach = length(sun_tangent);
	float shadow = 1.0;
	if (land > 0.01 && sun_reach > 0.001) {
		vec3 march = sun_tangent / sun_reach;
		float climb = dot(sun_direction, up) / sun_reach * 0.5;
		for (int i = 1; i <= 5; i++) {
			float travel = float(i) * SHADOW_STEP;
			vec3 probe = normalize(up + march * (travel / planet_radius));
			float under = texture(planet_field, probe).r;
			// The blocker is the bake, and so is the height it is compared against.
			// Sampling the detail here as well was five more evaluations per
			// fragment, and it measured slower, not faster: 29.8 ms against this
			// line's 22.2 ms at 2560 x 1440. This shader is decided by how many
			// live values the fragment can hold, not by how much arithmetic it
			// writes, so the cheaper line had to be measured to be believed.
			//
			// What it costs is detail-scale casters. Under thirty units they land
			// inside the shadow of the ridge that made them and read as noise at ten
			// pixels per world unit; ridge-to-ridge shadowing is the structure worth
			// keeping, and it is all in the bake.
			float blocker = under;
			float overshoot = (blocker - surface) * relief_units - travel * climb;
			shadow = min(shadow, smoothstep(0.0, 1.2, overshoot));
		}
	}
	color *= mix(1.0, mix(0.38, 1.0, shadow), land);
	// Hollows darker, crests barely lighter. Applied to albedo so it survives the
	// tonemapper in the open rather than clamping in the highlights.
	color *= 1.0 - cavity * 0.45 * land;

	color += vec3(0.55, 0.80, 0.78) * foam * 0.35;

	// Aerial perspective goes last, so it swallows the palette, the accents and the
	// city albedo in one pass. Mixing albedo alone would leave the sun glitter of a
	// far bay punching through the air as a hard spot, so the haze also flattens the
	// surface response and dims the far windows: air is matte, and a light seen
	// through 90 units of it is a glow, not a dot.
	float haze = smoothstep(61.0, 138.0, camera_distance);
	color = mix(color, vec3(0.115, 0.150, 0.180), haze);

	// Glare on the chop, added straight to emission. In albedo it would only dim the
	// diffuse term, and this sea is bright mostly from its specular sheen, which
	// albedo never touches.
	float glare = smoothstep(0.50, 0.95, ripple + 0.5) * (1.0 - land) * (1.0 - shore);
	// Water in a river is a thin line at this altitude, so it gets a sheen instead of
	// chop: the ripple field has nothing to work with inside a two-unit channel.
	float river_sheen = river * land * (1.0 - smoothstep(0.0, 0.10, field.g));
	// Flat glass never looks like water: the chop has to break the sheen up. Roughness
	// follows the ripple field, so the surface catches light in flecks and the eye
	// reads motion even in a still frame.
	float water_roughness = clamp(0.15 + (ripple + 0.5) * 0.22, 0.12, 0.42);

	ALBEDO = color;
	EMISSION = vec3(1.0, 0.26, 0.04) * windows * 0.30 * (1.0 - haze * 0.65)
		+ vec3(0.014, 0.021, 0.024) * glare * (1.0 - haze * 0.65)
		+ vec3(0.030, 0.046, 0.052) * river_sheen * (1.0 - haze);
	ROUGHNESS = clamp(
		mix(mix(water_roughness, 0.92, land), 0.88, haze) - river * land * 0.55,
		0.06,
		1.0
	);
	NORMAL = normalize(relief_view);
	METALLIC = 0.0;
}
