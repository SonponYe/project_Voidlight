extends Control
## Touch-drag aim pad: drag anywhere within this control to set an aim
## direction. Unlike virtual_joystick.gd, releasing does NOT reset the
## vector to zero — aim holds at its last direction, since "no aim
## direction" doesn't make sense once the player has one (a flashlight/
## gun always points somewhere). Each new touch-down starts a fresh
## relative drag from wherever the finger lands, so the pad can cover a
## big chunk of screen without needing a fixed-position base graphic.
##
## Join "touch_aim_p1" or "touch_aim_p2" (set via aim_group) so the
## matching player can find it, mirroring virtual_joystick.gd's pattern.

@export var aim_group: String = "touch_aim_p1"
@export var deadzone_px := 6.0

@onready var reticle: Control = get_node_or_null("Reticle")

var _touch_index := -1
var _origin := Vector2.ZERO
var _vector := Vector2.RIGHT  # holds last non-zero aim direction


func _ready() -> void:
	add_to_group(aim_group)
	visible = DisplayServer.is_touchscreen_available()
	if reticle:
		reticle.visible = false


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_update_vector(event.position)


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if _touch_index == -1 and get_global_rect().has_point(event.position):
			_touch_index = event.index
			_origin = event.position
			if reticle:
				reticle.visible = true
				reticle.global_position = _origin - reticle.size / 2.0
	elif event.index == _touch_index:
		_touch_index = -1
		if reticle:
			reticle.visible = false


func _update_vector(screen_pos: Vector2) -> void:
	var offset := screen_pos - _origin
	if offset.length() > deadzone_px:
		_vector = offset.normalized()
	if reticle:
		reticle.global_position = screen_pos - reticle.size / 2.0


func get_vector() -> Vector2:
	return _vector
