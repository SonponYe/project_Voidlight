extends Control
## On-screen virtual joystick for touch movement. Only active/visible on
## touchscreens. Drag anywhere within `radius` of the base's center to set a
## direction; release snaps back to center. player.gd reads get_vector()
## each frame as a fallback whenever keyboard/gamepad give zero input.
##
## Join the "touch_joystick_p1" or "touch_joystick_p2" group (set via
## joystick_group in the Inspector) so the matching player can find it —
## two joysticks, one per player, for local multiplayer on one touchscreen.

@export var joystick_group: String = "touch_joystick_p1"
@export var radius := 60.0

@onready var base: Control = $Base
@onready var knob: Control = $Base/Knob

var _touch_index := -1
var _vector := Vector2.ZERO


func _ready() -> void:
	add_to_group(joystick_group)
	visible = DisplayServer.is_touchscreen_available()
	_reset_knob()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_update_knob(event.position)


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if _touch_index == -1 and _is_within_base(event.position):
			_touch_index = event.index
			_update_knob(event.position)
	elif event.index == _touch_index:
		_touch_index = -1
		_vector = Vector2.ZERO
		_reset_knob()


func _is_within_base(screen_pos: Vector2) -> bool:
	return base.get_global_rect().get_center().distance_to(screen_pos) <= radius * 1.6


func _update_knob(screen_pos: Vector2) -> void:
	var center := base.get_global_rect().get_center()
	var offset := (screen_pos - center).limit_length(radius)
	knob.position = base.size / 2.0 - knob.size / 2.0 + offset
	_vector = offset / radius


func _reset_knob() -> void:
	knob.position = base.size / 2.0 - knob.size / 2.0


func get_vector() -> Vector2:
	return _vector
