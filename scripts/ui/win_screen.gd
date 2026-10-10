extends Control
## Win screen: shown when the player clears the final level. Placeholder layout/art.

@export_file("*.tscn") var first_level_path := "res://scenes/levels/level_1.tscn"

@onready var score_label: Label = $VBox/ScoreLabel


func _ready() -> void:
	Globals.register_score(Globals.total_kills * 10)
	score_label.text = "Total Kills: %d" % Globals.total_kills


func _on_play_again_pressed() -> void:
	Globals.reset_run()
	get_tree().change_scene_to_file(first_level_path)


func _on_main_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
