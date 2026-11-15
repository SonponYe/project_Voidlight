extends Enemy
class_name Decoy
## The "Decoy" superpower's clone: relentlessly hunts one specific opposing
## player — not the nearest one, a chosen one — set via set_target() right
## after spawning. Completely overrides Enemy's normal sight/sound
## detection with "always HUNT this exact target, no give-up timer." Dies
## in one hit like a Walker (max_hits default of 1, inherited unchanged),
## or expires on its own after lifespan seconds if nobody kills it first.

@export var lifespan := 10.0

var _life_timer := 0.0


## Called by player.gd immediately after instantiating this scene.
func set_target(target: Node2D) -> void:
	_player = target
	last_known_player_pos = target.global_position
	state = State.HUNT


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_life_timer += delta
	if _life_timer >= lifespan:
		_die()
		return
	super._physics_process(delta)


## Always hunting the one assigned target — no sight/sound gating, no
## hunt_memory_duration give-up. A decoy doesn't lose interest.
func _update_detection(_delta: float) -> void:
	if _player and is_instance_valid(_player):
		last_known_player_pos = _player.global_position
	state = State.HUNT
