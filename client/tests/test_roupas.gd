extends SceneTree
## Teste das roupas (fase 4.1, ADR 0052): para cada uma das 14 peças, sozinha e combinada com
## peças dos outros espaços, vestir só muda as regiões do próprio espaço (cabeça, corpo,
## pernas, pés, costas). O resto do personagem (posição, cor e UV de cada vértice) fica igual,
## o material do corpo é o mesmo para todos e não muda, e a capa tem material próprio, com
## parâmetros por instância que não colidem com os do corpo (o bug do personagem verde).
## Sem servidor: lê as peças de server/data/game/items.json.
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
		{"head": "male-a", "body": "male-a", "legs": "male-a", "skin": "", "hair": "", "hairstyle": "none", "accessory": "none"},
		{"head": "female-e", "body": "male-b", "legs": "female-c", "skin": "#6b4430", "hair": "#c0392b", "hairstyle": "ponytail", "accessory": "aid-glasses", "haircut": "female-a"},
		{"head": "male-c", "body": "female-d", "legs": "male-f", "skin": "#f6d5b8", "hair": "", "hairstyle": "bun", "accessory": "cap-male-c", "haircut": "none"},
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
	model.queue_free()
	print("roupas: %d combinações conferidas, %s" % [checked, "ok" if _fails == 0 else "%d falhas" % _fails])
	quit(1 if _fails else 0)


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
