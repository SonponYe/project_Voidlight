extends Control
## Main menu: start a fresh run or quit. Placeholder layout/art.

@export_file("*.tscn") var first_level_path := "res://scenes/levels/level_1.tscn"

@onready var high_score_label: Label = $VBox/HighScoreLabel


func _ready() -> void:
	high_score_label.text = "High Score: %d" % Globals.high_score


func _on_start_pressed() -> void:
	Globals.reset_run()
	get_tree().change_scene_to_file(first_level_path)


func _on_quit_pressed() -> void:
	get_tree().quit()
