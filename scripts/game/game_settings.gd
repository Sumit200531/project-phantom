extends Node
## Autoload "Settings": persistent user settings and graphics-quality application.

signal changed

const PATH := "user://phantom_settings.cfg"
const PRESETS := ["Low", "Medium", "High", "Ultra"]

# Gameplay
var mouse_sensitivity := 1.0        # multiplier
var invert_y := false
var mouse_smoothing := 0.0          # 0 = raw input
var fov := 74.0                     # vertical field of view in degrees
var bot_difficulty := 1             # 0 easy, 1 normal, 2 hard
var crosshair_color := Color(0.6, 1.0, 0.95)
var show_fps := false
var head_bob := 1.0                 # 0..1 scale of camera bob

# Audio (linear 0..1)
var master_volume := 0.8
var sfx_volume := 1.0
var ambience_volume := 0.6

# Display / graphics
var fullscreen := false
var vsync := true
var max_fps := 0
var preset := 1                     # index in PRESETS (Medium on first launch)
var render_scale := 1.0
var shadow_quality := 2             # 0 off, 1 low, 2 high
var ssao := true
var glow := true
var volumetric_fog := false
var ssr := false
var antialiasing := 1               # 0 off, 1 FXAA, 2 MSAA 2x, 3 MSAA 4x
var foliage_density := 1.0

var _env: Environment
var _sun: DirectionalLight3D
var _probes: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	_ensure_audio_buses()
	apply_display()
	apply_audio()


func apply_preset(index: int) -> void:
	preset = clampi(index, 0, PRESETS.size() - 1)
	match preset:
		0:
			shadow_quality = 1; ssao = false; glow = false; volumetric_fog = false; ssr = false
			antialiasing = 1; render_scale = 0.8; foliage_density = 0.35
		1:
			shadow_quality = 1; ssao = true; glow = true; volumetric_fog = false; ssr = false
			antialiasing = 1; render_scale = 1.0; foliage_density = 0.7
		2:
			shadow_quality = 2; ssao = true; glow = true; volumetric_fog = false; ssr = false
			antialiasing = 2; render_scale = 1.0; foliage_density = 1.0
		3:
			shadow_quality = 2; ssao = true; glow = true; volumetric_fog = true; ssr = true
			antialiasing = 3; render_scale = 1.0; foliage_density = 1.0


func register_world(env: Environment, sun: DirectionalLight3D, probes: Array = []) -> void:
	_env = env
	_sun = sun
	_probes = probes
	apply_graphics()


func world_environment() -> Environment:
	return _env


func world_sun() -> DirectionalLight3D:
	return _sun if is_instance_valid(_sun) else null


func apply_all() -> void:
	apply_display()
	apply_graphics()
	apply_audio()
	changed.emit()


func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = max_fps


func apply_graphics() -> void:
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_scale = render_scale
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR if render_scale >= 0.99 else Viewport.SCALING_3D_MODE_FSR
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if antialiasing == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
		match antialiasing:
			2: vp.msaa_3d = Viewport.MSAA_2X
			3: vp.msaa_3d = Viewport.MSAA_4X
			_: vp.msaa_3d = Viewport.MSAA_DISABLED
	RenderingServer.directional_shadow_atlas_set_size(4096 if shadow_quality >= 2 else 2048, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		RenderingServer.SHADOW_QUALITY_SOFT_LOW if shadow_quality >= 2 else RenderingServer.SHADOW_QUALITY_HARD)
	if is_instance_valid(_sun):
		_sun.shadow_enabled = shadow_quality > 0
		_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if shadow_quality >= 2 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		_sun.directional_shadow_max_distance = 140.0 if shadow_quality >= 2 else 80.0
	if _env:
		_env.ssao_enabled = ssao
		_env.glow_enabled = glow
		_env.volumetric_fog_enabled = volumetric_fog
		_env.ssr_enabled = ssr
		_env.ssil_enabled = preset >= 3
	for p in _probes:
		if is_instance_valid(p):
			p.visible = preset >= 1


func apply_audio() -> void:
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("SFX", sfx_volume)
	_set_bus_volume("Ambience", ambience_volume)


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
		AudioServer.set_bus_mute(idx, linear <= 0.001)


func _ensure_audio_buses() -> void:
	for bus_name in ["SFX", "Ambience", "UI"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


func sensitivity_radians() -> float:
	return 0.0022 * mouse_sensitivity


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in _keys():
		cfg.set_value("settings", key, get(key))
	cfg.save(PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		apply_preset(preset)
		return
	for key in _keys():
		if cfg.has_section_key("settings", key):
			set(key, cfg.get_value("settings", key))


func _keys() -> Array:
	return ["mouse_sensitivity", "invert_y", "mouse_smoothing", "fov", "bot_difficulty", "crosshair_color",
		"show_fps", "head_bob", "master_volume", "sfx_volume", "ambience_volume", "fullscreen", "vsync",
		"max_fps", "preset", "render_scale", "shadow_quality", "ssao", "glow", "volumetric_fog", "ssr",
		"antialiasing", "foliage_density"]
