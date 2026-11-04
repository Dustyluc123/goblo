class_name CharacterLook
extends Node
## Visual do personagem (fase 4.0, ADR 0051; 4.1, ADR 0052; 4.2, ADR 0053): editor e roupas
## numa malha só por personagem.
##
## Os 12 personagens do Mini Characters têm o mesmo esqueleto (root, pernas, tronco, braços e
## cabeça, na mesma ordem) e duas malhas: "body-mesh" (tronco, braços e pernas, já vestidos)
## e "head-mesh" (cabeça com o cabelo). Dá para misturar as partes:
## - cabeça: uma das 12 cabeças originais inteiras (rosto e cabelo, como vieram; 4.2);
## - tronco e braços de um personagem, pernas de outro (pelo osso que mais pesa).
##
## Pele (4.2): cada personagem tem um par de faixas de pele na paleta (a cor das orelhas e o
## tom de sombra dela). As mesmas faixas aparecem como cabelo, barba ou sapato em outros
## personagens, então a pele de cada parte é só o par do PRÓPRIO personagem, e nunca o que
## sai do crânio (cabelo, pela forma). A cor de pele do jogador vale para a cabeça, o corpo,
## as pernas e a pele que a roupa deixa à mostra; sem tom escolhido, é a pele original da
## cabeça (set_colors).
##
## Roupas (4.1): a peça vestida SUBSTITUI a parte da roupa original do espaço dela. Os
## vértices da região ganham a cor da peça (ou a pele, onde a peça deixa a pele à mostra:
## braços na regata, canelas no short, pés na sandália), sem malha a mais. Com o espaço vazio,
## a roupa original continua. Luvas e objetos que o personagem segura (cores do braço que não
## estão no tronco) ficam como vieram. Por cima, formas simples presas a um osso: chapéus (no
## alto da cabeça, com ajuste por cabeça em data/cabecas.json), óculos (na altura dos olhos),
## cachecol, solas das sandálias, a aba do poncho e a capa.
##
## Tudo vira UMA malha (uma superfície; duas com a capa, que usa o atlas de bandeiras), com
## um material só para todos os personagens: a pele troca de cor por parâmetro de instância
## (sem material por jogador). A malha é montada numa thread e fica em cache pela combinação
## (partes + acessório + roupas + cores das roupas): jogadores iguais dividem a mesma malha.
##
## Cor do vértice: rgb = cor da peça; alfa = modo (0 textura, 0,25 pele, 1 cor do vértice).
## Na pele, UV2 aponta o meio da faixa de pele da parte: o shader tinge a textura por pele ÷ a
## cor da textura ali, o que mantém o degradê da paleta (claro, sombra) e, sem tom escolhido,
## fica igual ao pacote (as duas cores saem da mesma textura, no mesmo espaço de cor).
## Ver shaders/character_look.gdshader.

const DIR := "res://assets/kenney/mini-characters/"
const DATA := "res://data/cabecas.json"
const SHADER := preload("res://shaders/character_look.gdshader")
const CAPE_SHADER := preload("res://shaders/character_cape.gdshader")
const B_ROOT := 0
const B_LEG_L := 1
const B_LEG_R := 2
const B_TORSO := 3
const B_ARM_L := 4
const B_ARM_R := 5
const B_HEAD := 6
const MODE_TEX := 0.0
const MODE_SKIN := 0.25
const MODE_COLOR := 1.0
## Região de cada vértice (para o teste das roupas): o que cada espaço pode mudar. R_HAIR é
## o que sai do crânio (cabelo; na male-c, o quepe, que sai com chapéu); R_STYLE, os óculos.
const R_HEAD := 0
const R_HAIR := 1
const R_BODY := 2
const R_LEGS := 3
const R_EXTRA_HEAD := 4
const R_EXTRA_BODY := 5
const R_EXTRA_LEGS := 6
const R_EXTRA_FEET := 7
const R_STYLE := 8
## Quais regiões cada espaço de roupa pode mudar.
const SLOT_REGIONS := {"head": [R_HAIR, R_EXTRA_HEAD], "body": [R_BODY, R_EXTRA_BODY],
	"legs": [R_LEGS, R_EXTRA_LEGS], "feet": [R_LEGS, R_EXTRA_FEET], "back": []}
## Quantas montagens de malha podem rodar ao mesmo tempo (threads).
const MAX_TASKS := 2
## Crânio comum das 12 cabeças: o que sai dele (fora do rosto e das orelhas) é cabelo, boné
## ou enfeite do alto, e nunca é pele. Medido nos modelos (tools/analisar_cabecas.gd).
const SKULL_MIN := Vector3(-0.165, 0.338, -0.167)
const SKULL_MAX := Vector3(0.165, 0.666, 0.162)
## Ponta da mão (|x|) nos 12 corpos; além disso, só o que a mão segura.
const HAND_END := 0.39
const EAR_X := 0.232
const EAR_Y := Vector2(0.395, 0.565)
const FACE_TOP := 0.585
## Alturas das pernas (fração do pé até o quadril): sapato, cano da bota, barra do short.
const SHOE_TOP := 0.18
const BOOT_TOP := 0.3
const SHORTS_BOTTOM := 0.55
## Pele nas pernas só conta se subir acima disto (fração): abaixo, a faixa de pele é sapato.
const LEG_SKIN_TOP := 0.6

static var instance: CharacterLook
## Parte ("female-a") → medidas e arrays (ver _measure).
static var _parts := {}
static var _prims := {}  # nome → arrays de uma forma unitária (caixa de −0,5 a 0,5)
static var _accessories := {}  # nome → [[arrays, Transform3D]] no espaço do personagem
static var _data := {}  # data/cabecas.json
static var _palette: Image
static var _material: ShaderMaterial
static var _cape_mats := {}  # países da capa → material com a textura das bandeiras
static var _meshes := {}  # chave → ArrayMesh pronta
static var _pending := {}  # chave → {"task", "out", "waiting": [Callable]}
static var _queue: Array = []  # chaves esperando thread

## Cores: hex → Color linear (para a cor do vértice; os parâmetros de instância recebem
## sRGB, que o Godot converte sozinho).
static func lin(hex: String) -> Color:
	return Color(hex).srgb_to_linear() if not hex.is_empty() else Color(0, 0, 0, 0)


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	for k: String in _pending:
		if int(_pending[k]["task"]) >= 0:
			WorkerThreadPool.wait_for_task_completion(_pending[k]["task"])
	_pending.clear()
	if instance == self:
		instance = null


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(DATA, FileAccess.READ)
		if f:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_data = d
	return _data


## Cabeça cujo "cabelo" é um chapéu (o quepe da male-c): com chapéu vestido, ele sai.
static func is_cap_head(part: String) -> bool:
	return (data().get("cap_heads", []) as Array).has(part)


## Carrega as partes dos 12 personagens e as formas (na entrada do jogo).
static func prepare(parts: Array) -> void:
	data()
	if _palette == null:
		var tex: Texture2D = load(DIR + "Textures/colormap.png")
		_palette = tex.get_image()
		if _palette.is_compressed():
			_palette.decompress()
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_material.set_shader_parameter("colormap", tex)
	for part: String in parts:
		if _parts.has(part):
			continue
		var scene := load(DIR + "character-" + part + ".glb") as PackedScene
		if scene == null:
			continue
		var root := scene.instantiate()
		var head: MeshInstance3D = root.find_child("head-mesh", true, false)
		var body: MeshInstance3D = root.find_child("body-mesh", true, false)
		if head == null or body == null:
			root.free()
			continue
		_parts[part] = _measure(head.mesh.surface_get_arrays(0), body.mesh.surface_get_arrays(0))
		root.free()
	_make_prims()
	for acc in ["aid-glasses", "aid-sunglasses"]:
		if _accessories.has(acc):
			continue
		var sc := load(DIR + acc + ".glb") as PackedScene
		if sc == null:
			continue
		var root := sc.instantiate() as Node3D
		var merged := []
		for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			var xf := Transform3D.IDENTITY
			var n: Node = mi
			while n != root and n is Node3D:
				xf = (n as Node3D).transform * xf
				n = n.get_parent()
			for si in mi.mesh.get_surface_count():
				merged.append([mi.mesh.surface_get_arrays(si), xf])
		_accessories[acc] = merged
		root.free()


