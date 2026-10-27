extends CharacterBody2D
## Player: movement, flashlight aim/rotation, shooting, HP, noise emission.
## Generates its own flashlight cone texture at runtime so no light-cookie
## art asset is required to test the core mechanic.

signal hp_changed(hp: int)
signal ammo_changed(ammo: int)
signal died
signal light_toggled(on: bool)

@export var speed := 140.0
@export var sprint_multiplier := 1.6
@export var base_noise_radius := 90.0
@export var sprint_noise_radius := 180.0
@export var flashlight_range := 260.0
@export var flashlight_half_angle_deg := 35.0
@export var muzzle_flash_duration := 0.06

@export var ambient_glow_radius := 80.0

@onready var flashlight: PointLight2D = $Flashlight
@onready var ambient_glow: PointLight2D = $AmbientGlow
@onready var gun_point: Marker2D = $GunPoint
@onready var muzzle_flash: Polygon2D = $GunPoint/MuzzleFlash
@onready var muzzle_light: PointLight2D = $GunPoint/MuzzleLight
@onready var shoot_audio: AudioStreamPlayer2D = $ShootAudio
@onready var heartbeat_audio: AudioStreamPlayer = $HeartbeatAudio
@onready var light_toggle_audio: AudioStreamPlayer2D = $LightToggleAudio

var _noise_radius := 0.0
var _light_on := true
var _speed_multiplier := 1.0
var _base_flashlight_range: float
var _effect_expiry: Dictionary = {}  # effect name -> seconds remaining
var _muzzle_flash_timer := 0.0

const _TEX_RANGE := 240.0
const _TEX_W := int(_TEX_RANGE * 2.0)
const _TEX_H := 192


func _ready() -> void:
	add_to_group("player")
	_base_flashlight_range = flashlight_range
	flashlight.texture = _build_cone_texture()
	flashlight.offset = Vector2(0, 0)
	flashlight.texture_scale = flashlight_range / _TEX_RANGE
	# Always-on, independent of the flashlight toggle: a small dim radius so
	# "light off" means stealthy and hard to navigate by torch-light, not
	# literally unable to see your own feet. Doesn't affect enemy detection
	# at all — that's driven purely by is_light_on()/is_stealthed(), not by
	# actual rendered brightness.
	ambient_glow.texture = _build_radial_texture(64, 30.0, Color(0.8, 0.82, 0.9))
	ambient_glow.texture_scale = ambient_glow_radius / 30.0
	ambient_glow.enabled = true
	muzzle_flash.visible = false
	muzzle_light.texture = _build_radial_texture(64, 30.0, Color(1.0, 0.9, 0.6))
	muzzle_light.enabled = false


func _physics_process(delta: float) -> void:
	_handle_movement()
	_aim_at_mouse()
	_update_effects(delta)
	_update_muzzle_flash(delta)
	if Input.is_action_just_pressed("shoot"):
		_shoot()
	if Input.is_action_just_pressed("toggle_light"):
		_toggle_light()


func _handle_movement() -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var moving := dir != Vector2.ZERO
	var sprinting := moving and Input.is_action_pressed("sprint")
	velocity = dir * (speed * _speed_multiplier * (sprint_multiplier if sprinting else 1.0))
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


## Enemies and the minimap query this: light on means the maze and nearby
## enemies are visible (to you AND to them), light off means you're blind to
## both but much harder to notice — sound is still what gives you away.
func is_light_on() -> bool:
	return _light_on


## Enemies check this before any detection logic at all — while active, a
## stealth powerup makes the player completely unnoticeable, even point-blank
## with the light on. Doesn't retroactively make an already-chasing enemy
## forget you; it just stops it (and everything else) from re-spotting you,
## so you have to actually use the window to get away.
func is_stealthed() -> bool:
	return _has_effect("stealth")


func _toggle_light() -> void:
	_light_on = not _light_on
	flashlight.enabled = _light_on
	light_toggled.emit(_light_on)
	if light_toggle_audio and light_toggle_audio.stream:
		light_toggle_audio.play()


func _shoot() -> void:
	if Globals.ammo <= 0:
		return
	Globals.ammo -= 1
	ammo_changed.emit(Globals.ammo)
	BulletPool.spawn(gun_point.global_position, Vector2.RIGHT.rotated(rotation))
	if shoot_audio and shoot_audio.stream:
		shoot_audio.play()
	_fire_muzzle_flash()
	_alert_nearby_idle_enemies()


