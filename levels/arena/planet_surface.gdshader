shader_type spatial;
render_mode cull_disabled, diffuse_burley;

// Planet surface for the play field. Procedural on purpose: the ship flies a few
// units above the ground, so a tiled texture would either blur into mush up close
// or shimmer at the horizon. World-space noise keeps the same detail at every
// distance and costs no texture memory.

varying vec3 world_position;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	vec2 smoothed = local * local * (3.0 - 2.0 * local);

	float a = hash21(cell);
	float b = hash21(cell + vec2(1.0, 0.0));
	float c = hash21(cell + vec2(0.0, 1.0));
	float d = hash21(cell + vec2(1.0, 1.0));

	return mix(mix(a, b, smoothed.x), mix(c, d, smoothed.x), smoothed.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		total += amplitude * value_noise(p);
		p = p * 2.07 + vec2(13.7, 7.3);
		amplitude *= 0.5;
	}
	return total;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_position.xz;

	// Three scales: continents read at roughly 35 units, ridges at roughly 10,
	// and the fine layer only matters under the ship.
	float continents = fbm(p * 0.030);
	float ridges = fbm(p * 0.105 + vec2(31.0, 17.0));

	// The fine layer is faded out with distance: without mipmaps a sub-pixel
	// procedural octave is pure aliasing and the ground sparkles when the camera
	// moves.
	float camera_distance = length(VERTEX);
	float fine_weight = 1.0 - smoothstep(35.0, 95.0, camera_distance);
	float fine = fbm(p * 0.42 + vec2(7.0, 3.0));

	float raw = continents * 0.55 + ridges * 0.30 + fine * 0.15 * fine_weight;

	// fBm clusters tightly around 0.5. Stretching the useful band is what makes
	// the palette read as terrain instead of one flat shelf colour.
	float height = smoothstep(0.32, 0.68, raw);

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

	// Thin luminous veins along the ridge lines, sparser than the contours.
	float vein = smoothstep(0.72, 0.90, ridges) * smoothstep(0.45, 0.65, height);
	vein *= 0.55 + 0.45 * fine_weight;

	ALBEDO = color;
	ROUGHNESS = 0.92;
	METALLIC = 0.0;
	EMISSION = vec3(0.035, 0.215, 0.200) * vein * 0.60;
	EMISSION += vec3(0.020, 0.115, 0.105) * contour * 0.35;
}
