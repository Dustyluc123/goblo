// Globinho do mini mapa: textura equirretangular dos biomas (gerada pelo cliente a partir
// do mundo) e linha dia/noite. A posição do objeto é a do mundo real, então lat/lon saem
// direto dela; o nó é girado para o jogador ficar de frente.
shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D map : source_color, filter_linear, repeat_enable;
uniform vec3 sun_dir = vec3(0.0, 0.0, 1.0);
// Estações: o alfa da textura marca os biomas que mudam (mesma conta do terreno).
uniform float season_phase = 1.5;
uniform float season_blend = 0.1095;

float season_weight(float p, float s) {
	float d = mod(p - s + 2.0, 4.0) - 2.0;
	return smoothstep(-season_blend, season_blend, d) * (1.0 - smoothstep(1.0 - season_blend, 1.0 + season_blend, d));
}

varying vec3 obj_pos;

void vertex() {
	obj_pos = normalize(VERTEX);
}

void fragment() {
	vec3 n = normalize(obj_pos);
	float lon = atan(n.x, n.z);
	float lat = asin(clamp(n.y, -1.0, 1.0));
	vec2 uv = vec2(lon / (2.0 * PI) + 0.5, 0.5 - lat / PI);
	vec4 tex = texture(map, uv);
	vec3 col = tex.rgb;
	float latd = degrees(lat);
	float k = tex.a * smoothstep(22.5, 25.5, abs(latd));
	if (k > 0.0) {
		float ph = mod(season_phase + (latd < 0.0 ? 2.0 : 0.0), 4.0);
		col = mix(col, col * vec3(1.25, 0.88, 0.45) + vec3(0.06, 0.03, 0.0), season_weight(ph, 2.0) * k * 0.8);
		col = mix(col, vec3(0.93, 0.95, 0.99), season_weight(ph, 3.0) * k * 0.9);
	}
	float day = smoothstep(-0.08, 0.08, dot(n, normalize(sun_dir)));
	col *= mix(vec3(0.28, 0.33, 0.6), vec3(1.0), day);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	ALBEDO = col + vec3(0.5, 0.7, 1.0) * rim * 0.35;
}
