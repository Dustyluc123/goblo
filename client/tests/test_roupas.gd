extends SceneTree
## Teste das roupas (fase 4.1, ADR 0052; 4.2, ADR 0053): para cada uma das 14 peças, sozinha e
## combinada com peças dos outros espaços, vestir só muda as regiões do próprio espaço
## (cabeça, corpo, pernas, pés, costas). O resto do personagem (posição, cor e UV de cada
## vértice) fica igual, o material do corpo é o mesmo para todos e não muda, e a capa tem
## material próprio, com parâmetros por instância que não colidem com os do corpo.
## Fase 4.2: cada acessório e peça presa a um osso está no osso certo e perto de onde deve
## (óculos nos olhos, chapéu no alto da cabeça, cachecol no pescoço, sola no pé, capa nas
## costas), nas 12 cabeças e nos 12 corpos; a pele à mostra usa a mesma referência de tom da
## pele da parte (fica da cor escolhida), cabelo nunca vira pele, e os tons vão em sRGB.
## Sem servidor: lê as peças de server/data/game/items.json e os tons de body.json.
##
##   godot --headless --path . -s tests/test_roupas.gd

const PARTS := ["female-a", "female-b", "female-c", "female-d", "female-e", "female-f", "male-a", "male-b", "male-c", "male-d", "male-e", "male-f"]

var _fails := 0


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		if _fails <= 30:
			print("FALHOU ", what)


func _run() -> void:
	var path := ProjectSettings.globalize_path("res://").path_join("../server/data/game/items.json")
	var items: Array = (JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary)["items"]
	var wear := {}  # item → {slot, color}
	var by_slot := {}
	for it: Dictionary in items:
		if str(it.get("category", "")) == "wear":
			wear[it["id"]] = it["wear"]
			var slot := str(it["wear"]["slot"])
			if not by_slot.has(slot):
				by_slot[slot] = []
			(by_slot[slot] as Array).append(it["id"])
	_check(wear.size() == 14, "esperava 14 peças, achei %d" % wear.size())
	CharacterLook.prepare(PARTS)
	var mat_params := _params(CharacterLook._material)
	var looks := [
		{"head": "male-a", "body": "male-a", "legs": "male-a", "skin": "", "accessory": "none"},
		{"head": "female-e", "body": "male-b", "legs": "female-c", "skin": "#6b4430", "accessory": "aid-glasses"},
		{"head": "male-c", "body": "female-d", "legs": "male-f", "skin": "#f6d5b8", "accessory": "aid-sunglasses"},
	]
	var checked := 0
	for look: Dictionary in looks:
		for item: String in wear:
			var slot := str(wear[item]["slot"])
			# Sozinha, e com uma peça em cada um dos outros espaços.
			var others := {}
			for s: String in by_slot:
				if s != slot:
					var list: Array = by_slot[s]
					others[s] = {"item": list[(checked + s.length()) % list.size()], "color": "#88aa66"}
			for base: Dictionary in [{}, others]:
				var with := base.duplicate()
				with[slot] = {"item": item, "color": str(wear[item]["color"])}
				_compare(look, base, with, slot, "%s + %s (%s)" % [item, "sozinha" if base.is_empty() else "combinada", look["head"]])
				checked += 1
	# Material do corpo: um só, sem parâmetros mudados; capa com material próprio.
	var mesh := CharacterLook.build_now(looks[1], {"back": {"item": "flag_cape", "color": "#ffffff"}, "body": {"item": "coat", "color": "#6d8fe8"}})
	_check(mesh.get_surface_count() == 2, "capa: esperava 2 superfícies")
	_check(mesh.surface_get_material(0) == CharacterLook._material, "corpo: material não é o compartilhado")
	var model := (load("res://assets/kenney/mini-characters/character-male-b.glb") as PackedScene).instantiate() as Node3D
	get_root().add_child(model)
	var mi := CharacterLook.apply(model, mesh, looks[1], ["BRA", "JPN"])
	_check(mi.get_surface_override_material(0) == null, "corpo: ganhou material próprio")
	_check(mi.get_surface_override_material(1) != CharacterLook._material and mi.get_surface_override_material(1) is ShaderMaterial, "capa: material errado")
	_check(_params(CharacterLook._material) == mat_params, "material do corpo mudou depois de vestir")
	# Parâmetros por instância: índices diferentes entre o corpo e a capa.
	var used := {}
	for sh: Shader in [CharacterLook.SHADER, CharacterLook.CAPE_SHADER]:
		var re := RegEx.create_from_string("instance uniform \\w+ (\\w+)\\s*:\\s*instance_index\\((\\d+)\\)")
		var n := 0
		for m in re.search_all(sh.code):
			n += 1
			_check(not used.has(m.get_string(2)), "índice de instância %s repetido (%s)" % [m.get_string(2), m.get_string(1)])
			used[m.get_string(2)] = m.get_string(1)
		_check(n == sh.code.count("instance uniform"), "%s: parâmetro por instância sem instance_index" % sh.resource_path)
	# Fase 4.2: acessórios e peças presas a ossos, e a pele.
	var skel := (model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D)
	_check(skel.get_bone_name(CharacterLook.B_HEAD) == "head" and skel.get_bone_name(CharacterLook.B_TORSO) == "torso",
		"ossos fora da ordem esperada: %s, %s" % [skel.get_bone_name(CharacterLook.B_HEAD), skel.get_bone_name(CharacterLook.B_TORSO)])
	_check_bare()
	var placed := _check_bones(wear)
	var skins := _check_skin(wear)
	model.queue_free()
	print("roupas: %d combinações, %d peças presas a ossos e %d visuais de pele conferidos, %s" % [checked, placed, skins, "ok" if _fails == 0 else "%d falhas" % _fails])
	quit(1 if _fails else 0)


