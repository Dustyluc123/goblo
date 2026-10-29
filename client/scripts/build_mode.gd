class_name BuildMode
extends Node3D
## Modo construção (B): escolhe um objeto colocável do inventário, mostra a prévia
## transparente (verde onde pode, vermelha onde não pode) na grade do lote, gira de 90 em
## 90 graus (R), coloca com o clique e guarda de volta com X. Também posiciona a casa
## (a partir do menu da bancada).
##
## As regras são conferidas aqui só para a prévia; quem decide é o servidor
## (POST /lot/place, /lot/remove, /lot/house).

var game: GameMain
var session: Session
var data: ChunkData
var api: Api
var ui: GameUi
var camera: Camera3D
var player: Player

var active := false
var house_mode := false
var item := ""
var rot := 0

var _ghost: MeshInstance3D
var _final_outline: MeshInstance3D
var _ok_mat: StandardMaterial3D
var _bad_mat: StandardMaterial3D
var _tile := Vector2i(-1, -1)
var _valid := false
var _busy := false


func _ready() -> void:
	_ok_mat = _ghost_material(Color(0.45, 0.95, 0.55, 0.55))
	_bad_mat = _ghost_material(Color(1.0, 0.4, 0.35, 0.55))
	_ghost = MeshInstance3D.new()
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ghost)
	_final_outline = MeshInstance3D.new()
	_final_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_final_outline)
	visible = false


func _ghost_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.no_depth_test = false
	return m


## Entra no modo construção (com um item, ou o primeiro colocável do inventário).
func enter(with_item := "") -> bool:
	if not _near_own_lot():
		ui.toast("Vá até o seu lote para construir (H leva para casa).")
		return false
	house_mode = false
	item = with_item if not with_item.is_empty() else _first_placeable()
	active = true
	visible = true
	_refresh_bar()
	return true


func enter_house() -> bool:
	if not _near_own_lot():
		ui.toast("Vá até o seu lote para escolher o lugar da casa (H leva para casa).")
		return false
	house_mode = true
	item = ""
	active = true
	visible = true
	ui.show_build_bar(session, "", true, func(_id: String) -> void: pass)
	return true


func exit() -> void:
	active = false
	visible = false
	house_mode = false
	ui.hide_build_bar()


func _refresh_bar() -> void:
	if house_mode:
		return
	ui.show_build_bar(session, item, false, func(id: String) -> void:
		item = id
		_refresh_bar())


func _first_placeable() -> String:
	for s: Dictionary in session.inventory:
		if session.is_placeable(s["item"]):
			return s["item"]
	return ""


func _near_own_lot() -> bool:
	var lot := session.lot()
	if lot.is_empty():
		return false
	var f := data.frame(int(lot["cell"]))
	var n := session.lot_tiles
	var center := LotGeom.point(f, lot, session.tile_size, n * 0.5, n * 0.5)
	return player.global_position.distance_to(center) < data.lot_size() * 1.6


func _footprint() -> Vector2i:
	if house_mode:
		var level: int = _house_levels()[1]
		var h := session.house_level(level)
		return Vector2i(int(h["footprint"][0]), int(h["footprint"][1])) if not h.is_empty() else Vector2i(6, 6)
	return LotGeom.footprint_of(session.items.get(item, {}))


## [nível pronto, nível que vai ser construído].
func _house_levels() -> Array:
	var house: Variant = session.lot().get("house")
	var level := int(house.get("level", 0)) if house is Dictionary else 0
	return [level, level + 1]


## Retângulos ocupados no lote (casa + objetos), menos a casa no modo casa.
func _taken() -> Array:
	var out: Array = []
	var lot := session.lot()
	var house: Variant = lot.get("house")
	if house is Dictionary and not house_mode:
		var lvl := maxi(int(house.get("level", 0)), int(house.get("pending_level", 0)))
		var h := session.house_level(lvl)
		if not h.is_empty():
			var r := LotGeom.rotated(Vector2i(int(h["footprint"][0]), int(h["footprint"][1])), int(house.get("rot", 0)))
			out.append(Rect2i(int(house["x"]), int(house["y"]), r.x, r.y))
	for p: Dictionary in lot.get("placements", []):
		var it: Dictionary = session.items.get(str(p["item"]), {})
		var r := LotGeom.rotated(LotGeom.footprint_of(it), int(p.get("rot", 0)))
		out.append(Rect2i(int(p["x"]), int(p["y"]), r.x, r.y))
	return out


func _process(_delta: float) -> void:
	if not active:
		return
	var lot := session.lot()
	if lot.is_empty() or (item.is_empty() and not house_mode):
		_ghost.visible = false
		return
	var f := data.frame(int(lot["cell"]))
	var tile := session.tile_size
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	var up: Vector3 = f["center"]
	var plane := Plane(up, float(f["top"]))
	var hit: Variant = plane.intersects_ray(origin, dir)
	if hit == null:
		_ghost.visible = false
		return
	var tc := LotGeom.tile_coords(f, lot, tile, hit)
	var fp := LotGeom.rotated(_footprint(), rot)
	_tile = Vector2i(int(floor(tc.x - fp.x * 0.5 + 0.5)), int(floor(tc.y - fp.y * 0.5 + 0.5)))
	var rect := Rect2i(_tile, fp)
	_valid = LotGeom.fits(session.lot_tiles, rect, _taken())
	if house_mode:
		_valid = _valid and session.can_afford(session.house_level(_house_levels()[1]).get("cost", {}))
	else:
		_valid = _valid and session.count(item) > 0
	_update_ghost(f, lot, tile)


