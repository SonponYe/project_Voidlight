extends Control
## Main menu: pick a mode or quit. Placeholder layout/art.

@export_file("*.tscn") var first_level_path := "res://scenes/levels/level_1.tscn"
@export_file("*.tscn") var versus_arena_path := "res://scenes/levels/arena_versus.tscn"

@onready var high_score_label: Label = $VBox/HighScoreLabel
@onready var music: AudioStreamPlayer = $Music


func _ready() -> void:
	high_score_label.text = "High Score: %d" % Globals.high_score
	if music.stream:
		music.play()


func _on_solo_pressed() -> void:
	Globals.reset_run()
	get_tree().change_scene_to_file(first_level_path)


func _on_versus_pressed() -> void:
	get_tree().change_scene_to_file(versus_arena_path)


func _on_quit_pressed() -> void:
	get_tree().quit()
