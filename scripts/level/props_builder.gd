class_name PropsBuilder
extends RefCounted
## Places every prop, landmark and piece of vegetation on the facility map.
## Visual geometry is batched through the builder's GeoBatch; collisions and cover data are
## registered on the builder so navigation and bots understand each prop.

var b: FacilityBuilder
var batch: GeoBatch
var rng := RandomNumberGenerator.new()
var _crate_mats := {}
var _grass_points: Array = []


func _init(builder: FacilityBuilder) -> void:
	b = builder
	batch = builder.batch
	rng.seed = 4242


func P(cx: float, cz: float, y := 0.0) -> Vector3:
	return b.P(cx, cz, y)


func build_all() -> void:
	_yard()
	_a_main()
	_site_a()
	_server_hall()
	_atrium()
	_market()
	_b_main()
	_site_b()
	_command_deck()
	_tunnels()
	_grass_scatter()


# ============================================================ prop primitives
func _rot_aabb_size(size: Vector3, yaw: float) -> Vector3:
	var c := absf(cos(yaw))
	var s := absf(sin(yaw))
	return Vector3(size.x * c + size.z * s, size.y, size.x * s + size.z * c)


func _crate_mat(color_key: String, size: Vector3) -> Material:
	var key := "%s_%.2f_%.2f_%.2f" % [color_key, size.x, size.y, size.z]
	if _crate_mats.has(key):
		return _crate_mats[key]
	var base: StandardMaterial3D = b.matlib.get_mat(color_key)
	var m: StandardMaterial3D = base.duplicate()
	m.uv1_scale = Vector3(1.0 / size.x, 1.0 / size.y, 1.0 / size.z)
	m.uv1_offset = Vector3(0.5, 0.5, 0.5)
	_crate_mats[key] = m
	return m


func crate(pos: Vector3, size: float, color := "crate_olive", yaw := 0.0, height_mult := 1.0) -> float:
	var s := Vector3(size, size * height_mult, size)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = s
	mi.mesh = bm
	mi.material_override = _crate_mat(color, s)
	mi.position = pos + Vector3(0, s.y * 0.5, 0)
	mi.rotation.y = yaw
	b.visuals.add_child(mi)
	b.collider_box("concrete", mi.position, s, Basis(Vector3.UP, yaw))
	b.add_obstacle(mi.position, _rot_aabb_size(s, yaw))
	return pos.y + s.y


func crate_stack(pos: Vector3, sizes: Array, color := "crate_olive", yaw := 0.0) -> void:
	var y := pos.y
	for i in sizes.size():
		var s: float = sizes[i]
		var jitter := Vector3(rng.randf_range(-0.08, 0.08), 0, rng.randf_range(-0.08, 0.08)) if i > 0 else Vector3.ZERO
		var cols := ["crate_olive", "crate_navy", "crate_orange"]
		var col: String = color if i == 0 else cols[(cols.find(color) + i) % 3]
		y = crate(Vector3(pos.x, y, pos.z) + jitter, s, col, yaw + rng.randf_range(-0.12, 0.12) * float(i > 0))


func container(pos: Vector3, yaw: float, mat: String) -> void:
	var L := 6.06
	var H := 2.59
	var W := 2.44
	var basis := Basis(Vector3.UP, yaw)
	var c := pos + Vector3(0, H * 0.5, 0)
	var xf := Transform3D(basis, c)
	batch.box(mat, xf, Vector3(L - 0.12, H - 0.16, W - 0.08), false)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			batch.box("metal_trim", xf * Transform3D(Basis(), Vector3(sx * (L * 0.5 - 0.08), 0, sz * (W * 0.5 - 0.08))), Vector3(0.18, H, 0.18))
		for sy in [-1.0, 1.0]:
			batch.box("metal_trim", xf * Transform3D(Basis(), Vector3(0, sy * (H * 0.5 - 0.08), sx * (W * 0.5 - 0.06))), Vector3(L, 0.16, 0.14))
			batch.box("metal_trim", xf * Transform3D(Basis(), Vector3(sx * (L * 0.5 - 0.06), sy * (H * 0.5 - 0.08), 0)), Vector3(0.14, 0.16, W))
	# Door end with locking bars.
	batch.box(mat, xf * Transform3D(Basis(), Vector3(L * 0.5 - 0.02, 0, 0)), Vector3(0.05, H - 0.3, W - 0.3))
	for i in 4:
		var z := -W * 0.36 + i * W * 0.24
		batch.cylinder("metal_bare", xf * Transform3D(Basis(), Vector3(L * 0.5 + 0.03, 0, z)), 0.025, 0.025, H - 0.3, 6)
	b.collider_box("metal", c, Vector3(L, H, W), basis)
	b.add_obstacle(c, _rot_aabb_size(Vector3(L, H, W), yaw))


