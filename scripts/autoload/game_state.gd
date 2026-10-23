extends Node
## Global game state: local profile, match configuration and the roster of gorillas.

const MODE_CLASSIC := 0
const MODE_INFECTION := 1
const MODE_HIDE_SEEK := 2
const MODE_NAMES := ["Classic Tag", "Infection", "Jungle Hide and Seek"]
const PLAYER_COUNTS := [2, 4, 6, 8, 10, 12, 16]
const ROUND_TIMES := [60, 120, 180, 300, 480, 600]
const BOT_ID_BASE := 100000

const COLORS := [
	Color("6b4a35"), Color("3b3b3f"), Color("c9772b"), Color("e3d2b3"),
	Color("8a2f2f"), Color("2f5f8a"), Color("6a3d8a"), Color("2e7d4f"),
	Color("d4b02a"), Color("e06aa0"), Color("4fb3c9"), Color("f2f2f2"),
]
const BOT_NAMES := [
	"Bonobo Bob", "Kong Kim", "Mango", "Banjo", "Coco", "Kiwi", "Tamarind", "Bongo",
	"Papaya", "Twiggy", "Mossy", "Rumble", "Loopy", "Ziggy", "Vinny", "Fig", "Nutmeg", "Pebble",
]

const PROFILE_PATH := "user://profile.cfg"

var profile_name: String = "Gorilla"
var profile_color: Color = COLORS[0]

## Current match configuration, set by the host and synced to every client.
var config := {
	"mode": MODE_CLASSIC,
	"round_time": 180,
	"max_players": 8,
	"bot_count": 5,
	"fill_bots": true,
	"seed": 1337,
	"room_name": "Jungle Room",
}

## id -> {"name": String, "color": Color, "bot": bool}
var roster := {}

## Message shown on the main menu after returning (e.g. "Host disconnected").
var menu_message := ""

var in_match := false


func _ready() -> void:
	_load_profile()
	if profile_name == "Gorilla":
		profile_name = "Gorilla%d" % (randi() % 900 + 100)


func _load_profile() -> void:
	var cf := ConfigFile.new()
	if cf.load(PROFILE_PATH) == OK:
		profile_name = cf.get_value("profile", "name", profile_name)
		profile_color = cf.get_value("profile", "color", profile_color)


func save_profile() -> void:
	var cf := ConfigFile.new()
	cf.set_value("profile", "name", profile_name)
	cf.set_value("profile", "color", profile_color)
	cf.save(PROFILE_PATH)


func sanitize_name(n: String) -> String:
	n = n.strip_edges().replace("\n", "").replace("[", "(").replace("]", ")")
	if n.is_empty():
		n = "Gorilla"
	return n.substr(0, 16)


func mode_name(mode: int = -1) -> String:
	if mode < 0:
		mode = config.mode
	return MODE_NAMES[clampi(mode, 0, MODE_NAMES.size() - 1)]


## Builds the final roster for a match: every connected human plus bots for empty slots.
func build_match_roster(humans: Dictionary) -> Dictionary:
	var r := {}
	for id in humans:
		r[id] = {"name": humans[id].name, "color": humans[id].color, "bot": false}
	var slots: int = maxi(0, int(config.max_players) - humans.size())
	var bots: int = slots if config.fill_bots else mini(int(config.bot_count), slots)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(config.seed)
	var names := BOT_NAMES.duplicate()
	for i in bots:
		var idx := rng.randi_range(0, names.size() - 1)
		var bname: String = names[idx]
		names.remove_at(idx)
		if names.is_empty():
			names = BOT_NAMES.duplicate()
		r[BOT_ID_BASE + i] = {"name": "%s [AI]" % bname, "color": COLORS[rng.randi_range(0, COLORS.size() - 1)], "bot": true}
	return r


func is_bot_id(id: int) -> bool:
	return id >= BOT_ID_BASE


func go_to_menu(message: String = "") -> void:
	menu_message = message
	in_match = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func go_to_lobby() -> void:
	in_match = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


func start_world() -> void:
	in_match = true
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/world.tscn")
