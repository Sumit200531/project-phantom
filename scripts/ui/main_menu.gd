class_name MainMenu
extends Control
## Title screen over a live flythrough of the facility, with match setup and controls cards.

signal play_requested(config: Dictionary)
signal settings_requested
signal quit_requested

var _deploy: Button
var _status: Label
var _setup_card: PanelContainer
var _controls_card: PanelContainer
var _side := 0
var _length := 1
var _ready_to_play := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	_build()


func _build() -> void:
	var shade := TextureRect.new()
	var g := GradientTexture2D.new()
	g.fill_from = Vector2(0, 0)
	g.fill_to = Vector2(1, 0)
	var grad := Gradient.new()
	grad.set_color(0, Color(0.02, 0.03, 0.04, 0.95))
	grad.add_point(0.42, Color(0.02, 0.03, 0.04, 0.75))
	grad.set_color(grad.get_point_count() - 1, Color(0.02, 0.03, 0.04, 0.0))
	g.gradient = grad
	shade.texture = g
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	HUD.place(shade, Control.PRESET_LEFT_WIDE, Vector2.ZERO, Vector2(1100, 0))
	shade.offset_bottom = 0

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	HUD.place(col, Control.PRESET_CENTER_LEFT, Vector2(96, -300), Vector2(560, 620))
	var tag := UIKit.label("TACTICAL 5V5   ·   ATTACK / DEFENSE", 15, UIKit.AMBER, "display_semi")
	col.add_child(tag)
	col.add_child(UIKit.label("PROJECT", 34, UIKit.DIM, "display_semi"))
	var title := UIKit.shadowed(UIKit.label("PHANTOM", 104, UIKit.TEXT, "display"), 0.5)
	title.add_theme_constant_override("line_spacing", -20)
	col.add_child(title)
	var bar := ColorRect.new()
	bar.color = UIKit.ALLY
	bar.custom_minimum_size = Vector2(120, 4)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(bar)
	col.add_child(UIKit.label("Helix Research Facility  ·  two sites, three lanes, one Phase Charge.", 20, UIKit.DIM))
	col.add_child(UIKit.spacer(26))
	var play := UIKit.button("PLAY", true, 300)
	play.pressed.connect(func() -> void: _toggle_card(_setup_card))
	col.add_child(play)
	var settings := UIKit.button("SETTINGS", false, 300)
	settings.pressed.connect(func() -> void: settings_requested.emit())
	col.add_child(settings)
	var controls := UIKit.button("CONTROLS", false, 300)
	controls.pressed.connect(func() -> void: _toggle_card(_controls_card))
	col.add_child(controls)
	var quit := UIKit.button("QUIT", false, 300)
	quit.pressed.connect(func() -> void: quit_requested.emit())
	col.add_child(quit)
	for b in [play, settings, controls, quit]:
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	_setup_card = _card("MATCH SETUP")
	var sv: VBoxContainer = _setup_card.get_child(0)
	sv.add_child(UIKit.label("STARTING SIDE", 14, UIKit.DIM, "display_semi"))
	sv.add_child(UIKit.segmented(["Attack", "Defense"], 0, func(i: int) -> void: _side = i))
	sv.add_child(UIKit.label("BOT DIFFICULTY", 14, UIKit.DIM, "display_semi"))
	sv.add_child(UIKit.segmented(["Easy", "Normal", "Hard"], Settings.bot_difficulty, func(i: int) -> void:
		Settings.bot_difficulty = i
		Settings.save_settings()))
	sv.add_child(UIKit.label("MATCH LENGTH", 14, UIKit.DIM, "display_semi"))
	sv.add_child(UIKit.segmented(["First to 3", "First to 5", "First to 7"], 1, func(i: int) -> void: _length = i))
	sv.add_child(UIKit.spacer(8))
	var brief := UIKit.label("You and four bots versus five bots. Attackers carry the Phase Charge to site A or B; defenders stop the plant or defuse it. Sides swap at halftime.", 16, UIKit.DIM)
	brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	brief.custom_minimum_size = Vector2(380, 0)
	sv.add_child(brief)
	sv.add_child(UIKit.spacer(6))
	_deploy = UIKit.button("DEPLOY", true, 380)
	_deploy.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_deploy.disabled = true
	_deploy.pressed.connect(_on_deploy)
	sv.add_child(_deploy)
	_status = UIKit.label("Building the facility…", 15, UIKit.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER)
	sv.add_child(_status)

	_controls_card = _card("CONTROLS")
	var cv: VBoxContainer = _controls_card.get_child(0)
	var binds := [["W A S D", "Move"], ["Shift (hold)", "Sprint"], ["Ctrl (hold)", "Crouch"], ["Space", "Jump"],
		["Left mouse", "Fire"], ["Right mouse", "Aim down sights"], ["R", "Reload"], ["1 / 2 / 3, wheel", "Rifle / SMG / Sidearm"],
		["Q", "Shroud: obscuring field"], ["E", "Aegis Wall: energy barrier"], ["C", "Echo Pulse: reveal enemies"],
		["F (hold)", "Plant or defuse"], ["Tab (hold)", "Scoreboard"], ["Esc", "Pause"]]
	for b in binds:
		var row := HBoxContainer.new()
		var k := UIKit.label(b[0], 17, UIKit.TEXT, "display_semi")
		k.custom_minimum_size = Vector2(170, 0)
		row.add_child(k)
		row.add_child(UIKit.label(b[1], 17, UIKit.DIM))
		cv.add_child(row)

	var foot := UIKit.label("Fonts: Chakra Petch and Barlow Semi Condensed (SIL Open Font License). All models, textures and sounds are generated for this project.", 13, Color(1, 1, 1, 0.4))
	add_child(foot)
	HUD.place(foot, Control.PRESET_BOTTOM_LEFT, Vector2(96, -44), Vector2(1100, 24))


func _card(title: String) -> PanelContainer:
	var p := UIKit.panel(UIKit.BG_SOLID, 4)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(p)
	HUD.place(p, Control.PRESET_CENTER_RIGHT, Vector2(-540, -280), Vector2(440, 0))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	v.add_child(UIKit.label(title, 26, UIKit.TEXT, "display"))
	v.add_child(UIKit.hline())
	p.visible = false
	return p


func _toggle_card(card: PanelContainer) -> void:
	var show := not card.visible
	_setup_card.visible = false
	_controls_card.visible = false
	card.visible = show
	if show:
		card.modulate.a = 0.0
		var tw := card.create_tween()
		tw.tween_property(card, "modulate:a", 1.0, 0.18)


func set_ready(ready: bool) -> void:
	_ready_to_play = ready
	_deploy.disabled = not ready
	_status.text = "Facility ready." if ready else "Building the facility…"


func open_setup() -> void:
	_setup_card.visible = true
	_controls_card.visible = false


func _on_deploy() -> void:
	if not _ready_to_play:
		return
	play_requested.emit({"side": "attack" if _side == 0 else "defend", "rounds_to_win": [3, 5, 7][_length]})
