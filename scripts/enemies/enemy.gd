extends CharacterBody2D
class_name Enemy
## Base enemy: Finite State Machine (IDLE / AWARE / HUNT / DEAD), direct-chase
## movement, positional audio hooks, and death handling.
## Walker / Crawler / Lurker extend this and only override what differs.
##
## Pathfinding note: this MVP steers straight toward its target and relies on
## CharacterBody2D's wall-sliding to avoid clipping through walls. Swap in a
## NavigationAgent2D + baked NavigationRegion2D later for smarter routing
## around obstacles — the FSM/signals here don't need to change for that.

signal killed(enemy: Enemy)

enum State { IDLE, AWARE, HUNT, DEAD }

@export var move_speed := 60.0
@export var hunt_speed := 120.0
@export var sound_radius := 160.0
@export var flashlight_range := 260.0
@export var flashlight_half_angle_deg := 35.0
@export var proximity_hunt_radius := 48.0
@export var max_hits := 1
@export var contact_damage := 1
@export var contact_cooldown := 1.0
@export var wander_interval := 2.5

var state: State = State.IDLE
var last_known_player_pos := Vector2.ZERO

var _hits_taken := 0
var _player: Node2D = null
var _wander_dir := Vector2.ZERO
var _wander_timer := 0.0
var _contact_timer := 0.0

@onready var sprite: Polygon2D = $Sprite
@onready var hit_area: Area2D = $HitArea
@onready var footstep_audio: AudioStreamPlayer2D = $FootstepAudio
@onready var growl_audio: AudioStreamPlayer2D = $GrowlAudio


func _ready() -> void:
	add_to_group("enemies")
	_player = get_tree().get_first_node_in_group("player")
	hit_area.body_entered.connect(_on_hit_area_body_entered)
	_pick_new_wander_direction()


func _physics_process(delta: float) -> void:
	if state == State.DEAD or _player == null:
		return

	_update_detection()
	_contact_timer = max(0.0, _contact_timer - delta)

	match state:
		State.IDLE:
			_process_idle(delta)
		State.AWARE:
			_process_aware(delta)
		State.HUNT:
			_process_hunt(delta)

	move_and_slide()


# --- Detection ---------------------------------------------------------------

func _update_detection() -> void:
	var dist := global_position.distance_to(_player.global_position)

	if dist <= proximity_hunt_radius or _player_sees_me(dist):
		_set_state(State.HUNT)
		return

	var noise_radius: float = 0.0
	if _player.has_method("get_noise_radius"):
		noise_radius = _player.get_noise_radius()
	if noise_radius > 0.0 and dist <= sound_radius + noise_radius and state == State.IDLE:
		last_known_player_pos = _player.global_position
		_set_state(State.AWARE)


## Called by the player on every shot; wakes this enemy if it's still IDLE.
func hear_gunshot(source_pos: Vector2) -> void:
	if state == State.IDLE:
		last_known_player_pos = source_pos
		_set_state(State.AWARE)


func _player_sees_me(dist: float) -> bool:
	if dist > flashlight_range:
		return false
	var to_enemy := (global_position - _player.global_position).normalized()
	var facing := Vector2.RIGHT.rotated(_player.rotation)
	var angle := rad_to_deg(abs(facing.angle_to(to_enemy)))
	return angle <= flashlight_half_angle_deg


# --- State behaviours (override in subclasses as needed) --------------------

func _process_idle(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_pick_new_wander_direction()
	velocity = _wander_dir * move_speed * 0.4


func _process_aware(_delta: float) -> void:
	var to_target := last_known_player_pos - global_position
	if to_target.length() < 8.0:
		_set_state(State.IDLE)
		velocity = Vector2.ZERO
		return
	velocity = to_target.normalized() * move_speed


func _process_hunt(_delta: float) -> void:
	velocity = (_player.global_position - global_position).normalized() * hunt_speed
	if growl_audio and growl_audio.stream and not growl_audio.playing:
		growl_audio.play()


func _pick_new_wander_direction() -> void:
	_wander_timer = wander_interval
	_wander_dir = Vector2.RIGHT.rotated(randf() * TAU)


# --- Transitions ----------------------------------------------------------

func _set_state(new_state: State) -> void:
	if state == State.DEAD or state == new_state:
		return
	state = new_state
	if state == State.AWARE:
		last_known_player_pos = _player.global_position


func _on_hit_area_body_entered(body: Node) -> void:
	if state == State.DEAD or _contact_timer > 0.0:
		return
	if body.is_in_group("player") and body.has_method("take_damage"):
		body.take_damage(contact_damage)
		_contact_timer = contact_cooldown


func hit(damage: int = 1) -> void:
	if state == State.DEAD:
		return
	_hits_taken += damage
	if _hits_taken >= max_hits:
		_die()
	else:
		_set_state(State.HUNT)


func _die() -> void:
	state = State.DEAD
	velocity = Vector2.ZERO
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	hit_area.set_deferred("monitoring", false)
	if sprite:
		sprite.color = Color(0.2, 0.2, 0.2, 0.6)
	killed.emit(self)
	await get_tree().create_timer(0.15).timeout
	queue_free()
