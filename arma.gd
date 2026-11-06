extends Node3D
## AK-47 de prueba, montada como viewmodel al estilo Call of Duty.
## Todo esto es desechable: arma.gd, arma_ak47.glb, el nodo PortaArma de la
## camara de primera persona y ArmaTercera del hueso de la mano.

const CARGADOR := 30
const RESERVA_INICIAL := 120
const CADENCIA := 0.1          # 600 disparos por minuto
const RECARGA := 2.4
const ALCANCE := 400.0

# Posicion del arma respecto a la camara. En cadera va abajo a la derecha;
# al apuntar sube al centro para alinear el alza con la mira.
const POS_CADERA := Vector3(0.175, -0.145, -0.34)
# El cristal de la mira esta en local (0, 0.078, 0): bajando el arma esa misma
# cantidad, el punto rojo cae exactamente en el centro de la pantalla.
const POS_APUNTA := Vector3(0.0, -0.078, -0.22)
const PUNTO_LOCAL := Vector3(0.0, 0.078, 0.0)
const ROT_CADERA := Vector3(0.0, -4.0, 0.0)
const ROT_APUNTA := Vector3(0.0, 0.0, 0.0)
const FOV_NORMAL := 90.0
const FOV_APUNTA := 52.0
const SENS_APUNTA := 0.42      # al apuntar el raton va mas fino
const SUAVIZADO := 14.0

const RETROCESO_CADERA := 0.016
const RETROCESO_APUNTA := 0.007

var municion := CARGADOR
var reserva := RESERVA_INICIAL
var equipada := false
var apuntando := false
var recargando := false

var _espera := 0.0
var _t_recarga := 0.0
var _retroceso := 0.0
var _bob := 0.0
var _vaiven := Vector2.ZERO
var _patada := Vector3.ZERO     # desplazamiento del arma al disparar

@onready var boca: Marker3D = $Boca
@onready var jugador: Node = owner
var _cam: Camera3D
var _arma_tercera: Node3D


func _ready() -> void:
	_cam = get_parent() as Camera3D
	if _cam == null and get_parent():
		_cam = get_parent().get_parent() as Camera3D
	_arma_tercera = jugador.get_node_or_null("Armature/Skeleton3D/ManoDerecha/ArmaTercera")
	position = POS_CADERA
	rotation_degrees = ROT_CADERA
	_actualizar_visibilidad()
	_refrescar_hud()


func _actualizar_visibilidad() -> void:
	var en_primera: bool = jugador.get("primera_persona")
	visible = equipada and en_primera
	if _arma_tercera:
		_arma_tercera.visible = equipada and not en_primera


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# el arma se retrasa un poco respecto al giro: eso es el vaiven
		_vaiven.x = clamp(_vaiven.x - event.relative.x * 0.00022, -0.035, 0.035)
		_vaiven.y = clamp(_vaiven.y - event.relative.y * 0.00022, -0.030, 0.030)
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1:
			equipada = not equipada
			if not equipada:
				recargando = false
				apuntando = false
			_actualizar_visibilidad()
			_refrescar_hud()
		elif event.keycode == KEY_R:
			_empezar_recarga()
		elif event.keycode == KEY_N:
			# jugador.gd cambia la vista en este mismo evento
			call_deferred("_actualizar_visibilidad")


func _process(delta: float) -> void:
	_espera = max(0.0, _espera - delta)

	if recargando:
		_t_recarga -= delta
		if _t_recarga <= 0.0:
			var mete: int = min(CARGADOR - municion, reserva)
			municion += mete
			reserva -= mete
			recargando = false
			_refrescar_hud()

	var quiere_apuntar: bool = equipada and not recargando and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if quiere_apuntar != apuntando:
		apuntando = quiere_apuntar
		if jugador.has_method("set"):
			jugador.set("sensibilidad_mult", SENS_APUNTA if apuntando else 1.0)
		_refrescar_hud()

	# --- balanceo al andar ---
	var rapidez := 0.0
	var v = jugador.get("velocity")
	if v != null:
		rapidez = Vector2(v.x, v.z).length()
	_bob += delta * clamp(rapidez, 0.0, 10.0) * 1.15
	var fuerza: float = clamp(rapidez / 7.0, 0.0, 1.0) * (0.25 if apuntando else 1.0)
	var balanceo := Vector3(
		sin(_bob * 2.0) * 0.011 * fuerza,
		-absf(sin(_bob)) * 0.009 * fuerza,
		0.0)

	# --- vaiven del raton, se recentra solo ---
	_vaiven = _vaiven.lerp(Vector2.ZERO, clamp(delta * 7.0, 0.0, 1.0))
	var amortigua: float = 0.3 if apuntando else 1.0
	var desvio := Vector3(_vaiven.x * amortigua, _vaiven.y * amortigua, 0.0)

	# --- patada del arma hacia atras ---
	_patada = _patada.lerp(Vector3.ZERO, clamp(delta * 11.0, 0.0, 1.0))

	var destino: Vector3 = (POS_APUNTA if apuntando else POS_CADERA) + balanceo + desvio + _patada
	var destino_rot: Vector3 = ROT_APUNTA if apuntando else ROT_CADERA
	var t: float = clamp(delta * SUAVIZADO, 0.0, 1.0)
	position = position.lerp(destino, t)
	rotation_degrees = rotation_degrees.lerp(destino_rot, t)

	if _cam:
		var fov_destino: float = FOV_APUNTA if apuntando else FOV_NORMAL
		_cam.fov = lerp(_cam.fov, fov_destino, t)

	# --- retroceso de la mira, sube y vuelve ---
	var piv = jugador.get_node_or_null("Pivote")
	if piv:
		if _retroceso > 0.0:
			var paso: float = min(_retroceso, delta * 7.0)
			piv.rotation.x += paso
			_retroceso -= paso

	if equipada and not recargando and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if _espera <= 0.0:
			_disparar()


