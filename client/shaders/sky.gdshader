// Céu: gradiente de dia ou de noite em relação ao "para cima" do personagem (o planeta é
// redondo, então o horizonte depende de onde ele está), disco do sol, estrelas e, no zoom
// afastado, o espaço.
shader_type sky;

uniform vec3 local_up = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform float day_amount : hint_range(0.0, 1.0) = 1.0;
uniform float space_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 day_top : source_color = vec4(0.42, 0.66, 0.92, 1.0);
uniform vec4 day_horizon : source_color = vec4(0.80, 0.90, 0.98, 1.0);
uniform vec4 dusk_horizon : source_color = vec4(0.98, 0.70, 0.55, 1.0);
uniform vec4 night_top : source_color = vec4(0.05, 0.08, 0.20, 1.0);
uniform vec4 night_horizon : source_color = vec4(0.14, 0.18, 0.36, 1.0);
uniform vec4 space_color : source_color = vec4(0.06, 0.07, 0.16, 1.0);

float hash(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float stars(vec3 d) {
	vec3 g = d * 180.0;
	vec3 cell = floor(g);
	float h = hash(cell);
	float on = step(0.9965, h);
	float r = length(fract(g) - 0.5);
	float twinkle = 0.7 + 0.3 * sin(TIME * (1.0 + h * 3.0) + h * 40.0);
	return on * smoothstep(0.35, 0.0, r) * twinkle;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = dot(d, normalize(local_up));
	float t = smoothstep(-0.05, 0.55, h);
	float dusk = (1.0 - abs(day_amount * 2.0 - 1.0));  // 1 no nascer/pôr do sol
	vec3 horizon_day = mix(day_horizon.rgb, dusk_horizon.rgb, dusk * 0.8);
	vec3 day = mix(horizon_day, day_top.rgb, t);
	vec3 night = mix(night_horizon.rgb, night_top.rgb, t);
	vec3 col = mix(night, day, day_amount);
	float sun = pow(max(dot(d, sun_dir), 0.0), 600.0) * 4.0 + pow(max(dot(d, sun_dir), 0.0), 12.0) * 0.25;
	col += vec3(1.0, 0.9, 0.7) * sun * max(day_amount, space_amount);
	float s = stars(d);
	col += vec3(s) * clamp(1.0 - day_amount * 1.3, 0.0, 1.0) * smoothstep(-0.1, 0.2, h);
	vec3 space = space_color.rgb + vec3(s) * 0.9 + vec3(1.0, 0.9, 0.7) * sun;
	COLOR = mix(col, space, space_amount);
}
