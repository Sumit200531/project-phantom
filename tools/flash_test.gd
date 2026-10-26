extends Node
## Dev tool: renders muzzle-flash material variants inside a transparent own-world SubViewport.
func _ready() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.size = Vector2i(640, 360)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	layer.add_child(vp)
	var rect := TextureRect.new()
	rect.texture = vp.get_texture()
	layer.add_child(rect)
	var cam := Camera3D.new()
	cam.cull_mask = 2
	vp.add_child(cam)
	var tex: Texture2D = load("res://assets/textures/muzzle_flash.png")
	var variants := [["mix_tex", true, BaseMaterial3D.BLEND_MODE_MIX, true], ["mix_notex", false, BaseMaterial3D.BLEND_MODE_MIX, true], ["mix_nobill", true, BaseMaterial3D.BLEND_MODE_MIX, false], ["opaque", false, -1, false]]
	for i in variants.size():
		var v = variants[i]
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.3, 0.3)
		mi.mesh = q
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if v[2] != -1:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = v[2]
		if v[1]:
			m.albedo_texture = tex
		m.albedo_color = Color(1.0, 0.9, 0.7)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		if v[3]:
			m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mi.material_override = m
		mi.layers = 2
		mi.position = Vector3(-0.75 + i * 0.5, 0, -1.2)
		vp.add_child(mi)
	for i in 8:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	print("tex=", tex, " size=", tex.get_size() if tex else Vector2.ZERO)
	get_tree().quit()
