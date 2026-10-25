extends CharacterBody2D
class_name Enemy
## Base enemy: Finite State Machine (IDLE / AWARE / HUNT / DEAD), maze-aware
## pathfinding via NavigationAgent2D, positional audio hooks, and death
## handling. Walker / Crawler / Lurker extend this and only override what
## differs.
##
## AWARE/HUNT route through the baked navigation mesh (level_manager bakes
## it from everything in the "walls" group) so a monster on the other side
## of a maze wall actually walks around to reach you instead of pushing
## uselessly against it. IDLE wander stays simple straight-line drift —
## it's ambient, not goal-directed, so it doesn't need a path.

signal killed(enemy: Enemy)

enum State { IDLE, AWARE, HUNT, DEAD }

@export var move_speed := 60.0
@export var hunt_speed := 120.0
@export var sound_radius := 160.0
@export var flashlight_range := 260.0
@export var flashlight_half_angle_deg := 35.0
@export var dark_bump_radius := 40.0
@export var light_on_sense_radius := 150.0
@export var hunt_memory_duration := 2.5
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
var _lost_contact_timer := 0.0

@onready var sprite: Polygon2D = $Sprite
@onready var hit_area: Area2D = $HitArea
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var footstep_audio: AudioStreamPlayer2D = $FootstepAudio
@onready var growl_audio: AudioStreamPlayer2D = $GrowlAudio
@onready var stinger_audio: AudioStreamPlayer2D = $StingerAudio


func _ready() -> void:
	add_to_group("enemies")
	_player = get_tree().get_first_node_in_group("player")
	_pick_new_wander_direction()


func _physics_process(delta: float) -> void:
	if state == State.DEAD or _player == null:
		return

	_update_detection(delta)
	_contact_timer = max(0.0, _contact_timer - delta)

	match state:
		State.IDLE:
			_process_idle(delta)
		State.AWARE:
			_process_aware(delta)
		State.HUNT:
			_process_hunt(delta)

	move_and_slide()
	_update_footsteps()
	_update_contact_damage()


## AudioStreamPlayer2D attenuates by distance automatically, so once a
## footstep sound is assigned this alone delivers "volume increases as the
## monster approaches" — no extra logic needed for that part.
func _update_footsteps() -> void:
	if footstep_audio == null or footstep_audio.stream == null:
		return
	var moving := velocity.length() > 1.0
	if moving and not footstep_audio.playing:
		footstep_audio.play()
	elif not moving and footstep_audio.playing:
		footstep_audio.stop()


# --- Detection ---------------------------------------------------------------
#
# Light ON:  the player is lit up and visible — close range omnidirectional
#            sense, plus the long forward cone (_player_sees_me) — but ONLY
#            if there's an unobstructed line of sight. A wall between you and
#            an enemy fully hides you from both of these; a straight-line
#            distance check with no raycast was the old bug that made
#            enemies "sense" the player through walls and hunt permanently.
# Light OFF: no visual tells at all except literally bumping into the player
#            (dark_bump_radius). Sound (movement noise, gunshots) is the only
#            other way to be noticed — makes going dark genuinely stealthier,
#            at the cost of the player losing the maze layout/minimap too.
#
# HUNT also isn't permanent: losing sight/proximity for hunt_memory_duration
# seconds drops it back to AWARE (still walks to the last place it saw you,
# then gives up to IDLE) instead of chasing forever on a single stale cue.

func _update_detection(delta: float) -> void:
	var dist := global_position.distance_to(_player.global_position)
	var light_on: bool = _player.is_light_on() if _player.has_method("is_light_on") else true

	var spotted := dist <= dark_bump_radius
	if light_on and not spotted:
		if (dist <= light_on_sense_radius or _player_sees_me(dist)) and _has_line_of_sight(_player.global_position):
			spotted = true

	if spotted:
		last_known_player_pos = _player.global_position
		_lost_contact_timer = 0.0
		_set_state(State.HUNT)
		return

	if state == State.HUNT:
		_lost_contact_timer += delta
		if _lost_contact_timer >= hunt_memory_duration:
			_set_state(State.AWARE)
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


## Raycasts against the "world" physics layer only (walls), so enemies and
## the player don't block each other's own sightline.
func _has_line_of_sight(target_pos: Vector2) -> bool:
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, target_pos, 1)
	query.exclude = [self]
	return space_state.intersect_ray(query).is_empty()


# --- State behaviours (override in subclasses as needed) --------------------

func _process_idle(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_pick_new_wander_direction()
	velocity = _wander_dir * move_speed * 0.4


func _process_aware(_delta: float) -> void:
	if global_position.distance_to(last_known_player_pos) < 8.0:
		_set_state(State.IDLE)
		velocity = Vector2.ZERO
		return
	velocity = _nav_velocity_toward(last_known_player_pos, move_speed)


func _process_hunt(_delta: float) -> void:
	# Chases last_known_player_pos, not the player's live position — while
	# actively spotted that's refreshed every frame in _update_detection, so
	# it tracks in real time either way. The moment contact is lost it
	# freezes on the last real cue instead of omnisciently following the
	# player through walls, which is what let hunt_memory_duration matter.
	velocity = _nav_velocity_toward(last_known_player_pos, hunt_speed)
	if growl_audio and growl_audio.stream and not growl_audio.playing:
		growl_audio.play()


## Routes through the baked navmesh instead of a straight line, so a wall
## between here and target_pos gets walked around rather than pushed on.
func _nav_velocity_toward(target_pos: Vector2, speed: float) -> Vector2:
	nav_agent.target_position = target_pos
	if nav_agent.is_navigation_finished():
		return Vector2.ZERO
	var next_point := nav_agent.get_next_path_position()
	return (next_point - global_position).normalized() * speed


func _pick_new_wander_direction() -> void:
	_wander_timer = wander_interval
	_wander_dir = Vector2.RIGHT.rotated(randf() * TAU)


# --- Transitions ----------------------------------------------------------

func _set_state(new_state: State) -> void:
	if state == State.DEAD or state == new_state:
		return
	var was_hunting := state == State.HUNT
	state = new_state
	# last_known_player_pos is set by whichever caller triggered this
	# transition (sound cue, gunshot, or the live position while still
	# HUNTing) — not overwritten here, so a HUNT->AWARE downgrade from lost
	# contact keeps the real last-seen spot instead of snapping to the
	# player's current (to this enemy, unknown) position.
	if new_state == State.HUNT and not was_hunting:
		# Jump-scare beat: the one-shot sting of the moment it locks on,
		# separate from the looping growl that follows while it's chasing.
		if stinger_audio and stinger_audio.stream:
			stinger_audio.play()
	elif was_hunting and growl_audio and growl_audio.playing:
		growl_audio.stop()


## Polls overlap instead of relying on the one-shot body_entered signal, so
## damage still re-applies after the cooldown even if the player and enemy
## remain pressed together rather than re-entering the area each time.
func _update_contact_damage() -> void:
	if state == State.DEAD or _contact_timer > 0.0:
		return
	for body in hit_area.get_overlapping_bodies():
		if body.is_in_group("player") and body.has_method("take_damage"):
			body.take_damage(contact_damage)
			_contact_timer = contact_cooldown
			break


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