## Mede uma parte. A paleta do Mini Characters tem faixas de cor (16 × 4), cada uma um
## degradê. A pele do personagem é a faixa de pele mais usada nas orelhas (que são só pele)
## mais o tom de sombra do par dela (10/11, 12/13, 14/15): pescoço e decote usam o outro tom.
## O cabelo é pela forma (o que sai do crânio), não pela cor.
static func _measure(ha: Array, ba: Array) -> Dictionary:
	var hv: PackedVector3Array = ha[Mesh.ARRAY_VERTEX]
	var huv: PackedVector2Array = ha[Mesh.ARRAY_TEX_UV]
	var hidx: PackedInt32Array = ha[Mesh.ARRAY_INDEX]
	var hair_tris := PackedByteArray()
	hair_tris.resize(hidx.size() / 3)
	for t in range(0, hidx.size(), 3):
		hair_tris[t / 3] = 1 if _is_hair_tri(hv, hidx, t) else 0
	var bv: PackedVector3Array = ba[Mesh.ARRAY_VERTEX]
	var bidx_all: PackedInt32Array = ba[Mesh.ARRAY_INDEX]
	var buv: PackedVector2Array = ba[Mesh.ARRAY_TEX_UV]
	var bones: PackedInt32Array = ba[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = ba[Mesh.ARRAY_WEIGHTS]
	# Pele: orelhas; sem orelha de pele, as pontas das mãos.
	var ears := {}
	for i in hv.size():
		var p := hv[i]
		if absf(p.x) > SKULL_MAX.x + 0.004 and absf(p.x) <= EAR_X + 0.004 and p.y >= EAR_Y.x and p.y <= EAR_Y.y and is_skin_cell(_cell(huv[i])):
			_vote(ears, _cell(huv[i]), _sample(huv[i]))
	var main := _winner(ears, Vector2i(-1, -1))
	var arm_low := INF
	var arm_high := -INF
	var torso_top := -INF
	var torso_back := INF
	var torso_w := 0.0
	var foot := INF
	var leg_top := -INF
	var torso_cells := {}
	var arm_cells := {}
	var leg_high := {}  # faixa → maior altura nas pernas
	for i in bv.size():
		var b := _dominant(bones, weights, i)
		var c := _cell(buv[i])
		if b == B_ARM_L or b == B_ARM_R:
			arm_low = minf(arm_low, bv[i].y)
			arm_high = maxf(arm_high, bv[i].y)
			arm_cells[c] = true
		if b == B_TORSO:
			torso_top = maxf(torso_top, bv[i].y)
			torso_back = minf(torso_back, bv[i].z)
			torso_w = maxf(torso_w, absf(bv[i].x))
			torso_cells[c] = true
		if b == B_LEG_L or b == B_LEG_R:
			foot = minf(foot, bv[i].y)
			leg_top = maxf(leg_top, bv[i].y)
			leg_high[c] = maxf(float(leg_high.get(c, -INF)), bv[i].y)
	var hand_y := arm_low + (arm_high - arm_low) * 0.25
	if main.x < 0:
		var hands := {}
		for i in bv.size():
			var b := _dominant(bones, weights, i)
			if (b == B_ARM_L or b == B_ARM_R) and bv[i].y < hand_y and is_skin_cell(_cell(buv[i])):
				_vote(hands, _cell(buv[i]), _sample(buv[i]))
		main = _winner(hands, Vector2i(-1, -1))
	var skins := {}
	if main.x >= 0:
		skins[main] = true
		skins[Vector2i(main.x ^ 1, main.y)] = true
	# Pernas: a faixa de pele só é pele se subir pela perna (embaixo, é sapato).
	var leg_skin := {}
	for c: Vector2i in skins:
		if leg_high.has(c) and float(leg_high[c]) > foot + (leg_top - foot) * LEG_SKIN_TOP:
			leg_skin[c] = true
	# Braços: cores que não estão no tronco nem são pele (luvas, o que a mão segura) ficam.
	var arm_keep := {}
	for c: Vector2i in arm_cells:
		if not torso_cells.has(c) and not skins.has(c):
			arm_keep[c] = true
	# Objeto na mão (fase 4.5): o da Personagem 1 passa da ponta da mão dos outros. As cores
	# dele (fora do tronco e da pele) saem dos braços, com o objeto inteiro.
	var held := {}
	for i in bv.size():
		var b := _dominant(bones, weights, i)
		var c := _cell(buv[i])
		if (b == B_ARM_L or b == B_ARM_R) and absf(bv[i].x) > HAND_END and arm_keep.has(c):
			held[c] = true
	var held_tris := PackedByteArray()
	held_tris.resize(bidx_all.size() / 3)
	for t in range(0, bidx_all.size(), 3):
		var tb := _dominant(bones, weights, bidx_all[t])
		held_tris[t / 3] = 1 if (tb == B_ARM_L or tb == B_ARM_R) and held.has(_cell(buv[bidx_all[t]])) else 0
	for c: Vector2i in held:
		arm_keep.erase(c)
	var bare := _bare_body(bv, bidx_all, bones, weights, held_tris, foot)
	# Tampas de cima das pernas (escondidas dentro do quadril do próprio personagem; com o
	# tronco de outro, apareciam como um aro escuro): ficam de fora.
	var bidx: PackedInt32Array = ba[Mesh.ARRAY_INDEX]
	var bn: PackedVector3Array = ba[Mesh.ARRAY_NORMAL]
	var caps := PackedByteArray()
	caps.resize(bidx.size() / 3)
	for t in range(0, bidx.size(), 3):
		var cy := (bv[bidx[t]].y + bv[bidx[t + 1]].y + bv[bidx[t + 2]].y) / 3.0
		var up := (bn[bidx[t]] + bn[bidx[t + 1]] + bn[bidx[t + 2]]).normalized().y
		caps[t / 3] = 1 if cy > leg_top - 0.012 and up > 0.8 else 0
	# Tom de referência (sRGB): o meio da faixa clara do par, a do rosto (o shader lê pelo
	# UV2). A pele forçada usa a faixa da orelha (a do corpo), como a pele original do corpo.
	var skin_uv := Vector2((main.x + 0.5) / PAL_COLS, (main.y + 0.5) / PAL_ROWS) if main.x >= 0 else Vector2(0.97, 0.9)
	var base_uv := Vector2(((main.x & ~1) + 0.5) / PAL_COLS, (main.y + 0.5) / PAL_ROWS) if main.x >= 0 else skin_uv
	var skin_col := _sample(base_uv)
	return {"head": ha, "body": ba, "hair_tris": hair_tris, "skins": skins, "skin_main": main,
		"skin_color": Color(skin_col.r, skin_col.g, skin_col.b, 1.0),
		"skin_uv": skin_uv, "base_uv": base_uv, "leg_skin": leg_skin, "arm_keep": arm_keep,
		"leg_caps": caps, "held_tris": held_tris, "bare": bare, "arm_low": arm_low, "arm_high": arm_high, "hand_y": hand_y,
		"torso_top": torso_top, "torso_back": torso_back, "torso_w": torso_w, "foot": foot, "leg_top": leg_top}


## Um vértice está no crânio (ou nas orelhas, ou no rosto)?
static func _in_skull(p: Vector3) -> bool:
	var e := 0.004
	if p.y < SKULL_MIN.y - e or p.y > SKULL_MAX.y + e or p.z < SKULL_MIN.z - e:
		# Barba e bigode: na frente e embaixo do rosto.
		return p.z > 0.05 and p.y < FACE_TOP and p.y > SKULL_MIN.y - 0.12 and absf(p.x) <= EAR_X
	if p.z > SKULL_MAX.z + e:
		return p.y < FACE_TOP and absf(p.x) <= EAR_X + e  # rosto (olhos, nariz, boca, óculos)
	if absf(p.x) > SKULL_MAX.x + e:
		return absf(p.x) <= EAR_X + e and p.y >= EAR_Y.x - e and p.y <= EAR_Y.y + e
	return true


## Triângulo do cabelo: algum vértice fora do crânio, do rosto e das orelhas.
static func _is_hair_tri(v: PackedVector3Array, idx: PackedInt32Array, t: int) -> bool:
	for k in 3:
		if not _in_skull(v[idx[t + k]]):
			return true
	return false


## Faixa da paleta: 16 colunas de 32 px (uma cor cada, em degradê) × 4 linhas de 128 px.
const PAL_COLS := 16
const PAL_ROWS := 4


static func _cell(uv: Vector2) -> Vector2i:
	return Vector2i(clampi(int(uv.x * PAL_COLS), 0, PAL_COLS - 1), clampi(int(uv.y * PAL_ROWS), 0, PAL_ROWS - 1))


## Cor do meio de uma faixa da paleta.
static func _cell_color(cell: Vector2i) -> Color:
	var w := _palette.get_width()
	var h := _palette.get_height()
	return _palette.get_pixel(clampi(int((cell.x + 0.5) * w / PAL_COLS), 0, w - 1), clampi(int((cell.y + 0.5) * h / PAL_ROWS), 0, h - 1))


static func _vote(votes: Dictionary, cell: Vector2i, c: Color) -> void:
	if not votes.has(cell):
		votes[cell] = {"n": 0, "lum": 0.0}
	votes[cell]["n"] += 1
	votes[cell]["lum"] += _lum(c)


## Faixas de pele da paleta: as seis últimas da linha de baixo (do claro ao escuro).
static func is_skin_cell(cell: Vector2i) -> bool:
	return cell.y == PAL_ROWS - 1 and cell.x >= 10


static func _winner(votes: Dictionary, skip: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var n := 0
	for cell: Vector2i in votes:
		if cell != skip and int(votes[cell]["n"]) > n:
			n = votes[cell]["n"]
			best = cell
	return best


static func _lum(c: Color) -> float:
	var l := c.srgb_to_linear()
	return 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b


static func _sample(uv: Vector2) -> Color:
	var x := clampi(int(uv.x * _palette.get_width()), 0, _palette.get_width() - 1)
	var y := clampi(int(uv.y * _palette.get_height()), 0, _palette.get_height() - 1)
	return _palette.get_pixel(x, y)


## Corpo base "sem roupa" (fase 4.5, ADR 0054), medido em cada corpo: as roupas do pacote
## vêm desenhadas no corpo (mangas, barras, sapatos). Quando uma peça deixa a pele à mostra
## (regata, short, sandália), as partes cobertas trocam a forma da roupa original por caixas
## no formato do braço, da perna e do pé, presas ao mesmo osso.
## Volta: "sleeve" (triângulos das mangas), "pants" (das pernas da calça), "shoe" (dos
## sapatos), e as caixas: "arm" (por lado, do ombro até a mão), "leg" e "foot" (por lado).
static func _bare_body(v: PackedVector3Array, idx: PackedInt32Array, bones: PackedInt32Array, weights: PackedFloat32Array, held: PackedByteArray, foot: float) -> Dictionary:
	var isl := _islands(v, idx)
	var n := idx.size() / 3
	var info := {}  # ilha → {bone, min, max}
	var tri_bone := PackedInt32Array()
	tri_bone.resize(n)
	for t in n:
		var counts := {}
		for k in 3:
			var b := _dominant(bones, weights, idx[t * 3 + k])
			counts[b] = int(counts.get(b, 0)) + 1
		var bone := -1
		var best := 0
		for b: int in counts:
			if counts[b] > best:
				best = counts[b]
				bone = b
		tri_bone[t] = bone
		if held[t] == 1:
			continue
		var i := isl[t]
		if not info.has(i):
			info[i] = {"bone": bone, "min": Vector3(INF, INF, INF), "max": -Vector3(INF, INF, INF)}
		for k in 3:
			var p := v[idx[t * 3 + k]]
			info[i]["min"] = (info[i]["min"] as Vector3).min(p)
			info[i]["max"] = (info[i]["max"] as Vector3).max(p)
	var sleeve := PackedByteArray()
	var pants := PackedByteArray()
	var shoe := PackedByteArray()
	for arr: PackedByteArray in [sleeve, pants, shoe]:
		arr.resize(n)
	var hands := {-1: [], 1: []}
	var shoes := {-1: [], 1: []}
	var uppers := {-1: [], 1: []}
	for i: int in info:
		var d: Dictionary = info[i]
		var mn: Vector3 = d["min"]
		var mx: Vector3 = d["max"]
		var side := 1 if mn.x + mx.x > 0.0 else -1
		var b := int(d["bone"])
		if b == B_ARM_L or b == B_ARM_R:
			if maxf(absf(mn.x), absf(mx.x)) >= HAND_END - 0.03:
				(hands[side] as Array).append(d)
		elif b == B_LEG_L or b == B_LEG_R:
			if mn.y <= foot + 0.005:
				(shoes[side] as Array).append(d)
			else:
				(uppers[side] as Array).append(d)
	var hand_isl := {}
	var shoe_isl := {}
	for i: int in info:
		var d: Dictionary = info[i]
		for side: int in [-1, 1]:
			if (hands[side] as Array).has(d):
				hand_isl[i] = true
			if (shoes[side] as Array).has(d):
				shoe_isl[i] = true
	for t in n:
		if held[t] == 1:
			continue
		var b := tri_bone[t]
		if b == B_ARM_L or b == B_ARM_R:
			sleeve[t] = 0 if hand_isl.has(isl[t]) else 1
		elif b == B_LEG_L or b == B_LEG_R:
			if shoe_isl.has(isl[t]):
				shoe[t] = 1
			else:
				pants[t] = 1
	var arm := {}
	var leg := {}
	var feet := {}
	for side: int in [-1, 1]:
		var hb := _union(hands[side])
		if not hb.is_empty():
			# Do ombro (onde o tronco acaba) até dentro da mão; seção um pouco menor que a mão.
			var inner := minf(absf(hb["min"].x), absf(hb["max"].x))
			var x0 := 0.11
			var x1 := inner + 0.03
			var sz := Vector3(x1 - x0, (hb["max"].y - hb["min"].y) * 0.8, (hb["max"].z - hb["min"].z) * 0.8)
			var c := Vector3(side * (x0 + x1) * 0.5, (hb["min"].y + hb["max"].y) * 0.5, (hb["min"].z + hb["max"].z) * 0.5)
			arm[side] = {"xf": Transform3D(Basis().scaled(sz), c), "bone": hb["bone"]}
		var sb := _union(shoes[side])
		var ub := _union(uppers[side])
		if not sb.is_empty():
			var smin: Vector3 = sb["min"]
			var smax: Vector3 = sb["max"]
			# Pé: o comprimento e a largura do sapato, mais baixo (sem sola nem cano).
			var fh := (smax.y - smin.y) * 0.45
			feet[side] = {"xf": Transform3D(Basis().scaled(Vector3((smax.x - smin.x) * 0.86, fh, (smax.z - smin.z) * 0.9)),
				Vector3((smin.x + smax.x) * 0.5, smin.y + fh * 0.5, (smin.z + smax.z) * 0.5)), "bone": sb["bone"]}
			# Perna: a seção da coxa (a ilha mais alta da perna) ou a do sapato, do pé até o quadril.
			var src: Dictionary = ub if not ub.is_empty() else sb
			var lmin: Vector3 = src["min"]
			var lmax: Vector3 = src["max"]
			var top: float = lmax.y if not ub.is_empty() else smax.y
			var y0 := smin.y + fh * 0.6
			leg[side] = {"x": (lmin.x + lmax.x) * 0.5, "z": (lmin.z + lmax.z) * 0.5, "w": (lmax.x - lmin.x) * 0.9,
				"d": (lmax.z - lmin.z) * 0.9, "y0": y0, "y1": top, "bone": sb["bone"]}
	return {"sleeve": sleeve, "pants": pants, "shoe": shoe, "arm": arm, "leg": leg, "foot": feet}


## Caixa que envolve várias ilhas ({} se nenhuma).
static func _union(list: Array) -> Dictionary:
	if list.is_empty():
		return {}
	var mn := Vector3(INF, INF, INF)
	var mx := -mn
	for d: Dictionary in list:
		mn = mn.min(d["min"])
		mx = mx.max(d["max"])
	return {"min": mn, "max": mx, "bone": int((list[0] as Dictionary)["bone"])}


## Ilhas (pedaços soltos) da malha: um número por triângulo. Vértices na mesma posição
## contam como ligados (as peças do pacote têm vértices repetidos nas quinas).
static func _islands(v: PackedVector3Array, idx: PackedInt32Array) -> PackedInt32Array:
	var id := {}  # posição arredondada → índice
	var parent: Array[int] = []  # Array (referência): a função abaixo muda o mesmo
	var vid := PackedInt32Array()
	vid.resize(v.size())
	for i in v.size():
		var k := Vector3i(roundi(v[i].x * 2000.0), roundi(v[i].y * 2000.0), roundi(v[i].z * 2000.0))
		if not id.has(k):
			id[k] = parent.size()
			parent.append(parent.size())
		vid[i] = id[k]
	var find := func(x: int) -> int:
		while parent[x] != x:
			parent[x] = parent[parent[x]]
			x = parent[x]
		return x
	for t in range(0, idx.size(), 3):
		var a: int = find.call(vid[idx[t]])
		for k in [1, 2]:
			var b: int = find.call(vid[idx[t + k]])
			if a != b:
				parent[b] = a
	var out := PackedInt32Array()
	out.resize(idx.size() / 3)
	for t in range(0, idx.size(), 3):
		out[t / 3] = find.call(vid[idx[t]])
	return out


static func _dominant(bones: PackedInt32Array, weights: PackedFloat32Array, v: int) -> int:
	var best := 0
	var bw := -1.0
	for k in 4:
		if weights[v * 4 + k] > bw:
			bw = weights[v * 4 + k]
			best = bones[v * 4 + k]
	return best


## Formas simples, todas encaixadas na caixa de −0,5 a 0,5 (o tamanho é a escala).
static func _make_prims() -> void:
	if not _prims.is_empty():
		return
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.5
	cyl.height = 1.0
	cyl.radial_segments = 12
	cyl.rings = 1
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.5
	cone.height = 1.0
	cone.radial_segments = 6
	cone.rings = 1
	var sph := SphereMesh.new()
	sph.radius = 0.5
	sph.height = 1.0
	sph.radial_segments = 10
	sph.rings = 5
	var hemi := SphereMesh.new()
	hemi.radius = 0.5
	hemi.height = 0.5
	hemi.is_hemisphere = true
	hemi.radial_segments = 12
	hemi.rings = 4
	var torus := TorusMesh.new()
	torus.inner_radius = 0.38
	torus.outer_radius = 0.5
	torus.rings = 12
	torus.ring_segments = 6
	for pair: Array in [["cyl", cyl], ["cone", cone], ["sphere", sph], ["hemi", hemi], ["box", BoxMesh.new()], ["torus", torus]]:
		_prims[pair[0]] = _unit((pair[1] as PrimitiveMesh).get_mesh_arrays())


## Encaixa os vértices na caixa de −0,5 a 0,5 (cada eixo).
static func _unit(arrays: Array) -> Array:
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var aabb := AABB(v[0], Vector3.ZERO)
	for p in v:
		aabb = aabb.expand(p)
	var size := aabb.size
	for a in 3:
		size[a] = maxf(size[a], 0.0001)
	var c := aabb.get_center()
	var nv := PackedVector3Array()
	nv.resize(v.size())
	for i in v.size():
		nv[i] = (v[i] - c) / size
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var nn := PackedVector3Array()
	nn.resize(n.size())
	for i in n.size():
		nn[i] = Vector3(n[i].x * size.y * size.z, n[i].y * size.x * size.z, n[i].z * size.x * size.y).normalized()
	var out := arrays.duplicate()
	out[Mesh.ARRAY_VERTEX] = nv
	out[Mesh.ARRAY_NORMAL] = nn
	return out


# --- Pedidos -------------------------------------------------------------------------------

## Chave da malha: partes, acessório e roupas (com as cores). A pele (a cor) não entra: é
## parâmetro de instância.
static func key_of(look: Dictionary, wear: Dictionary) -> String:
	var parts := [str(look.get("head", "")), str(look.get("body", "")), str(look.get("legs", "")),
		str(look.get("accessory", "none"))]
	var slots := wear.keys()
	slots.sort()
	for s: String in slots:
		var w: Dictionary = wear[s]
		parts.append("%s:%s:%s" % [s, w.get("item", ""), w.get("color", "")])
	return "|".join(parts)


## Pede a malha; `done(mesh)` é chamado quando ficar pronta (na hora, se já estiver em cache).
static func request(look: Dictionary, wear: Dictionary, done: Callable) -> void:
	var key := key_of(look, wear)
	if _meshes.has(key):
		done.call(_meshes[key])
		return
	if not _ready_for(look):
		return
	if _pending.has(key):
		(_pending[key]["waiting"] as Array).append(done)
		return
	_pending[key] = {"task": -1, "out": [], "waiting": [done], "job": _job(look, wear)}
	_queue.append(key)


static func _ready_for(look: Dictionary) -> bool:
	return _parts.has(str(look.get("head", ""))) and _parts.has(str(look.get("body", ""))) and _parts.has(str(look.get("legs", "")))


## Pronta agora mesmo (sem thread): para o espelho e o editor, que mostram na hora.
static func build_now(look: Dictionary, wear: Dictionary) -> ArrayMesh:
	var key := key_of(look, wear)
	if not _meshes.has(key):
		if not _ready_for(look):
			return null
		_meshes[key] = _finish(_build(_job(look, wear)))
	return _meshes[key]


func _process(_delta: float) -> void:
	# Começa as montagens da fila (no máximo MAX_TASKS de uma vez) e entrega as prontas.
	var running := 0
	for key: String in _pending:
		if int(_pending[key]["task"]) >= 0:
			running += 1
	while running < MAX_TASKS and not _queue.is_empty():
		var key: String = _queue.pop_front()
		var p: Dictionary = _pending[key]
		var job: Dictionary = p["job"]
		var out: Array = p["out"]
		p["task"] = WorkerThreadPool.add_task(func() -> void: out.append(CharacterLook._build(job)))
		running += 1
	for key: String in _pending.keys():
		var p: Dictionary = _pending[key]
		if int(p["task"]) < 0 or not WorkerThreadPool.is_task_completed(p["task"]):
			continue
		WorkerThreadPool.wait_for_task_completion(p["task"])
		_pending.erase(key)
		var t0 := Time.get_ticks_usec()
		var mesh := _finish(p["out"][0])
		HitchLog.note("visual de personagem", (Time.get_ticks_usec() - t0) / 1000.0)
		_meshes[key] = mesh
		for cb: Callable in p["waiting"]:
			if cb.is_valid():
				cb.call(mesh)
		return  # uma por quadro


## O que a thread precisa (cópias das referências; os arrays não mudam).
static func _job(look: Dictionary, wear: Dictionary) -> Dictionary:
	var w := {}
	for slot: String in wear:
		var d: Dictionary = wear[slot]
		w[slot] = {"item": str(d.get("item", "")), "color": lin(str(d.get("color", "#ffffff")))}
	var head := str(look["head"])
	var acc := str(look.get("accessory", "none"))
	var hats: Dictionary = data().get("hats", {})
	var fit: Dictionary = hats.get(head, hats.get("default", {}))
	var anchor: Array = data().get("anchor", [0.0, SKULL_MAX.y, 0.0])
	return {"head": _parts[head], "body": _parts[str(look["body"])], "legs": _parts[str(look["legs"])],
		"head_is_cap": is_cap_head(head), "accessory": _accessories.get(acc, []), "face": face_of(head),
		"wear": w, "prims": _prims,
		"anchor": Vector3(float(anchor[0]), float(anchor[1]), float(anchor[2])) + _vec(fit.get("offset", [0, 0, 0])),
		"hat_scale": float(fit.get("scale", 1.0)), "hat_rot": deg_to_rad(float(fit.get("rot", 0.0)))}


## Onde ficam os óculos numa cabeça (espaço do personagem, preso ao osso da cabeça): o ponto
## dos olhos (data/cabecas.json → face, o mesmo dos óculos que já vêm em duas cabeças do
## pacote) mais o ajuste da cabeça (faces).
static func face_of(head: String) -> Transform3D:
	var f: Dictionary = data().get("faces", {}).get(head, {})
	var at := _vec(data().get("face", [0.0, 0.435, 0.073])) + _vec(f.get("offset", [0, 0, 0]))
	return Transform3D(Basis().scaled(_vec(f.get("scale", [1.02, 1.0, 1.0]))), at)


static func _vec(a: Variant) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO


# --- Montagem (pode rodar numa thread: só mexe em arrays) ------------------------------------

## Junta tudo em arrays: [superfície do corpo, superfície da capa (ou vazia)]. A ordem dos
## vértices é fixa (cabeça, cabelo, corpo, pernas e depois as formas), para o teste das
## roupas comparar região por região.
static func _build(job: Dictionary) -> Array:
	var g := _group()
	var cape := _group()
	var head: Dictionary = job["head"]
	var body: Dictionary = job["body"]
	var legs: Dictionary = job["legs"]
	var wear: Dictionary = job["wear"]
	var prims: Dictionary = job["prims"]
	var hat := str(wear.get("head", {}).get("item", ""))
	# Cabeça inteira, como veio. Só a pele (o par de faixas do personagem) troca de cor.
	_add_part(g, head["head"], head["hair_tris"], false, R_HEAD, func(_p: Vector3, _n: Vector3, uv: Vector2) -> Color:
		return _skin_or_tex(head, uv), Callable(), Callable(), head["skin_uv"], -INF, head["base_uv"])
	# O que sai do crânio (cabelo), sempre com a cor original. O quepe da male-c sai com chapéu.
	if hat.is_empty() or not bool(job["head_is_cap"]):
		_add_part(g, head["head"], head["hair_tris"], true, R_HAIR, func(_p: Vector3, _n: Vector3, _uv: Vector2) -> Color:
			return Color(1, 1, 1, MODE_TEX))
	# Tronco e braços, com a peça do espaço corpo no lugar da roupa original.
	var top := str(wear.get("body", {}).get("item", ""))
	var top_col: Color = wear.get("body", {}).get("color", Color.WHITE)
	var bottom := str(wear.get("legs", {}).get("item", ""))
	var bottom_col: Color = wear.get("legs", {}).get("color", Color.WHITE)
	var body_bare: Dictionary = body["bare"]
	var legs_bare: Dictionary = legs["bare"]
	var body_skip: PackedByteArray = body["held_tris"]
	if top == "tank_top":
		body_skip = _or(body_skip, body_bare["sleeve"])
	_add_part(g, body["body"], body_skip, false, R_BODY, func(p: Vector3, _n: Vector3, uv: Vector2, b: int) -> Color:
		return _body_color(body, top, top_col, p, uv, b, bottom, bottom_col), Callable(),
		func(b: int) -> bool: return b != B_LEG_L and b != B_LEG_R, body["skin_uv"], waist_of(body), body["base_uv"])
	# Pernas e pés, com as peças dos espaços pernas e pés.
	var shoe := str(wear.get("feet", {}).get("item", ""))
	var shoe_col: Color = wear.get("feet", {}).get("color", Color.WHITE)
	var legs_skip: PackedByteArray = legs["leg_caps"]
	if bottom == "shorts":
		legs_skip = _or(legs_skip, legs_bare["pants"])
	if shoe == "sandals":
		legs_skip = _or(legs_skip, legs_bare["shoe"])
	_add_part(g, legs["body"], legs_skip, false, R_LEGS, func(p: Vector3, _n: Vector3, uv: Vector2, _b: int) -> Color:
		return _legs_color(legs, bottom, bottom_col, shoe, shoe_col, p, uv), Callable(),
		func(b: int) -> bool: return b == B_LEG_L or b == B_LEG_R, legs["skin_uv"], -INF, legs["base_uv"])
	# Corpo base onde a peça deixa a pele à mostra (ADR 0054).
	if top == "tank_top":
		for side: int in body_bare["arm"]:
			var a: Dictionary = body_bare["arm"][side]
			_add_skin_box(g, prims["box"], a["xf"], int(a["bone"]), body, R_BODY)
	if bottom == "shorts":
		var lf := float(legs["foot"])
		var y_sb := lf + (float(legs["leg_top"]) - lf) * SHORTS_BOTTOM
		for side: int in legs_bare["leg"]:
			var l: Dictionary = legs_bare["leg"][side]
			var y0 := float(l["y0"])
			var y1 := float(l["y1"])
			var lb := int(l["bone"])
			var sz := Vector3(float(l["w"]), y_sb - y0, float(l["d"]))
			_add_skin_box(g, prims["box"], Transform3D(Basis().scaled(sz), Vector3(float(l["x"]), (y0 + y_sb) * 0.5, float(l["z"]))), lb, legs, R_LEGS)
			var sz2 := Vector3(float(l["w"]) * 1.08, y1 - y_sb, float(l["d"]) * 1.08)
			_add_rigid(g, prims["box"], Transform3D(Basis().scaled(sz2), Vector3(float(l["x"]), (y_sb + y1) * 0.5, float(l["z"]))), lb, _solid(bottom_col), R_LEGS)
	if shoe == "sandals":
		for side: int in legs_bare["foot"]:
			var f: Dictionary = legs_bare["foot"][side]
			_add_skin_box(g, prims["box"], f["xf"], int(f["bone"]), legs, R_LEGS)
	# Formas por cima, na ordem dos espaços.
	if not hat.is_empty():
		_add_hat(g, prims, hat, job, _solid(wear["head"]["color"]))
	match top:
		"scarf":
			var neck := float(body["torso_top"])
			var col := _solid(top_col)
			_add_rigid(g, prims["torus"], Transform3D(Basis().scaled(Vector3(float(body["torso_w"]) * 2.15, 0.07, 0.24)), Vector3(0, neck - 0.015, 0)), B_TORSO, col, R_EXTRA_BODY)
			_add_rigid(g, prims["box"], Transform3D(Basis(Vector3.RIGHT, 0.2).scaled(Vector3(0.045, 0.12, 0.02)), Vector3(0.05, neck - 0.07, 0.09)), B_TORSO, col, R_EXTRA_BODY)
		"poncho":
			# A aba do poncho: uma casca larga só no tronco (o resto já ficou da cor da peça).
			_add_shell(g, body["body"], func(b: int) -> bool: return b == B_TORSO, 0.035, _solid(top_col.darkened(0.08)), R_EXTRA_BODY)
	if shoe == "sandals":
		var foot := float(legs["foot"])
		for side in [-1.0, 1.0]:
			_add_rigid(g, prims["box"], Transform3D(Basis().scaled(Vector3(0.07, 0.015, 0.11)), Vector3(side * 0.06, foot + 0.007, 0.01)), B_LEG_L if side < 0.0 else B_LEG_R, _solid(shoe_col), R_EXTRA_FEET)
	# Óculos: no osso da cabeça, na altura dos olhos.
	var face: Transform3D = job["face"]
	for part: Array in job["accessory"]:
		_add_arrays(g, part[0], face * (part[1] as Transform3D), B_HEAD, Color(1, 1, 1, MODE_TEX), R_STYLE)
	if str(wear.get("back", {}).get("item", "")) == "flag_cape":
		_add_cape(cape, body)
	return [g, cape]


## Junta duas máscaras de triângulos (1 em qualquer uma = 1).
static func _or(a: PackedByteArray, b: PackedByteArray) -> PackedByteArray:
	if a.is_empty():
		return b
	if b.is_empty():
		return a
	var out := a.duplicate()
	for i in mini(out.size(), b.size()):
		if b[i] == 1:
			out[i] = 1
	return out


## Caixa do corpo base com a pele da parte (o mesmo tom e referência da pele dela).
static func _add_skin_box(g: Dictionary, arrays: Array, xf: Transform3D, bone: int, part: Dictionary, region: int) -> void:
	var start := (g["v"] as PackedVector3Array).size()
	_add_arrays(g, arrays, xf, bone, Color(1, 1, 1, MODE_SKIN), region)
	var guv: PackedVector2Array = g["uv"]
	var guv2: PackedVector2Array = g["uv2"]
	for i in range(start, guv.size()):
		guv[i] = part["skin_uv"]
		guv2[i] = part["base_uv"]
	g["uv"] = guv
	g["uv2"] = guv2


static func _solid(c: Color) -> Color:
	return Color(c.r, c.g, c.b, MODE_COLOR)


## Pele marcada (o UV2, o meio da faixa de pele da parte, entra em _add_part).
static func _skin(_part: Dictionary) -> Color:
	return Color(1, 1, 1, MODE_SKIN)


## Pele (o par de faixas do personagem da parte) ou a textura original.
static func _skin_or_tex(part: Dictionary, uv: Vector2) -> Color:
	if (part["skins"] as Dictionary).has(_cell(uv)):
		return _skin(part)
	return Color(1, 1, 1, MODE_TEX)


## Tronco e braços: a peça do espaço corpo troca a roupa original. Luvas e o que a mão segura
## (arm_keep) ficam como vieram.
static func _body_color(part: Dictionary, item: String, col: Color, p: Vector3, uv: Vector2, bone: int, bottom: String, bcol: Color) -> Color:
	var cell := _cell(uv)
	var is_skin := (part["skins"] as Dictionary).has(cell)
	var orig := _skin_or_tex(part, uv)
	# Cintura (o calção ou a saia do tronco): é do espaço pernas.
	if bone == B_TORSO and p.y < waist_of(part):
		if bottom == "pants" or bottom == "shorts":
			return orig if is_skin else _solid(bcol)
		return orig
	var arm := bone == B_ARM_L or bone == B_ARM_R
	if arm and (part["arm_keep"] as Dictionary).has(cell):
		return orig
	var hand := arm and p.y < float(part["hand_y"])
	match item:
		"coat", "poncho":
			if hand and is_skin:
				return orig
			return _solid(col)
		"tank_top":
			if arm:
				return Color(-1, 0, 0, MODE_SKIN)
			return orig if is_skin else _solid(col)
	return orig


## Altura da cintura: abaixo dela, o tronco é do calção (espaço pernas).
static func waist_of(part: Dictionary) -> float:
	return float(part["leg_top"]) + 0.012


## Pernas e pés: calça ou short (espaço pernas) e bota ou sandália (espaço pés). Pele nas
## pernas só onde a faixa de pele sobe pela perna (leg_skin); embaixo, é sapato.
static func _legs_color(part: Dictionary, bottom: String, bcol: Color, shoe: String, scol: Color, p: Vector3, uv: Vector2) -> Color:
	var cell := _cell(uv)
	var orig := _skin(part) if (part["leg_skin"] as Dictionary).has(cell) else Color(1, 1, 1, MODE_TEX)
	var foot := float(part["foot"])
	var f := (p.y - foot) / maxf(float(part["leg_top"]) - foot, 0.001)
	var shoe_top := BOOT_TOP if shoe == "boots" else SHOE_TOP
	if f < shoe_top:
		match shoe:
			"boots":
				return _solid(scol)
			"sandals":
				return Color(-1, 0, 0, MODE_SKIN)
		if f < SHOE_TOP:
			return orig  # sapato original
	match bottom:
		"pants":
			return _solid(bcol)
		"shorts":
			return _solid(bcol) if f >= SHORTS_BOTTOM else Color(-1, 0, 0, MODE_SKIN)
	return orig


## Arrays vazios de uma superfície (r = região de cada vértice, só para o teste).
static func _group() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "uv2": PackedVector2Array(), "c": PackedColorArray(),
		"b": PackedInt32Array(), "w": PackedFloat32Array(), "i": PackedInt32Array(), "r": PackedByteArray()}


## Triângulos de uma malha com pele. `tris` (um byte por triângulo) + `want` filtram pelo
## cabelo; `keep_bone` filtra pelo osso dominante do triângulo. `color(centro, n, uv[, osso])`
## dá a cor de cada vértice (centro = do triângulo): vermelho −1 = pele forçada (o UV vira o
## de pele da parte, `skin_uv`); toda pele leva no UV2 a faixa de referência, `base_uv`. Abaixo de `waist`, o tronco conta como região das pernas (cintura).
## `move(p)` muda a posição (cabelo achatado).
static func _add_part(g: Dictionary, arrays: Array, tris: PackedByteArray, want: bool, region: int, color: Callable,
		move := Callable(), keep_bone := Callable(), skin_uv := Vector2(0.97, 0.9), waist := -INF, base_uv := Vector2(0.94, 0.9)) -> void:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var with_bone := keep_bone.is_valid()
	var gv: PackedVector3Array = g["v"]
	var gn: PackedVector3Array = g["n"]
	var guv: PackedVector2Array = g["uv"]
	var guv2: PackedVector2Array = g["uv2"]
	var gc: PackedColorArray = g["c"]
	var gb: PackedInt32Array = g["b"]
	var gw: PackedFloat32Array = g["w"]
	var gi: PackedInt32Array = g["i"]
	var gr: PackedByteArray = g["r"]
	for t in range(0, idx.size(), 3):
		if not tris.is_empty() and (tris[t / 3] == 1) != want:
			continue
		# Osso do triângulo: o que mais aparece entre os três vértices.
		var counts := {}
		for k in 3:
			var b := _dominant(bones, weights, idx[t + k])
			counts[b] = int(counts.get(b, 0)) + 1
		var bone := -1
		var best := 0
		for b: int in counts:
			if counts[b] > best:
				best = counts[b]
				bone = b
		if with_bone and not keep_bone.call(bone):
			continue
		# A cor é decidida pelo centro do triângulo (as peças do Mini Characters são caixas
		# com poucos vértices: pintar por vértice viraria degradê). Vértices não são
		# divididos entre triângulos, então cada face fica com uma cor só.
		var center := (verts[idx[t]] + verts[idx[t + 1]] + verts[idx[t + 2]]) / 3.0
		var reg := R_LEGS if region == R_BODY and bone == B_TORSO and center.y < waist else region
		for k in 3:
			var v := idx[t + k]
			var c: Color = color.call(center, normals[v], uvs[v], bone) if with_bone else color.call(center, normals[v], uvs[v])
			var uv := uvs[v]
			if c.r < 0.0:
				c = Color(1, 1, 1, MODE_SKIN)
				uv = skin_uv
			gi.append(gv.size())
			gv.append(move.call(verts[v]) if move.is_valid() else verts[v])
			gn.append(normals[v])
			guv.append(uv)
			guv2.append(base_uv if absf(c.a - MODE_SKIN) < 0.01 else Vector2.ZERO)
			gc.append(c)
			gr.append(reg)
			for j in 4:
				gb.append(bones[v * 4 + j])
				gw.append(weights[v * 4 + j])
	g["v"] = gv
	g["n"] = gn
	g["uv"] = guv
	g["uv2"] = guv2
	g["c"] = gc
	g["b"] = gb
	g["w"] = gw
	g["i"] = gi
	g["r"] = gr


## Casca (aba do poncho): os triângulos do osso, empurrados pela normal, com a cor `col`.
static func _add_shell(g: Dictionary, arrays: Array, keep_bone: Callable, push: float, col: Color, region: int) -> void:
	var start := (g["v"] as PackedVector3Array).size()
	_add_part(g, arrays, PackedByteArray(), true, region, func(_p: Vector3, _n: Vector3, _uv: Vector2, _b: int) -> Color: return col,
		Callable(), keep_bone)
	# Empurra pela normal só os vértices que acabaram de entrar.
	var gv: PackedVector3Array = g["v"]
	var gn: PackedVector3Array = g["n"]
	for i in range(start, gv.size()):
		gv[i] += gn[i] * push
	g["v"] = gv


## Forma presa a um osso (peso 1), transformada por `xf` (espaço do personagem).
static func _add_rigid(g: Dictionary, arrays: Array, xf: Transform3D, bone: int, col: Color, region: int) -> void:
	_add_arrays(g, arrays, xf, bone, col, region)


static func _add_arrays(g: Dictionary, arrays: Array, xf: Transform3D, bone: int, col: Color, region: int) -> void:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: Variant = arrays[Mesh.ARRAY_TEX_UV]
	var idx: Variant = arrays[Mesh.ARRAY_INDEX]
	var nb := xf.basis.inverse().transposed()
	var gv: PackedVector3Array = g["v"]
	var gn: PackedVector3Array = g["n"]
	var guv: PackedVector2Array = g["uv"]
	var guv2: PackedVector2Array = g["uv2"]
	var gc: PackedColorArray = g["c"]
	var gb: PackedInt32Array = g["b"]
	var gw: PackedFloat32Array = g["w"]
	var gi: PackedInt32Array = g["i"]
	var gr: PackedByteArray = g["r"]
	var base := gv.size()
	for k in verts.size():
		gv.append(xf * verts[k])
		gn.append((nb * normals[k]).normalized())
		guv.append((uvs as PackedVector2Array)[k] if uvs != null else Vector2.ZERO)
		guv2.append(Vector2.ZERO)
		gc.append(col)
		gr.append(region)
		gb.append_array([bone, 0, 0, 0])
		gw.append_array([1.0, 0.0, 0.0, 0.0])
	if idx == null:
		for k in verts.size():
			gi.append(base + k)
	else:
		for k in (idx as PackedInt32Array):
			gi.append(base + k)
	g["v"] = gv
	g["n"] = gn
	g["uv"] = guv
	g["uv2"] = guv2
	g["c"] = gc
	g["b"] = gb
	g["w"] = gw
	g["i"] = gi
	g["r"] = gr


## Chapéus: presos ao osso da cabeça no ponto de encaixe do alto do crânio (anchor), com o
## ajuste da cabeça (posição, escala e giro, em data/cabecas.json) para cobrir o cabelo dela
## sem flutuar. Nada mexe nos vértices da cabeça.
static func _add_hat(g: Dictionary, prims: Dictionary, item: String, job: Dictionary, col: Color) -> void:
	var a: Vector3 = job["anchor"]
	var s: float = job["hat_scale"]
	var rot := Basis(Vector3.UP, float(job["hat_rot"]))
	var r := 0.235 * s
	var put := func(prim: String, at: Vector3, size: Vector3, c: Color) -> void:
		_add_rigid(g, prims[prim], Transform3D(rot * Basis().scaled(size), a + rot * at), B_HEAD, c, R_EXTRA_HEAD)
	match item:
		"beanie":
			put.call("cyl", Vector3(0, -0.045, 0), Vector3(r * 2.04, 0.07, r * 2.04), col.darkened(0.08))
			put.call("hemi", Vector3(0, 0.055, 0), Vector3(r * 2.0, 0.13, r * 2.0), col)
			put.call("sphere", Vector3(0, 0.14, 0), Vector3.ONE * 0.075, Color(1, 1, 1, MODE_COLOR))
		"fur_hat":
			put.call("cyl", Vector3(0, 0.005, 0), Vector3(r * 2.12, 0.17, r * 2.12), col)
			put.call("hemi", Vector3(0, 0.115, 0), Vector3(r * 2.0, 0.06, r * 2.0), col.darkened(0.1))
		"straw_hat", "sun_hat":
			var brim := (0.4 if item == "straw_hat" else 0.52) * s
			put.call("cyl", Vector3(0, -0.035, 0), Vector3(brim * 2.0, 0.02, brim * 2.0), col)
			put.call("cyl", Vector3(0, 0.035, 0), Vector3(r * 1.86, 0.13, r * 1.86), col)
			put.call("cyl", Vector3(0, -0.01, 0), Vector3(r * 1.9, 0.03, r * 1.9), Color(0.55, 0.18, 0.15, MODE_COLOR))
		"cap":
			put.call("cyl", Vector3(0, -0.045, 0), Vector3(r * 1.98, 0.05, r * 1.98), col)
			put.call("hemi", Vector3(0, 0.035, 0), Vector3(r * 1.96, 0.11, r * 1.96), col)
			put.call("box", Vector3(0, -0.06, SKULL_MAX.z + 0.07), Vector3(0.27, 0.02, 0.15), col.darkened(0.06))
		"lamp_helmet":
			# Fase 4.5: capacete de mineração com a lanterninha na frente (a luz é do jogo).
			put.call("cyl", Vector3(0, -0.045, 0), Vector3(r * 2.1, 0.03, r * 2.1), col.darkened(0.15))
			put.call("hemi", Vector3(0, 0.035, 0), Vector3(r * 2.0, 0.13, r * 2.0), col)
			put.call("box", Vector3(0, 0.0, SKULL_MAX.z + 0.01), Vector3(0.1, 0.08, 0.05), Color(0.2, 0.2, 0.22, MODE_COLOR))
			put.call("cyl", Vector3(0, 0.0, SKULL_MAX.z + 0.04), Vector3(0.07, 0.02, 0.07), Color(1.0, 0.95, 0.7, MODE_COLOR))


## Capa: um pano atrás das costas (preso ao tronco), com UV para a textura das bandeiras.
static func _add_cape(g: Dictionary, body: Dictionary) -> void:
	var top := float(body["torso_top"]) - 0.02
	var bottom := float(body["foot"]) + 0.15
	var half := float(body["torso_w"]) * 1.05
	var z := float(body["torso_back"]) - 0.025
	var cols := 4
	var rows := 6
	var gv: PackedVector3Array = g["v"]
	var gn: PackedVector3Array = g["n"]
	var guv: PackedVector2Array = g["uv"]
	var guv2: PackedVector2Array = g["uv2"]
	var gc: PackedColorArray = g["c"]
	var gb: PackedInt32Array = g["b"]
	var gw: PackedFloat32Array = g["w"]
	var gi: PackedInt32Array = g["i"]
	for r in rows + 1:
		for c in cols + 1:
			var u := float(c) / cols
			var v := float(r) / rows
			# Mais larga embaixo e um tico afastada das costas.
			var w := half * (1.0 + 0.35 * v)
			gv.append(Vector3(lerpf(-w, w, u), lerpf(top, bottom, v), z - 0.04 * v))
			gn.append(Vector3(0, 0, -1))
			guv.append(Vector2(1.0 - u, v))
			guv2.append(Vector2.ZERO)
			gc.append(Color(1, 1, 1, v))  # alfa = quanto balança
			gb.append_array([B_TORSO, 0, 0, 0])
			gw.append_array([1.0, 0.0, 0.0, 0.0])
	for r in rows:
		for c in cols:
			var a := r * (cols + 1) + c
			var b := a + 1
			var d := a + cols + 1
			var e := d + 1
			gi.append_array([a, b, d, b, e, d])
	g["v"] = gv
	g["n"] = gn
	g["uv"] = guv
	g["uv2"] = guv2
	g["c"] = gc
	g["b"] = gb
	g["w"] = gw
	g["i"] = gi


## Arrays → ArrayMesh (thread principal).
static func _finish(groups: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for gi in groups.size():
		var g: Dictionary = groups[gi]
		if (g["i"] as PackedInt32Array).is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g["v"]
		arrays[Mesh.ARRAY_NORMAL] = g["n"]
		arrays[Mesh.ARRAY_TEX_UV] = g["uv"]
		arrays[Mesh.ARRAY_TEX_UV2] = g["uv2"]
		arrays[Mesh.ARRAY_COLOR] = g["c"]
		arrays[Mesh.ARRAY_BONES] = g["b"]
		arrays[Mesh.ARRAY_WEIGHTS] = g["w"]
		arrays[Mesh.ARRAY_INDEX] = g["i"]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _material if gi == 0 else null)
		mesh.surface_set_name(mesh.get_surface_count() - 1, "corpo" if gi == 0 else "capa")
	return mesh


# --- Aplicar num modelo --------------------------------------------------------------------

## Troca as duas malhas do personagem pela malha do visual. `cape` = países visitados (a
## textura dos retalhos). Devolve o MeshInstance3D novo (ou null).
static func apply(model: Node3D, mesh: ArrayMesh, look: Dictionary, cape: Array) -> MeshInstance3D:
	if model == null or mesh == null:
		return null
	var sks := model.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return null
	var sk := sks[0] as Skeleton3D
	var skin: Skin = null
	for mi: MeshInstance3D in sk.find_children("*", "MeshInstance3D", false, false):
		if mi.name in ["body-mesh", "head-mesh"]:
			skin = mi.skin
			mi.visible = false
		elif mi.name == "Look":
			mi.free()
	var out := MeshInstance3D.new()
	out.name = "Look"
	out.mesh = mesh
	out.skin = skin
	sk.add_child(out)
	out.skeleton = out.get_path_to(sk)
	set_colors(out, look)
	if mesh.get_surface_count() > 1:
		out.set_surface_override_material(1, cape_material(cape))
	return out


## Pele por parâmetro de instância (o material é o mesmo para todos). Sem tom escolhido, a
## pele original da cabeça: o corpo e a pele à mostra ficam do mesmo tom do rosto.
static func set_colors(mi: MeshInstance3D, look: Dictionary) -> void:
	mi.set_instance_shader_parameter("skin_color", skin_of(look))


## A cor de pele do jogador: a escolhida ou a original da cabeça. Em sRGB, como na bolinha
## do editor: o Godot já converte para linear os parâmetros por instância do tipo cor (a 4.1
## convertia de novo, e a pele saía mais escura e saturada que a escolhida).
static func skin_of(look: Dictionary) -> Color:
	var hex := str(look.get("skin", ""))
	if not hex.is_empty():
		return Color(hex)
	var head: Dictionary = _parts.get(str(look.get("head", "")), {})
	return head.get("skin_color", Color(0, 0, 0, 0))


## Material da capa com os retalhos das bandeiras (cache por lista de países).
static func cape_material(countries: Array) -> ShaderMaterial:
	var key := ",".join(countries)
	if _cape_mats.has(key):
		return _cape_mats[key]
	var m := ShaderMaterial.new()
	m.shader = CAPE_SHADER
	m.set_shader_parameter("flags", cape_texture(countries))
	_cape_mats[key] = m
	return m


## Textura dos retalhos: até 12 bandeiras (3 × 4), na ordem das viagens; sem viagens, um
## pano creme com a faixa verde.
static func cape_texture(countries: Array) -> ImageTexture:
	var cols := 3
	var rows := 4
	var tw := 32
	var th := 24
	var img := Image.create(cols * tw, rows * th, false, Image.FORMAT_RGBA8)
	img.fill(Color("fff6e4"))
	img.fill_rect(Rect2i(0, 0, cols * tw, 6), Color("7cc49a"))
	var atlas := FlagAtlas.texture().get_image()
	if atlas.is_compressed():
		atlas.decompress()
	atlas.convert(Image.FORMAT_RGBA8)
	var list := countries.slice(maxi(0, countries.size() - cols * rows))
	for i in list.size():
		var r := FlagAtlas.uv_rect(str(list[i]))
		var src := Rect2i(int(r.position.x * atlas.get_width()), int(r.position.y * atlas.get_height()),
			int(r.size.x * atlas.get_width()), int(r.size.y * atlas.get_height()))
		var tile := atlas.get_region(src)
		tile.resize(tw - 2, th - 2, Image.INTERPOLATE_BILINEAR)
		img.blit_rect(tile, Rect2i(0, 0, tw - 2, th - 2), Vector2i((i % cols) * tw + 1, (i / cols) * th + 1))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
