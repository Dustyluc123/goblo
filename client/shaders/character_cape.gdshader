shader_type spatial;
// Capa de bandeiras (fase 4.0): retalhos com as bandeiras dos países visitados (textura
// montada por CharacterLook.cape_texture). Balança de leve; mais quando o personagem anda
// (wave, por instância). O alfa da cor do vértice é quanto aquele ponto balança (0 em cima).
render_mode cull_disabled;

uniform sampler2D flags : source_color, filter_linear_mipmap;
instance uniform float wave = 0.3;

void vertex() {
	float k = COLOR.a;
	float t = TIME * (2.0 + wave * 4.0);
	VERTEX.z -= (0.02 + wave * 0.06) * k * (0.6 + 0.4 * sin(t + VERTEX.x * 30.0));
	VERTEX.x += 0.01 * k * sin(t * 1.3 + VERTEX.y * 20.0);
}

void fragment() {
	ALBEDO = texture(flags, UV).rgb;
	ROUGHNESS = 0.9;
}