func barrier(pos: Vector3, yaw: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var xf := Transform3D(basis, pos)
	batch.box("concrete_plain", xf * Transform3D(Basis(), Vector3(0, 0.2, 0)), Vector3(2.0, 0.4, 0.64), false)
	batch.box("concrete_plain", xf * Transform3D(Basis(), Vector3(0, 0.57, 0)), Vector3(2.0, 0.34, 0.42), false)
	batch.box("concrete_plain", xf * Transform3D(Basis(), Vector3(0, 0.86, 0)), Vector3(2.0, 0.24, 0.26), false)
	batch.box("hazard", xf * Transform3D(Basis(), Vector3(0, 0.82, 0)), Vector3(2.01, 0.12, 0.27), false)
	b.collider_box("concrete", pos + Vector3(0, 0.49, 0), Vector3(2.0, 0.98, 0.62), basis)
	b.add_obstacle(pos + Vector3(0, 0.49, 0), _rot_aabb_size(Vector3(2.0, 0.98, 0.62), yaw))


func pillar(pos: Vector3, h: float, mat := "concrete_plain") -> void:
	batch.box(mat, Transform3D(Basis(), pos + Vector3(0, h * 0.5, 0)), Vector3(0.9, h, 0.9))
	batch.box("metal_trim", Transform3D(Basis(), pos + Vector3(0, 0.15, 0)), Vector3(1.1, 0.3, 1.1))
	batch.box("emit_cyan", Transform3D(Basis(), pos + Vector3(0, 2.4, 0)), Vector3(0.94, 0.05, 0.94))
	b.collider_box("concrete", pos + Vector3(0, h * 0.5, 0), Vector3(0.9, h, 0.9))
	b.add_obstacle(pos + Vector3(0, h * 0.5, 0), Vector3(0.9, h, 0.9))


func barrels(pos: Vector3, count: int) -> void:
	var mats := ["paint_teal", "paint_red", "paint_amber", "paint_graphite"]
	for i in count:
		var a := TAU * i / count + rng.randf() * 0.4
		var p := pos + Vector3(cos(a), 0, sin(a)) * (0.0 if i == 0 else 0.68)
		var m: String = mats[rng.randi() % mats.size()]
		batch.cylinder(m, Transform3D(Basis(), p + Vector3(0, 0.45, 0)), 0.3, 0.3, 0.9, 14)
		for y in [0.2, 0.7]:
			batch.cylinder("metal_trim", Transform3D(Basis(), p + Vector3(0, y, 0)), 0.31, 0.31, 0.04, 14, false)
		b.collider_cylinder("metal", p + Vector3(0, 0.45, 0), 0.3, 0.9)


func lamp_post(pos: Vector3, yaw: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	batch.cylinder("metal_dark", Transform3D(Basis(), pos + Vector3(0, 2.75, 0)), 0.1, 0.07, 5.5, 8)
	batch.box("metal_dark", Transform3D(basis, pos + Vector3(0, 5.45, 0) + basis * Vector3(0.6, 0, 0)), Vector3(1.3, 0.08, 0.1))
	var head := pos + Vector3(0, 5.35, 0) + basis * Vector3(1.15, 0, 0)
	batch.box("metal_dark", Transform3D(basis, head), Vector3(0.7, 0.14, 0.32))
	batch.box("emit_warm", Transform3D(basis, head - Vector3(0, 0.075, 0)), Vector3(0.6, 0.02, 0.24))
	batch.box("concrete_plain", Transform3D(Basis(), pos + Vector3(0, 0.15, 0)), Vector3(0.45, 0.3, 0.45))
	b.collider_cylinder("metal", pos + Vector3(0, 2.75, 0), 0.14, 5.5)


func bench(pos: Vector3, yaw: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var xf := Transform3D(basis, pos)
	for i in 3:
		batch.box("wood", xf * Transform3D(Basis(), Vector3(0, 0.45, -0.15 + i * 0.15)), Vector3(1.8, 0.05, 0.12), false)
	for i in 2:
		batch.box("wood", xf * Transform3D(Basis(), Vector3(0, 0.62 + i * 0.16, 0.25)), Vector3(1.8, 0.1, 0.04), false)
	for sx in [-0.75, 0.75]:
		batch.box("metal_dark", xf * Transform3D(Basis(), Vector3(sx, 0.22, 0.0)), Vector3(0.06, 0.44, 0.45), false)
		batch.box("metal_dark", xf * Transform3D(Basis(), Vector3(sx, 0.6, 0.26)), Vector3(0.05, 0.4, 0.05), false)
	b.collider_box("concrete", pos + Vector3(0, 0.3, 0), Vector3(1.8, 0.6, 0.55), basis)


func server_rack_row(pos: Vector3, yaw: float, count: int) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var leds := ["emit_cyan", "emit_teal", "emit_amber", "emit_green"]
	var total := count * 0.84
	for i in count:
		var local := Vector3(-total * 0.5 + 0.42 + i * 0.84, 1.05, 0)
		var xf := Transform3D(basis, pos + basis * local)
		batch.box("metal_dark", xf, Vector3(0.8, 2.1, 1.0), false)
		batch.box("plastic_dark", xf * Transform3D(Basis(), Vector3(0, 0, 0.505)), Vector3(0.72, 1.95, 0.02), false)
		batch.box("plastic_dark", xf * Transform3D(Basis(), Vector3(0, 0, -0.505)), Vector3(0.72, 1.95, 0.02), false)
		for row in 9:
			for side in [-1.0, 1.0]:
				if rng.randf() < 0.75:
					var led: String = leds[rng.randi() % leds.size()]
					batch.box(led, xf * Transform3D(Basis(), Vector3(rng.randf_range(-0.28, 0.28), -0.8 + row * 0.2, side * 0.52)), Vector3(0.05, 0.025, 0.01), false)
	var size := Vector3(total, 2.1, 1.0)
	b.collider_box("metal", pos + Vector3(0, 1.05, 0), size, basis)
	b.add_obstacle(pos + Vector3(0, 1.05, 0), _rot_aabb_size(size, yaw))


func hydro_tank(pos: Vector3) -> void:
	var xf := func(y: float) -> Transform3D: return Transform3D(Basis(), pos + Vector3(0, y, 0))
	batch.cylinder("metal_trim", xf.call(0.18), 1.05, 1.0, 0.36, 20)
	batch.cylinder("emit_green", xf.call(1.4), 0.12, 0.12, 2.1, 8)
	for i in 5:
		batch.blob("foliage_light" if i % 2 == 0 else "foliage", pos + Vector3(rng.randf_range(-0.45, 0.45), 0.6 + i * 0.42, rng.randf_range(-0.45, 0.45)), Vector3(0.38, 0.3, 0.38), rng)
	batch.cylinder("glass_green", xf.call(1.5), 0.9, 0.9, 2.3, 24, false)
	for y in [0.75, 2.6]:
		batch.cylinder("metal_bare", xf.call(y), 0.93, 0.93, 0.08, 24, false)
	batch.cylinder("paint_white", xf.call(2.85), 1.0, 0.7, 0.3, 20)
	batch.cylinder("metal_dark", xf.call(3.2), 0.12, 0.12, 0.5, 8)
	b.collider_cylinder("metal", pos + Vector3(0, 1.5, 0), 0.98, 3.0)
	b.add_obstacle(pos + Vector3(0, 1.5, 0), Vector3(1.96, 3.0, 1.96))
	var l := OmniLight3D.new()
	l.light_color = Color(0.5, 1.0, 0.55)
	l.light_energy = 0.9
	l.omni_range = 5.0
	l.position = pos + Vector3(0, 1.6, 0)
	b.visuals.add_child(l)


func grow_bed(pos: Vector3, yaw: float, length: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var xf := Transform3D(basis, pos)
	batch.box("metal_panel_white", xf * Transform3D(Basis(), Vector3(0, 0.42, 0)), Vector3(length, 0.84, 1.1), false)
	batch.box("soil", xf * Transform3D(Basis(), Vector3(0, 0.85, 0)), Vector3(length - 0.1, 0.04, 1.0), false)
	batch.box("emit_teal", xf * Transform3D(Basis(), Vector3(0, 0.55, 0.56)), Vector3(length - 0.2, 0.04, 0.02), false)
	var plants := int(length / 0.45)
	for i in plants:
		for row in [-0.25, 0.25]:
			var lp := xf * Vector3(-length * 0.5 + 0.25 + i * 0.45, 1.0, row)
			batch.blob("foliage_light" if (i + int(row * 4)) % 3 == 0 else "foliage", lp, Vector3(0.2, 0.18, 0.2), rng)
	for sx in [-1.0, 1.0]:
		batch.box("metal_trim", xf * Transform3D(Basis(), Vector3(sx * (length * 0.5 - 0.1), 1.5, 0)), Vector3(0.05, 1.3, 0.05), false)
	batch.box("metal_dark", xf * Transform3D(Basis(), Vector3(0, 2.15, 0)), Vector3(length, 0.08, 0.3), false)
	batch.box("emit_green", xf * Transform3D(Basis(), Vector3(0, 2.1, 0)), Vector3(length - 0.2, 0.02, 0.22), false)
	b.collider_box("metal", pos + Vector3(0, 0.45, 0), Vector3(length, 0.9, 1.1), basis)


func lab_bench(pos: Vector3, yaw: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var xf := Transform3D(basis, pos)
	batch.box("paint_white", xf * Transform3D(Basis(), Vector3(0, 0.88, 0)), Vector3(2.4, 0.08, 0.9), false)
	batch.box("metal_panel_white", xf * Transform3D(Basis(), Vector3(0, 0.42, 0)), Vector3(2.3, 0.84, 0.82), false)
	batch.box("metal_dark", xf * Transform3D(Basis(), Vector3(-0.6, 1.2, -0.25)), Vector3(0.6, 0.55, 0.06), false)
	batch.box("emit_screen", xf * Transform3D(Basis(), Vector3(-0.6, 1.2, -0.215)), Vector3(0.54, 0.48, 0.01), false)
	batch.cylinder("glass_green", xf * Transform3D(Basis(), Vector3(0.5, 1.05, 0.1)), 0.08, 0.06, 0.26, 10)
	batch.cylinder("glass", xf * Transform3D(Basis(), Vector3(0.75, 1.02, -0.1)), 0.06, 0.06, 0.2, 10)
	batch.box("metal_trim", xf * Transform3D(Basis(), Vector3(0.2, 1.0, -0.2)), Vector3(0.3, 0.18, 0.3), false)
	b.collider_box("metal", pos + Vector3(0, 0.48, 0), Vector3(2.4, 0.96, 0.9), basis)
	b.add_obstacle(pos + Vector3(0, 0.48, 0), _rot_aabb_size(Vector3(2.4, 0.96, 0.9), yaw))


func generator(pos: Vector3, yaw: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var xf := Transform3D(basis, pos)
	batch.box("paint_amber", xf * Transform3D(Basis(), Vector3(0, 0.85, 0)), Vector3(2.4, 1.5, 1.4), false)
	batch.box("metal_dark", xf * Transform3D(Basis(), Vector3(0, 0.05, 0)), Vector3(2.6, 0.1, 1.6), false)
	for i in 5:
		batch.box("metal_dark", xf * Transform3D(Basis(), Vector3(-0.8 + i * 0.4, 0.95, 0.71)), Vector3(0.28, 0.9, 0.03), false)
	batch.box("hazard", xf * Transform3D(Basis(), Vector3(0, 1.55, 0)), Vector3(2.41, 0.12, 1.41), false)
	for sx in [-0.6, 0.6]:
		batch.cylinder("metal_bare", xf * Transform3D(Basis(), Vector3(sx, 1.95, -0.3)), 0.12, 0.12, 0.8, 10)
	batch.box("emit_red", xf * Transform3D(Basis(), Vector3(0.9, 1.3, 0.71)), Vector3(0.1, 0.1, 0.02), false)
	batch.box("emit_green", xf * Transform3D(Basis(), Vector3(1.05, 1.3, 0.71)), Vector3(0.1, 0.1, 0.02), false)
	b.collider_box("metal", pos + Vector3(0, 0.8, 0), Vector3(2.6, 1.6, 1.6), basis)
	b.add_obstacle(pos + Vector3(0, 0.8, 0), _rot_aabb_size(Vector3(2.6, 1.6, 1.6), yaw))


func truck(pos: Vector3, yaw: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var xf := Transform3D(basis, pos)
	var part := func(local: Vector3) -> Transform3D: return xf * Transform3D(Basis(), local)
	batch.box("metal_dark", part.call(Vector3(0, 0.75, 0)), Vector3(7.2, 0.35, 2.2), false)
	batch.box("paint_white", part.call(Vector3(2.65, 1.85, 0)), Vector3(1.9, 1.9, 2.3), false)
	batch.box("glass_dark", part.call(Vector3(3.61, 2.15, 0)), Vector3(0.04, 0.8, 2.0), false)
	for sz in [-1.0, 1.0]:
		batch.box("glass_dark", part.call(Vector3(2.9, 2.15, sz * 1.16)), Vector3(1.1, 0.7, 0.02), false)
	batch.box("paint_teal", part.call(Vector3(2.65, 1.2, 0)), Vector3(1.92, 0.12, 2.32), false)
	batch.box("corrugated_cream", part.call(Vector3(-1.0, 2.25, 0)), Vector3(4.9, 2.7, 2.4), false)
	batch.box("emit_amber", part.call(Vector3(3.61, 1.1, 0.85)), Vector3(0.03, 0.12, 0.3), false)
	batch.box("emit_amber", part.call(Vector3(3.61, 1.1, -0.85)), Vector3(0.03, 0.12, 0.3), false)
	for wx in [2.6, -0.6, -2.4]:
		for sz in [-1.0, 1.0]:
			batch.cylinder("rubber", xf * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(wx, 0.5, sz * 1.0)), 0.5, 0.5, 0.36, 14)
			batch.cylinder("metal_bare", xf * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(wx, 0.5, sz * 1.19)), 0.24, 0.24, 0.03, 10)
	b.collider_box("metal", xf * Vector3(-1.0, 1.8, 0), Vector3(4.9, 3.6, 2.4), basis)
	b.collider_box("metal", xf * Vector3(2.65, 1.45, 0), Vector3(1.9, 2.9, 2.3), basis)
	b.add_obstacle(xf * Vector3(0, 1.6, 0), _rot_aabb_size(Vector3(7.2, 3.2, 2.4), yaw))


func stall(pos: Vector3, yaw: float, fabric: String) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var xf := Transform3D(basis, pos)
	batch.box("wood", xf * Transform3D(Basis(), Vector3(0, 0.5, 0)), Vector3(2.6, 1.0, 0.8), false)
	batch.box("paint_white", xf * Transform3D(Basis(), Vector3(0, 1.02, 0)), Vector3(2.7, 0.05, 0.9), false)
	for sx in [-1.25, 1.25]:
		for sz in [-0.35, 1.2]:
			batch.cylinder("metal_dark", xf * Transform3D(Basis(), Vector3(sx, 1.25, sz)), 0.04, 0.04, 2.5, 6)
	batch.box(fabric, xf * Transform3D(Basis(Vector3.RIGHT, -0.25), Vector3(0, 2.45, 0.42)), Vector3(2.9, 0.05, 2.0), false)
	for i in 4:
		crate(pos + basis * Vector3(-0.9 + i * 0.6, 1.05, -0.1), 0.35, "crate_orange" if i % 2 == 0 else "crate_navy", yaw)
	b.collider_box("concrete", pos + Vector3(0, 0.5, 0), Vector3(2.6, 1.0, 0.8), basis)
	b.add_obstacle(pos + Vector3(0, 0.5, 0), _rot_aabb_size(Vector3(2.6, 1.0, 0.8), yaw))


func console(pos: Vector3, yaw: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var xf := Transform3D(basis, pos)
	batch.box("metal_dark", xf * Transform3D(Basis(), Vector3(0, 0.45, 0)), Vector3(2.2, 0.9, 0.8), false)
	batch.box("metal_trim", xf * Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0, 0.95, 0.1)), Vector3(2.2, 0.06, 0.7), false)
	for sx in [-0.62, 0.0, 0.62]:
		batch.box("metal_dark", xf * Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(sx, 1.45, -0.22)), Vector3(0.58, 0.42, 0.05), false)
		batch.box("emit_screen", xf * Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(sx, 1.45, -0.19)), Vector3(0.52, 0.36, 0.01), false)
	b.collider_box("metal", pos + Vector3(0, 0.5, 0), Vector3(2.2, 1.0, 0.8), basis)
	b.add_obstacle(pos + Vector3(0, 0.5, 0), _rot_aabb_size(Vector3(2.2, 1.0, 0.8), yaw))


func reactor(pos: Vector3) -> void:
	var xf := func(y: float) -> Transform3D: return Transform3D(Basis(), pos + Vector3(0, y, 0))
	batch.cylinder("metal_trim", xf.call(0.15), 3.0, 2.9, 0.3, 32)
	batch.cylinder("hazard", xf.call(0.31), 2.6, 2.6, 0.02, 32, true)
	batch.cylinder("paint_graphite", xf.call(0.9), 2.05, 1.95, 1.2, 28)
	batch.cylinder("emit_cyan", xf.call(3.25), 0.7, 0.7, 3.4, 16)
	batch.cylinder("glass", xf.call(3.25), 1.5, 1.5, 3.5, 32, false)
	for y in [2.2, 3.3, 4.4]:
		batch.cylinder("metal_bare", xf.call(y), 1.62, 1.62, 0.14, 32)
	for i in 6:
		var a := TAU * i / 6.0
		batch.box("metal_trim", Transform3D(Basis(Vector3.UP, -a), pos + Vector3(cos(a) * 1.55, 3.25, sin(a) * 1.55)), Vector3(0.12, 3.5, 0.12))
	batch.cylinder("paint_graphite", xf.call(5.5), 1.95, 2.05, 1.0, 28)
	batch.cylinder("hazard", xf.call(5.5), 2.07, 2.07, 0.3, 28, false)
	batch.cylinder("concrete_dark", xf.call(12.0), 1.3, 1.0, 12.0, 20)
	for y in [9.0, 13.0, 16.5]:
		batch.cylinder("emit_cyan", xf.call(y), 1.22 - (y - 6.0) * 0.024, 1.22 - (y - 6.0) * 0.024, 0.18, 20)
	batch.box("emit_red", xf.call(18.1), Vector3(0.3, 0.2, 0.3))
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		var dir := Vector3(cos(a), 0, sin(a))
		var out := pos + dir * 2.0
		batch.cylinder("paint_amber", Transform3D(Basis(Vector3.UP, -a) * Basis(Vector3(0, 0, 1), PI * 0.5), out + dir * 0.6 + Vector3(0, 4.6, 0)), 0.18, 0.18, 1.4, 10)
		batch.cylinder("paint_amber", Transform3D(Basis(), out + dir * 1.25 + Vector3(0, 2.4, 0)), 0.18, 0.18, 4.6, 10)
		batch.box("metal_trim", Transform3D(Basis(Vector3.UP, -a), out + dir * 1.25 + Vector3(0, 0.15, 0)), Vector3(0.5, 0.3, 0.5))
	b.collider_cylinder("metal", pos + Vector3(0, 0.15, 0), 3.0, 0.3)
	b.collider_cylinder("metal", pos + Vector3(0, 3.0, 0), 2.1, 6.0)
	b.add_obstacle(pos + Vector3(0, 3.0, 0), Vector3(4.2, 6.0, 4.2))
	var l := OmniLight3D.new()
	l.light_color = Color(0.35, 0.9, 1.0)
	l.light_energy = 2.6
	l.omni_range = 12.0
	l.position = pos + Vector3(0, 3.2, 0)
	b.visuals.add_child(l)
	Sfx.make_loop("amb_reactor_loop", b.visuals, pos + Vector3(0, 2, 0), -4.0, 32.0)


func holo_table(pos: Vector3) -> void:
	batch.cylinder("metal_dark", Transform3D(Basis(), pos + Vector3(0, 0.45, 0)), 0.9, 1.1, 0.9, 24)
	batch.cylinder("emit_teal", Transform3D(Basis(), pos + Vector3(0, 0.92, 0)), 0.8, 0.8, 0.04, 24)
	for r in [0.5, 0.75]:
		batch.cylinder("emit_cyan", Transform3D(Basis(), pos + Vector3(0, 1.6 + r, 0)), r, r, 0.015, 32, false)
	b.collider_cylinder("metal", pos + Vector3(0, 0.45, 0), 1.0, 0.9)
	b.add_obstacle(pos + Vector3(0, 0.5, 0), Vector3(2.0, 1.0, 2.0))


func planter_box(pos: Vector3, size: Vector2, with_tree := false, tree_scale := 1.0) -> void:
	var h := 0.65
	batch.box("concrete_dark", Transform3D(Basis(), pos + Vector3(0, h * 0.5, 0)), Vector3(size.x, h, size.y))
	batch.box("soil", Transform3D(Basis(), pos + Vector3(0, h - 0.03, 0)), Vector3(size.x - 0.24, 0.04, size.y - 0.24))
	var n := int(size.x * size.y * 0.8) + 2
	for i in n:
		var p := pos + Vector3(rng.randf_range(-size.x, size.x) * 0.38, h + 0.15, rng.randf_range(-size.y, size.y) * 0.38)
		batch.blob(["foliage", "foliage_dark", "foliage_light"][i % 3], p, Vector3(0.36, 0.3, 0.36) * rng.randf_range(0.7, 1.3), rng)
	b.collider_box("concrete", pos + Vector3(0, h * 0.5, 0), Vector3(size.x, h, size.y))
	if with_tree:
		tree(pos + Vector3(0, h, 0), tree_scale)


func round_planter(pos: Vector3, radius: float) -> void:
	batch.cylinder("concrete_dark", Transform3D(Basis(), pos + Vector3(0, 0.35, 0)), radius, radius, 0.7, 32)
	batch.cylinder("metal_trim", Transform3D(Basis(), pos + Vector3(0, 0.71, 0)), radius + 0.05, radius + 0.05, 0.04, 32, false)
	batch.cylinder("emit_teal", Transform3D(Basis(), pos + Vector3(0, 0.12, 0)), radius + 0.01, radius + 0.01, 0.04, 32, false)
	batch.cylinder("soil", Transform3D(Basis(), pos + Vector3(0, 0.68, 0)), radius - 0.12, radius - 0.12, 0.04, 32)
	for i in 14:
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.6, radius - 0.4)
		batch.blob(["foliage", "foliage_dark", "foliage_light"][i % 3], pos + Vector3(cos(a) * d, 0.85, sin(a) * d), Vector3(0.45, 0.35, 0.45) * rng.randf_range(0.7, 1.2), rng)
	b.collider_cylinder("concrete", pos + Vector3(0, 0.35, 0), radius, 0.7)
	tree(pos + Vector3(0, 0.7, 0), 1.7)


func tree(pos: Vector3, s := 1.0) -> void:
	var trunk_h := 2.8 * s
	batch.cylinder("bark", Transform3D(Basis(), pos + Vector3(0, trunk_h * 0.5, 0)), 0.2 * s, 0.11 * s, trunk_h, 9)
	var crown := pos + Vector3(0, trunk_h + 0.6 * s, 0)
	for i in 3:
		var a := TAU * i / 3.0 + rng.randf() * 0.5
		var dir := Vector3(cos(a), 1.2, sin(a)).normalized()
		var bp := pos + Vector3(0, trunk_h * 0.65, 0)
		var basis := Basis(Vector3.UP.cross(dir).normalized(), Vector3.UP.angle_to(dir)) if Vector3.UP.cross(dir).length() > 0.01 else Basis()
		batch.cylinder("bark", Transform3D(basis, bp + dir * 0.7 * s), 0.08 * s, 0.04 * s, 1.4 * s, 6)
	# Canopy: a dark inner mass plus many smaller, lighter clumps for a layered silhouette.
	batch.blob("foliage_dark", crown + Vector3(0, 0.3 * s, 0), Vector3(1.25, 0.95, 1.25) * s, rng, 6, 10)
	var clumps := 14
	for i in clumps:
		var a := TAU * i / clumps + rng.randf() * 0.5
		var tier := float(i % 3)
		var r := (1.05 - tier * 0.3) * s * rng.randf_range(0.85, 1.15)
		var p := crown + Vector3(cos(a) * r, (-0.35 + tier * 0.55) * s + rng.randf_range(-0.15, 0.15) * s, sin(a) * r)
		var mat: String = ["foliage", "foliage_light", "foliage"][i % 3]
		batch.blob(mat, p, Vector3(0.62, 0.5, 0.62) * s * rng.randf_range(0.8, 1.2), rng, 5, 9)
	batch.blob("foliage_light", crown + Vector3(0, 1.0 * s, 0), Vector3(0.7, 0.55, 0.7) * s, rng, 5, 9)
	b.collider_cylinder("concrete", pos + Vector3(0, 1.5 * s, 0), 0.24 * s, 3.0 * s)


func bush(pos: Vector3, s := 1.0) -> void:
	batch.blob("foliage_dark", pos + Vector3(0, 0.35 * s, 0), Vector3(0.7, 0.45, 0.7) * s, rng, 5, 9)
	for i in 6:
		var a := TAU * i / 6.0 + rng.randf() * 0.4
		var off := Vector3(cos(a), 0, sin(a)) * 0.45 * s
		batch.blob(["foliage", "foliage_light", "foliage"][i % 3], pos + off + Vector3(0, rng.randf_range(0.3, 0.55) * s, 0), Vector3(0.36, 0.3, 0.36) * s * rng.randf_range(0.8, 1.2), rng, 5, 8)


func pipe_run(start: Vector3, end: Vector3, radius: float, mat: String, supports := true) -> void:
	var d := end - start
	var length := d.length()
	var dir := d / length
	var axis := Vector3.UP.cross(dir)
	var basis := Basis(axis.normalized(), Vector3.UP.angle_to(dir)) if axis.length() > 0.001 else Basis()
	batch.cylinder(mat, Transform3D(basis, (start + end) * 0.5), radius, radius, length, 14, false)
	if supports:
		var n := int(length / 3.0)
		for i in n + 1:
			var p := start + dir * (length * i / maxf(n, 1))
			batch.cylinder("metal_trim", Transform3D(basis, p), radius + 0.04, radius + 0.04, 0.12, 14, false)
			if p.y > 0.3:
				batch.box("metal_dark", Transform3D(Basis(), Vector3(p.x, (p.y - radius) * 0.5, p.z)), Vector3(0.12, maxf(p.y - radius, 0.05), 0.12))


# ============================================================ areas
func _yard() -> void:
	container(P(4.0, 29.6), 0.0, "corrugated_orange")
	container(P(4.0, 29.6, 2.59), 0.08, "corrugated_teal")
	container(P(8.6, 31.8), PI * 0.5, "corrugated_graphite")
	container(P(23.8, 29.6), 0.0, "corrugated_teal")
	container(P(19.6, 31.8), PI * 0.5, "corrugated_red")
	container(P(24.0, 32.3), 0.0, "corrugated_cream")
	truck(P(7.8, 29.3), 0.0)
	crate_stack(P(11.2, 28.7), [1.25, 1.0], "crate_olive", 0.2)
	crate_stack(P(17.0, 28.8), [1.6, 1.0], "crate_navy", -0.1)
	crate(P(20.4, 28.9), 1.25, "crate_orange", 0.4)
	barrier(P(2.2, 28.5), 0.0)
	barrier(P(25.8, 28.5), 0.0)
	barrier(P(14.0, 28.4), 0.0)
	lamp_post(P(6.0, 30.8), PI)
	lamp_post(P(22.0, 30.8), 0.0)
	lamp_post(P(14.0, 32.8), PI * 0.5)
	for p in [Vector2(1.4, 30.4), Vector2(1.6, 32.3), Vector2(26.5, 30.6), Vector2(26.3, 32.5), Vector2(5.0, 32.6), Vector2(9.4, 32.7), Vector2(18.6, 32.7), Vector2(22.6, 32.8)]:
		tree(P(p.x, p.y), rng.randf_range(0.9, 1.25))
	for p in [Vector2(3.0, 32.6), Vector2(7.0, 32.7), Vector2(21.0, 32.6), Vector2(25.4, 31.6), Vector2(1.5, 31.4)]:
		bush(P(p.x, p.y), rng.randf_range(0.8, 1.2))
	Sfx.make_loop("amb_wind_loop", b.visuals, P(14.0, 30.0, 3.0), -10.0, 70.0)


func _a_main() -> void:
	crate_stack(P(4.3, 24.2), [1.6, 1.0], "crate_olive", 0.15)
	barrier(P(3.2, 16.6), PI * 0.5)
	crate(P(4.3, 14.8), 1.6, "crate_navy", -0.1)
	crate_stack(P(1.6, 18.4), [1.25], "crate_orange", 0.0)
	crate(P(2.1, 18.9), 1.25, "crate_olive", 0.3)
	planter_box(P(1.6, 15.2), Vector2(2.2, 2.2), true, 1.0)
	crate(P(1.5, 20.6, 2.4), 1.25, "crate_navy", 0.2)
	tree(P(1.6, 25.9), 1.15)
	bush(P(2.4, 25.3), 1.0)
	bush(P(1.3, 26.8), 0.9)
	barrels(P(4.4, 26.6), 4)


func _site_a() -> void:
	# Greenhouse frame around the plant zone.
	var corners := [P(3, 6), P(7, 6), P(3, 10), P(7, 10)]
	for c in corners:
		pillar(c, 7.4, "metal_panel_white")
	var roof_y := 7.4
	for pair in [[P(3, 6), P(7, 6)], [P(3, 10), P(7, 10)], [P(3, 6), P(3, 10)], [P(7, 6), P(7, 10)]]:
		var a: Vector3 = pair[0]
		var c2: Vector3 = pair[1]
		var mid := (a + c2) * 0.5 + Vector3(0, roof_y, 0)
		var size := Vector3(absf(c2.x - a.x) + 0.5, 0.45, absf(c2.z - a.z) + 0.5)
		batch.box("metal_panel_white", Transform3D(Basis(), mid), size, false)
	for i in 5:
		var x := P(3, 6).x + i * 4.0
		batch.box("metal_trim", Transform3D(Basis(), Vector3(x, roof_y + 0.3, P(5, 8).z)), Vector3(0.18, 0.18, 16.0), false)
		if i < 4:
			batch.box("glass", Transform3D(Basis(), Vector3(x + 2.0, roof_y + 0.3, P(5, 8).z)), Vector3(3.8, 0.03, 16.0), false)
	hydro_tank(P(3.4, 11.4))
	hydro_tank(P(6.6, 11.4))
	hydro_tank(P(7.7, 5.0))
	grow_bed(P(4.0, 7.3), 0.0, 3.0)
	grow_bed(P(5.9, 8.8), PI * 0.5, 3.0)
	crate_stack(P(3.7, 9.3), [1.6, 1.0], "crate_navy", 0.1)
	crate_stack(P(6.3, 6.6), [1.25, 1.25], "crate_olive", -0.2)
	lab_bench(P(1.55, 9.0), PI * 0.5)
	crate(P(2.6, 4.5, 2.4), 1.0, "crate_orange", 0.2)
	planter_box(P(8.4, 4.6), Vector2(1.4, 1.4), true, 0.7)
	bush(P(1.4, 11.6), 0.9)


func _server_hall() -> void:
	server_rack_row(P(12.0, 8.4), 0.0, 3)
	server_rack_row(P(16.0, 8.4), 0.0, 3)
	server_rack_row(P(11.5, 11.4), 0.0, 2)
	server_rack_row(P(16.5, 11.4), 0.0, 2)
	pillar(P(13.0, 10.0), 5.0, "metal_panel_teal")
	pillar(P(15.0, 10.0), 5.0, "metal_panel_teal")
	crate(P(12.6, 5.6), 1.25, "crate_navy", 0.3)
	crate(P(15.3, 6.8), 1.6, "crate_olive", -0.2)
	console(P(14.0, 4.35), PI)
	pipe_run(P(11.0, 8.15, 4.4), P(17.0, 8.15, 4.4), 0.16, "paint_teal", false)
	pipe_run(P(11.0, 8.3, 4.65), P(17.0, 8.3, 4.65), 0.1, "metal_bare", false)


func _atrium() -> void:
	round_planter(P(14.0, 17.0), 2.7)
	bench(P(12.3, 17.0), PI * 0.5)
	bench(P(15.7, 17.0), -PI * 0.5)
	crate(P(12.6, 13.5), 1.6, "crate_olive", 0.25)
	crate_stack(P(15.4, 20.4), [1.25, 1.0], "crate_orange", -0.15)
	barrier(P(12.8, 20.6), 0.0)
	planter_box(P(10.7, 20.6), Vector2(1.6, 1.6), true, 0.95)
	planter_box(P(17.3, 20.6), Vector2(1.6, 1.6), true, 0.95)
	lamp_post(P(10.4, 16.4), 0.0)
	lamp_post(P(17.6, 16.4), PI)
	for p in [Vector2(10.4, 12.4), Vector2(17.6, 12.4)]:
		bush(P(p.x, p.y), 1.0)


func _market() -> void:
	stall(P(12.5, 23.6), PI * 0.5, "fabric_teal")
	stall(P(15.5, 25.6), -PI * 0.5, "fabric_orange")
	crate(P(14.6, 23.2), 1.0, "crate_navy", 0.3)
	barrier(P(13.4, 26.8), 0.0)
	for z in [22.6, 24.6, 26.6]:
		pipe_run(P(12.0, z, 4.4), P(16.0, z, 4.4), 0.015, "metal_dark", false)
		for i in 7:
			var x := 12.25 + i * 0.58
			var sag := sin(PI * (x - 12.0) / 4.0) * 0.35
			batch.box("emit_warm", Transform3D(Basis(), P(x, z, 4.3 - sag)), Vector3(0.14, 0.18, 0.14))


func _b_main() -> void:
	pipe_run(P(26.85, 13.0, 0.75), P(26.85, 20.0, 0.75), 0.5, "paint_teal")
	pipe_run(P(26.85, 13.0, 1.85), P(26.85, 20.0, 1.85), 0.32, "metal_bare", false)
	b.collider_box("metal", P(26.85, 16.5, 1.2), Vector3(1.2, 2.4, 28.0))
	b.add_obstacle(P(26.85, 16.5, 1.2), Vector3(1.2, 2.4, 28.0))
	container(P(23.9, 15.8), PI * 0.5, "corrugated_graphite")
	generator(P(25.0, 24.6), 0.0)
	barrels(P(23.6, 19.4), 5)
	barrier(P(24.6, 13.7), 0.0)
	crate_stack(P(25.6, 18.2), [1.25, 1.0], "crate_orange", 0.2)
	tree(P(26.0, 26.0), 1.1)
	bush(P(25.4, 25.4), 0.9)
	crate(P(25.6, 20.7, 2.4), 1.25, "crate_olive", -0.2)


func _site_b() -> void:
	reactor(P(23.0, 8.0))
	generator(P(20.4, 5.2), PI * 0.5)
	generator(P(25.4, 11.3), 0.0)
	crate_stack(P(21.2, 10.6), [1.6, 1.0], "crate_navy", 0.1)
	crate_stack(P(24.9, 6.3), [1.25, 1.25], "crate_olive", 0.2)
	barrels(P(19.6, 11.6), 4)
	crate(P(25.4, 4.5, 2.4), 1.0, "crate_orange", -0.3)
	pipe_run(P(23.0, 8.0, 6.2) + Vector3(2.0, 0, 0), P(27.0, 8.0, 6.2), 0.3, "paint_amber", false)
	pipe_run(P(23.0, 8.0, 7.0) - Vector3(2.0, 0, 0), P(19.0, 8.0, 7.0), 0.24, "metal_bare", false)


func _command_deck() -> void:
	holo_table(P(14.0, 3.4))
	console(P(11.0, 1.2), PI)
	console(P(17.0, 1.2), PI)
	planter_box(P(10.5, 3.5), Vector2(1.0, 1.0), false)
	planter_box(P(17.5, 3.5), Vector2(1.0, 1.0), false)
	var l := OmniLight3D.new()
	l.light_color = Color(0.3, 0.95, 0.9)
	l.light_energy = 1.2
	l.omni_range = 9.0
	l.position = P(14.0, 3.4, 2.5)
	b.visuals.add_child(l)


func _tunnels() -> void:
	crate(P(6.8, 17.4), 1.25, "crate_navy", 0.15)
	crate(P(21.4, 18.6), 1.25, "crate_olive", -0.2)
	barrels(P(20.0, 17.3), 3)
	crate(P(7.2, 2.6), 1.0, "crate_orange", 0.3)
	crate(P(20.8, 3.4), 1.0, "crate_navy", -0.2)


# ============================================================ grass
func _grass_scatter() -> void:
	var density := 16.0 * Settings.foliage_density
	var points := []
	for r in b.rows:
		for c in b.cols:
			if b.cell(c, r) != "g":
				continue
			var n := int(density * rng.randf_range(0.8, 1.2))
			for i in n:
				var p := b.P(c + rng.randf(), r + rng.randf())
				var blocked := false
				for a in b.obstacles:
					if a.grow(0.2).has_point(p + Vector3(0, 0.3, 0)):
						blocked = true
						break
				if not blocked:
					points.append(p)
	if points.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 2:
		var a := PI * 0.5 * k + 0.4
		var d := Vector3(cos(a), 0, sin(a)) * 0.3
		var quad := [-d, d, d + Vector3(0, 0.42, 0), -d + Vector3(0, 0.42, 0)]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_uv(uvs[idx])
			st.add_vertex(quad[idx])
	var mesh := st.commit()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = points.size()
	for i in points.size():
		var s := rng.randf_range(0.6, 1.15)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.2), s))
		mm.set_instance_transform(i, Transform3D(basis, points[i]))
		var tint := Color(1, 1, 1).lerp(Color(1.25, 1.15, 0.7), rng.randf() * 0.5)
		mm.set_instance_color(i, tint)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = b.matlib.get_mat("grass_card")
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 70.0
	mmi.name = "GrassTufts"
	b.visuals.add_child(mmi)
