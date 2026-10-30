// Fronteira viva (fase 3, ADR 0038): a cortina de luz, as bandeirolas e os ícones dos
// marcos, num shader só (part escolhe a peça). openness vai de 0 (fechada: sem o
// passaporte) a 1 (aberta) e anima a troca: a cortina desce e fica transparente, a corda
// das bandeirolas sobe em arco e o cadeadinho abre.
//
// As malhas são montadas no chão, em coordenadas do mundo (planeta na origem): o "para
// cima" de cada vértice é normalize(VERTEX), e o shader levanta cada peça.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform int part = 0; // 0 = cortina, 1 = bandeirolas, 2 = ícone (billboard)
uniform float openness : hint_range(0.0, 1.0) = 0.0;
uniform float curtain_height = 1.05;
// Onda ao encostar: ponto de contato (mundo) e idade em segundos (< 0 = nenhuma).
uniform vec3 ripple_origin = vec3(0.0);
uniform float ripple_age = -1.0;
uniform sampler2D icon_atlas : source_color, filter_linear_mipmap;
// Some com a distância da câmera (unidades).
uniform float fade_near = 22.0;
uniform float fade_far = 38.0;

varying vec3 v_world;
varying float v_height;

const vec3 CLOSED_A = vec3(1.0, 0.72, 0.86);  // rosa
const vec3 CLOSED_B = vec3(0.80, 0.72, 1.0);  // lilás
const vec3 OPEN_A = vec3(0.70, 0.96, 0.84);   // menta
const vec3 OPEN_B = vec3(0.98, 0.95, 0.70);   // amarelinho

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	vec3 up = normalize(VERTEX);
	if (part == 0) {
		// UV.y: 0 no chão, 1 no alto. A cortina baixa para 35% da altura quando abre e
		// ondula devagar para os lados (NORMAL é o lado, no plano do chão).
		float h = curtain_height * mix(1.0, 0.35, openness);
		float wave = sin(UV.x * 1.3 + TIME * 1.1) * 0.035 + sin(UV.x * 3.1 - TIME * 0.7) * 0.015;
		VERTEX += up * UV.y * h + NORMAL * wave * UV.y;
		v_height = UV.y;
	} else if (part == 1) {
		// UV.x: 0 a 1 entre dois marcos; UV.y: altura em relação à corda. Fechada, a corda
		// cai um pouco no meio; aberta, sobe em arco.
		float t = UV.x;
		float bump = 4.0 * t * (1.0 - t);
		float rope = mix(0.52 - 0.10 * bump, 0.58 + 0.34 * bump, openness);
		float sway = sin(TIME * 1.6 + UV.x * 6.0) * 0.02 * step(UV.y, -0.01);
		VERTEX += up * (rope + UV.y) + NORMAL * sway;
		v_height = 1.0;
	} else {
		// Ícone: billboard em cima do marco (o MultiMesh põe cada um no lugar).
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
		v_height = 1.0;
	}
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float dist = distance(CAMERA_POSITION_WORLD, v_world);
	float fade = 1.0 - smoothstep(fade_near, fade_far, dist);
	if (part == 0) {
		float g = 0.5 + 0.5 * sin(UV.x * 0.35);
		vec3 closed_c = mix(CLOSED_A, CLOSED_B, g);
		vec3 open_c = mix(OPEN_A, OPEN_B, g);
		vec3 c = mix(closed_c, open_c, openness);
		// Mais forte embaixo, sumindo para cima.
		float a = pow(1.0 - v_height, 1.4) * mix(0.42, 0.16, openness);
		// Brilhinhos subindo: células de uma grade que andam para cima com o tempo.
		vec2 cell_uv = vec2(UV.x * 3.0, UV.y * 5.0 - TIME * 0.45);
		vec2 id = floor(cell_uv);
		vec2 f = fract(cell_uv) - 0.5;
		float r = hash(id);
		float spark = step(0.82, r) * smoothstep(0.16, 0.0, length(f - vec2(r - 0.5, 0.0) * 0.6));
		spark *= 0.6 + 0.4 * sin(TIME * 4.0 + r * 30.0);
		// Onda que se espalha a partir do ponto em que o personagem encostou.
		float ring = 0.0;
		if (ripple_age >= 0.0) {
			float d = distance(v_world, ripple_origin);
			float radius = ripple_age * 3.5;
			ring = exp(-pow((d - radius) * 2.2, 2.0)) * exp(-ripple_age * 1.6);
		}
		ALBEDO = c + vec3(spark * 0.6 + ring * 0.5);
		ALPHA = clamp(a + spark * 0.55 * (1.0 - v_height) + ring * 0.45, 0.0, 1.0) * fade;
	} else if (part == 1) {
		ALBEDO = COLOR.rgb;
		ALPHA = fade;
	} else {
		// Atlas com dois ícones lado a lado: cadeado fechado (esquerda) e aberto (direita).
		vec2 uv = vec2(UV.x * 0.5 + step(0.5, openness) * 0.5, UV.y);
		vec4 t = texture(icon_atlas, uv);
		ALBEDO = t.rgb;
		ALPHA = t.a * fade;
	}
}
