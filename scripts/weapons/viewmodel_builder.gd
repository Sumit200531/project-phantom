class_name ViewmodelBuilder
## Builds the first-person weapon models (original designs) with gloved hands and sleeves.
## Each rig exposes named nodes the WeaponManager animates:
##   Gun, Gun/Mag, Gun/Bolt, Gun/HandL, Gun/Muzzle, Gun/Ejector, Gun/Sight

static var _mats := {}


static func mat(key: String) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	match key:
		"polymer":
			m.albedo_color = Color(0.085, 0.095, 0.105); m.roughness = 0.62; m.metallic = 0.05
		"metal":
			m.albedo_color = Color(0.2, 0.215, 0.235); m.roughness = 0.32; m.metallic = 0.85
		"metal_light":
			m.albedo_color = Color(0.46, 0.48, 0.5); m.roughness = 0.28; m.metallic = 0.9
		"black":
			m.albedo_color = Color(0.02, 0.02, 0.025); m.roughness = 0.7
		"teal":
			m.albedo_color = Color(0.12, 0.58, 0.58); m.roughness = 0.4; m.metallic = 0.3
		"amber":
			m.albedo_color = Color(1.0, 0.62, 0.16); m.roughness = 0.4; m.metallic = 0.2
		"glove":
			m.albedo_color = Color(0.13, 0.135, 0.14); m.roughness = 0.82
		"glove_pad":
			m.albedo_color = Color(0.24, 0.25, 0.26); m.roughness = 0.7
		"sleeve":
			m.albedo_color = Color(0.2, 0.25, 0.27); m.roughness = 0.9
		"sleeve_band":
			m.albedo_color = Color(0.1, 0.4, 0.42); m.roughness = 0.5
			m.emission_enabled = true; m.emission = Color(0.2, 0.9, 0.85); m.emission_energy_multiplier = 0.6
		"rubber":
			m.albedo_color = Color(0.04, 0.04, 0.045); m.roughness = 0.95
		"lens":
			m.albedo_color = Color(0.3, 0.75, 0.8, 0.25); m.roughness = 0.05; m.metallic = 0.4
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		"reticle":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(1.0, 0.25, 0.18)
			m.no_depth_test = true
			m.render_priority = 10
		"brass":
			m.albedo_color = Color(0.85, 0.62, 0.25); m.roughness = 0.3; m.metallic = 0.9
	_mats[key] = m
	return m


