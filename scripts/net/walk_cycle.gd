class_name WalkCycle
extends RefCounted
## Procedural walk animation for the top-down character sprites, which are a
## single still frame. In the spirit of Hunter Assassin's small, bouncy figures
## seen from above: while moving, the shoulders sway, the body bobs and
## squashes with each step, and two boots step along the direction of travel;
## standing still, a faint breath; firing, a small gun kick.
##
## Driven purely by how far the character actually moved, so it plays the same
## for the local player, for remote players (whose positions are smoothed) and
## for the Decoy — which therefore can't be told from a player by how it moves.

const STRIDE := 30.0  # distance covered by one full left-right step cycle
const MIN_SPEED := 14.0
const MAX_SPEED := 260.0  # ignores the huge "speed" of a teleport/snap
const FOOT_REACH := 8.0
const FOOT_SIDE := 5.5
const BOOT := Color(0.10, 0.09, 0.08)
const BOOT_SHINE := Color(0.32, 0.30, 0.27)
const RECOIL_TIME := 0.09

## Where in the step cycle we are (radians) and how "walking" we are (0..1,
## eased so starting and stopping blend instead of snapping).
var phase := 0.0
var moving := 0.0

var _recoil := 0.0
var _time := 0.0
var _last := Vector2.INF
var _dir := Vector2.ZERO  # direction of travel, in the character's own frame


func tick(delta: float, pos: Vector2, rot: float) -> void:
	_time += delta
	var step := Vector2.ZERO
	if _last != Vector2.INF:
		step = pos - _last
	_last = pos
	var speed := minf(step.length() / maxf(delta, 0.0001), MAX_SPEED)
	var walking := speed > MIN_SPEED
	if walking:
		var local := step.rotated(-rot).normalized()
		_dir = local if _dir == Vector2.ZERO else _dir.lerp(local, clampf(delta * 12.0, 0.0, 1.0)).normalized()
		phase += speed * delta / STRIDE * TAU
	moving = move_toward(moving, 1.0 if walking else 0.0, delta * 9.0)
	_recoil = maxf(0.0, _recoil - delta)


## A shot was fired: the body jerks back a touch.
func kick() -> void:
	_recoil = RECOIL_TIME


## Sways, bobs and squashes the character sprite. `base` is its resting scale.
func apply(body: Sprite2D, base: float) -> void:
	var s := sin(phase) * moving
	var step := absf(s)
	var breath := sin(_time * 2.2) * 0.012 * (1.0 - moving)
	body.scale = Vector2(base * (1.0 + 0.06 * step + breath), base * (1.0 - 0.045 * step + breath))
	body.rotation = s * 0.11
	var kick_amount := _recoil / RECOIL_TIME
	body.position = Vector2(-kick_amount * 3.5 + step * 1.0, s * 1.4)


## Two boots stepping along the direction of travel (the character's own
## forward when standing). Drawn on the character's canvas item, under the sprite.
func draw_feet(canvas: CanvasItem) -> void:
	var forward := Vector2.RIGHT.lerp(_dir, moving)
	forward = forward.normalized() if forward != Vector2.ZERO else Vector2.RIGHT
	var side := forward.orthogonal()
	var swing := sin(phase) * moving
	for foot in 2:
		var sign := 1.0 if foot == 0 else -1.0
		var at := forward * (sign * swing * FOOT_REACH) + side * (sign * FOOT_SIDE)
		var lifted := maxf(0.0, cos(phase) * sign) * moving  # the stepping foot rises a little
		canvas.draw_circle(at, 3.6 + 0.9 * lifted, BOOT)
		canvas.draw_circle(at + Vector2(-0.8, -0.8), 1.4, BOOT_SHINE)
