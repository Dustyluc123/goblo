// Globinho do mini mapa: textura equirretangular dos biomas (gerada pelo cliente a partir
// do mundo) e linha dia/noite. A posição do objeto é a do mundo real, então lat/lon saem
// direto dela; o nó é girado para o jogador ficar de frente.
shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D map : source_color, filter_linear, repeat_enable;
uniform vec3 sun_dir = vec3(0.0, 0.0, 1.0);

varying vec3 obj_pos;

void vertex() {
	obj_pos = normalize(VERTEX);
}

void fragment() {
	vec3 n = normalize(obj_pos);
	float lon = atan(n.x, n.z);
	float lat = asin(clamp(n.y, -1.0, 1.0));
	vec2 uv = vec2(lon / (2.0 * PI) + 0.5, 0.5 - lat / PI);
	vec3 col = texture(map, uv).rgb;
	float day = smoothstep(-0.08, 0.08, dot(n, normalize(sun_dir)));
	col *= mix(vec3(0.28, 0.33, 0.6), vec3(1.0), day);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	ALBEDO = col + vec3(0.5, 0.7, 1.0) * rim * 0.35;
}
