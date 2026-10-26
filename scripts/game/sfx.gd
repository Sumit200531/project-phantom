extends Node
## Autoload "Sfx": loads every WAV in assets/audio and plays pooled 2D / 3D sounds.
## Names without a numeric suffix pick a random variant, e.g. "step_metal" -> step_metal_1..4.

const AUDIO_DIR := "res://assets/audio/"
const POOL_2D := 20
const POOL_3D := 40

var _streams := {}          # exact name -> AudioStream
var _variants := {}         # base name -> Array of names
var _pool_2d: Array[AudioStreamPlayer] = []
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _ui_player: AudioStreamPlayer
var _i2 := 0
var _i3 := 0
var _last_played := {}      # name -> msec, to avoid stacking identical sounds in one frame
var _world_root: Node3D


func _ready() -> void:
	_load_streams()
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool_2d.append(p)
	_ui_player = AudioStreamPlayer.new()
	_ui_player.bus = "UI"
	_ui_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_ui_player)
	_world_root = Node3D.new()
	_world_root.name = "Sfx3D"
	add_child(_world_root)
	for i in POOL_3D:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = "SFX"
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.unit_size = 6.0
		p3.max_distance = 90.0
		p3.attenuation_filter_cutoff_hz = 6000.0
		p3.attenuation_filter_db = -18.0
		p3.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		_world_root.add_child(p3)
		_pool_3d.append(p3)


func _load_streams() -> void:
	var dir := DirAccess.open(AUDIO_DIR)
	if dir == null:
		push_warning("Sfx: audio folder missing, game will run silently")
		return
	var names: Array[String] = []
	for f in dir.get_files():
		# Exported builds list "x.wav.import"; editor builds list "x.wav".
		var file := f.replace(".import", "")
		if file.ends_with(".wav") and not names.has(file):
			names.append(file)
	for file in names:
		var res_path := AUDIO_DIR + file
		if not ResourceLoader.exists(res_path):
			continue
		var stream: AudioStream = load(res_path)
		if stream == null:
			continue
		var key := file.get_basename()
		if key.ends_with("_loop") and stream is AudioStreamWAV:
			var wav := stream as AudioStreamWAV
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = int(wav.get_length() * wav.mix_rate)
		_streams[key] = stream
		var parts := key.rsplit("_", true, 1)
		if parts.size() == 2 and parts[1].is_valid_int():
			if not _variants.has(parts[0]):
				_variants[parts[0]] = []
			_variants[parts[0]].append(key)


func has_sound(sound: String) -> bool:
	return _streams.has(sound) or _variants.has(sound)


func get_stream(sound: String) -> AudioStream:
	if _streams.has(sound):
		return _streams[sound]
	if _variants.has(sound):
		return _streams[_variants[sound].pick_random()]
	return null


func _throttled(sound: String) -> bool:
	var now := Time.get_ticks_msec()
	if _last_played.get(sound, -1000) > now - 25:
		return true
	_last_played[sound] = now
	return false


func play(sound: String, volume_db := 0.0, pitch_jitter := 0.04) -> AudioStreamPlayer:
	var stream := get_stream(sound)
	if stream == null or _throttled(sound):
		return null
	var p := _pool_2d[_i2]
	_i2 = (_i2 + 1) % POOL_2D
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()
	return p


func play_ui(sound: String, volume_db := 0.0) -> void:
	var stream := get_stream(sound)
	if stream == null:
		return
	_ui_player.stream = stream
	_ui_player.volume_db = volume_db
	_ui_player.play()


func play_at(sound: String, pos: Vector3, volume_db := 0.0, max_distance := 90.0, pitch_jitter := 0.05, unit_size := 6.0) -> AudioStreamPlayer3D:
	var stream := get_stream(sound)
	if stream == null:
		return null
	var p := _pool_3d[_i3]
	_i3 = (_i3 + 1) % POOL_3D
	p.stop()
	p.stream = stream
	p.global_position = pos
	p.volume_db = volume_db
	p.max_distance = max_distance
	p.unit_size = unit_size
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()
	return p


## Creates a looping positional emitter owned by `parent` (ambience, reactor hum, barrier hum).
func make_loop(sound: String, parent: Node, pos: Vector3, volume_db := -6.0, max_distance := 40.0) -> AudioStreamPlayer3D:
	var stream := get_stream(sound)
	if stream == null or parent == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = "Ambience"
	p.volume_db = volume_db
	p.max_distance = max_distance
	p.unit_size = 8.0
	p.autoplay = true
	parent.add_child(p)
	p.global_position = pos
	return p


func stop_all_3d() -> void:
	for p in _pool_3d:
		p.stop()