## Fase 4.5 (ADR 0054): todo corpo tem o corpo base (dois braços, duas pernas, dois pés) e o
## objeto da mão da Personagem 1 sai. Com regata, nada da pele do braço passa da seção da mão.
func _check_bare() -> void:
	for part: String in PARTS:
		var d: Dictionary = CharacterLook._parts[part]
		var bare: Dictionary = d["bare"]
		_check((bare["arm"] as Dictionary).size() == 2 and (bare["leg"] as Dictionary).size() == 2 and (bare["foot"] as Dictionary).size() == 2,
			"%s: corpo base incompleto" % part)
		var look := {"head": part, "body": part, "legs": part, "skin": "", "accessory": "none"}
		var g: Dictionary = CharacterLook._build(CharacterLook._job(look, {}))[0]
		var far := 0.0
		for i in (g["v"] as PackedVector3Array).size():
			if g["r"][i] == CharacterLook.R_BODY:
				far = maxf(far, absf((g["v"][i] as Vector3).x))
		_check(far <= CharacterLook.HAND_END, "%s: algo passa da ponta da mão (%.3f)" % [part, far])


## Compara as regiões que o espaço não pode mudar, vértice por vértice.
func _compare(look: Dictionary, a: Dictionary, b: Dictionary, slot: String, what: String) -> void:
	var ga: Dictionary = CharacterLook._build(CharacterLook._job(look, a))[0]
	var gb: Dictionary = CharacterLook._build(CharacterLook._job(look, b))[0]
	var allowed: Array = CharacterLook.SLOT_REGIONS[slot]
	for region in range(0, 9):
		if allowed.has(region):
			continue
		var va := _region(ga, region)
		var vb := _region(gb, region)
		if va.size() != vb.size():
			_check(false, "%s: região %d mudou de tamanho (%d → %d)" % [what, region, va.size(), vb.size()])
			continue
		for i in va.size():
			if va[i] != vb[i]:
				_check(false, "%s: região %d mudou no vértice %d" % [what, region, i])
				break


