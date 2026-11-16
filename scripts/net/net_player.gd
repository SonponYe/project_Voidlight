extends CharacterBody2D
class_name NetPlayer
## A networked player avatar. Still deliberately light — no Gens, no
## flashlight/darkness yet. Those layer on top once online matches are
## playable end to end.
##
## Authority model (first pass, documented tradeoff):
## - The SERVER simulates every remote player's movement from received
##   input and is the authoritative source of position/rotation/hp,
##   replicated to everyone via the MultiplayerSynchronizer (default
##   authority is always peer 1 = server).
## - The OWNING client ALSO simulates its own movement locally, immediately,
##   so input feels instant ("prediction"). It does not yet reconcile or
##   smooth against the server's correction; the raw snap is visible.
## - Hits are server-authoritative: a client's shoot press only SENDS a
##   request; the server alone raycasts and decides damage. The host's own
##   avatar skips the RPC and calls the server logic directly, since an
##   RPC targeted at yourself isn't delivered in call_remote mode.

signal died(owner_peer_id: int)

const COLORS := [
	Color(0.3, 0.8, 0.5), Color(0.9, 0.4, 0.3), Color(0.35, 0.6, 1.0),
	Color(1.0, 0.8, 0.3), Color(0.8, 0.4, 0.9), Color(0.4, 0.9, 0.9),
]
const AIM_SEND_INTERVAL := 0.05
const TRACER_LIFETIME := 0.12

## Vision rule (see net_arena.gd): enemies inside VISION_RADIUS are seen in
## any direction; out to VIEW_RANGE only inside the forward cone.
const VISION_RADIUS := 180.0
const VIEW_RANGE := 420.0
const VIEW_HALF_ANGLE := deg_to_rad(40.0)
## Firing gives your position away to everyone for this long.
const REVEAL_ON_SHOT := 0.5
const VISION_GUIDE_COLOR := Color(1, 1, 1, 0.08)

@export var speed := 160.0
@export var max_hp := 5
@export var shoot_range := 400.0
@export var fire_cooldown := 0.3

## Set once at spawn time (net_arena.gd) — which peer this avatar belongs
## to. Not multiplayer authority (that's always the server); just "whose
## input do I predict locally and whose shoot requests do I accept."
var owner_peer_id: int = 1

var hp: int
var dead := false
var reveal_timer := 0.0

var _input_dir := Vector2.ZERO
var _aim := 0.0
var _last_sent_aim := 0.0
var _aim_send_timer := 0.0
var _cooldown_left := 0.0
var _joystick: Control = null
var _aim_pad: Control = null

@onready var visual: Polygon2D = $Visual
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var name_label: Label = $NameLabel


func _ready() -> void:
	hp = max_hp
	add_to_group("net_player")
	visual.color = COLORS[absi(owner_peer_id) % COLORS.size()]
	_refresh_name()
	Network.player_list_changed.connect(_refresh_name)
	if _is_mine():
		_joystick = get_tree().get_first_node_in_group("touch_joystick_p1")
		_aim_pad = get_tree().get_first_node_in_group("touch_aim_p1")
		queue_redraw()


## Faint guides for your own vision: the close ring and the forward cone's
## far edge. Drawn in local space, so the cone turns with your aim for free.
func _draw() -> void:
	if not _is_mine():
		return
	draw_arc(Vector2.ZERO, VISION_RADIUS, 0.0, TAU, 48, VISION_GUIDE_COLOR, 1.0)
	draw_arc(Vector2.ZERO, VIEW_RANGE, -VIEW_HALF_ANGLE, VIEW_HALF_ANGLE, 24, VISION_GUIDE_COLOR, 1.0)
	var edge_start := Vector2.RIGHT * VISION_RADIUS
	var edge_end := Vector2.RIGHT * VIEW_RANGE
	draw_line(edge_start.rotated(-VIEW_HALF_ANGLE), edge_end.rotated(-VIEW_HALF_ANGLE), VISION_GUIDE_COLOR, 1.0)
	draw_line(edge_start.rotated(VIEW_HALF_ANGLE), edge_end.rotated(VIEW_HALF_ANGLE), VISION_GUIDE_COLOR, 1.0)


func _exit_tree() -> void:
	if Network.player_list_changed.is_connected(_refresh_name):
		Network.player_list_changed.disconnect(_refresh_name)