func _update_ghost(f: Dictionary, lot: Dictionary, tile: float) -> void:
	_ghost.visible = true
	var mat := _ok_mat if _valid else _bad_mat
	if house_mode:
		var h := session.house_level(_house_levels()[1])
		var lib := ModelLibrary.get_model(str(h.get("scene", "")))
		if lib.is_empty():
			return
		_ghost.mesh = lib["mesh"]
		_ghost.transform = LotGeom.model_transform(f, lot, tile, _footprint(), _tile.x, _tile.y, rot, lib["aabb"], 1.0)
		_ghost.material_override = mat
		# Contorno da casa grande (o maior nível), para o jogador deixar espaço para crescer.
		var top := session.house_level(session.houses.size())
		var tfp := LotGeom.rotated(Vector2i(int(top["footprint"][0]), int(top["footprint"][1])), rot)
		_final_outline.visible = true
		_final_outline.mesh = _rect_mesh(f, lot, tile, Rect2i(_tile, tfp))
		_final_outline.material_override = _ok_mat if LotGeom.fits(session.lot_tiles, Rect2i(_tile, tfp), _taken()) else _bad_mat
		return
	_final_outline.visible = false
	var it: Dictionary = session.items.get(item, {})
	var lib := ModelLibrary.get_model(str(it.get("model", "")))
	if lib.is_empty():
		return
	_ghost.mesh = lib["mesh"]
	_ghost.transform = LotGeom.model_transform(f, lot, tile, LotGeom.footprint_of(it), _tile.x, _tile.y, rot, lib["aabb"], float(it.get("scale", 1.0)))
	_ghost.material_override = mat


## Contorno fino de um retângulo da grade, no chão.
func _rect_mesh(f: Dictionary, lot: Dictionary, tile: float, r: Rect2i) -> ArrayMesh:
	var verts := PackedVector3Array()
	var c := [Vector2(r.position), Vector2(r.end.x, r.position.y), Vector2(r.end), Vector2(r.position.x, r.end.y)]
	var w := 0.12
	for k in 4:
		var a: Vector2 = c[k]
		var b: Vector2 = c[(k + 1) % 4]
		var d := (b - a).normalized()
		var side := Vector2(-d.y, d.x) * w
		var p0 := LotGeom.point(f, lot, tile, a.x, a.y, 0.05)
		var p1 := LotGeom.point(f, lot, tile, b.x, b.y, 0.05)
		var p2 := LotGeom.point(f, lot, tile, b.x + side.x, b.y + side.y, 0.05)
		var p3 := LotGeom.point(f, lot, tile, a.x + side.x, a.y + side.y, 0.05)
		verts.append_array([p0, p1, p2, p0, p2, p3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("rotate"):
		rot = (rot + 1) % 4
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pick_up") and not house_mode:
		get_viewport().set_input_as_handled()
		remove_at_cursor()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		confirm()
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("build"):
		get_viewport().set_input_as_handled()
		exit()


## Coloca o item (ou a casa) no quadradinho embaixo do cursor.
func confirm() -> void:
	if _busy:
		return
	if not _valid:
		ui.toast("Não dá para colocar aí." if not house_mode else "A casa não cabe aí (ou faltam materiais).")
		return
	var lot := session.lot()
	_busy = true
	var r: Dictionary
	if house_mode:
		r = await api.request("POST", "/lot/house", {"lot": lot["id"], "x": _tile.x, "y": _tile.y, "rot": rot})
	else:
		r = await api.request("POST", "/lot/place", {"lot": lot["id"], "item": item, "x": _tile.x, "y": _tile.y, "rot": rot})
	_busy = false
	if not r["ok"]:
		ui.toast(str(r["message"]))
		return
	game.apply_lot_result(r["data"])
	if house_mode:
		ui.toast("A obra começou! Fica pronta amanhã às 5h.")
		exit()
		return
	if session.count(item) == 0:
		item = _first_placeable()
	_refresh_bar()


## Guarda no inventário o objeto embaixo do cursor.
func remove_at_cursor() -> void:
	if _busy:
		return
	var lot := session.lot()
	var target := {}
	for p: Dictionary in lot.get("placements", []):
		var it: Dictionary = session.items.get(str(p["item"]), {})
		var r := LotGeom.rotated(LotGeom.footprint_of(it), int(p.get("rot", 0)))
		var rect := Rect2i(int(p["x"]), int(p["y"]), r.x, r.y)
		var fp := LotGeom.rotated(_footprint(), rot) if not item.is_empty() else Vector2i.ONE
		var center := _tile + fp / 2
		if rect.has_point(center) or rect.has_point(_tile):
			target = p
			break
	if target.is_empty():
		ui.toast("Aponte o cursor para um objeto do seu lote.")
		return
	_busy = true
	var res := await api.request("POST", "/lot/remove", {"placement": target["id"]})
	_busy = false
	if not res["ok"]:
		ui.toast(str(res["message"]))
		return
	game.apply_lot_result(res["data"])
	ui.toast("Guardado: %s" % session.item_name(target["item"]), target["item"])
	if item.is_empty():
		item = str(target["item"])
	_refresh_bar()