func _empezar_recarga() -> void:
	if recargando or not equipada:
		return
	if municion >= CARGADOR or reserva <= 0:
		return
	recargando = true
	_t_recarga = RECARGA
	_refrescar_hud()


func _disparar() -> void:
	if municion <= 0:
		_empezar_recarga()
		return
	municion -= 1
	_espera = CADENCIA
	_retroceso += (RETROCESO_APUNTA if apuntando else RETROCESO_CADERA)
	_patada = Vector3(0, 0.004, 0.028)
	_refrescar_hud()
	_fogonazo()

	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var desde := cam.global_position
	# dispersion: minima al apuntar, mayor desde la cadera
	var disp: float = 0.002 if apuntando else 0.016
	var dir := -cam.global_transform.basis.z
	dir += cam.global_transform.basis.x * randf_range(-disp, disp)
	dir += cam.global_transform.basis.y * randf_range(-disp, disp)
	var par := PhysicsRayQueryParameters3D.create(desde, desde + dir.normalized() * ALCANCE)
	if jugador is CollisionObject3D:
		par.exclude = [jugador.get_rid()]
	var golpe := get_world_3d().direct_space_state.intersect_ray(par)
	if golpe.has("position"):
		_impacto(golpe["position"], golpe.get("normal", Vector3.UP))


func _fogonazo() -> void:
	var luz := OmniLight3D.new()
	luz.light_color = Color(1.0, 0.78, 0.38)
	luz.light_energy = 7.0
	luz.omni_range = 5.0
	boca.add_child(luz)
	var destello := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.26, 0.26)
	destello.mesh = q
	destello.material_override = _material_fuego()
	destello.rotation_degrees.z = randf() * 360.0
	boca.add_child(destello)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(luz, "light_energy", 0.0, 0.05)
	tw.tween_property(destello, "scale", Vector3.ONE * 1.7, 0.05)
	tw.chain().tween_callback(func():
		if is_instance_valid(luz): luz.queue_free()
		if is_instance_valid(destello): destello.queue_free())


func _impacto(pos: Vector3, nor: Vector3) -> void:
	var escena := get_tree().current_scene
	if escena == null:
		return
	var raiz := Node3D.new()
	escena.add_child(raiz)
	raiz.global_position = pos + nor * 0.04

	var bola := MeshInstance3D.new()
	var esf := SphereMesh.new()
	esf.radius = 0.1
	esf.height = 0.2
	esf.radial_segments = 8
	esf.rings = 4
	bola.mesh = esf
	bola.material_override = _material_fuego()
	raiz.add_child(bola)

	var luz := OmniLight3D.new()
	luz.light_color = Color(1.0, 0.55, 0.2)
	luz.light_energy = 5.0
	luz.omni_range = 4.5
	raiz.add_child(luz)

	var ch := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.direction = nor
	pm.spread = 55.0
	pm.initial_velocity_min = 2.5
	pm.initial_velocity_max = 7.0
	pm.gravity = Vector3(0, -12, 0)
	pm.scale_min = 0.25
	pm.scale_max = 0.7
	pm.color = Color(1.0, 0.72, 0.3)
	ch.process_material = pm
	var mm := QuadMesh.new()
	mm.size = Vector2(0.05, 0.05)
	ch.draw_pass_1 = mm
	ch.material_override = _material_fuego()
	ch.amount = 14
	ch.lifetime = 0.6
	ch.one_shot = true
	ch.explosiveness = 1.0
	ch.emitting = true
	raiz.add_child(ch)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(bola, "scale", Vector3.ONE * 2.6, 0.22)
	tw.tween_property(luz, "light_energy", 0.0, 0.3)
	tw.chain().tween_callback(func():
		if is_instance_valid(bola): bola.queue_free())
	get_tree().create_timer(1.2).timeout.connect(func():
		if is_instance_valid(raiz): raiz.queue_free())


func _material_fuego() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(1.0, 0.66, 0.26, 0.95)
	m.disable_receive_shadows = true
	return m


func _refrescar_hud() -> void:
	var et := get_tree().get_first_node_in_group("hud_municion")
	if et == null or not (et is Label):
		return
	var l := et as Label
	if not equipada:
		l.text = ""
	elif recargando:
		l.text = "RECARGANDO..."
	else:
		l.text = "%d / %d" % [municion, reserva]
	var mira := get_tree().get_first_node_in_group("hud_mira")
	if mira is Control:
		# al apuntar se usa el alza del arma, la mira estorba
		(mira as Control).visible = not apuntando
