extends Node
## Plays music, ambience and one-shot sound effects (2D and positional 3D).

const SOUNDS := [
	"amb_jungle", "amb_wind", "amb_river", "amb_waterfall",
	"bird_0", "bird_1", "bird_2", "bird_3",
	"step_0", "step_1", "step_2", "step_3", "climb_0", "climb_1", "climb_2",
	"vine_grab", "swing", "jump", "land", "tag", "infect",
	"camo_on", "camo_off", "camo_ready", "round_start", "round_end",
	"beep", "beep_high", "ui_click", "ui_hover", "music_loop",
]
const LOOPED := ["amb_jungle", "amb_wind", "amb_river", "amb_waterfall", "music_loop"]

var streams := {}
var _music: AudioStreamPlayer
var _pool: Array[AudioStreamPlayer] = []
var _pool_idx := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for s in SOUNDS:
		var path := "res://audio/%s.wav" % s
		if ResourceLoader.exists(path):
			var st: AudioStream = load(path)
			if st is AudioStreamWAV and s in LOOPED:
				var wav := st as AudioStreamWAV
				wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
				wav.loop_begin = 0
				wav.loop_end = int(wav.get_length() * wav.mix_rate)
			streams[s] = st
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)


func get_stream(sound: String) -> AudioStream:
	return streams.get(sound)


func play_music() -> void:
	if _music.playing or not streams.has("music_loop"):
		return
	_music.stream = streams["music_loop"]
	_music.volume_db = -4.0
	_music.play()


func stop_music() -> void:
	_music.stop()


## Non-positional sound (UI, local player events).
func play(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var st: AudioStream = streams.get(sound)
	if st == null:
		return
	var p := _pool[_pool_idx]
	_pool_idx = (_pool_idx + 1) % _pool.size()
	p.stream = st
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


## Positional one-shot sound in the current 3D scene.
func play_at(sound: String, pos: Vector3, volume_db: float = 0.0, pitch: float = 1.0, max_dist: float = 45.0) -> void:
	var st: AudioStream = streams.get(sound)
	var scene := get_tree().current_scene
	if st == null or scene == null or not (scene is Node3D):
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = st
	p.bus = "SFX"
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.max_distance = max_dist
	p.unit_size = 6.0
	p.attenuation_filter_cutoff_hz = 9000.0
	scene.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


## Creates a looping positional emitter (rivers, waterfalls).
func make_loop_emitter(sound: String, parent: Node3D, pos: Vector3, volume_db: float, max_dist: float, bus: String = "Ambience") -> AudioStreamPlayer3D:
	var st: AudioStream = streams.get(sound)
	if st == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = st
	p.bus = bus
	p.volume_db = volume_db
	p.max_distance = max_dist
	p.unit_size = 10.0
	p.autoplay = true
	parent.add_child(p)
	p.position = pos
	return p
