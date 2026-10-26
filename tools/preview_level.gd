extends Node3D
## Dev tool: builds the facility and saves screenshots from preset viewpoints.
## Run with a display: godot --path . res://tools/preview_level.tscn -- --out=/abs/dir

var shots := [
	["yard", Vector3(0, 1.7, 58), Vector3(-6, 180 + 180, 0)],
	["a_main", Vector3(-44, 1.7, 36), Vector3(-4, 0, 0)],
	["site_a", Vector3(-46, 1.7, -14), Vector3(-6, -25, 0)],
	["atrium", Vector3(0, 1.7, 14), Vector3(-6, 0, 0)],
	["site_b", Vector3(42, 1.7, -14), Vector3(-6, 20, 0)],
	["b_main", Vector3(44, 1.7, 36), Vector3(-4, 0, 0)],
	["server", Vector3(0, 1.7, -22), Vector3(-4, 0, 0)],
	["overview", Vector3(0, 95, 40), Vector3(-58, 0, 0)],
	["command", Vector3(0, 1.7, -50), Vector3(-4, 180, 0)],
	["tunnel", Vector3(-30, 1.7, 4), Vector3(-2, 90, 0)],
]

func _ready() -> void:
	var out := "/tmp"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	var fac: FacilityBuilder = load("res://scenes/levels/facility.tscn").instantiate()
	add_child(fac)
	var t0 := Time.get_ticks_msec()
	fac.build()
	print("build ms: ", Time.get_ticks_msec() - t0)
	await fac.navigation_ready
	print("nav ready ms: ", Time.get_ticks_msec() - t0, " cover points: ", fac.cover_points.size(), " obstacles: ", fac.obstacles.size())
	var cam := Camera3D.new()
	cam.fov = 74
	cam.far = 400
	add_child(cam)
	cam.make_current()
	for s in shots:
		if only != "" and s[0] != only:
			continue
		cam.position = s[1]
		cam.rotation_degrees = s[2]
		for i in 6:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png(out + "/" + s[0] + ".png")
		print("saved ", s[0])
	get_tree().quit()
