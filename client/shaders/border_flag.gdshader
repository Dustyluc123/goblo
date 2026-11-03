shader_type spatial;
// Bandeirinha dos marcos da fronteira (fase 3.6): pano preso no mastro pela borda u = 0,
// tremulando (mais na ponta solta). Cada face mostra uma bandeira do atlas (FlagAtlas): a da
// frente vem de INSTANCE_CUSTOM.r e a de trás de INSTANCE_CUSTOM.g (índices no atlas);
// INSTANCE_CUSTOM.b é a fase da onda. Quem olha de um lado da fronteira vê a bandeira do
// país do outro lado.
render_mode cull_disabled, diffuse_lambert, specular_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 grid = vec2(16.0, 15.0);
uniform vec2 margin = vec2(0.047, 0.0625);
uniform float wave = 0.07;
uniform float speed = 3.2;

varying flat vec2 tiles;

void vertex() {
	tiles = INSTANCE_CUSTOM.rg;
	float free_end = UV.x;
	float t = TIME * speed + INSTANCE_CUSTOM.b * 6.2831;
	// O pano ondula para os lados (x local) e cai um tiquinho na ponta.
	VERTEX.x += sin(t + UV.x * 5.0) * wave * free_end;
	VERTEX.y -= (1.0 - cos(t * 0.7 + UV.x * 3.0)) * 0.02 * free_end;
	NORMAL = normalize(NORMAL + vec3(0.0, 0.0, -cos(t + UV.x * 5.0) * 0.35 * free_end));
}

void fragment() {
	float idx = FRONT_FACING ? tiles.x : tiles.y;
	vec2 cell = vec2(mod(idx, grid.x), floor(idx / grid.x));
	vec2 local = margin + UV * (1.0 - margin * 2.0);
	vec4 c = texture(atlas, (cell + local) / grid);
	// Um pouco de sombra na dobra da onda, para dar volume.
	float fold = 0.92 + 0.08 * sin(TIME * speed + UV.x * 5.0);
	ALBEDO = c.rgb * fold;
	ROUGHNESS = 0.9;
}
