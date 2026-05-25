shader_type canvas_item;

uniform vec4 color_dark : source_color = vec4(0.1, 0.1, 0.15, 0.6);
uniform vec4 color_light : source_color = vec4(0.2, 0.5, 0.9, 1.0);
uniform int band_count = 6;
uniform float focus_progress : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float safe_bands = float(max(band_count, 2));

	float inverted_uv = 1.0 - UV.x;
	float blended_uv = mix(UV.x, inverted_uv, focus_progress);

	float band = floor(blended_uv * safe_bands);
	float local = fract(blended_uv * safe_bands);
	float smooth_local = smoothstep(0.0, 0.5, local);
	float pos = (band + smooth_local) / (safe_bands - 1.0);

	float shimmer = sin(UV.x * 2.0 * 3.14159 - TIME * 0.4) * 0.04;

	COLOR = mix(color_dark, color_light, clamp(pos + shimmer, 0.0, 1.0));
}
