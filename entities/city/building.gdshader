shader_type spatial;
render_mode cull_back, diffuse_burley;

// A city tower, painted procedurally so a district of them costs no textures.
//
// Windows are laid out in WORLD space, not UV. A BoxMesh stretches its UVs across
// each face, so a 38-unit perimeter block and a 21-unit tower would show
// different window sizes from the same material. World coordinates keep one
// window at one size across the whole city, and the building's own origin goes
// into the hash so no two towers light the same windows.
//
// The ghost term is a screen-space ordered dither, not alpha blending. A blended
// tower leaves the transparent queue and stops writing depth, which lets one
// building sort over another; a dithered one stays opaque and still lets the ship
// show through the tower the camera is looking past.

uniform vec3 concrete : source_color = vec3(0.20, 0.21, 0.245);
uniform vec3 glass : source_color = vec3(0.05, 0.065, 0.095);
uniform vec3 lit_window : source_color = vec3(1.0, 0.71, 0.35);
uniform vec3 roof_color : source_color = vec3(0.115, 0.125, 0.15);
uniform vec3 ember_color : source_color = vec3(1.0, 0.42, 0.16);

// 0 is intact, 1 is a ruin about to fall.
uniform float damage = 0.0;
// One-frame white wash when a shot lands.
uniform float flash = 0.0;
// 0 is solid, 1 is fully dithered away.
uniform float ghost = 0.0;

varying vec3 world_position;
varying vec3 world_normal;

const float WINDOW_WIDTH = 2.6;
const float WINDOW_HEIGHT = 3.2;
const float LIT_SHARE = 0.34;
const float WINDOW_INSET = 0.22;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// The classic two-by-two ordered dither, folded twice into a four-by-four one.
float bayer2(vec2 a) {
	a = floor(a);
	return fract(a.x / 2.0 + a.y * a.y * 0.75);
}

float bayer4(vec2 a) {
	return bayer2(0.5 * a) * 0.25 + bayer2(a);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(world_normal);
	float roof = step(0.5, n.y);

	// A wall runs along whichever world axis its normal does not use. Picking the
	// wrong one paints the windows as vertical stripes instead of a grid.
	float along = abs(n.x) > abs(n.z) ? world_position.z : world_position.x;
	vec2 cell = vec2(along / WINDOW_WIDTH, world_position.y / WINDOW_HEIGHT);
	vec2 local = fract(cell);
	vec2 id = floor(cell);

	float frame = step(WINDOW_INSET, local.x) * step(local.x, 1.0 - WINDOW_INSET)
		* step(WINDOW_INSET, local.y) * step(local.y, 1.0 - WINDOW_INSET);
	vec2 building_id = MODEL_MATRIX[3].xz;
	float lit = frame * step(1.0 - LIT_SHARE, hash12(id + building_id));

	vec3 wall = mix(concrete, glass, frame);
	wall = mix(wall, lit_window, lit);
	vec3 surface = mix(wall, roof_color, roof);

	// Damage: the tower darkens and a sparse pattern of vertical cracks picks up a
	// warm glow, so a long demolition shows progress between bar appearances.
	float crack = step(
		0.93,
		hash12(vec2(floor(along * 0.7), floor(world_position.y * 0.45)) + building_id)
	);
	surface = mix(surface, surface * 0.30, damage * (1.0 - roof));
	vec3 emission = lit_window * lit * 2.2;
	emission += ember_color * crack * damage * (1.0 - roof) * 2.4;

	// The hit flash is a single frame of white over the whole tower.
	surface = mix(surface, vec3(1.0), flash);
	emission += vec3(1.0) * flash * 1.5;

	if (ghost > 0.001 && bayer4(FRAGCOORD.xy) < ghost) {
		discard;
	}

	ALBEDO = surface;
	EMISSION = emission;
	ROUGHNESS = mix(0.92, 0.58, frame);
	METALLIC = 0.0;
	SPECULAR = 0.3;
}
