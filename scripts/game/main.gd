extends Node3D
## Root of the game: builds the facility, runs the menus, starts/stops matches and handles
## pause, mouse capture and the cinematic menu camera.

@onready var facility: FacilityBuilder = $Facility
@onready var units_root: Node3D = $Units
@onready var match_manager: MatchManager = $MatchManager
@onready var menu_camera: Camera3D = $MenuCamera
@onready var hud: HUD = $UI/HUD
@onready var scoreboard: Scoreboard = $UI/Scoreboard
@onready var match_end: MatchEndScreen = $UI/MatchEnd
@onready var pause_menu: PauseMenu = $UI/PauseMenu
@onready var settings_menu: SettingsMenu = $UI/SettingsMenu
@onready var main_menu: MainMenu = $UI/MainMenu

var state := "menu"          # menu, playing, paused, ended
var last_config := {"side": "attack", "rounds_to_win": 5}
var _settings_return := "menu"
var _menu_t := 0.0
var _end_timer := -1.0
var autotest: Node = null

const MENU_PATH := [
	[Vector3(4, 7, 58), Vector3(0, 2, 30)],
	[Vector3(-8, 9, 24), Vector3(0, 3, -2)],
	[Vector3(-30, 8, -6), Vector3(-36, 2, -34)],
	[Vector3(-10, 7, -30), Vector3(4, 3, -40)],
	[Vector3(22, 9, -10), Vector3(36, 4, -36)],
	[Vector3(30, 7, 24), Vector3(40, 2, 2)],
]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for n in [facility, units_root, match_manager]:
		n.process_mode = Node.PROCESS_MODE_PAUSABLE
	facility.build()
	menu_camera.make_current()
	main_menu.play_requested.connect(start_match)
	main_menu.settings_requested.connect(func() -> void: _open_settings("menu"))
	main_menu.quit_requested.connect(func() -> void: get_tree().quit())
	pause_menu.resume_requested.connect(resume)
	pause_menu.settings_requested.connect(func() -> void: _open_settings("paused"))
	pause_menu.restart_requested.connect(func() -> void:
		get_tree().paused = false
		start_match(last_config))
	pause_menu.menu_requested.connect(go_to_menu)
	pause_menu.quit_requested.connect(func() -> void: get_tree().quit())
	settings_menu.closed.connect(_on_settings_closed)
	match_end.again_requested.connect(func() -> void: start_match(last_config))
	match_end.menu_requested.connect(go_to_menu)
	match_manager.match_ended.connect(_on_match_ended)
	get_window().focus_exited.connect(_on_focus_lost)
	if "--autotest" in OS.get_cmdline_user_args() or "--movetest" in OS.get_cmdline_user_args() or "--combattest" in OS.get_cmdline_user_args() or _has_arg("--shots="):
		autotest = load("res://scripts/game/autotest.gd").new()
		autotest.name = "Autotest"
		add_child(autotest)
	await facility.navigation_ready
	main_menu.set_ready(true)
	if autotest:
		autotest.begin(self)


func _has_arg(prefix: String) -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return true
	return false


# ================================================================== flow
func start_match(config: Dictionary, with_player := true) -> void:
	last_config = config
	get_tree().paused = false
	main_menu.visible = false
	match_end.visible = false
	pause_menu.visible = false
	_end_timer = -1.0
	match_manager.start_match({"level": facility, "units_root": units_root, "side": config.get("side", "attack"),
		"rounds_to_win": config.get("rounds_to_win", 5), "player": with_player})
	hud.bind(match_manager, facility)
	hud.visible = true
	scoreboard.mm = match_manager
	if match_manager.player:
		match_manager.player.activate_camera()
	else:
		var bots := match_manager.team_units(0)
		if not bots.is_empty():
			menu_camera.make_current()
	state = "playing"
	_capture(true)


func go_to_menu() -> void:
	get_tree().paused = false
	match_manager.clear_match()
	facility.set_spawn_walls(false)
	hud.visible = false
	scoreboard.visible = false
	pause_menu.visible = false
	match_end.visible = false
	main_menu.visible = true
	menu_camera.make_current()
	state = "menu"
	_capture(false)


func pause() -> void:
	if state != "playing":
		return
	get_tree().paused = true
	pause_menu.visible = true
	scoreboard.visible = false
	state = "paused"
	_capture(false)


func resume() -> void:
	if state != "paused":
		return
	get_tree().paused = false
	pause_menu.visible = false
	state = "playing"
	_capture(true)


func _open_settings(from: String) -> void:
	_settings_return = from
	if from == "paused":
		pause_menu.visible = false
	else:
		main_menu.visible = false
	settings_menu.open()


func _on_settings_closed() -> void:
	if _settings_return == "paused":
		pause_menu.visible = true
	else:
		main_menu.visible = true
	if match_manager.player:
		match_manager.player.camera.fov = Settings.fov


func _on_match_ended(_winner: int) -> void:
	state = "ended"
	_end_timer = 3.0


func _on_focus_lost() -> void:
	if state == "playing" and autotest == null:
		pause()


func _capture(on: bool) -> void:
	if autotest:
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


# ================================================================== input / frame
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if state == "playing":
			pause()
			get_viewport().set_input_as_handled()
		return
	if state == "playing" and event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_capture(true)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if state == "playing":
		scoreboard.visible = Input.is_action_pressed("scoreboard")
	if _end_timer > 0.0:
		_end_timer -= delta
		if _end_timer <= 0.0:
			hud.visible = false
			scoreboard.visible = false
			match_end.show_result(match_manager, 0 if match_manager.scores[0] > match_manager.scores[1] else 1)
			_capture(false)
	if menu_camera.current:
		_menu_t += delta
		var seg_len := 9.0
		var n := MENU_PATH.size()
		var f := fmod(_menu_t / seg_len, float(n))
		var i := int(f)
		var k := smoothstep(0.0, 1.0, f - i)
		var a: Array = MENU_PATH[i]
		var b: Array = MENU_PATH[(i + 1) % n]
		var pos: Vector3 = a[0].lerp(b[0], k)
		var look: Vector3 = a[1].lerp(b[1], k)
		menu_camera.global_position = menu_camera.global_position.lerp(pos, clampf(delta * 1.5, 0, 1)) if _menu_t > 0.1 else pos
		var target := menu_camera.global_transform.looking_at(look, Vector3.UP)
		menu_camera.global_transform = menu_camera.global_transform.interpolate_with(target, clampf(delta * 1.5, 0, 1)) if _menu_t > 0.1 else target
