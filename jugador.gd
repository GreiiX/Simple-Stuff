extends CharacterBody3D

# Velocidades en metros por segundo. Los umbrales de animacion mas abajo
# dependen de estos numeros: si los cambias, revisa _elegir_animacion().
const VEL_CAMINAR := 2.6
const VEL_CORRER := 6.2
const VEL_SPRINT := 9.2
const VEL_AGACHADO := 1.6
const SALTO := 5.4
const SENSIBILIDAD := 0.0028

# Inercia: en el suelo responde rapido, en el aire casi no puedes corregir.
# Sin esto puedes cambiar de direccion en seco a media parabola, que para
# saltar entre plataformas se siente mal.
const ACELERA_SUELO := 14.0
const ACELERA_AIRE := 2.2

const ALTO_NORMAL := 1.78
const ALTO_AGACHADO := 1.15
const CAMARA_NORMAL := 1.52
const CAMARA_AGACHADO := 1.00

# En primera persona puedes mirar mas abajo: no hay cuerpo delante que estorbe.
const LIMITE_ARRIBA := 0.45
const LIMITE_ABAJO_3A := -1.1
const LIMITE_ABAJO_1A := -1.4

var agachado := false
var primera_persona := false
# El arma lo baja mientras apuntas, para afinar la punteria.
var sensibilidad_mult := 1.0
var estado := ""
var estaba_en_suelo := true

@onready var pivote: Node3D = $Pivote
@onready var cam_tercera: Camera3D = $Pivote/CamaraTercera
@onready var cam_primera: Camera3D = $Pivote/CamaraPrimera
@onready var arbol: AnimationTree = $AnimationTree
@onready var forma: CollisionShape3D = $CollisionShape3D
@onready var esqueleto: Skeleton3D = $Armature/Skeleton3D

var _maq: AnimationNodeStateMachinePlayback


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_maq = arbol.get("parameters/playback")
	if _maq:
		_maq.start("Idle")
		estado = "Idle"
	_aplicar_vista()


func _aplicar_vista() -> void:
	cam_primera.current = primera_persona
	cam_tercera.current = not primera_persona
	# En primera persona el cuerpo no se dibuja, pero sigue proyectando
	# sombra: asi te ves la sombra en el suelo al saltar.
	var modo := (
		GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		if primera_persona
		else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	)
	for m in esqueleto.get_children():
		if m is MeshInstance3D:
			m.cast_shadow = modo
	var limite: float = LIMITE_ABAJO_1A if primera_persona else LIMITE_ABAJO_3A
	pivote.rotation.x = clamp(pivote.rotation.x, limite, LIMITE_ARRIBA)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s: float = SENSIBILIDAD * sensibilidad_mult
		rotate_y(-event.relative.x * s)
		pivote.rotate_x(-event.relative.y * s)
		var limite: float = LIMITE_ABAJO_1A if primera_persona else LIMITE_ABAJO_3A
		pivote.rotation.x = clamp(pivote.rotation.x, limite, LIMITE_ARRIBA)

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_N:
			primera_persona = not primera_persona
			_aplicar_vista()
		elif event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _ir_a(nuevo: String) -> void:
	if estado != nuevo and _maq:
		estado = nuevo
		_maq.travel(nuevo)


func _agacharse(quiere: bool) -> void:
	if quiere == agachado:
		return
	agachado = quiere
	var cap: CapsuleShape3D = forma.shape
	cap.height = ALTO_AGACHADO if agachado else ALTO_NORMAL
	forma.position.y = cap.height * 0.5
	pivote.position.y = CAMARA_AGACHADO if agachado else CAMARA_NORMAL


func _physics_process(delta: float) -> void:
	var en_suelo := is_on_floor()

	if not en_suelo:
		velocity += get_gravity() * delta

	_agacharse(Input.is_key_pressed(KEY_CTRL) and en_suelo)

	var acaba_de_saltar := false
	if Input.is_key_pressed(KEY_SPACE) and en_suelo and not agachado:
		velocity.y = SALTO
		acaba_de_saltar = true

	var entrada := Vector2.ZERO
	if Input.is_key_pressed(KEY_D):
		entrada.x += 1.0
	if Input.is_key_pressed(KEY_A):
		entrada.x -= 1.0
	if Input.is_key_pressed(KEY_S):
		entrada.y += 1.0
	if Input.is_key_pressed(KEY_W):
		entrada.y -= 1.0
	entrada = entrada.normalized()

	var vel := VEL_CAMINAR
	if agachado:
		vel = VEL_AGACHADO
	elif Input.is_key_pressed(KEY_SHIFT):
		vel = VEL_SPRINT
	elif entrada.length() > 0.0:
		vel = VEL_CORRER

	var direccion := (transform.basis * Vector3(entrada.x, 0.0, entrada.y)).normalized()
	var objetivo := direccion * vel
	var t: float = clamp((ACELERA_SUELO if en_suelo else ACELERA_AIRE) * delta, 0.0, 1.0)
	velocity.x = lerp(velocity.x, objetivo.x, t)
	velocity.z = lerp(velocity.z, objetivo.z, t)

	move_and_slide()

	_elegir_animacion(is_on_floor(), acaba_de_saltar)
	estaba_en_suelo = is_on_floor()


func _elegir_animacion(en_suelo: bool, acaba_de_saltar: bool) -> void:
	if acaba_de_saltar:
		_ir_a("Jump_Start")
		return

	if not en_suelo:
		if velocity.y < -0.5:
			_ir_a("Jump")
		return

	if not estaba_en_suelo:
		_ir_a("Jump_Land")
		return

	var rapidez := Vector2(velocity.x, velocity.z).length()

	if agachado:
		_ir_a("Crouch_Fwd" if rapidez > 0.35 else "Crouch_Idle")
		return

	if rapidez < 0.35:
		_ir_a("Idle")
	elif rapidez < 4.2:
		_ir_a("Walk")
	elif rapidez < 7.6:
		_ir_a("Jog_Fwd")
	else:
		_ir_a("Sprint")
