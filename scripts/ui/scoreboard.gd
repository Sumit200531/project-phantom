class_name Scoreboard
extends Control
## Hold-Tab scoreboard. `build_table` is shared with the match-end screen.

var mm: MatchManager
var _panel: PanelContainer
var _content: VBoxContainer
var _refresh := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UIKit.theme()
	_panel = UIKit.panel(UIKit.BG_SOLID, 4)
	add_child(_panel)
	HUD.place(_panel, Control.PRESET_CENTER, Vector2(-470, -290), Vector2(940, 560))
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 6)
	_panel.add_child(_content)
	visible = false


func _process(delta: float) -> void:
	if not visible or mm == null:
		return
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.25
		_rebuild()


func _rebuild() -> void:
	for c in _content.get_children():
		c.queue_free()
	var head := HBoxContainer.new()
	head.add_child(UIKit.label("SCOREBOARD", 26, UIKit.TEXT, "display"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(UIKit.label("ROUND %d   ·   %d — %d" % [mm.round_number, mm.scores[0], mm.scores[1]], 20, UIKit.DIM, "display_semi"))
	_content.add_child(head)
	_content.add_child(UIKit.hline())
	_content.add_child(build_table(mm))


static func build_table(m: MatchManager) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var viewer := MatchManager.viewer_team()
	var rounds := maxi(1, m.round_number)
	for t in [viewer, 1 - viewer]:
		var col := UIKit.ALLY if t == viewer else UIKit.ENEMY
		var side := "ATTACK" if t == m.attack_team else "DEFENSE"
		var title := UIKit.label(("YOUR TEAM" if t == viewer else "OPPONENTS") + "  ·  " + side, 15, col, "display_semi")
		box.add_child(UIKit.spacer(6))
		box.add_child(title)
		box.add_child(_row(["OPERATIVE", "K", "D", "A", "ACS", "HS%", "STATUS"], UIKit.DIM, false, Color(0, 0, 0, 0)))
		var members: Array = m.team_units(t)
		members.sort_custom(func(a, b): return a.score > b.score)
		for u in members:
			var hs := 0
			if u.kills > 0:
				hs = int(round(100.0 * u.headshots / u.kills))
			var status := "ALIVE" if u.is_alive() else "DOWN"
			if u.carrying_device:
				status = "CHARGE"
			var bg := Color(col.r, col.g, col.b, 0.16) if u.is_player else Color(1, 1, 1, 0.03)
			box.add_child(_row([u.unit_name.to_upper(), str(u.kills), str(u.deaths), str(u.assists),
				str(int(u.score / float(rounds))), "%d%%" % hs, status], UIKit.TEXT if u.is_alive() else UIKit.DIM, true, bg))
	return box


static func _row(cells: Array, color: Color, data: bool, bg: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var st := UIKit.box(bg, 2)
	st.content_margin_top = 5
	st.content_margin_bottom = 5
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	p.add_child(row)
	var widths := [330, 70, 70, 70, 100, 90, 140]
	for i in cells.size():
		var l := UIKit.label(cells[i], 18 if data else 13, color, "body_bold" if data else "display_semi",
			HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_CENTER)
		l.custom_minimum_size = Vector2(widths[i], 0)
		row.add_child(l)
	return p
