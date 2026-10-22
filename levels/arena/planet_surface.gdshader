shader_type spatial;
render_mode cull_disabled, diffuse_burley;

// Planet surface for the play field. Procedural on purpose: the ship flies a few
// units above the ground, so a tiled texture would either blur into mush up close
// or shimmer at the horizon.
//
// Sampled in OBJECT space, not world space. The planet rotates under the ship as
// it travels, so the terrain must be painted onto the sphere: the same vertex has
// to keep the same colour no matter how the planet is oriented. World-space noise
// would stay put while the geometry turned, and the ground would look static.
//
// 3D noise instead of spherical UVs: the ship sits at the pole of its own local
// patch, and every UV layout collapses at a pole. Three-dimensional noise has no
// poles and is uniform over the whole sphere.
//
// Land is a field with a sea level: below it the surface is water, above it are
// islands with beaches, vegetation and high ground. Cities are painted on top,
// because the ship flies 1.5 units above the ground and a city has to read from
// 50 units up - a real building at that height is a speck.

uniform float planet_radius = 1600.0;

// Land layout. SEA_LEVEL is a threshold on the land field; the three scales are
// feature sizes in units: continents, islands and shoreline detail.
const float SEA_LEVEL = 0.50;
const float REGION_SCALE = 0.0055;
const float ISLAND_SCALE = 0.021;
const float COAST_SCALE = 0.085;

// City layout. One candidate district per CITY_CELL, CITY_HALF is the half-size
// of a district, CITY_BLOCK the street pitch and CITY_ROAD the road width.
const float CITY_CELL = 26.0;
const float CITY_HALF = 10.0;
const float CITY_BLOCK = 2.9;
const float CITY_ROAD = 0.34;
const float CITY_ROOF = 1.05;
const float CITY_LIT = 0.28;

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

float fbm3(vec3 p) {
	float total = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 3; i++) {
		total += amplitude * value_noise3(p);
		p = p * 2.07 + vec3(13.7, 7.3, 5.1);
		amplitude *= 0.5;
	}
	return total;
}

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	object_position = VERTEX;
}

