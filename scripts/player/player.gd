extends CharacterBody2D
## Player: movement, flashlight aim/rotation, shooting, HP, noise emission.
## Generates its own flashlight cone texture at runtime so no light-cookie
## art asset is required to test the core mechanic.

signal hp_changed(hp: int)
signal ammo_changed(ammo: int)
signal died

@export var speed := 140.0
@export var sprint_multiplier := 1.6
@export var base_noise_radius := 90.0
@export var sprint_noise_radius := 180.0
@export var flashlight_range := 260.0
@export var flashlight_half_angle_deg := 35.0

@onready var flashlight: PointLight2D = $Flashlight
@onready var gun_point: Marker2D = $GunPoint
@onready var shoot_audio: AudioStreamPlayer2D = $ShootAudio

var _noise_radius := 0.0

const _TEX_W := 256
const _TEX_H := 192
const _TEX_RANGE := 240.0


func _ready() -> void:
	add_to_group("player")
	flashlight.texture = _build_cone_texture()
	flashlight.offset = Vector2(0, 0)
	flashlight.texture_scale = flashlight_range / _TEX_RANGE


func _physics_process(_delta: float) -> void:
	_handle_movement()
	_aim_at_mouse()
	if Input.is_action_just_pressed("shoot"):
		_shoot()


func _handle_movement() -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var moving := dir != Vector2.ZERO
	var sprinting := moving and Input.is_action_pressed("sprint")
	velocity = dir * (speed * (sprint_multiplier if sprinting else 1.0))
	move_and_slide()

	_noise_radius = 0.0
	if moving:
		_noise_radius = sprint_noise_radius if sprinting else base_noise_radius


func _aim_at_mouse() -> void:
	var target := get_global_mouse_position()
	if target.distance_to(global_position) > 1.0:
		rotation = (target - global_position).angle()


## Enemies query this to decide whether they heard the player this frame.
func get_noise_radius() -> float:
	return _noise_radius


func _shoot() -> void:
	if Globals.ammo <= 0:
		return
	Globals.ammo -= 1
	ammo_changed.emit(Globals.ammo)
	BulletPool.spawn(gun_point.global_position, Vector2.RIGHT.rotated(rotation))
	if shoot_audio and shoot_audio.stream:
		shoot_audio.play()
	_alert_nearby_idle_enemies()


## Gunshots alert nearby IDLE monsters within a radius, per the design doc.
func _alert_nearby_idle_enemies(radius: float = 320.0) -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.global_position.distance_to(global_position) <= radius:
			if enemy.has_method("hear_gunshot"):
				enemy.hear_gunshot(global_position)


func add_ammo(amount: int) -> void:
	Globals.ammo += amount
	ammo_changed.emit(Globals.ammo)


func heal(amount: int) -> void:
	Globals.player_hp += amount
	hp_changed.emit(Globals.player_hp)


func take_damage(amount: int = 1) -> void:
	Globals.player_hp -= amount
	hp_changed.emit(Globals.player_hp)
	if Globals.player_hp <= 0:
		died.emit()


## Builds a soft-edged cone texture once at startup: RGB white, alpha falloff
## by distance and angle from +X. Assigned to the PointLight2D as its cookie.
func _build_cone_texture() -> ImageTexture:
	var img := Image.create(_TEX_W, _TEX_H, false, Image.FORMAT_RGBA8)
	var half_angle := deg_to_rad(flashlight_half_angle_deg)
	var cy := _TEX_H / 2.0
	for y in _TEX_H:
		for x in _TEX_W:
			var dx := float(x)
			var dy := float(y) - cy
			var dist := sqrt(dx * dx + dy * dy)
			var denom: float = dx if dx > 0.001 else 0.001
			var angle: float = abs(atan2(dy, denom))
			var a := 0.0
			if dist <= _TEX_RANGE and angle <= half_angle:
				var dist_falloff := 1.0 - smoothstep(_TEX_RANGE * 0.55, _TEX_RANGE, dist)
				var angle_falloff := 1.0 - smoothstep(half_angle * 0.55, half_angle, angle)
				a = clamp(dist_falloff * angle_falloff, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 0.95, 0.82, a))
	return ImageTexture.create_from_image(img)
