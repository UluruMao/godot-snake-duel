shader_type canvas_item;

uniform float barrel_strength : hint_range(0.0, 0.5) = 0.10;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.22;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.55;
uniform float glow_strength : hint_range(0.0, 1.0) = 0.45;
uniform float grain_strength : hint_range(0.0, 0.2) = 0.02;
uniform float glitch_amount : hint_range(0.0, 1.0) = 0.0;
uniform float rgb_shift : hint_range(0.0, 0.05) = 0.0;

float hash(float n) {
	return fract(sin(n) * 43758.5453123);
}

vec2 barrel(vec2 uv) {
	vec2 c = uv * 2.0 - 1.0;
	float r2 = dot(c, c);
	c *= 1.0 + barrel_strength * r2;
	return c * 0.5 + 0.5;
}

void fragment() {
	vec2 uv = barrel(UV);

	if (glitch_amount > 0.001) {
		float band = floor(uv.y * 36.0);
		float n = hash(band + floor(TIME * 24.0) * 7.13);
		uv.x += (n - 0.5) * glitch_amount * 0.12 * step(0.55, n);
	}

	bool outside = uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0;
	vec3 col = vec3(0.0);
	if (!outside) {
		vec2 off = vec2(rgb_shift * (1.0 + glitch_amount), 0.0);
		float r = texture(TEXTURE, clamp(uv + off, vec2(0.0), vec2(1.0))).r;
		float g = texture(TEXTURE, uv).g;
		float b = texture(TEXTURE, clamp(uv - off, vec2(0.0), vec2(1.0))).b;
		col = vec3(r, g, b);

		float sl = sin(uv.y * 200.0 * 6.2831);
		col *= 1.0 - scanline_strength * (0.5 + 0.5 * sl);

		float d = distance(uv, vec2(0.5));
		col *= 1.0 + glow_strength * smoothstep(0.75, 0.0, d);
		col *= 1.0 - vignette_strength * smoothstep(0.32, 0.85, d);

		// static grain only — no TIME term, so the screen never flickers
		float gr = hash(dot(UV, vec2(123.4, 567.8)));
		col += (gr - 0.5) * grain_strength * 2.0;
	}
	COLOR = vec4(col, 1.0);
}
