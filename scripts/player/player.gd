extends CharacterBody2D
## Player: movement, flashlight aim/rotation, shooting, HP, noise emission.
## Generates its own flashlight cone texture at runtime so no light-cookie
## art asset is required to test the core mechanic.
##
## Multiplayer-ready: player_index selects which input actions this instance
## reads (plain names for player 1, "_p2" suffixed for player 2 — see
## _action()), and hp/ammo/lighter charges are this instance's OWN state
## rather than shared globals, so two players never fight over one HP pool.
## Globals.player_hp/ammo are still mirrored for player 1 only, so solo mode
## (which only ever has a player_index == 1) behaves exactly as before.

signal hp_changed(hp: int)
signal ammo_changed(ammo: int)
signal died
signal light_toggled(on: bool)
signal power_cooldown_changed(ratio: float)  # 0 = ready, 1 = just used

@export var player_index: int = 1
@export var team: int = 1  ## Bullets only damage players on a DIFFERENT team.
@export var owns_camera: bool = true  ## False in multiplayer — a shared ArenaCamera frames everyone instead.

@export var speed := 140.0
@export var sprint_multiplier := 1.6
@export var base_noise_radius := 90.0
@export var sprint_noise_radius := 180.0
@export var flashlight_range := 260.0
@export var flashlight_half_angle_deg := 35.0
@export var muzzle_flash_duration := 0.06

## -1 = use Globals.STARTING_HP/AMMO (solo mode, unaffected). Versus mode
## sets these explicitly — a 3-HP duel ends on the first exchange, which
## doesn't make for much of a fight.
@export var starting_hp := -1
@export var starting_ammo := -1

@export var ambient_glow_radius := 80.0

## The "unique power" each player can trigger on a cooldown — reuses the
## exact same timed-effect system pickups use (apply_powerup), just
## activated by a button instead of walking over an item.
@export var power_effect: String = "speed"
@export var power_duration: float = 5.0
@export var power_strength: float = 1.6
@export var power_cooldown: float = 12.0

@onready var flashlight: PointLight2D = $Flashlight
@onready var ambient_glow: PointLight2D = $AmbientGlow
@onready var gun_point: Marker2D = $GunPoint
@onready var muzzle_flash: Polygon2D = $GunPoint/MuzzleFlash
@onready var muzzle_light: PointLight2D = $GunPoint/MuzzleLight
@onready var shoot_audio: AudioStreamPlayer2D = $ShootAudio
@onready var heartbeat_audio: AudioStreamPlayer = $HeartbeatAudio
@onready var light_toggle_audio: AudioStreamPlayer2D = $LightToggleAudio
@onready var wall_bump_audio: AudioStreamPlayer2D = $WallBumpAudio
@onready var camera: Camera2D = get_node_or_null("Camera2D")

var hp: int
var ammo: int

var _noise_radius := 0.0
var _light_on := true
var _speed_multiplier := 1.0
var _base_flashlight_range: float
var _effect_expiry: Dictionary = {}  # effect name -> seconds remaining
var _muzzle_flash_timer := 0.0
var _wall_bump_cooldown := 0.0
var _power_cooldown_timer := 0.0
var _joystick: Control = null

const WALL_BUMP_COOLDOWN := 0.4

const _TEX_RANGE := 240.0
const _TEX_W := int(_TEX_RANGE * 2.0)
const _TEX_H := 192


func _ready() -> void:
	add_to_group("player")
	hp = starting_hp if starting_hp > 0 else Globals.STARTING_HP
	ammo = starting_ammo if starting_ammo > 0 else Globals.STARTING_AMMO
	if camera:
		camera.enabled = owns_camera
		if owns_camera:
			camera.make_current()
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
	_joystick = get_tree().get_first_node_in_group(_joystick_group()) as Control


## Player 1 reads the plain action names (unchanged from solo mode); player 2
## reads the same actions with an "_p2" suffix (see project.godot).
func _action(name: String) -> String:
	return name if player_index == 1 else name + "_p2"


func _joystick_group() -> String:
	return "touch_joystick_p%d" % player_index


func _physics_process(delta: float) -> void:
	_handle_movement(delta)
	_aim(delta)
	_update_effects(delta)
	_update_muzzle_flash(delta)
	_update_power_cooldown(delta)
	if Input.is_action_just_pressed(_action("shoot")):
		_shoot()
	if Input.is_action_just_pressed(_action("toggle_light")):
		_toggle_light()
	if Input.is_action_just_pressed(_action("use_power")):
		_use_power()


