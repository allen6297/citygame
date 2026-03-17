shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

uniform vec2 u_panel_size = vec2(320.0, 180.0);
uniform float u_corner_radius = 30.0;
uniform float u_distortion_intensity = 0.35;
uniform float u_blur_intensity = 1.2;
uniform float u_alpha : hint_range(0.0, 1.0) = 0.34;
uniform vec4 u_tint : source_color = vec4(0.90, 0.95, 1.0, 1.0);
uniform float u_tint_strength : hint_range(0.0, 1.0) = 0.14;
uniform float u_brightness : hint_range(0.5, 1.5) = 1.02;
uniform float u_gradient_strength : hint_range(0.0, 0.5) = 0.08;
uniform float u_edge_highlight_strength : hint_range(0.0, 0.5) = 0.12;
uniform float u_warp_strength : hint_range(0.0, 8.0) = 1.6;
uniform float u_warp_scale : hint_range(1.0, 40.0) = 12.0;
uniform float u_warp_speed : hint_range(0.0, 3.0) = 0.25;

float rounded_box_sdf(vec2 p, vec2 half_extents, float radius) {
	vec2 q = abs(p) - (half_extents - vec2(radius));
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

vec3 get_blurred_color(sampler2D tex, vec2 screen_uv, vec2 pixel_size, float blur_radius) {
	vec3 color = vec3(0.0);
	float total_weight = 0.0;

	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			vec2 offset = vec2(float(x), float(y)) * blur_radius * pixel_size;
			float weight = 1.0 / (1.0 + float(x * x + y * y));

			color += texture(tex, screen_uv + offset).rgb * weight;
			total_weight += weight;
		}
	}

	return color / max(total_weight, 0.0001);
}

void fragment() {
	vec2 panel_size = max(u_panel_size, vec2(1.0));
	vec2 local_pos = (UV - 0.5) * panel_size;
	vec2 half_size = panel_size * 0.5;
	float corner_radius = clamp(u_corner_radius, 1.0, min(half_size.x, half_size.y));
	float dist = rounded_box_sdf(local_pos, half_size, corner_radius);
	float aa = max(fwidth(dist), 1.0);
	float mask = 1.0 - smoothstep(0.0, aa, dist);
 
	if (mask <= 0.0) {
		discard;
	}

	vec2 safe_normal = normalize(local_pos + vec2(0.0001));
	float edge_proximity = clamp(1.0 - (-dist / max(corner_radius, 1.0)), 0.0, 1.0);
	float edge_factor = smoothstep(0.7, 1.0, edge_proximity);
	float center_factor = 1.0 - edge_proximity;
	float vertical_gradient = mix(1.0 + u_gradient_strength, 1.0 - u_gradient_strength, UV.y);

	float distortion = edge_factor * edge_factor;
	vec2 edge_offset_pixels = distortion * safe_normal * corner_radius * u_distortion_intensity;

	float t = TIME * u_warp_speed;
	vec2 warp_wave = vec2(
		sin(UV.y * u_warp_scale + t) + cos(UV.y * (u_warp_scale * 0.61) - t * 1.3),
		cos(UV.x * u_warp_scale - t * 0.9) + sin(UV.x * (u_warp_scale * 0.73) + t * 1.1)
	) * 0.5;

	float interior_warp_factor = 0.35 + center_factor * 0.65;
	vec2 interior_offset_pixels = warp_wave * u_warp_strength * interior_warp_factor;

	vec2 total_offset_pixels = edge_offset_pixels + interior_offset_pixels;
	vec2 target_uv = SCREEN_UV - (total_offset_pixels * SCREEN_PIXEL_SIZE);

	float current_blur_radius = mix(u_blur_intensity, u_blur_intensity * 0.7, center_factor);
	vec2 chromatic_shift = safe_normal * edge_factor * 1.5 * SCREEN_PIXEL_SIZE;

	float r = get_blurred_color(screen_texture, target_uv - chromatic_shift, SCREEN_PIXEL_SIZE, current_blur_radius).r;
	float g = get_blurred_color(screen_texture, target_uv, SCREEN_PIXEL_SIZE, current_blur_radius).g;
	float b = get_blurred_color(screen_texture, target_uv + chromatic_shift, SCREEN_PIXEL_SIZE, current_blur_radius).b;

	vec3 glass_color = vec3(r, g, b);
	glass_color *= u_brightness * vertical_gradient;
	glass_color = mix(glass_color, u_tint.rgb, u_tint_strength);

	float edge_highlight = smoothstep(corner_radius * 1.8, 0.0, abs(dist));
	glass_color += edge_highlight * u_edge_highlight_strength;

	COLOR = vec4(glass_color, u_alpha * mask);
}
