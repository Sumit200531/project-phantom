class_name SmokeField
extends Node3D
## "Shroud" — a thrown canister that blooms into an obscuring field. Bots cannot see through it
## and the HUD fogs the screen when the camera is inside.

const MAX_RADIUS := 4.6
const LIFETIME := 14.0
const GRAVITY := 16.0

var team := 0
var vel := Vector3.ZERO
var radius := 0.0
var _state := "flying"
var _t := 0.0
var _life := 0.0
var _canister: MeshInstance3D
var _shells: Array[MeshInstance3D] = []
var _mats: Array[ShaderMaterial] = []
var _puffs: CPUParticles3D


static func throw(owner_unit: Combatant, origin: Vector3, velocity: Vector3) -> SmokeField:
	var s: SmokeField = load("res://scenes/abilities/smoke_field.tscn").instantiate()
	s.team = owner_unit.team
	s.vel = velocity
	s.position = origin
	MatchManager.ability_root().add_child(s)
	Sfx.play_at("smoke_throw", origin, -4.0, 30.0)
	return s


static func solve_throw(origin: Vector3, target: Vector3) -> Vector3:
	var flat := Vector2(target.x - origin.x, target.z - origin.z).length()
	var t := clampf(flat / 15.0, 0.45, 1.6)
	var v := (target - origin) / t
	v.y += 0.5 * GRAVITY * t
	return v


## Segment–sphere test against every active field.
static func blocks_segment(a: Vector3, b: Vector3) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	for s in tree.get_nodes_in_group("smoke_fields"):
		var r: float = s.radius * 0.92
		if r < 0.8:
			continue
		var c: Vector3 = s.center()
		var ab := b - a
		var t := clampf((c - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		if (a + ab * t).distance_squared_to(c) < r * r:
			return true
	return false


## 0..1 how deep `p` sits inside any field (for the screen fog overlay).
static func density_at(p: Vector3) -> float:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return 0.0
	var best := 0.0
	for s in tree.get_nodes_in_group("smoke_fields"):
		var r: float = s.radius
		if r < 0.5:
			continue
		var d: float = p.distance_to(s.center())
		best = maxf(best, clampf((r - d) / 1.2, 0.0, 1.0) * s.fade_factor())
	return best


func center() -> Vector3:
	return global_position + Vector3(0, radius * 0.45, 0)


func fade_factor() -> float:
	return clampf((LIFETIME - _life) / 1.2, 0.0, 1.0)


func _ready() -> void:
	add_to_group("ability_objects")
	_canister = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.055
	cm.bottom_radius = 0.055
	cm.height = 0.2
	_canister.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.25, 0.28, 0.32)
	m.metallic = 0.7
	m.roughness = 0.35
	m.emission_enabled = true
	m.emission = Color(0.6, 0.5, 1.0)
	m.emission_energy_multiplier = 0.8
	_canister.material_override = m
	add_child(_canister)


func _physics_process(delta: float) -> void:
	_t += delta
	if _state == "flying":
		vel.y -= GRAVITY * delta
		var from := global_position
		var to := from + vel * delta
		var q := PhysicsRayQueryParameters3D.create(from, to, GameConst.LAYER_WORLD)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			var n: Vector3 = hit.normal
			global_position = hit.position + n * 0.05
			if n.y > 0.6:
				_deploy()
				return
			vel = vel.bounce(n) * 0.45
		else:
			global_position = to
		_canister.rotation += Vector3(9.0, 4.0, 0) * delta
		if _t > 2.2:
			_deploy()
	elif _state == "active":
		_life += delta
		radius = minf(MAX_RADIUS, radius + delta * MAX_RADIUS / 0.8)
		var f := fade_factor()
		for i in _shells.size():
			var s := _shells[i]
			var base_scale: float = s.get_meta("scale")
			s.scale = Vector3.ONE * radius * base_scale
			_mats[i].set_shader_parameter("fade", f)
		if _puffs:
			_puffs.emitting = _life < LIFETIME - 2.0
		if _life >= LIFETIME:
			queue_free()


func _deploy() -> void:
	_state = "active"
	add_to_group("smoke_fields")
	_canister.visible = false
	Sfx.play_at("smoke_deploy", global_position, 0.0, 45.0)
	MatchManager.report_sound(global_position, team, 25.0)
	var shader: Shader = load("res://assets/materials/smoke_field.gdshader")
	var layout := [[Vector3(0, 0.45, 0), 1.0], [Vector3(0.35, 0.3, 0.2), 0.72], [Vector3(-0.3, 0.32, -0.25), 0.7],
		[Vector3(0.1, 0.62, -0.3), 0.6], [Vector3(-0.2, 0.25, 0.35), 0.62]]
	for entry in layout:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 24
		sm.rings = 12
		mi.mesh = sm
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("seed", randf() * 10.0)
		mat.set_shader_parameter("density", 1.0 if entry[1] >= 1.0 else 0.9)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = entry[0] * MAX_RADIUS
		mi.set_meta("scale", entry[1])
		mi.scale = Vector3.ONE * 0.01
		add_child(mi)
		_shells.append(mi)
		_mats.append(mat)
	_puffs = CPUParticles3D.new()
	_puffs.amount = 22
	_puffs.lifetime = 3.5
	_puffs.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	_puffs.emission_sphere_radius = MAX_RADIUS * 0.9
	_puffs.direction = Vector3.UP
	_puffs.spread = 90.0
	_puffs.initial_velocity_min = 0.1
	_puffs.initial_velocity_max = 0.5
	_puffs.gravity = Vector3(0, 0.15, 0)
	_puffs.scale_amount_min = 2.5
	_puffs.scale_amount_max = 4.0
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	var pm := StandardMaterial3D.new()
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pm.albedo_texture = load("res://assets/textures/smoke_puff.png") if ResourceLoader.exists("res://assets/textures/smoke_puff.png") else null
	pm.albedo_color = Color(0.78, 0.8, 0.88, 0.6)
	pm.vertex_color_use_as_albedo = true
	q.material = pm
	_puffs.mesh = q
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.0))
	ramp.add_point(0.3, Color(1, 1, 1, 0.7))
	ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0.0))
	_puffs.color_ramp = ramp
	_puffs.position = Vector3(0, MAX_RADIUS * 0.4, 0)
	add_child(_puffs)
