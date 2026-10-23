extends Node
## Saves screenshots of the main menu and lobby UI (needs a renderer, e.g. xvfb).

var f := 0
var menu: Node


func _ready() -> void:
	menu = load("res://scenes/main_menu.tscn").instantiate()
	add_child(menu)
	DirAccess.make_dir_recursive_absolute("user://screens")


func _process(_d: float) -> void:
	f += 1
	if f == 40:
		get_viewport().get_texture().get_image().save_png("user://screens/menu.png")
		menu.queue_free()
		get_node("/root/Net").host(24990, "")
		menu = load("res://scenes/lobby.tscn").instantiate()
		add_child(menu)
	if f == 80:
		get_viewport().get_texture().get_image().save_png("user://screens/lobby.png")
		get_tree().quit()
