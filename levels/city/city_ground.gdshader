shader_type spatial;
render_mode cull_disabled, diffuse_burley;

// The street grid, painted from world coordinates so the asphalt, the curb and
// the centre lines line up with the towers exactly. The city places its blocks on
// the same `pitch` these uniforms carry, which is the whole reason the level can
// change its grid without repainting a texture.

uniform vec2 grid_origin = vec2(0.0);
uniform float block = 26.0;
uniform float street = 12.0;
uniform float pitch = 38.0;
uniform float sidewalk = 2.5;
uniform vec3 asphalt : source_color = vec3(0.085, 0.09, 0.105);
uniform vec3 pavement : source_color = vec3(0.155, 0.16, 0.175);
uniform vec3 curb : source_color = vec3(0.20, 0.205, 0.22);
uniform vec3 line : source_color = vec3(0.86, 0.74, 0.40);

varying vec3 world_position;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 local = world_position.xz - grid_origin;
	vec2 cell = mod(local, pitch);

	// A cell is a block; the band after it is the street. The block is paved and the
	// street is asphalt, which is what makes a plaza or a demolished lot read as a
	// lot instead of as a hole where a tower used to be.
	float street_x = step(block, cell.x);
	float street_y = step(block, cell.y);
	float on_street = max(street_x, street_y);

	// The sidewalk hugs the block from the street side. Painting it inside the
	// block would hide it: the tower's footprint reaches the block edge, so the
	// band a player can actually see is the one in the road, against the wall.
	float curb_x = min(cell.x - block, pitch - cell.x);
	float curb_y = min(cell.y - block, pitch - cell.y);
	float walk = clamp(
		street_x * step(curb_x, sidewalk) + street_y * step(curb_y, sidewalk),
		0.0,
		1.0
	);

	// Centre lines run down the middle of each street band, dashed along its length.
	float mid = (block + pitch) * 0.5;
	float along_x = step(abs(cell.y - mid), 0.16) * step(0.5, fract(local.x / 7.0));
	float along_z = step(abs(cell.x - mid), 0.16) * step(0.5, fract(local.y / 7.0));
	float markings = max(along_x, along_z);

	float grain = hash12(floor(world_position.xz * 3.0)) * 0.6
		+ hash12(floor(world_position.xz * 0.7)) * 0.4;
	vec3 surface = mix(mix(pavement, asphalt, on_street), curb, walk)
		* (0.88 + grain * 0.24);

	ALBEDO = mix(surface, line, markings);
	ROUGHNESS = mix(0.94, 0.70, markings);
	METALLIC = 0.0;
}