static func part(parent: Node3D, mesh_kind: String, size: Vector3, material: String, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh: Mesh
	match mesh_kind:
		"box":
			var bm := BoxMesh.new()
			bm.size = size
			mesh = bm
		"cyl":  # size = (radius_top, length, radius_bottom); axis along local Y
			var cm := CylinderMesh.new()
			cm.top_radius = size.x
			cm.bottom_radius = size.z
			cm.height = size.y
			cm.radial_segments = 16
			cm.rings = 1
			mesh = cm
		"zcyl":  # cylinder along -Z (barrels): size = (radius, length, radius)
			var zc := CylinderMesh.new()
			zc.top_radius = size.x
			zc.bottom_radius = size.z
			zc.height = size.y
			zc.radial_segments = 18
			zc.rings = 1
			mesh = zc
			rot += Vector3(PI * 0.5, 0, 0)
		"sphere":
			var sm := SphereMesh.new()
			sm.radius = size.x
			sm.height = size.x * 2.0
			sm.radial_segments = 12
			sm.rings = 6
			mesh = sm
		"capsule":
			var cp := CapsuleMesh.new()
			cp.radius = size.x
			cp.height = size.y
			cp.radial_segments = 12
			cp.rings = 4
			mesh = cp
	mi.mesh = mesh
	mi.material_override = mat(material)
	mi.position = pos
	mi.rotation = rot
	mi.layers = GameConst.VIS_VIEWMODEL
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func node(parent: Node3D, n: String, pos: Vector3) -> Node3D:
	var nd := Node3D.new()
	nd.name = n
	nd.position = pos
	parent.add_child(nd)
	return nd


## A limb segment (cylinder) spanning two points in parent space.
static func limb(parent: Node3D, a: Vector3, b2: Vector3, r_a: float, r_b: float, material: String) -> MeshInstance3D:
	var d := b2 - a
	var mi := part(parent, "cyl", Vector3(r_b, d.length(), r_a), material, (a + b2) * 0.5)
	var up := d.normalized()
	var axis := Vector3.UP.cross(up)
	if axis.length() > 0.0001:
		mi.basis = Basis(axis.normalized(), Vector3.UP.angle_to(up))
	return mi


static func build(weapon_id: String) -> Node3D:
	var rig := Node3D.new()
	rig.name = "Rig_" + weapon_id
	var gun := node(rig, "Gun", Vector3.ZERO)
	match weapon_id:
		"lancet": _rifle(gun)
		"hornet": _smg(gun)
		"kite": _pistol(gun)
	return rig


# ------------------------------------------------------------------ hands
static func _right_hand(gun: Node3D, grip: Vector3, grip_tilt: float) -> void:
	var h := node(gun, "HandR", grip)
	h.rotation.x = grip_tilt
	part(h, "box", Vector3(0.052, 0.088, 0.07), "glove", Vector3(0.0, -0.005, 0.03))
	part(h, "box", Vector3(0.058, 0.07, 0.03), "glove", Vector3(0.0, -0.01, -0.03))
	for i in 3:
		part(h, "cyl", Vector3(0.0105, 0.058, 0.0105), "glove", Vector3(0.0, 0.016 - i * 0.022, -0.036), Vector3(0, 0, PI * 0.5))
	part(h, "box", Vector3(0.05, 0.014, 0.05), "glove_pad", Vector3(0.0, 0.03, 0.03))
	part(h, "capsule", Vector3(0.011, 0.07, 0), "glove", Vector3(-0.03, 0.035, -0.005), Vector3(-1.35, 0, 0.2))
	part(h, "capsule", Vector3(0.0105, 0.06, 0), "glove", Vector3(0.025, 0.045, -0.06), Vector3(-1.5, 0, 0))
	var wrist := Vector3(0.012, -0.02, 0.07)
	var elbow := Vector3(0.11, -0.2, 0.36)
	limb(h, wrist, elbow, 0.031, 0.04, "glove")
	part(h, "cyl", Vector3(0.037, 0.03, 0.037), "glove_pad", wrist + (elbow - wrist) * 0.12, Vector3(-0.95, 0, -0.3))
	var sleeve_a := wrist + (elbow - wrist) * 0.45
	limb(h, sleeve_a, elbow + (elbow - wrist) * 0.6, 0.046, 0.056, "sleeve")
	var band := limb(h, sleeve_a, sleeve_a + (elbow - wrist).normalized() * 0.02, 0.048, 0.048, "sleeve_band")
	band.scale = Vector3(1.0, 1.0, 1.0)


static func _left_hand(gun: Node3D, at: Vector3, pistol := false) -> void:
	var h := node(gun, "HandL", at)
	h.set_meta("base", at)
	if pistol:
		part(h, "box", Vector3(0.05, 0.08, 0.07), "glove", Vector3(-0.02, -0.01, 0.0), Vector3(0, 0, 0.25))
		for i in 3:
			part(h, "cyl", Vector3(0.0105, 0.055, 0.0105), "glove", Vector3(0.004, -0.01 - i * 0.02, -0.035), Vector3(0, 0, PI * 0.5))
		part(h, "capsule", Vector3(0.011, 0.065, 0), "glove", Vector3(-0.004, 0.035, -0.02), Vector3(-1.4, 0, 0))
	else:
		part(h, "box", Vector3(0.03, 0.08, 0.085), "glove", Vector3(-0.03, -0.012, 0.0))
		for i in 4:
			part(h, "cyl", Vector3(0.0102, 0.05, 0.0102), "glove", Vector3(0.0, 0.004 - i * 0.02, -0.03 + 0.0 * i), Vector3(0, PI * 0.5, PI * 0.5))
		part(h, "box", Vector3(0.022, 0.07, 0.07), "glove", Vector3(0.022, -0.012, 0.0))
		part(h, "capsule", Vector3(0.011, 0.07, 0), "glove", Vector3(-0.01, 0.045, -0.01), Vector3(-1.4, 0.3, 0))
	var wrist := Vector3(-0.035, -0.035, 0.035)
	var elbow := Vector3(-0.2, -0.24, 0.24)
	limb(h, wrist, elbow, 0.031, 0.04, "glove")
	part(h, "cyl", Vector3(0.037, 0.03, 0.037), "glove_pad", wrist + (elbow - wrist) * 0.12, Vector3(-0.7, 0, 0.7))
	var sleeve_a := wrist + (elbow - wrist) * 0.45
	limb(h, sleeve_a, elbow + (elbow - wrist) * 0.7, 0.046, 0.056, "sleeve")
	limb(h, sleeve_a, sleeve_a + (elbow - wrist).normalized() * 0.02, 0.048, 0.048, "sleeve_band")


# ------------------------------------------------------------------ Lancet rifle
static func _rifle(g: Node3D) -> void:
	part(g, "box", Vector3(0.056, 0.064, 0.36), "metal", Vector3(0, 0.035, -0.06))
	part(g, "box", Vector3(0.04, 0.012, 0.36), "metal", Vector3(0, 0.072, -0.06))
	part(g, "box", Vector3(0.05, 0.05, 0.22), "polymer", Vector3(0, -0.02, -0.01))
	part(g, "box", Vector3(0.046, 0.045, 0.09), "polymer", Vector3(0, -0.058, -0.115))
	part(g, "box", Vector3(0.066, 0.072, 0.32), "polymer", Vector3(0, 0.032, -0.4))
	part(g, "box", Vector3(0.068, 0.008, 0.28), "teal", Vector3(0, 0.0, -0.4))
	for side in [-1.0, 1.0]:
		for i in 3:
			part(g, "box", Vector3(0.004, 0.02, 0.055), "black", Vector3(side * 0.0335, 0.04, -0.31 - i * 0.075))
	part(g, "box", Vector3(0.024, 0.01, 0.62), "metal", Vector3(0, 0.083, -0.22))
	for i in 22:
		part(g, "box", Vector3(0.027, 0.005, 0.009), "metal_light", Vector3(0, 0.089, 0.07 - i * 0.026))
	part(g, "zcyl", Vector3(0.0115, 0.2, 0.0115), "metal", Vector3(0, 0.032, -0.66))
	part(g, "zcyl", Vector3(0.019, 0.07, 0.019), "polymer", Vector3(0, 0.032, -0.785))
	for z in [-0.77, -0.795]:
		part(g, "box", Vector3(0.042, 0.007, 0.012), "metal", Vector3(0, 0.032, z))
	part(g, "box", Vector3(0.03, 0.032, 0.034), "metal", Vector3(0, 0.058, -0.575))
	# Open-frame red-dot optic (you look through the window when aiming)
	part(g, "box", Vector3(0.036, 0.018, 0.09), "metal", Vector3(0, 0.098, -0.13))
	for sx in [-1.0, 1.0]:
		part(g, "box", Vector3(0.004, 0.046, 0.085), "polymer", Vector3(sx * 0.021, 0.13, -0.135))
		part(g, "box", Vector3(0.005, 0.052, 0.012), "polymer", Vector3(sx * 0.022, 0.13, -0.18))
	part(g, "box", Vector3(0.046, 0.005, 0.085), "polymer", Vector3(0, 0.1535, -0.135))
	part(g, "box", Vector3(0.05, 0.006, 0.012), "polymer", Vector3(0, 0.156, -0.18))
	part(g, "box", Vector3(0.046, 0.005, 0.085), "polymer", Vector3(0, 0.1065, -0.135))
	part(g, "box", Vector3(0.05, 0.006, 0.012), "polymer", Vector3(0, 0.103, -0.18))
	part(g, "box", Vector3(0.038, 0.044, 0.002), "lens", Vector3(0, 0.129, -0.177))
	part(g, "box", Vector3(0.008, 0.014, 0.022), "amber", Vector3(0.026, 0.13, -0.12))
	part(g, "box", Vector3(0.026, 0.004, 0.06), "teal", Vector3(0, 0.157, -0.13))
	part(g, "sphere", Vector3(0.0011, 0, 0), "reticle", Vector3(0, 0.129, -0.175))
	# Charging handle
	var bolt := node(g, "Bolt", Vector3(0, 0.068, 0.11))
	part(bolt, "box", Vector3(0.054, 0.01, 0.022), "metal_light", Vector3.ZERO)
	part(bolt, "box", Vector3(0.012, 0.012, 0.05), "metal", Vector3(0, 0, -0.03))
	part(g, "box", Vector3(0.002, 0.024, 0.065), "black", Vector3(0.0285, 0.04, -0.03))
	part(g, "box", Vector3(0.002, 0.01, 0.05), "amber", Vector3(0.0262, -0.005, 0.03))
	# Grip, guard, trigger
	part(g, "box", Vector3(0.034, 0.105, 0.046), "polymer", Vector3(0, -0.085, 0.055), Vector3(0.32, 0, 0))
	part(g, "box", Vector3(0.036, 0.06, 0.006), "teal", Vector3(0, -0.085, 0.03), Vector3(0.32, 0, 0))
	part(g, "box", Vector3(0.012, 0.008, 0.075), "metal", Vector3(0, -0.062, -0.005))
	part(g, "box", Vector3(0.006, 0.022, 0.007), "metal_light", Vector3(0, -0.05, -0.012))
	# Stock
	part(g, "zcyl", Vector3(0.015, 0.14, 0.015), "metal", Vector3(0, 0.022, 0.19))
	part(g, "box", Vector3(0.042, 0.072, 0.16), "polymer", Vector3(0, 0.004, 0.275))
	part(g, "box", Vector3(0.032, 0.022, 0.13), "teal", Vector3(0, 0.048, 0.265))
	part(g, "box", Vector3(0.047, 0.12, 0.026), "rubber", Vector3(0, -0.012, 0.36))
	# Magazine (curved)
	var mag := node(g, "Mag", Vector3(0, -0.08, -0.115))
	part(mag, "box", Vector3(0.03, 0.1, 0.072), "polymer", Vector3(0, -0.03, 0), Vector3(0.12, 0, 0))
	part(mag, "box", Vector3(0.03, 0.09, 0.07), "polymer", Vector3(0, -0.115, -0.018), Vector3(0.32, 0, 0))
	part(mag, "box", Vector3(0.034, 0.012, 0.078), "teal", Vector3(0, -0.162, -0.036), Vector3(0.32, 0, 0))
	part(mag, "box", Vector3(0.031, 0.02, 0.05), "brass", Vector3(0, 0.025, -0.005))
	# Foregrip
	part(g, "box", Vector3(0.03, 0.075, 0.034), "polymer", Vector3(0, -0.035, -0.43))
	part(g, "box", Vector3(0.032, 0.012, 0.036), "teal", Vector3(0, -0.07, -0.43))
	node(g, "Muzzle", Vector3(0, 0.032, -0.83))
	node(g, "Ejector", Vector3(0.04, 0.04, -0.03))
	node(g, "Sight", Vector3(0, 0.129, -0.175))
	_right_hand(g, Vector3(0, -0.075, 0.055), 0.32)
	_left_hand(g, Vector3(0.0, -0.045, -0.43))


# ------------------------------------------------------------------ Hornet SMG
static func _smg(g: Node3D) -> void:
	part(g, "box", Vector3(0.056, 0.085, 0.3), "polymer", Vector3(0, 0.03, -0.08))
	part(g, "box", Vector3(0.058, 0.01, 0.26), "teal", Vector3(0, 0.0, -0.08))
	part(g, "box", Vector3(0.05, 0.03, 0.22), "metal", Vector3(0, 0.085, -0.12))
	part(g, "zcyl", Vector3(0.023, 0.15, 0.023), "metal", Vector3(0, 0.03, -0.3))
	for i in 3:
		for side in [-1.0, 1.0]:
			part(g, "box", Vector3(0.004, 0.012, 0.024), "black", Vector3(side * 0.022, 0.03, -0.26 - i * 0.04))
	part(g, "zcyl", Vector3(0.016, 0.04, 0.016), "polymer", Vector3(0, 0.03, -0.395))
	part(g, "box", Vector3(0.022, 0.008, 0.2), "metal_light", Vector3(0, 0.104, -0.12))
	part(g, "box", Vector3(0.036, 0.03, 0.05), "polymer", Vector3(0, 0.12, -0.1))
	part(g, "box", Vector3(0.036, 0.022, 0.004), "lens", Vector3(0, 0.124, -0.126))
	part(g, "box", Vector3(0.004, 0.026, 0.004), "polymer", Vector3(0.017, 0.137, -0.126))
	part(g, "box", Vector3(0.004, 0.026, 0.004), "polymer", Vector3(-0.017, 0.137, -0.126))
	part(g, "sphere", Vector3(0.001, 0, 0), "reticle", Vector3(0, 0.124, -0.125))
	var bolt := node(g, "Bolt", Vector3(0.03, 0.06, 0.0))
	part(bolt, "box", Vector3(0.012, 0.014, 0.03), "metal_light", Vector3.ZERO)
	part(g, "box", Vector3(0.002, 0.02, 0.05), "black", Vector3(0.0285, 0.05, -0.05))
	part(g, "box", Vector3(0.032, 0.1, 0.045), "polymer", Vector3(0, -0.07, 0.055), Vector3(0.3, 0, 0))
	part(g, "box", Vector3(0.01, 0.008, 0.06), "metal", Vector3(0, -0.035, 0.0))
	for side in [-1.0, 1.0]:
		part(g, "box", Vector3(0.006, 0.006, 0.18), "metal", Vector3(side * 0.02, 0.0, 0.16))
	part(g, "box", Vector3(0.05, 0.07, 0.012), "rubber", Vector3(0, -0.01, 0.25))
	var mag := node(g, "Mag", Vector3(0, -0.03, -0.12))
	part(mag, "box", Vector3(0.028, 0.17, 0.05), "polymer", Vector3(0, -0.07, 0), Vector3(0.08, 0, 0))
	part(mag, "box", Vector3(0.032, 0.012, 0.054), "amber", Vector3(0, -0.158, -0.007), Vector3(0.08, 0, 0))
	part(g, "box", Vector3(0.028, 0.07, 0.03), "polymer", Vector3(0, -0.035, -0.24))
	node(g, "Muzzle", Vector3(0, 0.03, -0.42))
	node(g, "Ejector", Vector3(0.035, 0.05, -0.05))
	node(g, "Sight", Vector3(0, 0.124, -0.125))
	_right_hand(g, Vector3(0, -0.065, 0.055), 0.3)
	_left_hand(g, Vector3(0.0, -0.04, -0.24))


# ------------------------------------------------------------------ Kite pistol
static func _pistol(g: Node3D) -> void:
	var slide := node(g, "Bolt", Vector3(0, 0.035, -0.05))
	part(slide, "box", Vector3(0.03, 0.032, 0.19), "metal", Vector3.ZERO)
	part(slide, "box", Vector3(0.031, 0.006, 0.12), "teal", Vector3(0, -0.012, -0.02))
	for i in 5:
		part(slide, "box", Vector3(0.032, 0.022, 0.003), "black", Vector3(0, 0.002, 0.07 - i * 0.008))
	part(slide, "box", Vector3(0.004, 0.009, 0.006), "metal", Vector3(0, 0.02, -0.088))
	part(slide, "sphere", Vector3(0.0018, 0, 0), "reticle", Vector3(0, 0.025, -0.088))
	part(slide, "box", Vector3(0.024, 0.009, 0.008), "metal", Vector3(0, 0.02, 0.085))
	part(slide, "box", Vector3(0.002, 0.012, 0.035), "black", Vector3(0.0155, 0.004, -0.01))
	part(g, "box", Vector3(0.028, 0.024, 0.17), "polymer", Vector3(0, 0.008, -0.05))
	part(g, "zcyl", Vector3(0.009, 0.012, 0.009), "metal_light", Vector3(0, 0.035, -0.147))
	part(g, "box", Vector3(0.03, 0.105, 0.048), "polymer", Vector3(0, -0.05, 0.03), Vector3(0.28, 0, 0))
	part(g, "box", Vector3(0.032, 0.05, 0.004), "teal", Vector3(0, -0.05, 0.007), Vector3(0.28, 0, 0))
	part(g, "box", Vector3(0.01, 0.006, 0.05), "polymer", Vector3(0, -0.02, -0.015))
	var mag := node(g, "Mag", Vector3(0, -0.1, 0.045))
	part(mag, "box", Vector3(0.032, 0.012, 0.05), "teal", Vector3(0, -0.006, 0), Vector3(0.28, 0, 0))
	part(mag, "box", Vector3(0.024, 0.1, 0.04), "metal", Vector3(0, 0.045, -0.012), Vector3(0.28, 0, 0))
	node(g, "Muzzle", Vector3(0, 0.035, -0.16))
	node(g, "Ejector", Vector3(0.022, 0.045, -0.04))
	node(g, "Sight", Vector3(0, 0.06, -0.088))
	_right_hand(g, Vector3(0, -0.045, 0.035), 0.28)
	_left_hand(g, Vector3(-0.012, -0.05, 0.015), true)
