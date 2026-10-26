extends SceneTree
## Dev tool: writes the input map into project.godot.
## Run: godot --headless --path . --script res://tools/setup_input.gd

func _init() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE],
		"sprint": [KEY_SHIFT],
		"crouch": [KEY_CTRL],
		"reload": [KEY_R],
		"interact": [KEY_F],
		"weapon_1": [KEY_1],
		"weapon_2": [KEY_2],
		"weapon_3": [KEY_3],
		"ability_1": [KEY_Q],
		"ability_2": [KEY_E],
		"ability_3": [KEY_C],
		"scoreboard": [KEY_TAB],
		"pause": [KEY_ESCAPE],
	}
	for action in keys:
		var events := []
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			ev.device = -1
			events.append(ev)
		ProjectSettings.set_setting("input/" + action, {"deadzone": 0.5, "events": events})
	var mouse := {
		"fire": MOUSE_BUTTON_LEFT,
		"aim": MOUSE_BUTTON_RIGHT,
		"weapon_next": MOUSE_BUTTON_WHEEL_DOWN,
		"weapon_prev": MOUSE_BUTTON_WHEEL_UP,
	}
	for action in mouse:
		var mb := InputEventMouseButton.new()
		mb.button_index = mouse[action]
		mb.device = -1
		ProjectSettings.set_setting("input/" + action, {"deadzone": 0.5, "events": [mb]})
	var err := ProjectSettings.save()
	print("input map saved: ", err)
	quit()
