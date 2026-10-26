class_name SettingsMenu
extends Control
## Settings: gameplay, graphics (presets plus individual options) and audio. Changes apply live
## and are saved when the screen closes.

signal closed

var _rows := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UIKit.theme()
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.02, 0.8)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	visible = false


func open() -> void:
	for c in get_children():
		if c is PanelContainer:
			c.queue_free()
	_build()
	visible = true


func _build() -> void:
	var p := UIKit.panel(UIKit.BG_SOLID, 4)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(p)
	HUD.place(p, Control.PRESET_CENTER, Vector2(-430, -330), Vector2(860, 660))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var head := HBoxContainer.new()
	head.add_child(UIKit.label("SETTINGS", 30, UIKit.TEXT, "display"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var back := UIKit.button("BACK", true, 140)
	back.alignment = HORIZONTAL_ALIGNMENT_CENTER
	back.pressed.connect(_close)
	head.add_child(back)
	v.add_child(head)
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(820, 560)
	v.add_child(tabs)
	var game := _tab(tabs, "Gameplay")
	_slider(game, "Mouse sensitivity", 0.1, 4.0, 0.05, Settings.mouse_sensitivity, "%.2f", 1.0, func(x): Settings.mouse_sensitivity = x)
	_toggle(game, "Invert mouse Y", Settings.invert_y, func(x): Settings.invert_y = x)
	_slider(game, "Mouse smoothing", 0.0, 1.0, 0.05, Settings.mouse_smoothing, "%.2f", 1.0, func(x): Settings.mouse_smoothing = x)
	_slider(game, "Field of view (vertical)", 60.0, 90.0, 1.0, Settings.fov, "%d°", 1.0, func(x): Settings.fov = x)
	_slider(game, "Camera bob", 0.0, 1.0, 0.05, Settings.head_bob, "%.2f", 1.0, func(x): Settings.head_bob = x)
	_option(game, "Bot difficulty", ["Easy", "Normal", "Hard"], Settings.bot_difficulty, func(i): Settings.bot_difficulty = i)
	_option(game, "Crosshair colour", ["Cyan", "Green", "White", "Amber", "Magenta"], _crosshair_index(), func(i):
		Settings.crosshair_color = [Color(0.6, 1.0, 0.95), Color(0.45, 1.0, 0.45), Color(1, 1, 1), Color(1.0, 0.78, 0.3), Color(1.0, 0.45, 0.95)][i])
	_toggle(game, "Show FPS", Settings.show_fps, func(x): Settings.show_fps = x)
	var gfx := _tab(tabs, "Graphics")
	_option(gfx, "Quality preset", Settings.PRESETS, Settings.preset, func(i):
		Settings.apply_preset(i)
		Settings.apply_graphics()
		open())
	_slider(gfx, "Render scale", 0.5, 1.0, 0.05, Settings.render_scale, "%d%%", 100.0, func(x):
		Settings.render_scale = x
		Settings.apply_graphics())
	_option(gfx, "Shadows", ["Off", "Low", "High"], Settings.shadow_quality, func(i):
		Settings.shadow_quality = i
		Settings.apply_graphics())
	_option(gfx, "Anti-aliasing", ["Off", "FXAA", "MSAA 2x", "MSAA 4x"], Settings.antialiasing, func(i):
		Settings.antialiasing = i
		Settings.apply_graphics())
	_toggle(gfx, "Ambient occlusion (SSAO)", Settings.ssao, func(x):
		Settings.ssao = x
		Settings.apply_graphics())
	_toggle(gfx, "Bloom / glow", Settings.glow, func(x):
		Settings.glow = x
		Settings.apply_graphics())
	_toggle(gfx, "Volumetric fog", Settings.volumetric_fog, func(x):
		Settings.volumetric_fog = x
		Settings.apply_graphics())
	_toggle(gfx, "Screen-space reflections", Settings.ssr, func(x):
		Settings.ssr = x
		Settings.apply_graphics())
	_toggle(gfx, "Fullscreen", Settings.fullscreen, func(x):
		Settings.fullscreen = x
		Settings.apply_display())
	_toggle(gfx, "V-Sync", Settings.vsync, func(x):
		Settings.vsync = x
		Settings.apply_display())
	_option(gfx, "Frame rate limit", ["Unlimited", "60", "120", "144", "240"], [0, 60, 120, 144, 240].find(Settings.max_fps), func(i):
		Settings.max_fps = [0, 60, 120, 144, 240][i]
		Settings.apply_display())
	var note := UIKit.label("Grass density applies the next time the facility is built.", 14, UIKit.DIM)
	gfx.add_child(note)
	_slider(gfx, "Grass density", 0.0, 1.0, 0.05, Settings.foliage_density, "%d%%", 100.0, func(x): Settings.foliage_density = x)
	var audio := _tab(tabs, "Audio")
	_slider(audio, "Master volume", 0.0, 1.0, 0.01, Settings.master_volume, "%d%%", 100.0, func(x):
		Settings.master_volume = x
		Settings.apply_audio())
	_slider(audio, "Effects", 0.0, 1.0, 0.01, Settings.sfx_volume, "%d%%", 100.0, func(x):
		Settings.sfx_volume = x
		Settings.apply_audio())
	_slider(audio, "Ambience", 0.0, 1.0, 0.01, Settings.ambience_volume, "%d%%", 100.0, func(x):
		Settings.ambience_volume = x
		Settings.apply_audio())


func _crosshair_index() -> int:
	var opts := [Color(0.6, 1.0, 0.95), Color(0.45, 1.0, 0.45), Color(1, 1, 1), Color(1.0, 0.78, 0.3), Color(1.0, 0.45, 0.95)]
	for i in opts.size():
		if opts[i].is_equal_approx(Settings.crosshair_color):
			return i
	return 0


func _tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	return v


func _row(parent: VBoxContainer, title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 44)
	var l := UIKit.label(title, 18, UIKit.TEXT)
	l.custom_minimum_size = Vector2(340, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	parent.add_child(row)
	return row


func _slider(parent: VBoxContainer, title: String, mn: float, mx: float, step: float, value: float, fmt: String, display_mult: float, setter: Callable) -> void:
	var row := _row(parent, title)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(320, 0)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var val := UIKit.label(fmt % (value * display_mult), 17, UIKit.DIM, "display_semi", HORIZONTAL_ALIGNMENT_RIGHT)
	val.custom_minimum_size = Vector2(90, 0)
	s.value_changed.connect(func(x: float) -> void:
		setter.call(x)
		val.text = fmt % (x * display_mult))
	row.add_child(s)
	row.add_child(val)


func _toggle(parent: VBoxContainer, title: String, value: bool, setter: Callable) -> void:
	var row := _row(parent, title)
	var c := CheckButton.new()
	c.button_pressed = value
	c.toggled.connect(func(x: bool) -> void:
		Sfx.play_ui("ui_click", -6.0)
		setter.call(x))
	row.add_child(c)


func _option(parent: VBoxContainer, title: String, options: Array, selected: int, setter: Callable) -> void:
	var row := _row(parent, title)
	var o := OptionButton.new()
	for opt in options:
		o.add_item(str(opt))
	o.select(maxi(selected, 0))
	o.custom_minimum_size = Vector2(320, 40)
	o.item_selected.connect(func(i: int) -> void:
		Sfx.play_ui("ui_click", -6.0)
		setter.call(i))
	row.add_child(o)


func _close() -> void:
	Settings.save_settings()
	Settings.apply_all()
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_close()