## The MultiplayerSynchronizer needs its replication_config set BEFORE this
## node is added to the tree — the engine wires up spawn-replication as
## part of add_child() itself, ahead of this node's own _ready(), so
## building the config in _ready() loses that race and corrupts the peer's
## replication state (ERR_UNCONFIGURED, then a dropped connection).
## net_arena.gd's spawn function calls this right after instantiate().
func configure_replication() -> void:
	var sync := get_node("MultiplayerSynchronizer") as MultiplayerSynchronizer
	var config := SceneReplicationConfig.new()
	for prop in ["position", "rotation", "hp", "dead"]:
		var path := NodePath(".:%s" % prop)
		config.add_property(path)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	sync.replication_config = config


func _is_mine() -> bool:
	return multiplayer.has_multiplayer_peer() and owner_peer_id == multiplayer.get_unique_id()


func _refresh_name() -> void:
	name_label.text = Network.player_name(owner_peer_id)


func _process(delta: float) -> void:
	reveal_timer = maxf(0.0, reveal_timer - delta)
	name_label.rotation = -rotation
	var alpha := 0.25 if dead else 1.0
	visual.modulate.a = alpha
	name_label.modulate.a = alpha
	if dead and not collision.disabled:
		collision.set_deferred("disabled", true)


func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	if dead:
		return
	if _is_mine():
		_local_update(delta)
		return
	# Remote avatars: only the server drives movement from received input;
	# a client rendering ANOTHER player just displays whatever the
	# synchronizer last replicated.
	if multiplayer.is_server():
		velocity = _input_dir * speed
		move_and_slide()
		rotation = _aim


func _local_update(delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if dir == Vector2.ZERO and _joystick and _joystick.visible:
		dir = _joystick.get_vector()
	dir = dir.limit_length(1.0)
	if dir != _input_dir:
		_input_dir = dir
		if not multiplayer.is_server():
			_send_move.rpc_id(1, dir)
	velocity = dir * speed
	move_and_slide()

	if _aim_pad and _aim_pad.visible:
		_aim = _aim_pad.get_vector().angle()
	else:
		_aim = (get_global_mouse_position() - global_position).angle()
	rotation = _aim
	_aim_send_timer -= delta
	if _aim_send_timer <= 0.0 and absf(angle_difference(_last_sent_aim, _aim)) > 0.01:
		_aim_send_timer = AIM_SEND_INTERVAL
		_last_sent_aim = _aim
		if not multiplayer.is_server():
			_send_aim.rpc_id(1, _aim)

	if Input.is_action_just_pressed("shoot") and _cooldown_left <= 0.0:
		_cooldown_left = fire_cooldown
		if multiplayer.is_server():
			_server_shoot(_aim)
		else:
			_request_shoot.rpc_id(1, _aim)


@rpc("any_peer", "call_remote", "reliable")
func _send_move(dir: Vector2) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != owner_peer_id:
		return  # a peer can only drive the avatar it owns
	_input_dir = dir.limit_length(1.0)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _send_aim(aim: float) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != owner_peer_id:
		return
	_aim = aim


@rpc("any_peer", "call_remote", "reliable")
func _request_shoot(aim: float) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != owner_peer_id:
		return
	_server_shoot(aim)


## Server-only. Uses the server's own idea of where this player stands, not
## a client-supplied origin, so a client can't shoot from somewhere it isn't.
func _server_shoot(aim: float) -> void:
	if dead:
		return
	if not _is_mine() and _cooldown_left > 0.0:
		return
	_cooldown_left = fire_cooldown
	_aim = aim
	var from := global_position
	var to := from + Vector2.RIGHT.rotated(aim) * shoot_range
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.exclude = [self]
	var result := get_world_2d().direct_space_state.intersect_ray(query)
	var hit_point := to
	if result:
		hit_point = result.position
		if result.collider is NetPlayer:
			(result.collider as NetPlayer).apply_damage(1)
	_shot_fx.rpc(from, hit_point)


@rpc("authority", "call_local", "unreliable")
func _shot_fx(from: Vector2, to: Vector2) -> void:
	reveal_timer = REVEAL_ON_SHOT
	var tracer := Line2D.new()
	tracer.width = 2.0
	tracer.default_color = Color(1.0, 0.95, 0.6)
	tracer.points = PackedVector2Array([from, to])
	get_parent().add_child(tracer)
	var tween := tracer.create_tween()
	tween.tween_property(tracer, "modulate:a", 0.0, TRACER_LIFETIME)
	tween.tween_callback(tracer.queue_free)


## Server-only, direct call (not an RPC) — the server already holds the
## authoritative NetPlayer instance, so it just mutates it; the
## MultiplayerSynchronizer's own replication (hp/dead, ALWAYS mode above)
## is what actually informs every client, no separate RPC needed.
func apply_damage(amount: int) -> void:
	if not multiplayer.is_server():
		return
	if dead:
		return
	hp -= amount
	if hp <= 0:
		hp = 0
		dead = true
		died.emit(owner_peer_id)