func _handle_movement(delta: float) -> void:
	var dir := Input.get_vector(_action("move_left"), _action("move_right"), _action("move_up"), _action("move_down"))
	if dir == Vector2.ZERO and _joystick and _joystick.visible:
		dir = _joystick.get_vector()
	var moving := dir != Vector2.ZERO
	var sprinting := moving and Input.is_action_pressed(_action("sprint"))
	velocity = dir * (speed * _speed_multiplier * (sprint_multiplier if sprinting else 1.0))
	move_and_slide()
	_update_wall_bump(delta, moving)

	_noise_radius = 0.0
	if moving:
		_noise_radius = sprint_noise_radius if sprinting else base_noise_radius


## Tactile feedback for "I just walked into something" — a short cooldown
## so it doesn't spam while held against a wall, not just a one-shot.
func _update_wall_bump(delta: float, moving: bool) -> void:
	_wall_bump_cooldown = max(0.0, _wall_bump_cooldown - delta)
	if not moving or _wall_bump_cooldown > 0.0:
		return
	for i in get_slide_collision_count():
		var collider := get_slide_collision(i).get_collider()
		if collider and collider.is_in_group("walls"):
			_wall_bump_cooldown = WALL_BUMP_COOLDOWN
			if wall_bump_audio and wall_bump_audio.stream:
				wall_bump_audio.play()
			break


## Player 1 on a desktop aims at the mouse, same as always. There's no mouse
## to share with a second local player, and a touchscreen's "mouse" is just
## wherever you last touched the joystick, so everyone else (player 2, or
## anyone on touch) faces the direction they're moving instead, holding the
## last facing when stationary. Real analog-stick aim is a natural follow-up
## once there's gamepad hardware to actually test it against.
func _aim(_delta: float) -> void:
	var touch_active := _joystick != null and _joystick.visible
	if player_index == 1 and not touch_active:
		var target := get_global_mouse_position()
		if target.distance_to(global_position) > 1.0:
			rotation = (target - global_position).angle()
		return
	var dir := Input.get_vector(_action("move_left"), _action("move_right"), _action("move_up"), _action("move_down"))
	if dir == Vector2.ZERO and touch_active:
		dir = _joystick.get_vector()
	if dir.length() > 0.2:
		rotation = dir.angle()


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
	if ammo <= 0:
		return
	ammo -= 1
	if player_index == 1:
		Globals.ammo = ammo
	ammo_changed.emit(ammo)
	_bullet_pool().spawn(gun_point.global_position, Vector2.RIGHT.rotated(rotation), 1, team)
	if shoot_audio and shoot_audio.stream:
		shoot_audio.play()
	_fire_muzzle_flash()
	_alert_nearby_idle_enemies()


## A SubViewport (split-screen multiplayer) has its own World2D, separate
## from the root window's — so the global BulletPool autoload's bullets
## (which live in the root window's World2D) can never physically collide
## with anything inside that viewport. A scene can drop a bullet-pool
## instance in the "local_bullet_pool" group inside the same viewport as
## the players to fix that; solo scenes have none, so they keep using the
## global autoload exactly as before.
func _bullet_pool() -> Node:
	var local := get_tree().get_first_node_in_group("local_bullet_pool")
	return local if local else BulletPool


## The unique per-player ability, reusing the exact same timed-effect system
## a pickup would — the only difference is it's triggered by a button and
## gated on its own cooldown instead of needing to walk over an item.
func _use_power() -> void:
	if _power_cooldown_timer > 0.0:
		return
	apply_powerup(power_effect, power_duration, power_strength)
	_power_cooldown_timer = power_cooldown
	power_cooldown_changed.emit(1.0)


func _update_power_cooldown(delta: float) -> void:
	if _power_cooldown_timer <= 0.0:
		return
	_power_cooldown_timer = max(0.0, _power_cooldown_timer - delta)
	power_cooldown_changed.emit(_power_cooldown_timer / power_cooldown)


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
	ammo += amount
	if player_index == 1:
		Globals.ammo = ammo
	ammo_changed.emit(ammo)


func heal(amount: int) -> void:
	hp += amount
	if player_index == 1:
		Globals.player_hp = hp
	hp_changed.emit(hp)
	_update_heartbeat()


func take_damage(amount: int = 1) -> void:
	if _has_effect("invincible"):
		return
	hp -= amount
	if player_index == 1:
		Globals.player_hp = hp
	hp_changed.emit(hp)
	_update_heartbeat()
	if hp <= 0:
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
	var critical := hp == 1
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
