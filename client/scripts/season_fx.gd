class_name SeasonFx
extends Node3D
## Partículas das estações em volta da câmera: folhas caindo no outono e flocos de neve no
## inverno, só onde o personagem está num bioma com estações e perto do chão. A quantidade
## vem da qualidade (Quality, "weather"; na baixa, nada). Leves: quads pequenos sem sombra.

const BOX := Vector3(26, 10, 26)

var _leaves: GPUParticles3D
var _snow: GPUParticles3D
var _amount := 0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return  # sem desenho nos testes (e a malha da partícula dá erro no renderizador falso)
	_leaves = _make(_leaf_texture(), Vector2(0.16, 0.12), 1.1, 0.9)
	_snow = _make(_flake_texture(), Vector2(0.07, 0.07), 0.8, 0.25)
	Quality.emitter.changed.connect(_apply_quality)
	_apply_quality()


func _apply_quality() -> void:
	_amount = int(Quality.current().get("weather", 0))
	if _leaves == null:
		return
	for p: GPUParticles3D in [_leaves, _snow]:
		p.amount = maxi(_amount, 1)
		p.emitting = false


func _make(tex: Texture2D, size: Vector2, fall: float, wobble: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.lifetime = 8.0
	p.preprocess = 4.0
	p.visibility_aabb = AABB(-BOX, BOX * 2.0)
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(BOX.x, 0.5, BOX.z) * 0.5
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = fall * 0.7
	pm.initial_velocity_max = fall * 1.2
	pm.gravity = Vector3.ZERO
	pm.turbulence_enabled = wobble > 0.5
	pm.turbulence_noise_strength = wobble
	pm.angular_velocity_min = -90.0
	pm.angular_velocity_max = 90.0
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.4
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = mat
	p.draw_pass_1 = quad
	p.emitting = false
	add_child(p)
	return p


## A cada quadro: segue a câmera (com o "para cima" da superfície) e liga o que a estação
## pede. `autumn`/`winter`: pesos (0 a 1) da estação onde o personagem está.
func update(camera: Camera3D, autumn: float, winter: float, far_amount: float) -> void:
	if _amount <= 0 or _leaves == null:
		return
	var near := far_amount < 0.15
	var up := camera.global_position.normalized()
	var fwd := -camera.global_basis.z
	var ref := (fwd - up * fwd.dot(up))
	if ref.length() < 0.01:
		ref = camera.global_basis.x.cross(up)
	var z := -ref.normalized()
	var x := up.cross(z).normalized()
	global_transform = Transform3D(Basis(x, up, z), camera.global_position + up * (BOX.y * 0.4) + ref.normalized() * 6.0)
	_leaves.emitting = near and autumn > 0.35
	_snow.emitting = near and winter > 0.35


static func _leaf_texture() -> ImageTexture:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var cols := [Color("e8873a"), Color("d9582b"), Color("f2b443")]
	for y in n:
		for x in n:
			var u := (x - n * 0.5) / (n * 0.5)
			var v := (y - n * 0.5) / (n * 0.5)
			# Folha: elipse com ponta, nervura mais escura no meio.
			var q := u * u / 0.35 + v * v
			if q < 1.0 - absf(v) * 0.25:
				var c: Color = (cols[0] as Color).lerp(cols[2], (v + 1.0) * 0.5)
				if absf(u) < 0.07:
					c = c.darkened(0.25)
				img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


static func _flake_texture() -> ImageTexture:
	var n := 16
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x - 7.5, y - 7.5).length()
			if d < 7.0:
				img.set_pixel(x, y, Color(1, 1, 1, clampf(1.6 - d / 5.0, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)