void fragment() {
	vec3 p = object_position;

	// --- land field ---
	// Three scales with different jobs: region decides where there is open ocean
	// at all, island carves the landmass the ship actually crosses, and the coast
	// octave keeps the shoreline ragged instead of a smooth blob.
	// fbm3 sums weights 0.5 + 0.25 + 0.125 over noise that averages 0.5, so its
	// own mean is 0.4375. Each octave is recentred and stretched before it is
	// composed, or the whole field sits on the sea level and every island turns
	// into one soft blob with no shoreline.
	float region = (fbm3(p * REGION_SCALE) - 0.4375) * 2.2;
	float island = (fbm3(p * ISLAND_SCALE) - 0.4375) * 2.6;
	float coast = (value_noise3(p * COAST_SCALE) - 0.5) * 0.55;

	float field = 0.50 + island * 0.55 + region * 0.45 + coast * 0.18;

	float sea = SEA_LEVEL;
	float height = clamp((field - sea) / (1.0 - sea), 0.0, 1.0);
	float depth = clamp((sea - field) / sea, 0.0, 1.0);
	float land = smoothstep(0.0, 0.010, height);

	float camera_distance = length(VERTEX);
	float fine_weight = 1.0 - smoothstep(35.0, 95.0, camera_distance);

	// --- palette ---
	vec3 deep_water = vec3(0.004, 0.013, 0.030);
	vec3 shallow_water = vec3(0.018, 0.095, 0.125);
	vec3 sand = vec3(0.300, 0.262, 0.176);
	vec3 highland = vec3(0.100, 0.145, 0.102);

	// Two vegetation tones picked by the continental octave. Without it every
	// landmass is the same flat olive and a planet this size looks like a swatch.
	vec3 grass_cool = vec3(0.046, 0.110, 0.086);
	vec3 grass_warm = vec3(0.090, 0.130, 0.052);
	vec3 grass = mix(grass_cool, grass_warm, smoothstep(-0.35, 0.35, region));

	vec3 water = mix(shallow_water, deep_water, smoothstep(0.02, 0.22, depth));
	// Painted swell: the sea is a flat surface, and a little large-scale variation
	// stops it from reading as a solid colour under the glossy roughness.
	water *= 0.90 + 0.20 * value_noise3(p * 0.35);
	vec3 ground = mix(sand, grass, smoothstep(0.008, 0.050, height));
	ground = mix(ground, highland, smoothstep(0.55, 0.85, height));

	vec3 color = mix(water, ground, land);

	// A thin bright ring at the waterline. From 50 units up a beach is a couple of
	// pixels wide, so the foam is what actually draws the coastline.
	float foam = (1.0 - smoothstep(0.0, 0.004, abs(field - sea))) * fine_weight;

	// Contour lines only on land: they read as terrain and help judge travel.
	float contour_phase = abs(fract(height * 9.0) - 0.5) * 2.0;
	float contour = (1.0 - smoothstep(0.0, 0.14, contour_phase)) * land * fine_weight;
	float high = smoothstep(0.55, 0.85, height) * land;

	// --- cities ---
	// Two steps. A cube-sphere chart decides *where* districts are: a tangent frame
	// has two poles where it degenerates and the rolling planet carries the ship
	// over them constantly, while six faces have no singularity at all. The chart
	// alone cannot draw them, because it is not conformal and a straight grid bends
	// across a district, so every district then gets its own tangent plane.
	vec3 n = normalize(p);
	vec3 an = abs(n);
	vec2 uv;
	float face;
	if (an.x >= an.y && an.x >= an.z) {
		uv = n.yz / an.x;
		face = n.x > 0.0 ? 0.0 : 1.0;
	} else if (an.y >= an.z) {
		uv = n.xz / an.y;
		face = n.y > 0.0 ? 2.0 : 3.0;
	} else {
		uv = n.xy / an.z;
		face = n.z > 0.0 ? 4.0 : 5.0;
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

	float district = step(0.66, hash21(seed));
	float inside = 1.0 - smoothstep(CITY_HALF - 0.8, CITY_HALF, max(abs(local.x), abs(local.y)));

	vec2 block = abs(mod(local, CITY_BLOCK) - CITY_BLOCK * 0.5);
	float edge = CITY_BLOCK * 0.5 - max(block.x, block.y);
	float road = 1.0 - smoothstep(CITY_ROAD * 0.5, CITY_ROAD * 0.5 + 0.06, edge);

	// Lit buildings, not lit windows. A window is 0.3 units wide, which is four
	// pixels from 50 units up and turns into white noise the moment the surface
	// tilts. One block of roof is what actually reads as a city from here.
	vec2 building = floor(local / CITY_ROOF);
	float lit = step(hash21(building + seed * 3.0 + face), CITY_LIT);

	vec3 city_color = mix(vec3(0.052, 0.055, 0.066), vec3(0.011, 0.012, 0.016), road);
	float city = district * inside * step(0.02, height);
	// A lit building gets almost no albedo: sunlight on a grey roof washes the
	// emission out to cream, and the point is that the lights read as lights.
	city_color = mix(city_color, vec3(0.028, 0.017, 0.010), lit * (1.0 - road));
	float windows = lit * (1.0 - road) * city;

	color = mix(color, city_color, city);
	// Terrain accents stop at the city edge: a contour line running across an
	// asphalt block reads as a seam in the surface.
	float open_land = 1.0 - city;
	color += vec3(0.32, 0.66, 0.58) * (contour * 0.10 + high * 0.06) * open_land;
	color += vec3(0.55, 0.80, 0.78) * foam * 0.35;

	ALBEDO = color;
	EMISSION = vec3(1.0, 0.26, 0.04) * windows * 0.60;
	ROUGHNESS = mix(0.18, 0.92, land);
	METALLIC = 0.0;
}
