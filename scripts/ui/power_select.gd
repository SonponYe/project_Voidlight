extends Control
## Mode + power selection lobby — the *basic logic* for picking a match
## mode and a superpower per player before a match starts. Plain buttons
## for now; the polished "press something, a ring of options pops out"
## look is a separate visual pass on top of this same selection logic.
##
## Selections are written to Globals (match_mode, selected_power_p1/p2)
## and read by versus_manager.gd when the arena loads.

@export_file("*.tscn") var versus_arena_path := "res://scenes/levels/arena_versus.tscn"

@onready var ffa_button: Button = $VBox/ModeRow/FFAButton
@onready var team_button: Button = $VBox/ModeRow/TeamButton
@onready var p1_power_list: VBoxContainer = $VBox/Columns/P1Column/PowerList
@onready var p2_power_list: VBoxContainer = $VBox/Columns/P2Column/PowerList

const SELECTED_TINT := Color(1.3, 1.2, 0.7)
const UNSELECTED_TINT := Color(1, 1, 1)

var _p1_power: String = Globals.DEFAULT_POWER_P1
var _p2_power: String = Globals.DEFAULT_POWER_P2
var _p1_buttons: Dictionary = {}  # power key -> Button
var _p2_buttons: Dictionary = {}


func _ready() -> void:
	_build_power_buttons(p1_power_list, _p1_buttons, 1)
	_build_power_buttons(p2_power_list, _p2_buttons, 2)
	_refresh_selection(_p1_buttons, _p1_power)
	_refresh_selection(_p2_buttons, _p2_power)
	_set_mode(Globals.match_mode)


## Built from Globals.POWER_DEFS rather than hand-placed in the scene, so
## naming the 6th power later is a one-line table edit, not a scene edit.
func _build_power_buttons(list: VBoxContainer, registry: Dictionary, player_index: int) -> void:
	for key in Globals.POWER_DEFS.keys():
		var def: Dictionary = Globals.POWER_DEFS[key]
		var button := Button.new()
		button.text = String(def["label"])
		button.pressed.connect(_select_power.bind(player_index, key))
		list.add_child(button)
		registry[key] = button

	var coming_soon := Button.new()
	coming_soon.text = "? Coming Soon"
	coming_soon.disabled = true
	list.add_child(coming_soon)


func _select_power(player_index: int, key: String) -> void:
	if player_index == 1:
		_p1_power = key
		_refresh_selection(_p1_buttons, key)
	else:
		_p2_power = key
		_refresh_selection(_p2_buttons, key)


func _refresh_selection(registry: Dictionary, selected_key: String) -> void:
	for key in registry.keys():
		var button: Button = registry[key]
		button.modulate = SELECTED_TINT if key == selected_key else UNSELECTED_TINT


func _set_mode(mode: String) -> void:
	Globals.match_mode = mode
	ffa_button.modulate = SELECTED_TINT if mode == "ffa" else UNSELECTED_TINT
	team_button.modulate = SELECTED_TINT if mode == "team" else UNSELECTED_TINT


func _on_ffa_pressed() -> void:
	_set_mode("ffa")


func _on_team_pressed() -> void:
	_set_mode("team")


func _on_start_pressed() -> void:
	Globals.selected_power_p1 = _p1_power
	Globals.selected_power_p2 = _p2_power
	get_tree().change_scene_to_file(versus_arena_path)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