## Cada forma presa a um osso: no osso certo (peso 1) e com o centro perto de onde deve ficar,
## nas 12 cabeças (óculos e chapéus) e nos 12 corpos (cachecol, poncho, sandália e capa).
func _check_bones(wear: Dictionary) -> int:
	var n := 0
	for part: String in PARTS:
		var look := {"head": part, "body": part, "legs": part, "skin": "", "accessory": "none"}
		for acc in ["aid-glasses", "aid-sunglasses"]:
			look["accessory"] = acc
			var g: Dictionary = CharacterLook._build(CharacterLook._job(look, {}))[0]
			var c := _shape(g, CharacterLook.R_STYLE, [CharacterLook.B_HEAD], "%s em %s" % [acc, part])
			# Na altura dos olhos (0,40 a 0,51), na frente do rosto (que fica em z 0,16) e no meio.
			_check(c.y > 0.46 and c.y < 0.51 and c.z > 0.11 and c.z < 0.18 and absf(c.x) < 0.01, "%s em %s: fora dos olhos (%s)" % [acc, part, c])
			n += 1
		look["accessory"] = "none"
		for item: String in wear:
			var slot := str(wear[item]["slot"])
			var g: Dictionary = CharacterLook._build(CharacterLook._job(look, {slot: {"item": item, "color": "#88aa66"}}))[0]
			var what := "%s em %s" % [item, part]
			var body: Dictionary = CharacterLook._parts[part]
			match slot:
				"head":
					var c := _shape(g, CharacterLook.R_EXTRA_HEAD, [CharacterLook.B_HEAD], what)
					var low := _lowest(g, CharacterLook.R_EXTRA_HEAD)
					# No alto da cabeça (acima dos olhos, sem flutuar acima do cabelo).
					_check(c.y > 0.6 and c.y < 0.76 and absf(c.x) < 0.03 and low > 0.52, "%s: fora do alto da cabeça (centro %s, base %.3f)" % [what, c, low])
				"body":
					if item == "scarf" or item == "poncho":
						var c := _shape(g, CharacterLook.R_EXTRA_BODY, [CharacterLook.B_TORSO], what)
						_check(c.y > float(body["leg_top"]) and c.y < float(body["torso_top"]) + 0.02, "%s: fora do tronco (%s)" % [what, c])
				"feet":
					if item == "sandals":
						var c := _shape(g, CharacterLook.R_EXTRA_FEET, [CharacterLook.B_LEG_L, CharacterLook.B_LEG_R], what)
						_check(c.y < float(body["foot"]) + 0.03, "%s: fora do pé (%s)" % [what, c])
				"back":
					var cape: Dictionary = CharacterLook._build(CharacterLook._job(look, {slot: {"item": item, "color": "#ffffff"}}))[1]
					var bones: PackedInt32Array = cape["b"]
					var ok := not bones.is_empty()
					var cz := 0.0
					for i in range(0, bones.size(), 4):
						ok = ok and bones[i] == CharacterLook.B_TORSO
					for v: Vector3 in (cape["v"] as PackedVector3Array):
						cz += v.z
					_check(ok and cz / maxf((cape["v"] as PackedVector3Array).size(), 1) < float(body["torso_back"]), "%s: capa fora das costas" % what)
			n += 1
	return n


## Centro dos vértices da região, conferindo que todos estão presos (peso 1) a um dos ossos.
func _shape(g: Dictionary, region: int, bones: Array, what: String) -> Vector3:
	var r: PackedByteArray = g["r"]
	var b: PackedInt32Array = g["b"]
	var w: PackedFloat32Array = g["w"]
	var sum := Vector3.ZERO
	var count := 0
	var ok := true
	for i in r.size():
		if r[i] != region:
			continue
		ok = ok and bones.has(b[i * 4]) and is_equal_approx(w[i * 4], 1.0)
		sum += (g["v"] as PackedVector3Array)[i]
		count += 1
	_check(count > 0, "%s: não apareceu" % what)
	_check(ok, "%s: preso ao osso errado" % what)
	return sum / maxf(count, 1)


func _lowest(g: Dictionary, region: int) -> float:
	var low := INF
	var r: PackedByteArray = g["r"]
	for i in r.size():
		if r[i] == region:
			low = minf(low, (g["v"] as PackedVector3Array)[i].y)
	return low


