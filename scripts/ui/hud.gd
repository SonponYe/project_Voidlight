extends CanvasLayer
## HUD: connects player/level signals and updates all on-screen UI.
## Pause menu toggling lives here since it's purely input + tree.paused logic.

@onready var kill_counter: Label = $KillCounter
@onready var ammo_display: Label = $AmmoDisplay
@onready var hp_bar: ProgressBar = $HPBar
@onready var pause_menu: Control = $PauseMenu
@onready var minimap: Control = $Minimap

var _total_monsters := 0


func _ready() -> void:
	hp_bar.max_value = Globals.STARTING_HP
	refresh()
	pause_menu.hide()


func set_total_monsters(total: int) -> void:
	_total_monsters = total
	_refresh_kill_counter(0)


func refresh() -> void:
	_refresh_kill_counter(0)
	ammo_display.text = "Ammo: %d" % Globals.ammo
	hp_bar.value = Globals.player_hp


func on_hp_changed(hp: int) -> void:
	hp_bar.value = hp


func on_ammo_changed(ammo: int) -> void:
	ammo_display.text = "Ammo: %d" % ammo


func on_kill_registered(kills: int) -> void:
	_refresh_kill_counter(kills)


func _refresh_kill_counter(kills: int) -> void:
	kill_counter.text = "Kills: %d / %d" % [kills, _total_monsters]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		toggle_pause()


func toggle_pause() -> void:
	var paused := not get_tree().paused
	get_tree().paused = paused
	pause_menu.visible = paused


func _on_resume_pressed() -> void:
	toggle_pause()


func _on_quit_to_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
