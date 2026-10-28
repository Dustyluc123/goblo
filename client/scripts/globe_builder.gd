class_name GlobeBuilder
extends RefCounted
## Monta a malha do globo: uma única ArrayMesh com cor por vértice e sombreamento flat.
##
## Cada célula vira um "azulejo": um polígono plano no meio (o topo) e um anel mais escuro
## em volta (a borda sutil do hexágono). Células de terra ficam `land_height` acima do
## oceano, com uma parede cor de areia onde encostam no mar — o "degrau" fofo.

const OCEAN := Color("86c5e6")
const OCEAN_SHALLOW := Color("9fdbe0")
const SNOW := Color("f2f6fb")
const SAND := Color("eedcaa")
const SNOW_WALL := Color("d8e2ef")
const EDGE_DARKEN := 0.1
const SNOW_LATITUDE := 62.0


## Malha do globo inteiro. `inset` é a fração do raio do azulejo ocupada pelo topo
## (o resto é a borda).
static func build(world: WorldData, land_height: float, inset := 0.86) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var r := world.radius
	for i in world.cell_count():
		var c := world.centers[i]
		var on_land := world.is_land(i)
		var h := r + (land_height if on_land else 0.0)
		var top := cell_color(world, i)
		var edge := top.darkened(EDGE_DARKEN)
		var wall := SNOW_WALL if _is_snow(world, i) else SAND
		var poly := world.vertices[i]
		var count := poly.size()
		var inner := _inner_ring(c, poly, h, inset)
		var center := c * h
		for k in count:
			var k2 := (k + 1) % count
			var outer_a := poly[k] * h
			var outer_b := poly[k2] * h
			_tri(verts, normals, colors, center, inner[k], inner[k2], top)
			_tri(verts, normals, colors, inner[k], outer_a, outer_b, edge)
			_tri(verts, normals, colors, inner[k], outer_b, inner[k2], edge)
			if on_land and not world.is_land(world.neighbors[i][k]):
				var low_a := poly[k] * r
				var low_b := poly[k2] * r
				_tri(verts, normals, colors, outer_a, low_a, low_b, wall)
				_tri(verts, normals, colors, outer_a, low_b, outer_b, wall)
	return _mesh(verts, normals, colors, _globe_material())


## Malha de destaque da célula embaixo do personagem (um véu branco por cima do azulejo).
static func highlight(world: WorldData, id: int, land_height: float) -> ArrayMesh:
	var c := world.centers[id]
	var h := world.radius + (land_height if world.is_land(id) else 0.0) + 0.04
	var ring := _inner_ring(c, world.vertices[id], h, 0.97)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for k in ring.size():
		_tri(verts, normals, colors, c * h, ring[k], ring[(k + 1) % ring.size()], Color.WHITE)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 1, 1, 0.35)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _mesh(verts, normals, colors, mat)


## Cor do topo da célula: oceano azul (mais claro perto da costa), neve nos polos e,
## em terra, um verde pastel com um tom levemente diferente para cada país.
static func cell_color(world: WorldData, id: int) -> Color:
	var jitter := _hash01(str(id)) - 0.5
	if not world.is_land(id):
		var coastal := false
		for nb in world.neighbors[id]:
			if world.is_land(nb):
				coastal = true
				break
		var base := OCEAN_SHALLOW if coastal else OCEAN
		return base.lightened(jitter * 0.04)
	if _is_snow(world, id):
		return SNOW.darkened(absf(jitter) * 0.03)
	var t := _hash01(world.country_codes[id])
	var hue := 0.20 + 0.09 * t
	var sat := 0.36 + 0.08 * _hash01(world.country_codes[id] + "s")
	var val := 0.78 + 0.06 * t + jitter * 0.02
	return Color.from_hsv(hue, sat, val)


static func _is_snow(world: WorldData, id: int) -> bool:
	return world.is_land(id) and (
		absf(world.lats[id]) > SNOW_LATITUDE or world.country_codes[id] == "ATA"
	)


## Pontos do topo plano: o plano passa por c·h e é perpendicular a c.
static func _inner_ring(c: Vector3, poly: PackedVector3Array, h: float, inset: float) -> PackedVector3Array:
	var ring := PackedVector3Array()
	for corner in poly:
		var d := c.lerp(corner, inset).normalized()
		ring.append(d * (h / d.dot(c)))
	return ring


## Recebe o triângulo em sentido anti-horário visto de fora (a convenção do servidor)
## e grava no sentido horário, que é a face da frente no Godot. Normal da própria face
## = sombreamento flat.
static func _tri(
	verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
	a: Vector3, b: Vector3, c: Vector3, color: Color
) -> void:
	var n := (b - a).cross(c - a).normalized()
	verts.append_array([a, c, b])
	normals.append_array([n, n, n])
	colors.append_array([color, color, color])


static func _mesh(
	verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, mat: Material
) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	return mesh


static func _globe_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	mat.metallic_specular = 0.15
	return mat


## Número estável entre 0 e 1 a partir de um texto (a mesma entrada dá sempre a mesma cor).
static func _hash01(s: String) -> float:
	return float(absi(s.hash()) % 1000) / 1000.0
