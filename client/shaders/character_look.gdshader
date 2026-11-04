shader_type spatial;
// Personagem do editor (fase 4.0, ADR 0051; 4.2, ADR 0053): uma malha com a textura de
// paleta do Mini Characters e as peças feitas em código. A cor do vértice diz o que cada
// pedaço é (alfa): 0 = textura; 0,25 = pele (a textura tingida por skin_color ÷ a cor da
// textura no UV2, o meio da faixa de pele da parte: mantém o degradê da paleta e, com
// skin_color igual a essa cor, fica igual ao pacote); 1 = a cor do vértice (roupas,
// chapéus). A pele é parâmetro de instância: um material só para todos os personagens.

uniform sampler2D colormap : source_color, filter_linear_mipmap;
// Índices fixos (fase 4.1): a capa é outra superfície da MESMA instância e tem o parâmetro
// dela (wave, índice 2). Sem instance_index, os dois shaders usavam o índice 0 e a capa
// escrevia por cima de skin_color, pintando o corpo inteiro.
instance uniform vec4 skin_color : instance_index(0) = vec4(0.0);

void fragment() {
	vec3 tex = texture(colormap, UV).rgb;
	float mode = COLOR.a;
	vec3 c = tex;
	if (mode > 0.9) {
		c = COLOR.rgb;
	} else if (mode > 0.1) {
		vec3 base = textureLod(colormap, UV2, 0.0).rgb;
		c = skin_color.a > 0.5 ? tex * skin_color.rgb / max(base, vec3(0.004)) : tex;
	}
	ALBEDO = c;
	ROUGHNESS = 0.85;
}
