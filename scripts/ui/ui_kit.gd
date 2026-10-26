class_name UIKit
## Shared typography, palette and widget factories for every screen.

const BG := Color(0.035, 0.05, 0.062, 0.82)
const BG_SOLID := Color(0.04, 0.055, 0.068, 0.96)
const LINE := Color(1, 1, 1, 0.09)
const TEXT := Color(0.93, 0.95, 0.96)
const DIM := Color(0.58, 0.64, 0.68)
const ALLY := Color(0.2, 0.86, 0.8)
const ENEMY := Color(1.0, 0.36, 0.26)
const AMBER := Color(1.0, 0.71, 0.28)
const CYAN := Color(0.33, 0.9, 1.0)

static var _fonts := {}
static var _theme: Theme


static func font(kind := "body") -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var path := ""
	match kind:
		"display": path = "res://assets/fonts/ChakraPetch-Bold.ttf"
		"display_semi": path = "res://assets/fonts/ChakraPetch-SemiBold.ttf"
		"body": path = "res://assets/fonts/BarlowSemiCondensed-Medium.ttf"
		"body_bold": path = "res://assets/fonts/BarlowSemiCondensed-SemiBold.ttf"
	var f: Font = null
	if ResourceLoader.exists(path):
		f = load(path)
	if f == null:
		f = ThemeDB.fallback_font
	_fonts[kind] = f
	return f


static func box(color: Color, radius := 3, border := Color(0, 0, 0, 0), border_w := 0, skew := 0.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	if border_w > 0:
		s.border_color = border
		s.set_border_width_all(border_w)
	s.skew = Vector2(skew, 0)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	s.anti_aliasing = true
	return s


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font("body")
	t.default_font_size = 18
	t.set_color("font_color", "Label", TEXT)
	# Buttons
	var normal := box(Color(1, 1, 1, 0.04), 2, LINE, 1)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	var hover := normal.duplicate()
	hover.bg_color = Color(0.2, 0.86, 0.8, 0.14)
	hover.border_color = Color(0.2, 0.86, 0.8, 0.7)
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.2, 0.86, 0.8, 0.28)
	pressed.border_color = ALLY
	var focus := normal.duplicate()
	focus.bg_color = Color(0, 0, 0, 0)
	focus.border_color = AMBER
	focus.set_border_width_all(2)
	var disabled := normal.duplicate()
	disabled.bg_color = Color(1, 1, 1, 0.02)
	disabled.border_color = Color(1, 1, 1, 0.04)
	for type in ["Button", "OptionButton", "CheckButton"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("focus", type, focus)
		t.set_stylebox("disabled", type, disabled)
		t.set_font("font", type, font("body_bold"))
		t.set_font_size("font_size", type, 19)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color(1, 1, 1))
		t.set_color("font_pressed_color", type, Color(1, 1, 1))
		t.set_color("font_disabled_color", type, Color(1, 1, 1, 0.3))
	# Sliders
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.12)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	var fill := StyleBoxFlat.new()
	fill.bg_color = ALLY
	fill.content_margin_top = 2
	fill.content_margin_bottom = 2
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _dot_icon(ALLY, 16))
	t.set_icon("grabber_highlight", "HSlider", _dot_icon(Color(1, 1, 1), 16))
	# Panels / popups
	t.set_stylebox("panel", "PanelContainer", box(BG, 4, LINE, 1))
	var popup := box(BG_SOLID, 3, LINE, 1)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_font("font", "PopupMenu", font("body"))
	t.set_font_size("font_size", "PopupMenu", 18)
	var tab_sel := box(Color(0.2, 0.86, 0.8, 0.16), 2, ALLY, 0)
	tab_sel.border_width_bottom = 2
	tab_sel.border_color = ALLY
	var tab_unsel := box(Color(0, 0, 0, 0), 2)
	t.set_stylebox("tab_selected", "TabBar", tab_sel)
	t.set_stylebox("tab_unselected", "TabBar", tab_unsel)
	t.set_stylebox("tab_hovered", "TabBar", box(Color(1, 1, 1, 0.06), 2))
	t.set_font("font", "TabBar", font("display_semi"))
	t.set_font_size("font_size", "TabBar", 18)
	t.set_color("font_selected_color", "TabBar", TEXT)
	t.set_color("font_unselected_color", "TabBar", DIM)
	t.set_color("font_hovered_color", "TabBar", TEXT)
	t.set_stylebox("panel", "TabContainer", StyleBoxEmpty.new())
	t.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)
	t.set_stylebox("tab_unselected", "TabContainer", tab_unsel)
	t.set_stylebox("tab_hovered", "TabContainer", box(Color(1, 1, 1, 0.06), 2))
	t.set_font("font", "TabContainer", font("display_semi"))
	t.set_font_size("font_size", "TabContainer", 18)
	t.set_color("font_selected_color", "TabContainer", TEXT)
	t.set_color("font_unselected_color", "TabContainer", DIM)
	t.set_color("font_hovered_color", "TabContainer", TEXT)
	t.set_constant("separation", "VBoxContainer", 8)
	t.set_constant("separation", "HBoxContainer", 8)
	_theme = t
	return t


static func _dot_icon(color: Color, size: int) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length()
			img.set_pixel(x, y, Color(color.r, color.g, color.b, clampf(c - d + 0.5, 0, 1)))
	return ImageTexture.create_from_image(img)


static func label(text: String, size := 18, color := TEXT, kind := "body", align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(kind))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func shadowed(l: Label, alpha := 0.6) -> Label:
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, alpha))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", 6)
	return l


static func button(text: String, primary := false, min_w := 220) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 46)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_ALL
	if primary:
		var n := box(AMBER, 2)
		n.content_margin_left = 18
		var h := box(Color(1.0, 0.8, 0.45), 2)
		h.content_margin_left = 18
		b.add_theme_stylebox_override("normal", n)
		b.add_theme_stylebox_override("hover", h)
		b.add_theme_stylebox_override("pressed", h)
		b.add_theme_color_override("font_color", Color(0.08, 0.06, 0.02))
		b.add_theme_color_override("font_hover_color", Color(0.08, 0.06, 0.02))
		b.add_theme_color_override("font_pressed_color", Color(0.08, 0.06, 0.02))
		b.add_theme_font_override("font", font("display"))
	b.mouse_entered.connect(func() -> void: Sfx.play_ui("ui_hover", -10.0))
	b.pressed.connect(func() -> void: Sfx.play_ui("ui_click", -4.0))
	return b


static func panel(color := BG, radius := 4) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(color, radius, LINE, 1))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func spacer(h := 8) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func hline(color := LINE) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Segmented toggle (e.g. Attack / Defense). Returns the container; selection reported via callback.
static func segmented(options: Array, selected: int, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var group := ButtonGroup.new()
	for i in options.size():
		var b := Button.new()
		b.text = options[i]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == selected
		b.custom_minimum_size = Vector2(0, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var idx := i
		b.pressed.connect(func() -> void:
			Sfx.play_ui("ui_click", -6.0)
			on_change.call(idx))
		row.add_child(b)
	return row
