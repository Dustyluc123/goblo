class_name DayNight
extends Node
## Dia e noite pelo horário real (UTC).
##
## O sol aponta a partir do ponto subsolar: latitude = declinação solar do dia do ano,
## longitude = hora UTC (com a equação do tempo). Do lado oposto, uma luz azulada fraca
## ("lua") e a luz ambiente fria deixam a noite aconchegante e com o caminho visível.
## O céu (sky.gdshader) e a luz ambiente seguem o horário onde o personagem está.
##
## F3 acelera o tempo (×60, ×600, ×3600); F4 volta ao horário real.
##
## Visual (fase 2.1): tonemapping AgX, luz ambiente vinda do céu, glow leve (média e alta)
## e névoa de distância com a cor do horizonte, que dá profundidade e esconde onde os
## pedaços de vegetação terminam. Tudo some no zoom afastado (o globo fica limpo).

const SPEEDS := [1.0, 60.0, 600.0, 3600.0]
const SKY_SHADER := preload("res://shaders/sky.gdshader")

@export var sun: DirectionalLight3D
@export var moon: DirectionalLight3D
@export var world_environment: WorldEnvironment

## Segundos somados ao relógio real (acelerar o tempo muda isto).
var offset_seconds := 0.0
var speed := 1.0
## Direção do centro do planeta para o sol.
var sun_dir := Vector3.UP
## 1 = dia onde o personagem está, 0 = noite.
var local_day := 1.0
var _sky_material: ShaderMaterial
var _shadows_wanted := true
## Névoa: densidade máxima perto do personagem (some no zoom afastado).
var _fog_density := 1.0

## Cores do horizonte (iguais às do sky.gdshader), para a névoa combinar com o céu.
const DAY_HORIZON := Color(0.80, 0.90, 0.98)
const DUSK_HORIZON := Color(0.98, 0.70, 0.55)
const NIGHT_HORIZON := Color(0.14, 0.18, 0.36)


func _ready() -> void:
	var env := world_environment.environment
	_sky_material = ShaderMaterial.new()
	_sky_material.shader = SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = _sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	# Luz ambiente: metade vem do céu (de cima mais azul, do horizonte mais claro), metade
	# da cor ajustada abaixo conforme a hora.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.1
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.28
	env.adjustment_contrast = 1.07
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_curve = 1.6
	env.fog_sky_affect = 0.0
	env.fog_sun_scatter = 0.12
	env.glow_intensity = 0.35
	env.glow_strength = 0.9
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 0.95
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT


## Onde a névoa começa e onde fica cheia (distância da câmera), pelo preset de qualidade.
func set_fog_distance(begin: float, end: float, density := 1.0) -> void:
	var env := world_environment.environment
	env.fog_depth_begin = begin
	env.fog_depth_end = end
	_fog_density = density


func set_glow(on: bool) -> void:
	world_environment.environment.glow_enabled = on


## Hora UTC fixa (0–24) hoje, para testes e screenshots.
func set_utc_hour(hour: float) -> void:
	var now := Time.get_unix_time_from_system()
	var midnight := floorf(now / 86400.0) * 86400.0
	offset_seconds = midnight + hour * 3600.0 - now
	speed = 1.0


func faster() -> void:
	var i := SPEEDS.find(speed)
	speed = SPEEDS[(i + 1) % SPEEDS.size()] if i < SPEEDS.size() - 1 else SPEEDS[1]


func real_time() -> void:
	offset_seconds = 0.0
	speed = 1.0


## As sombras do sol só valem de dia onde o personagem está (economiza GPU à noite).
func set_shadows_wanted(on: bool) -> void:
	_shadows_wanted = on


func unix_time() -> float:
	return Time.get_unix_time_from_system() + offset_seconds


## Hora UTC atual (0–24).
func utc_hours() -> float:
	return fmod(unix_time() / 3600.0, 24.0)