func _fire_muzzle_flash() -> void:
	_muzzle_flash_timer = muzzle_flash_duration
	muzzle_flash.visible = true
	muzzle_light.enabled = true


func _update_muzzle_flash(delta: float) -> void:
	if _muzzle_flash_timer <= 0.0:
		return
	_muzzle_flash_timer -= delta
	if _muzzle_flash_timer <= 0.0:
		muzzle_flash.visible = false
		muzzle_light.enabled = false


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
	_update_heartbeat()


func take_damage(amount: int = 1) -> void:
	if _has_effect("invincible"):
		return
	Globals.player_hp -= amount
	hp_changed.emit(Globals.player_hp)
	_update_heartbeat()
	if Globals.player_hp <= 0:
		died.emit()


## Generic timed powerup hook — Powerup (scripts/world/powerup.gd) calls this
## on pickup with one of: "speed", "invincible", "light_boost". Picking up
## the same effect again extends the remaining time rather than restarting
## it short, so overlapping pickups stack usefully instead of fighting.
func apply_powerup(effect: String, duration: float, strength: float = 1.0) -> void:
	var was_active := _has_effect(effect)
	_effect_expiry[effect] = max(_effect_expiry.get(effect, 0.0), duration)
	if was_active:
		return
	match effect:
		"speed":
			_speed_multiplier = strength
		"light_boost":
			flashlight_range = _base_flashlight_range * strength
			flashlight.texture_scale = flashlight_range / _TEX_RANGE


func _has_effect(effect: String) -> bool:
	return _effect_expiry.has(effect)


func _update_effects(delta: float) -> void:
	if _effect_expiry.is_empty():
		return
	for effect in _effect_expiry.keys().duplicate():
		_effect_expiry[effect] -= delta
		if _effect_expiry[effect] <= 0.0:
			_effect_expiry.erase(effect)
			_end_effect(effect)


func _end_effect(effect: String) -> void:
	match effect:
		"speed":
			_speed_multiplier = 1.0
		"light_boost":
			flashlight_range = _base_flashlight_range
			flashlight.texture_scale = flashlight_range / _TEX_RANGE


## Last-stand tension cue: loops a heartbeat once the player is down to
## their last hit point, stops as soon as they're healed back up.
func _update_heartbeat() -> void:
	if heartbeat_audio == null or heartbeat_audio.stream == null:
		return
	var critical := Globals.player_hp == 1
	if critical and not heartbeat_audio.playing:
		heartbeat_audio.play()
	elif not critical and heartbeat_audio.playing:
		heartbeat_audio.stop()


## Builds a soft-edged cone texture once at startup: RGB white, alpha falloff
## by distance and angle from +X. Assigned to the PointLight2D as its cookie.
##
## Godot centers a Light2D's texture on the node by default. The canvas is
## therefore built TWICE as wide as the cone's actual reach, with the cone's
## apex placed at the image's own center (left half left fully transparent)
## — so that default centering lands the apex exactly on the player instead
## of the light rendering with its origin floating a half-texture-width
## behind them (which is what "the light is behind the player" actually was).
func _build_cone_texture() -> ImageTexture:
	var img := Image.create(_TEX_W, _TEX_H, false, Image.FORMAT_RGBA8)
	var half_angle := deg_to_rad(flashlight_half_angle_deg)
	var cx := _TEX_W / 2.0
	var cy := _TEX_H / 2.0
	for y in _TEX_H:
		for x in _TEX_W:
			var dx := float(x) - cx
			if dx < 0.0:
				continue
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


## Small omnidirectional soft-falloff cookie, reused for the muzzle flash's
## brief point light and the always-on ambient glow — a PointLight2D with no
## texture assigned renders nothing, so even these small effects need one.
func _build_radial_texture(size: int, px_range: float, color: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := size / 2.0
	for y in size:
		for x in size:
			var dist := Vector2(x - c, y - c).length()
			var a := 0.0
			if dist <= px_range:
				a = 1.0 - smoothstep(px_range * 0.3, px_range, dist)
			img.set_pixel(x, y, Color(color.r, color.g, color.b, a))
	return ImageTexture.create_from_image(img)
