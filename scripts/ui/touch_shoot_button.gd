extends Control
## On-screen fire button — only shown on touchscreens. Handles touch input
## manually via _input + Input.action_press/release (same pattern as
## virtual_joystick.gd/touch_aim_pad.gd) rather than the engine's
## TouchScreenButton, which is Node2D-based and can't use the anchor-based
## responsive layout the rest of the HUD relies on.

@export var action_name: String = "shoot"

@onready var panel: Panel = $Panel

var _touch_index := -1


func _ready() -> void:
	visible = DisplayServer.is_touchscreen_available()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		_handle_touch(event)


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if _touch_index == -1 and panel.get_global_rect().has_point(event.position):
			_touch_index = event.index
			Input.action_press(action_name)
			if panel:
				panel.modulate.a = 1.5
	elif event.index == _touch_index:
		_touch_index = -1
		Input.action_release(action_name)
		if panel:
			panel.modulate.a = 1.0
