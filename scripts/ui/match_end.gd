class_name MatchEndScreen
extends Control
## Victory / defeat screen with final score, MVP and full stats.

signal again_requested
signal menu_requested

var _panel: PanelContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UIKit.theme()
	visible = false


func show_result(mm: MatchManager, winner: int) -> void:
	for c in get_children():
		c.queue_free()
	var won := winner == MatchManager.viewer_team()
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.02, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_panel = UIKit.panel(UIKit.BG_SOLID, 4)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	HUD.place(_panel, Control.PRESET_CENTER, Vector2(-480, -340), Vector2(960, 680))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_panel.add_child(v)
	var title := UIKit.shadowed(UIKit.label("VICTORY" if won else "DEFEAT", 88, UIKit.ALLY if won else UIKit.ENEMY, "display", HORIZONTAL_ALIGNMENT_CENTER), 0.6)
	v.add_child(title)
	var viewer := MatchManager.viewer_team()
	v.add_child(UIKit.label("%d  —  %d" % [mm.scores[viewer], mm.scores[1 - viewer]], 34, UIKit.TEXT, "display_semi", HORIZONTAL_ALIGNMENT_CENTER))
	var mvp: Combatant = null
	for u in mm.units:
		if mvp == null or u.score > mvp.score:
			mvp = u
	if mvp:
		var m := UIKit.label("MATCH MVP   ·   %s   ·   %d / %d / %d" % [mvp.unit_name.to_upper(), mvp.kills, mvp.deaths, mvp.assists], 18, UIKit.AMBER, "display_semi", HORIZONTAL_ALIGNMENT_CENTER)
		v.add_child(m)
	v.add_child(UIKit.hline())
	v.add_child(Scoreboard.build_table(mm))
	v.add_child(UIKit.spacer(10))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	var again := UIKit.button("PLAY AGAIN", true, 240)
	again.alignment = HORIZONTAL_ALIGNMENT_CENTER
	again.pressed.connect(func() -> void: again_requested.emit())
	var menu := UIKit.button("MAIN MENU", false, 240)
	menu.alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu.pressed.connect(func() -> void: menu_requested.emit())
	row.add_child(again)
	row.add_child(menu)
	v.add_child(row)
	visible = true
	_panel.modulate.a = 0.0
	_panel.scale = Vector2(0.96, 0.96)
	_panel.pivot_offset = Vector2(480, 340)
	var tw := _panel.create_tween()
	tw.set_parallel(true)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.35)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
