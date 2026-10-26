class_name EnergyBarrier
extends StaticBody3D
## "Aegis Wall" — a deployable energy barrier on the owner's barrier layer. Enemy bullets
## (whose ray mask includes this layer) are stopped; allied bullets and all movement pass through.

const SIZE := Vector3(6.0, 3.2, 0.3)
const MAX_HEALTH := 750.0
const LIFETIME := 15.0

var team := 0
var hp := MAX_HEALTH
var _t := 0.0
var _mat: ShaderMaterial
var _wall: MeshInstance3D
var _hit := 0.0
var _dying := -1.0
var _hum: AudioStreamPlayer3D


static func deploy(owner_unit: Combatant, origin: Vector3, dir: Vector3) -> bool:
	var flat := Vector3(dir.x, 0, dir.z)
	if flat.length() < 0.1:
		return false
	flat = flat.normalized()
	var space := owner_unit.get_world_3d().direct_space_state
	var dist := 3.4
	var eye := owner_unit.global_position + Vector3(0, 1.2, 0)
	var q := PhysicsRayQueryParameters3D.create(eye, eye + flat * dist, GameConst.LAYER_WORLD)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		dist = maxf(1.0, eye.distance_to(hit.position) - 0.5)
	var spot := owner_unit.global_position + flat * dist
	var down := PhysicsRayQueryParameters3D.create(spot + Vector3(0, 2.0, 0), spot + Vector3(0, -4.0, 0), GameConst.LAYER_WORLD)
	var ground := space.intersect_ray(down)
	if not ground.is_empty():
		spot.y = ground.position.y
	var b: EnergyBarrier = load("res://scenes/abilities/energy_barrier.tscn").instantiate()
	b.team = owner_unit.team
	b.transform = Transform3D(Basis.looking_at(-flat, Vector3.UP), spot)
	MatchManager.ability_root().add_child(b)
	Sfx.play_at("barrier_up", spot, 0.0, 45.0)
	MatchManager.report_sound(spot, owner_unit.team, 25.0)
	return true


func _ready() -> void:
	add_to_group("ability_objects")
	collision_layer = GameConst.barrier_layer(team)
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = SIZE
	cs.shape = shape
	cs.position = Vector3(0, SIZE.y * 0.5, 0)
	add_child(cs)
	_wall = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(SIZE.x, SIZE.y)
	_wall.mesh = qm
	_wall.position = Vector3(0, SIZE.y * 0.5, 0)
	_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://assets/materials/energy_barrier.gdshader")
	var ally := team == MatchManager.viewer_team()
	_mat.set_shader_parameter("color", GameConst.COLOR_CYAN if ally else Color(1.0, 0.45, 0.25))
	_mat.set_shader_parameter("aspect", Vector2(SIZE.x, SIZE.y))
	_wall.material_override = _mat
	add_child(_wall)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.15, 0.17, 0.2)
	metal.metallic = 0.8
	metal.roughness = 0.35
	var glow := StandardMaterial3D.new()
	glow.emission_enabled = true
	glow.emission = GameConst.COLOR_CYAN if ally else Color(1.0, 0.45, 0.25)
	glow.emission_energy_multiplier = 3.0
	glow.albedo_color = Color(0.1, 0.1, 0.1)
	for sx in [-1.0, 1.0]:
		var pylon := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.07
		cm.bottom_radius = 0.12
		cm.height = 0.5
		pylon.mesh = cm
		pylon.material_override = metal
		pylon.position = Vector3(sx * SIZE.x * 0.5, 0.25, 0)
		add_child(pylon)
		var cap := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.06
		sm.height = 0.12
		cap.mesh = sm
		cap.material_override = glow
		cap.position = Vector3(sx * SIZE.x * 0.5, 0.52, 0)
		add_child(cap)
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(SIZE.x, 0.05, 0.12)
	base.mesh = bm
	base.material_override = glow
	base.position = Vector3(0, 0.03, 0)
	add_child(base)
	_wall.scale = Vector3(1, 0.01, 1)
	_hum = Sfx.make_loop("amb_reactor_loop", self, global_position + Vector3(0, 1.0, 0), -16.0, 14.0)


func take_hit(dmg: float, at: Vector3) -> void:
	if _dying >= 0.0:
		return
	hp -= dmg
	_hit = 1.0
	var local := to_local(at)
	_mat.set_shader_parameter("hit_uv", Vector2(local.x / SIZE.x + 0.5, 1.0 - local.y / SIZE.y))
	Sfx.play_at("barrier_hit", at, -6.0, 30.0, 0.15)
	if hp <= 0.0:
		_begin_death()


func _begin_death() -> void:
	if _dying >= 0.0:
		return
	_dying = 0.0
	collision_layer = 0
	Sfx.play_at("barrier_down", global_position + Vector3(0, 1.5, 0), -2.0, 40.0)
	Fx.impact(global_position + Vector3(0, 1.5, 0), global_transform.basis.z, "metal", true)


func _process(delta: float) -> void:
	_t += delta
	var grow := clampf(_t / 0.35, 0.0, 1.0)
	_wall.scale = Vector3(1, ease(grow, 0.4), 1)
	_wall.position.y = SIZE.y * 0.5 * _wall.scale.y
	_hit = maxf(0.0, _hit - delta * 2.5)
	_mat.set_shader_parameter("hit_strength", _hit)
	var flicker := 1.0
	if _t > LIFETIME - 2.0:
		flicker = 0.6 + 0.4 * sin(_t * 30.0)
	_mat.set_shader_parameter("intensity", flicker * (0.7 + 0.3 * hp / MAX_HEALTH))
	if _t >= LIFETIME and _dying < 0.0:
		_begin_death()
	if _dying >= 0.0:
		_dying += delta
		_mat.set_shader_parameter("dissolve", clampf(_dying / 0.5, 0.0, 1.0))
		if _dying >= 0.55:
			queue_free()
