class_name BotModel
extends Node3D
## Procedural armoured operative used by bots: walk cycle, aim posture, recoil, reload,
## hit flinch, directional death fall, team accents and reveal (x-ray) overlay.

var team_color := Color.WHITE
var hips: Node3D
var spine: Node3D
var chest: Node3D
var head: Node3D
var thigh_l: Node3D
var thigh_r: Node3D
var knee_l: Node3D
var knee_r: Node3D
var gun: Node3D
var muzzle: Node3D
var arm_l: Node3D
var device_mesh: Node3D
var marker: MeshInstance3D
var name_label: Label3D

var _meshes: Array[MeshInstance3D] = []
var _accent: StandardMaterial3D
var _overlay: ShaderMaterial
var _phase := 0.0
var _flinch := Vector3.ZERO
var _flinch_v := Vector3.ZERO
var _kick := 0.0
var _dead_t := -1.0
var _fall := Vector2.ZERO
var _reload := 0.0
var _flash := 0.0
var _revealed := false

static var _shared := {}


static func _mat(key: String, color: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	if _shared.has(key):
		return _shared[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	_shared[key] = m
	return m


func build(color: Color, ally: bool, display_name: String) -> void:
	team_color = color
	var suit := _mat("suit", Color(0.16, 0.18, 0.2), 0.9)
	var plate := _mat("plate_ally" if ally else "plate_enemy", Color(0.24, 0.32, 0.34) if ally else Color(0.34, 0.24, 0.22), 0.45, 0.5)
	var dark := _mat("dark", Color(0.06, 0.065, 0.07), 0.6, 0.3)
	var boot := _mat("boot", Color(0.09, 0.09, 0.1), 0.85)
	var gunm := _mat("gunm", Color(0.12, 0.13, 0.14), 0.4, 0.8)
	_accent = StandardMaterial3D.new()
	_accent.albedo_color = color * 0.4
	_accent.emission_enabled = true
	_accent.emission = color
	_accent.emission_energy_multiplier = 2.2
	hips = _node(self, Vector3(0, 0.95, 0))
	_box(hips, Vector3(0.36, 0.18, 0.24), suit, Vector3(0, 0, 0))
	_box(hips, Vector3(0.4, 0.06, 0.26), dark, Vector3(0, 0.08, 0))
	for sx in [-1.0, 1.0]:
		_box(hips, Vector3(0.08, 0.12, 0.08), dark, Vector3(sx * 0.19, 0.0, -0.06))
	thigh_l = _node(hips, Vector3(-0.11, -0.06, 0))
	thigh_r = _node(hips, Vector3(0.11, -0.06, 0))
	for thigh in [thigh_l, thigh_r]:
		_capsule(thigh, 0.085, 0.48, suit, Vector3(0, -0.22, 0))
		_box(thigh, Vector3(0.1, 0.16, 0.06), plate, Vector3(0, -0.18, -0.08))
	knee_l = _node(thigh_l, Vector3(0, -0.44, 0))
	knee_r = _node(thigh_r, Vector3(0, -0.44, 0))
	for knee in [knee_l, knee_r]:
		_capsule(knee, 0.075, 0.46, suit, Vector3(0, -0.21, 0))
		_box(knee, Vector3(0.11, 0.1, 0.06), plate, Vector3(0, -0.02, -0.07))
		_box(knee, Vector3(0.12, 0.09, 0.26), boot, Vector3(0, -0.44, -0.04))
	spine = _node(hips, Vector3(0, 0.08, 0))
	chest = _node(spine, Vector3(0, 0.27, 0))
	_box(chest, Vector3(0.42, 0.5, 0.25), suit, Vector3(0, 0, 0))
	_box(chest, Vector3(0.38, 0.34, 0.07), plate, Vector3(0, 0.03, -0.14))
	_box(chest, Vector3(0.3, 0.04, 0.02), _accent, Vector3(0, 0.12, -0.18))
	_box(chest, Vector3(0.34, 0.4, 0.17), dark, Vector3(0, 0.02, 0.2))
	_box(chest, Vector3(0.05, 0.3, 0.02), _accent, Vector3(0.12, 0.02, 0.29))
	for sx in [-1.0, 1.0]:
		_box(chest, Vector3(0.15, 0.1, 0.22), plate, Vector3(sx * 0.27, 0.2, 0))
		_box(chest, Vector3(0.08, 0.1, 0.06), dark, Vector3(sx * 0.12, -0.18, -0.15))
	device_mesh = _node(chest, Vector3(0, 0.05, 0.32))
	var dev := _cyl(device_mesh, 0.09, 0.28, _mat("device", Color(0.2, 0.22, 0.25), 0.4, 0.7), Vector3.ZERO)
	dev.rotation.x = PI * 0.5
	var dev_glow := StandardMaterial3D.new()
	dev_glow.emission_enabled = true
	dev_glow.emission = GameConst.COLOR_AMBER
	dev_glow.emission_energy_multiplier = 3.0
	var dev_ring := _cyl(device_mesh, 0.095, 0.05, dev_glow, Vector3(0, 0, 0))
	dev_ring.rotation.x = PI * 0.5
	device_mesh.visible = false
	head = _node(chest, Vector3(0, 0.37, 0))
	_capsule(head, 0.075, 0.16, suit, Vector3(0, -0.08, 0))
	var helm := _sphere(head, 0.15, _mat("helm_ally" if ally else "helm_enemy", Color(0.2, 0.26, 0.28) if ally else Color(0.28, 0.2, 0.19), 0.4, 0.4), Vector3(0, 0.03, 0))
	helm.scale = Vector3(1.0, 1.05, 1.1)
	_box(head, Vector3(0.24, 0.07, 0.06), _accent, Vector3(0, 0.03, -0.14))
	_box(head, Vector3(0.18, 0.08, 0.06), dark, Vector3(0, -0.06, -0.12))
	_box(head, Vector3(0.04, 0.12, 0.04), dark, Vector3(0.15, 0.04, 0.0))
	# Arms in a two-handed rifle hold.
	var arm_r := _node(chest, Vector3(0.24, 0.16, 0))
	_limb(arm_r, Vector3.ZERO, Vector3(0.02, -0.22, -0.12), 0.06, suit)
	_limb(arm_r, Vector3(0.02, -0.22, -0.12), Vector3(-0.08, -0.2, -0.36), 0.05, suit)
	_box(arm_r, Vector3(0.08, 0.08, 0.1), boot, Vector3(-0.08, -0.2, -0.38))
	arm_l = _node(chest, Vector3(-0.24, 0.16, 0))
	_limb(arm_l, Vector3.ZERO, Vector3(-0.02, -0.2, -0.2), 0.06, suit)
	_limb(arm_l, Vector3(-0.02, -0.2, -0.2), Vector3(0.12, -0.12, -0.52), 0.05, suit)
	_box(arm_l, Vector3(0.08, 0.08, 0.1), boot, Vector3(0.13, -0.12, -0.54))
	gun = _node(chest, Vector3(0.08, -0.02, -0.32))
	_box(gun, Vector3(0.06, 0.09, 0.42), gunm, Vector3(0, 0, -0.08))
	_box(gun, Vector3(0.065, 0.07, 0.24), dark, Vector3(0, 0.0, -0.38))
	var barrel := _cyl(gun, 0.014, 0.2, gunm, Vector3(0, 0.0, -0.58))
	barrel.rotation.x = PI * 0.5
	_box(gun, Vector3(0.04, 0.14, 0.07), dark, Vector3(0, -0.11, -0.14))
	_box(gun, Vector3(0.04, 0.05, 0.08), dark, Vector3(0, 0.07, -0.1))
	_box(gun, Vector3(0.045, 0.08, 0.18), dark, Vector3(0, -0.01, 0.2))
	_box(gun, Vector3(0.068, 0.01, 0.2), _accent, Vector3(0, -0.03, -0.38))
	muzzle = _node(gun, Vector3(0, 0, -0.7))
	# Marker above the head (allies always; enemies only while revealed).
	marker = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.045, 0.045)
	marker.mesh = q
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.no_depth_test = true
	mm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mm.fixed_size = true
	mm.albedo_texture = _diamond_texture()
	mm.albedo_color = color
	mm.render_priority = 5
	marker.material_override = mm
	marker.position = Vector3(0, 2.15, 0)
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(marker)
	marker.visible = ally
	if ally:
		name_label = Label3D.new()
		name_label.text = display_name.to_upper()
		if ResourceLoader.exists("res://assets/fonts/BarlowSemiCondensed-SemiBold.ttf"):
			name_label.font = load("res://assets/fonts/BarlowSemiCondensed-SemiBold.ttf")
		name_label.font_size = 40
		name_label.pixel_size = 0.0022
		name_label.fixed_size = true
		name_label.no_depth_test = true
		name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_label.modulate = Color(color.r, color.g, color.b, 0.85)
		name_label.outline_size = 8
		name_label.outline_modulate = Color(0, 0, 0, 0.6)
		name_label.position = Vector3(0, 2.32, 0)
		name_label.render_priority = 6
		add_child(name_label)
	_overlay = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_back, blend_add;
uniform vec4 color : source_color = vec4(1.0, 0.3, 0.2, 1.0);
void fragment() {
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 1.5);
	ALBEDO = color.rgb * (0.25 + rim * 1.6);
	ALPHA = 0.85;
}
"""
	_overlay.shader = sh
	_overlay.set_shader_parameter("color", Color(1.0, 0.32, 0.22))


func _diamond_texture() -> Texture2D:
	if _shared.has("diamond"):
		return _shared["diamond"]
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := absf(x - 31.5) + absf(y - 31.5) * 1.3
			var a := clampf((30.0 - d) / 2.0, 0.0, 1.0)
			var inner := clampf((22.0 - d) / 2.0, 0.0, 1.0)
			var c := Color(1, 1, 1, a) if inner < 0.5 else Color(1, 1, 1, a * 0.55)
			img.set_pixel(x, y, c)
	var t := ImageTexture.create_from_image(img)
	_shared["diamond"] = t
	return t


# ------------------------------------------------------------------ building helpers
func _node(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _register(mi: MeshInstance3D) -> MeshInstance3D:
	_meshes.append(mi)
	return mi


func _box(parent: Node3D, size: Vector3, m: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return _register(mi)


func _capsule(parent: Node3D, r: float, h: float, m: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = h
	cm.radial_segments = 10
	cm.rings = 3
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return _register(mi)


func _cyl(parent: Node3D, r: float, h: float, m: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 10
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return _register(mi)


func _sphere(parent: Node3D, r: float, m: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 14
	sm.rings = 8
	mi.mesh = sm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return _register(mi)


func _limb(parent: Node3D, a: Vector3, b: Vector3, r: float, m: Material) -> void:
	var mi := _capsule(parent, r, a.distance_to(b) + r * 2.0, m, (a + b) * 0.5)
	var up := (b - a).normalized()
	var axis := Vector3.UP.cross(up)
	if axis.length() > 0.0001:
		mi.basis = Basis(axis.normalized(), Vector3.UP.angle_to(up))


# ------------------------------------------------------------------ animation
func reset_pose() -> void:
	_dead_t = -1.0
	rotation = Vector3.ZERO
	position = Vector3.ZERO
	_flinch = Vector3.ZERO
	_flinch_v = Vector3.ZERO
	_reload = 0.0
	gun.visible = true
	visible = true
	set_revealed(false)


func set_carrying(on: bool) -> void:
	device_mesh.visible = on


func set_revealed(on: bool) -> void:
	if on == _revealed:
		return
	_revealed = on
	for mi in _meshes:
		mi.material_overlay = _overlay if on else null


func show_marker(on: bool, color: Color) -> void:
	marker.visible = on
	(marker.material_override as StandardMaterial3D).albedo_color = color


func fire_kick() -> void:
	_kick = 1.0


func start_reload(duration: float) -> void:
	_reload = duration


func flinch(local_dir: Vector3, headshot: bool) -> void:
	var s := 2.6 if headshot else 1.6
	_flinch_v += Vector3(-local_dir.z * s, 0, local_dir.x * s) + Vector3(0, randf_range(-1, 1), 0)
	_flash = 1.0


func die(local_dir: Vector3) -> void:
	_dead_t = 0.0
	if absf(local_dir.x) > absf(local_dir.z):
		_fall = Vector2(0, -signf(local_dir.x))
	else:
		_fall = Vector2(signf(local_dir.z) if local_dir.z != 0.0 else 1.0, 0)
	marker.visible = false
	if name_label:
		name_label.visible = false
	set_revealed(false)


func animate(delta: float, speed: float, aim_pitch: float, moving_back: bool) -> void:
	var steps := clampi(ceili(delta / 0.005), 1, 40)
	var h := delta / steps
	for _i in steps:
		_flinch_v += (-_flinch * 160.0 - _flinch_v * 16.0) * h
		_flinch += _flinch_v * h * 0.04
	_kick = maxf(0.0, _kick - delta * 12.0)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 6.0)
		_accent.emission_energy_multiplier = 2.2 + _flash * 6.0
	if _dead_t >= 0.0:
		_dead_t += delta
		var k := ease(clampf(_dead_t / 0.55, 0.0, 1.0), 0.5)
		rotation.x = _fall.x * PI * 0.5 * k
		rotation.z = _fall.y * PI * 0.5 * k
		position.y = 0.12 * k
		thigh_l.rotation.x = -0.6 * k
		thigh_r.rotation.x = -0.3 * k
		knee_l.rotation.x = 0.9 * k
		knee_r.rotation.x = 0.5 * k
		chest.rotation.x = 0.3 * k
		head.rotation.x = 0.4 * k
		if _dead_t > 0.3:
			gun.visible = false
		return
	var k_move := clampf(speed / 5.0, 0.0, 1.2)
	_phase += delta * speed * 2.1 * (-1.0 if moving_back else 1.0)
	var sw := sin(_phase) * 0.62 * k_move
	thigh_l.rotation.x = sw
	thigh_r.rotation.x = -sw
	knee_l.rotation.x = maxf(0.0, -sin(_phase)) * 0.95 * k_move
	knee_r.rotation.x = maxf(0.0, sin(_phase)) * 0.95 * k_move
	hips.position.y = 0.95 - absf(cos(_phase)) * 0.045 * k_move
	spine.rotation.y = sin(_phase) * 0.08 * k_move
	spine.rotation.x = clampf(aim_pitch, -1.0, 1.0) * 0.55 + _flinch.x
	spine.rotation.z = _flinch.z
	head.rotation.x = clampf(aim_pitch, -1.0, 1.0) * 0.35
	gun.position.z = -0.32 + _kick * 0.06
	gun.rotation.x = _kick * 0.12
	if _reload > 0.0:
		_reload -= delta
		gun.rotation.z = 0.6 * sin(clampf(_reload, 0, 1.6) / 1.6 * PI)
		arm_l.rotation.x = 0.5 * sin(clampf(_reload, 0, 1.6) / 1.6 * PI)
	else:
		gun.rotation.z = 0.0
		arm_l.rotation.x = 0.0
