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

void vertex() {
	object_position = VERTEX;
}

void fragment() {
	vec3 p = object_position;

	// Two scales: terrain fields roughly 14 units across carry the readable
	// landmass shapes, and one fine octave gives the ship something to track at
	// speed.
	float terrain = fbm3(p * 0.072);

	// The fine layer is faded out with distance: without mipmaps a sub-pixel
	// procedural octave is pure aliasing and the ground sparkles when the camera
	// moves.
	float camera_distance = length(VERTEX);
	float fine_weight = 1.0 - smoothstep(35.0, 95.0, camera_distance);
	float fine = value_noise3(p * 0.40 + vec3(7.0, 3.0, 11.0));

	float raw = terrain * 0.85 + fine * 0.15 * fine_weight;

	// fBm clusters tightly around 0.5. Stretching the useful band is what makes
	// the palette read as terrain instead of one flat shelf colour.
	float height = smoothstep(0.30, 0.68, raw);

	vec3 abyss = vec3(0.006, 0.014, 0.020);
	vec3 basin = vec3(0.016, 0.038, 0.044);
	vec3 shelf = vec3(0.030, 0.070, 0.070);
	vec3 land = vec3(0.055, 0.110, 0.090);
	vec3 peak = vec3(0.105, 0.155, 0.115);

	vec3 color = mix(abyss, basin, smoothstep(0.10, 0.35, height));
	color = mix(color, shelf, smoothstep(0.32, 0.55, height));
	color = mix(color, land, smoothstep(0.52, 0.74, height));
	color = mix(color, peak, smoothstep(0.72, 0.92, height));

	// Topographic isolines. Soft gradients alone give the eye nothing to track
	// while the ship travels; the lines carry the sense of scale and speed.
	float contour_phase = abs(fract(height * 7.0) - 0.5) * 2.0;
	float contour = (1.0 - smoothstep(0.0, 0.16, contour_phase)) * fine_weight;

	// Thin luminous veins along the high ground, sparser than the contours.
	float vein = smoothstep(0.58, 0.82, terrain) * smoothstep(0.45, 0.65, height);
	vein *= 0.55 + 0.45 * fine_weight;

	ALBEDO = color;
	ROUGHNESS = 0.92;
	METALLIC = 0.0;
	EMISSION = vec3(0.035, 0.215, 0.200) * vein * 0.60;
	EMISSION += vec3(0.020, 0.115, 0.105) * contour * 0.35;
}