## Hora solar local numa longitude (graus): 12h = sol a pino.
func local_hours(lon: float) -> float:
	return fposmod(utc_hours() + lon / 15.0 + equation_of_time_minutes() / 60.0, 24.0)


func day_of_year() -> float:
	var t := unix_time()
	var d := Time.get_datetime_dict_from_unix_time(int(t))
	var jan1 := Time.get_unix_time_from_datetime_dict({"year": d["year"], "month": 1, "day": 1, "hour": 0, "minute": 0, "second": 0})
	return (t - jan1) / 86400.0


## Diferença entre o sol verdadeiro e o relógio (minutos), aproximação padrão.
func equation_of_time_minutes() -> float:
	var b := TAU * (day_of_year() - 81.0) / 364.0
	return 9.87 * sin(2.0 * b) - 7.53 * cos(b) - 1.5 * sin(b)


## Ponto subsolar (lat, lon em graus).
func subsolar_point() -> Vector2:
	var decl := -23.44 * cos(TAU / 365.24 * (day_of_year() + 10.0))
	var lon := -15.0 * (utc_hours() - 12.0 + equation_of_time_minutes() / 60.0)
	return Vector2(decl, wrapf(lon, -180.0, 180.0))


## Atualiza luzes, céu e ambiente. `up` = "para cima" do personagem; `far` = zoom da câmera.
func update(delta: float, up: Vector3, far: float) -> void:
	if speed != 1.0:
		offset_seconds += delta * (speed - 1.0)
	var p := subsolar_point()
	sun_dir = WorldData.lat_lon_to_vec(p.x, p.y)
	var hint := Vector3.UP if absf(sun_dir.y) < 0.99 else Vector3.FORWARD
	sun.global_basis = Basis.looking_at(-sun_dir, hint)
	moon.global_basis = Basis.looking_at(sun_dir, hint)

	var elevation := sun_dir.dot(up)
	local_day = smoothstep(-0.12, 0.12, elevation)
	# Sol mais quente e mais fraco perto do horizonte (manhã e fim de tarde).
	var high := smoothstep(0.0, 0.4, elevation)
	sun.light_color = Color(1.0, 0.6, 0.36).lerp(Color(1.0, 0.95, 0.86), high)
	sun.light_energy = lerpf(0.75, 1.15, high)
	sun.shadow_enabled = _shadows_wanted and local_day > 0.05 and far < 0.3

	var env := world_environment.environment
	var day_ambient := Color(0.85, 0.88, 1.0)
	var night_ambient := Color(0.42, 0.5, 0.85)
	# No zoom afastado, ambiente e lua mais fracos para a linha dia/noite aparecer no globo.
	var space := smoothstep(0.2, 0.8, far)
	var dusk := 1.0 - absf(local_day * 2.0 - 1.0)
	var dusk_ambient := Color(1.0, 0.78, 0.7)
	env.ambient_light_color = night_ambient.lerp(day_ambient, local_day).lerp(dusk_ambient, dusk * 0.7).lerp(night_ambient, space)
	env.ambient_light_energy = lerpf(lerpf(0.6, 0.5, local_day), 0.12, space)
	# Névoa da cor do horizonte (o mesmo cálculo do céu), sumindo no zoom afastado.
	var horizon := NIGHT_HORIZON.lerp(DAY_HORIZON.lerp(DUSK_HORIZON, dusk * 0.8), local_day)
	env.fog_light_color = horizon
	env.fog_light_energy = lerpf(0.55, 1.0, local_day)
	env.fog_density = _fog_density * (1.0 - smoothstep(0.05, 0.35, far))
	moon.light_energy = lerpf(lerpf(0.35, 0.15, local_day), 0.1, space)

	_sky_material.set_shader_parameter("local_up", up)
	_sky_material.set_shader_parameter("sun_dir", sun_dir)
	_sky_material.set_shader_parameter("day_amount", local_day)
	_sky_material.set_shader_parameter("space_amount", smoothstep(0.15, 0.6, far))
