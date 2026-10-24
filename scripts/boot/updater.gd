extends Control
## First scene at startup: checks GitHub for a newer version of the game, downloads it
## and restarts into it. Any problem (offline, GitHub down) just starts the game as it is.
##
## Updates live on the repository's "updates" branch: version.json ({"build": N}) and game.pck.
## The exe runs a downloaded pack with "--main-pack <file>", which replaces everything,
## autoloads included. A downloaded pack ("--updated") still checks for an even newer build,
## so updates keep coming; it never re-downloads the build it already has.

const BASE_URL := "https://raw.githubusercontent.com/SirKevinTheFirst/jungle-tag/updates/"
const DIR := "user://updates/"
const MENU := "res://scenes/main_menu.tscn"

var _label: Label
var _bar: ProgressBar
var _http: HTTPRequest
var _base := BASE_URL
var _remote := 0
var _downloading := false
var _updated := false


static func build() -> int:
	return int(ProjectSettings.get_setting("application/config/build", 0))


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.07, 0.05)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(520, 0)
	box.position -= Vector2(260, 40)
	box.add_theme_constant_override("separation", 14)
	add_child(box)
	_label = Label.new()
	_label.text = "Checking for updates..."
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 28)
	box.add_child(_label)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(520, 26)
	_bar.visible = false
	box.add_child(_bar)

	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--update-url="):
			_base = a.trim_prefix("--update-url=")
	# (tests run the editor binary headless: JT_UPDATER_TEST=1 and JT_UPDATER_ARGS carry that over)
	var testing := OS.get_environment("JT_UPDATER_TEST") == "1"
	var skip: bool = OS.has_feature("editor") and not args.has("--force-update") and not testing
	if skip or args.has("--no-update"):
		_go.call_deferred()
		return
	_updated = args.has("--updated")
	DirAccess.make_dir_recursive_absolute(DIR)
	# an update downloaded earlier: start it straight away (it checks for anything newer itself)
	var cached := _cached_build()
	if not _updated and cached > build() and FileAccess.file_exists(_pck_path(cached)):
		_relaunch.call_deferred(cached)
		return
	_http = HTTPRequest.new()
	_http.timeout = 6.0
	add_child(_http)
	_http.request_completed.connect(_on_version)
	if _http.request(_base + "version.json?t=%d" % int(Time.get_unix_time_from_system())) != OK:
		_go.call_deferred()


func _process(_d: float) -> void:
	if _downloading and _http.get_body_size() > 0:
		_bar.value = 100.0 * _http.get_downloaded_bytes() / _http.get_body_size()


func _on_version(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_go()
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY or not data.has("build"):
		_go()
		return
	_remote = int(data.build)
	var have := build()
	if _updated:
		have = maxi(have, _cached_build())   # never fetch the same build twice
	if _remote <= have:
		_go()
		return
	_label.text = "Downloading update %d..." % _remote
	_bar.visible = true
	_downloading = true
	_http.request_completed.disconnect(_on_version)
	_http.request_completed.connect(_on_pck)
	_http.timeout = 300.0
	_http.download_file = DIR + "download.tmp"
	if _http.request(_base + "game.pck?b=%d" % _remote) != OK:
		_go()


func _on_pck(result: int, code: int, _h: PackedStringArray, _body: PackedByteArray) -> void:
	_downloading = false
	var tmp := DIR + "download.tmp"
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or FileAccess.get_file_as_bytes(tmp).size() < 100000:
		DirAccess.remove_absolute(tmp)
		_go()
		return
	var dest := _pck_path(_remote)
	DirAccess.remove_absolute(dest)
	DirAccess.rename_absolute(tmp, dest)
	var f := FileAccess.open(DIR + "build.txt", FileAccess.WRITE)
	f.store_string(str(_remote))
	f.close()
	# tidy up older downloads (the one we are running from may be locked, which is fine)
	for file in DirAccess.get_files_at(DIR):
		if file.begins_with("game_") and file != dest.get_file():
			DirAccess.remove_absolute(DIR + file)
	_label.text = "Update installed! Restarting..."
	_bar.value = 100.0
	await get_tree().create_timer(0.6).timeout
	_relaunch(_remote)


func _cached_build() -> int:
	if not FileAccess.file_exists(DIR + "build.txt"):
		return 0
	return FileAccess.get_file_as_string(DIR + "build.txt").strip_edges().to_int()


func _pck_path(b: int) -> String:
	return DIR + "game_%d.pck" % b


func _relaunch(b: int) -> void:
	var args := ["--main-pack", ProjectSettings.globalize_path(_pck_path(b)), "--", "--updated"]
	if OS.get_environment("JT_UPDATER_ARGS") != "":
		args = Array(OS.get_environment("JT_UPDATER_ARGS").split(" ")) + args
		args.append("--update-url=" + _base)
	var pid := OS.create_process(OS.get_executable_path(), args)
	if pid <= 0:
		_go()
		return
	get_tree().quit()


func _go() -> void:
	print("boot: running build %d" % build())
	var f := FileAccess.open("user://last_boot.txt", FileAccess.WRITE)
	if f:
		f.store_string("build %d args %s\n" % [build(), str(OS.get_cmdline_args())])
	get_tree().change_scene_to_file(MENU)
