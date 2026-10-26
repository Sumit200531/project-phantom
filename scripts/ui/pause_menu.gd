class_name PauseMenu
extends Control
## Pause overlay. Works while the tree is paused.

signal resume_requested
signal settings_requested
signal restart_requested
signal menu_requested
signal quit_requested


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UIKit.theme()
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.02, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var p := UIKit.panel(UIKit.BG_SOLID, 4)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(p)
	HUD.place(p, Control.PRESET_CENTER, Vector2(-190, -220), Vector2(380, 0))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	v.add_child(UIKit.label("PAUSED", 34, UIKit.TEXT, "display"))
	v.add_child(UIKit.label("The match is frozen.", 16, UIKit.DIM))
	v.add_child(UIKit.hline())
	var items := [["RESUME", resume_requested, true], ["SETTINGS", settings_requested, false], ["RESTART MATCH", restart_requested, false],
		["QUIT TO MENU", menu_requested, false], ["QUIT TO DESKTOP", quit_requested, false]]
	for it in items:
		var b := UIKit.button(it[0], it[2], 340)
		var sig: Signal = it[1]
		b.pressed.connect(func() -> void: sig.emit())
		v.add_child(b)
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		resume_requested.emit()
