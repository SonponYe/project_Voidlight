class_name WalkCycle
extends RefCounted
## Procedural movement for the top-down character sprites, which are a single
## still frame. The feel is a trained soldier, not a cartoon: the torso and the
## gun stay steady and the LEGS do the work — two boots striding along the
## direction of travel with a quick, even cadence — plus a slight forward lean
## while running and a faint tremor of the shoulders. Standing still, almost
## nothing (a very slow breath). Firing, a small controlled kick.
##
## Driven purely by how far the character actually moved, so it plays the same
## for the local player, for remote players (whose positions are smoothed) and
## for the Decoy — which therefore can't be told from a player by how it moves.

const STRIDE := 25.0  # distance covered by one full left-right step cycle (shorter = quicker cadence)
const MIN_SPEED := 14.0
const MAX_SPEED := 260.0  # ignores the huge "speed" of a teleport/snap
const FOOT_REACH := 15.0  # how far each boot swings fore and aft
const FOOT_SIDE := 4.8  # how far each boot sits to the side of the body's centre line
const BOOT_LENGTH := 4.6  # half the length of a boot, along the direction of travel
const BOOT_WIDTH := 2.7  # half its width
const BOOT := Color(0.09, 0.08, 0.07)
const BOOT_SHINE := Color(0.30, 0.28, 0.25)
const LEAN := 1.8  # pixels the torso pushes forward while running
const SHOULDER_TREMOR := 0.03  # radians (under 2 degrees) of shoulder turn per step
const STEP_BOB := 0.012  # a barely-there rise on each footfall
const RECOIL_TIME := 0.09
const FOOTFALL_DISTANCE := 54.0  # pixels between audible footsteps (about 3 a second at full speed)

## Where in the step cycle we are (radians) and how "running" we are (0..1,
## eased so starting and stopping blend instead of snapping).
var phase := 0.0
var moving := 0.0

var _recoil := 0.0
var _time := 0.0
var _since_step := 0.0
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
		_dir = local if _dir == Vector2.ZERO else _dir.lerp(local, clampf(delta * 14.0, 0.0, 1.0)).normalized()
		phase += speed * delta / STRIDE * TAU
		_since_step += speed * delta
	else:
		_since_step = FOOTFALL_DISTANCE * 0.5  # the first step after stopping comes a half-stride in
	moving = move_toward(moving, 1.0 if walking else 0.0, delta * 12.0)  # quick on, quick off
	_recoil = maxf(0.0, _recoil - delta)


## True once each time the character has covered another footstep's worth of
## ground (call it every frame after tick()). Separate from the drawn stride,
## which is much shorter — the legs swing fast, but boots only land ~3 times a second.
func footfall() -> bool:
	if _since_step < FOOTFALL_DISTANCE:
		return false
	_since_step -= FOOTFALL_DISTANCE
	return true


## A shot was fired: the body is pushed back a touch, then recovers.
func kick() -> void:
	_recoil = RECOIL_TIME


## Holds the character steady with a slight lean; no squashing or swaying.
## `base` is its resting scale.
func apply(body: Sprite2D, base: float) -> void:
	var s := sin(phase) * moving
	var breath := sin(_time * 1.4) * 0.006 * (1.0 - moving)
	var rise := 1.0 + STEP_BOB * absf(s) + breath
	body.scale = Vector2.ONE * base * rise  # uniform: a soldier doesn't squash
	body.rotation = s * SHOULDER_TREMOR
	var kick_amount := _recoil / RECOIL_TIME
	body.position = Vector2(LEAN * moving - kick_amount * 3.0, s * 0.5)


## Two boots striding along the direction of travel (the character's own
## forward when standing). Drawn on the character's canvas item, under the sprite.
func draw_feet(canvas: CanvasItem) -> void:
	var forward := Vector2.RIGHT.lerp(_dir, moving)
	forward = forward.normalized() if forward != Vector2.ZERO else Vector2.RIGHT
	var side := forward.orthogonal()
	var swing := sin(phase) * moving
	for foot in 2:
		var sign := 1.0 if foot == 0 else -1.0
		var at := forward * (sign * swing * FOOT_REACH) + side * (sign * FOOT_SIDE)
		# The striding foot is the one passing under the body: slightly lifted (a touch larger and lighter).
		var passing := maxf(0.0, 1.0 - absf(swing)) * moving
		var half_length := BOOT_LENGTH * (1.0 + 0.12 * passing)
		var half_width := BOOT_WIDTH * (1.0 + 0.12 * passing)
		var polygon := PackedVector2Array([
			at + forward * half_length + side * half_width * 0.6,
			at + forward * half_length * 0.55 + side * half_width,
			at - forward * half_length + side * half_width,
			at - forward * half_length - side * half_width,
			at + forward * half_length * 0.55 - side * half_width,
			at + forward * half_length - side * half_width * 0.6,
		])
		canvas.draw_colored_polygon(polygon, BOOT)
		canvas.draw_line(at + forward * half_length * 0.6, at - forward * half_length * 0.2, BOOT_SHINE, 1.2)