## Pele: nas 12 partes (como cabeça, corpo e pernas) e com as peças que mostram pele, toda
## pele (natural ou à mostra pela peça) usa a referência de tom da própria parte (UV2), então
## fica da cor escolhida; o cabelo nunca é pele; a cabeça tem pele (aceita o tom); o que a
## mão segura e as luvas ficam com a cor original; os tons vão em sRGB (sem converter duas
## vezes). Devolve quantos visuais conferiu.
func _check_skin(wear: Dictionary) -> int:
	var n := 0
	var show_skin := {"body": {"item": "tank_top", "color": "#f4f1e4"}, "legs": {"item": "shorts", "color": "#e9c46a"}, "feet": {"item": "sandals", "color": "#c99a6b"}}
	for k in PARTS.size():
		var head: String = PARTS[k]
		var body: String = PARTS[(k + 3) % PARTS.size()]
		var legs: String = PARTS[(k + 7) % PARTS.size()]
		var look := {"head": head, "body": body, "legs": legs, "skin": "", "accessory": "none"}
		for w: Dictionary in [{}, show_skin, {"body": {"item": "coat", "color": "#6d8fe8"}}]:
			var g: Dictionary = CharacterLook._build(CharacterLook._job(look, w))[0]
			var by_region := {CharacterLook.R_HEAD: head, CharacterLook.R_HAIR: head, CharacterLook.R_BODY: body, CharacterLook.R_LEGS: legs}
			var head_skin := 0
			for i in (g["r"] as PackedByteArray).size():
				var reg: int = g["r"][i]
				if not by_region.has(reg):
					continue
				var part: Dictionary = CharacterLook._parts[by_region[reg]]
				var c: Color = g["c"][i]
				var is_skin := absf(c.a - CharacterLook.MODE_SKIN) < 0.01
				if reg == CharacterLook.R_HAIR:
					_check(not is_skin, "%s: cabelo virou pele" % head)
				if is_skin:
					# A cintura (calção do tronco) conta como pernas, mas vem do corpo.
					var ref: Vector2 = (g["uv2"] as PackedVector2Array)[i]
					var ok: bool = ref == part["base_uv"] or (reg == CharacterLook.R_LEGS and ref == CharacterLook._parts[body]["base_uv"])
					_check(ok, "%s/%s/%s: pele sem a referência da parte" % [head, body, legs])
					if reg == CharacterLook.R_HEAD:
						head_skin += 1
				elif reg == CharacterLook.R_BODY and w.has("body"):
					var cell := CharacterLook._cell((g["uv"] as PackedVector2Array)[i])
					if (part["arm_keep"] as Dictionary).has(cell):
						_check(absf(c.a - CharacterLook.MODE_TEX) < 0.01, "%s: o que a mão segura mudou de cor" % body)
			_check(head_skin > 0, "%s: cabeça sem pele (não aceita o tom)" % head)
			n += 1
	# Pele à mostra pela regata: braços inteiros na pele (fora luvas e o que a mão segura).
	var g2: Dictionary = CharacterLook._build(CharacterLook._job({"head": "male-a", "body": "male-a", "legs": "male-a", "skin": "", "accessory": "none"}, show_skin))[0]
	var forced := 0
	for i in (g2["r"] as PackedByteArray).size():
		if g2["r"][i] == CharacterLook.R_BODY and absf((g2["c"][i] as Color).a - CharacterLook.MODE_SKIN) < 0.01 and (g2["uv"] as PackedVector2Array)[i] == CharacterLook._parts["male-a"]["skin_uv"]:
			forced += 1
	_check(forced > 50, "regata: braços sem a pele à mostra (%d)" % forced)
	# Tons do editor: o parâmetro vai em sRGB, igual à bolinha (o Godot converte sozinho).
	var path := ProjectSettings.globalize_path("res://").path_join("../server/data/game/body.json")
	var tones: Array = (JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary)["look"]["skins"]
	_check(tones.size() >= 6, "body.json: poucos tons de pele")
	for hex: String in tones:
		var want: Color = Color(hex) if not hex.is_empty() else CharacterLook._parts["female-b"]["skin_color"]
		_check(CharacterLook.skin_of({"head": "female-b", "skin": hex}).is_equal_approx(want), "tom %s: cor errada no parâmetro" % hex)
		n += 1
	return n


func _region(g: Dictionary, region: int) -> Array:
	var out := []
	var r: PackedByteArray = g["r"]
	for i in r.size():
		if r[i] == region:
			out.append([g["v"][i], g["c"][i], g["uv"][i]])
	return out


func _params(m: ShaderMaterial) -> Dictionary:
	var out := {}
	for p: Dictionary in m.shader.get_shader_uniform_list():
		out[p["name"]] = m.get_shader_parameter(p["name"])
	return out
