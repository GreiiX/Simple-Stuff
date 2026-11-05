extends CharacterBody3D

const VELOCIDAD = 5.0
const VELOCIDAD_CORRER = 9.0
const VELOCIDAD_AGACHADO = 2.5
const SALTO = 4.5
const SENSIBILIDAD = 0.003

var agachado = false

@onready var pivote = $Pivote

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event):
	# Girar la cámara con el ratón
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * SENSIBILIDAD)
		pivote.rotate_x(-event.relative.y * SENSIBILIDAD)
		pivote.rotation.x = clamp(pivote.rotation.x, -1.2, 0.5)

	# Esc suelta el ratón, clic lo vuelve a capturar
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta):
	# Gravedad
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Agacharse con Ctrl (mantén pulsado)
	var quiere_agacharse = Input.is_key_pressed(KEY_CTRL)
	if quiere_agacharse and not agachado:
		agachado = true
		scale.y = 0.5
	elif not quiere_agacharse and agachado:
		agachado = false
		scale.y = 1.0

	# Salto con la barra espaciadora
	if Input.is_key_pressed(KEY_SPACE) and is_on_floor() and not agachado:
		velocity.y = SALTO

	# Movimiento con W A S D
	var entrada = Vector2.ZERO
	if Input.is_key_pressed(KEY_D):
		entrada.x += 1
	if Input.is_key_pressed(KEY_A):
		entrada.x -= 1
	if Input.is_key_pressed(KEY_S):
		entrada.y += 1
	if Input.is_key_pressed(KEY_W):
		entrada.y -= 1
	entrada = entrada.normalized()

	# Elegir velocidad: agachado > correr > caminar
	var velocidad_actual = VELOCIDAD
	if agachado:
		velocidad_actual = VELOCIDAD_AGACHADO
	elif Input.is_key_pressed(KEY_SHIFT):
		velocidad_actual = VELOCIDAD_CORRER

	# Moverse hacia donde miras
	var direccion = (transform.basis * Vector3(entrada.x, 0, entrada.y)).normalized()
	velocity.x = direccion.x * velocidad_actual
	velocity.z = direccion.z * velocidad_actual

	move_and_slide()
