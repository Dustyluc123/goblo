class_name Clouds
extends MultiMeshInstance3D
## Nuvens low-poly fofas orbitando devagar acima do globo. Cada nuvem é um punhado de
## "bolinhas" (esferas achatadas) num único MultiMesh. Posições sorteadas com semente fixa.
## Aparecem no zoom afastado e somem suavemente quando a câmera chega perto do personagem.

const CLOUD_SHADER := preload("res://shaders/cloud.gdshader")
const SEED := 2026

## Velocidade da órbita (radianos por segundo): uma volta a cada ~35 minutos.
@export var orbit_speed := 0.003
@export var altitude_min := 90.0
@export var altitude_max := 150.0

var _material: ShaderMaterial


func build(radius: float, count: int) -> void:
	_material = ShaderMaterial.new()
	_material.shader = CLOUD_SHADER
	var puff := SphereMesh.new()
	puff.radial_segments = 8
	puff.rings = 4
	puff.radius = 1.0
	puff.height = 2.0
	puff.material = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var rng := DecorRng.new(SEED)
	var transforms: Array[Transform3D] = []
	for i in count:
		var lat := rad_to_deg(asin(rng.next_float() * 1.7 - 0.85))
		var lon := rng.next_float() * 360.0 - 180.0
		var up := WorldData.lat_lon_to_vec(lat, lon)
		var center := up * (radius + lerpf(altitude_min, altitude_max, rng.next_float()))
		var side := up.cross(Vector3.UP if absf(up.y) < 0.99 else Vector3.RIGHT).normalized()
		side = side.rotated(up, rng.next_float() * TAU)
		var fwd := side.cross(up)
		var puffs := 4 + int(rng.next_float() * 4.0)
		var length := lerpf(90.0, 200.0, rng.next_float())
		for j in puffs:
			var t := (float(j) / float(puffs - 1)) - 0.5
			var size := lerpf(28.0, 60.0, rng.next_float()) * (1.0 - absf(t) * 0.7)
			var p := center + side * t * length + fwd * (rng.next_float() - 0.5) * 40.0 + up * (rng.next_float() * 15.0)
			var b := Basis(side * size, up * size * 0.62, fwd * size)
			transforms.append(Transform3D(b, p))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = puff
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	multimesh = mm


## `far` = zoom da câmera (0 perto, 1 longe); `day` clareia/escurece as nuvens.
func update(delta: float, far: float, day: float) -> void:
	if _material == null:
		return
	rotate_y(orbit_speed * delta)
	var opacity := smoothstep(0.3, 0.6, far) * 0.92
	visible = opacity > 0.01
	_material.set_shader_parameter("opacity", opacity)
	_material.set_shader_parameter("tint", Color(0.55, 0.6, 0.8).lerp(Color.WHITE, day))
