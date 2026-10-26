class_name ObjectiveDevice
extends Node3D
## The "Phase Charge": carried by an attacker, planted inside site A or B, defused by defenders
## (with a checkpoint at the half-way mark) or detonated when its timer expires.

signal planted(site: String, unit: Combatant)
signal defused(unit: Combatant)
signal detonated
signal dropped
signal picked_up(unit: Combatant)

var state := "idle"            # idle, carried, dropped, planted, defused, detonated
var carrier: Combatant = null
var site := ""
var time_left := 0.0
var planter: Combatant = null
var plant_progress := 0.0
var defuser: Combatant = null
var defuse_progress := 0.0
var defuse_checkpoint := 0.0
var level: FacilityBuilder

var _core_mat: StandardMaterial3D
var _ring: MeshInstance3D
var _light: OmniLight3D
var _beep_t := 0.0
var _t := 0.0
var _fall_v := 0.0


func setup(p_level: FacilityBuilder) -> void:
	level = p_level
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.16, 0.18, 0.2)
	body_mat.metallic = 0.75
	body_mat.roughness = 0.35
	_core_mat = StandardMaterial3D.new()
	_core_mat.albedo_color = Color(0.3, 0.2, 0.05)
	_core_mat.emission_enabled = true
	_core_mat.emission = GameConst.COLOR_AMBER
	_core_mat.emission_energy_multiplier = 3.0
	var base := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.26
	bm.bottom_radius = 0.32
	bm.height = 0.16
	bm.radial_segments = 8
	base.mesh = bm
	base.material_override = body_mat
	base.position.y = 0.08
	add_child(base)
	var core := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.1
	cm.bottom_radius = 0.12
	cm.height = 0.42
	cm.radial_segments = 12
	core.mesh = cm
	core.material_override = _core_mat
	core.position.y = 0.36
	add_child(core)
	for i in 3:
		var fin := MeshInstance3D.new()
		var fb := BoxMesh.new()
		fb.size = Vector3(0.04, 0.44, 0.16)
		fin.mesh = fb
		fin.material_override = body_mat
		var a := TAU * i / 3.0
		fin.position = Vector3(cos(a) * 0.17, 0.32, sin(a) * 0.17)
		fin.rotation.y = -a
		add_child(fin)
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.17
	tm.outer_radius = 0.2
	_ring.mesh = tm
	_ring.material_override = _core_mat
	_ring.position.y = 0.6
	add_child(_ring)
	_light = OmniLight3D.new()
	_light.light_color = GameConst.COLOR_AMBER
	_light.omni_range = 4.0
	_light.light_energy = 1.2
	_light.position.y = 0.6
	add_child(_light)
	visible = false


func reset() -> void:
	state = "idle"
	if carrier:
		carrier.carrying_device = false
	carrier = null
	site = ""
	planter = null
	defuser = null
	plant_progress = 0.0
	defuse_progress = 0.0
	defuse_checkpoint = 0.0
	time_left = 0.0
	visible = false


func give_to(u: Combatant) -> void:
	if carrier:
		carrier.carrying_device = false
	carrier = u
	u.carrying_device = true
	state = "carried"
	visible = false
	picked_up.emit(u)


func drop(at: Vector3) -> void:
	if carrier:
		carrier.carrying_device = false
	carrier = null
	planter = null
	plant_progress = 0.0
	state = "dropped"
	global_position = _ground(at)
	visible = true
	dropped.emit()


func _ground(at: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 1.0, 0), at + Vector3(0, -6.0, 0), GameConst.LAYER_WORLD)
	var hit := space.intersect_ray(q)
	return hit.position if not hit.is_empty() else at


func zone_at(pos: Vector3) -> String:
	for s in level.plant_zones:
		var r: Rect2 = level.plant_zones[s]
		if r.has_point(Vector2(pos.x, pos.z)) and pos.y < 1.2:
			return s
	return ""


func tick_plant(u: Combatant, delta: float) -> bool:
	if state != "carried" or u != carrier or not u.is_on_floor() or MatchManager.instance.phase != "live":
		cancel_plant(u)
		return false
	var z := zone_at(u.global_position)
	if z == "":
		cancel_plant(u)
		return false
	if planter != u:
		planter = u
		plant_progress = 0.0
		Sfx.play_at("device_tick", u.global_position + Vector3(0, 0.6, 0), -2.0, 30.0)
	plant_progress += delta
	_beep_t -= delta
	if _beep_t <= 0.0:
		_beep_t = 0.5
		Sfx.play_at("device_tick", u.global_position + Vector3(0, 0.6, 0), -6.0, 25.0, 0.0)
	if plant_progress >= GameConst.PLANT_TIME:
		_plant(u, z)
	return true


func cancel_plant(u: Combatant) -> void:
	if planter == u:
		planter = null
		plant_progress = 0.0


func _plant(u: Combatant, z: String) -> void:
	state = "planted"
	site = z
	u.carrying_device = false
	carrier = null
	planter = null
	plant_progress = 0.0
	global_position = _ground(u.global_position + u.aim_direction().slide(Vector3.UP).normalized() * 0.5)
	time_left = GameConst.DEVICE_TIME
	visible = true
	_beep_t = 0.0
	Sfx.play_at("device_planted", global_position + Vector3(0, 0.5, 0), 2.0, 80.0, 0.0)
	MatchManager.report_sound(global_position, u.team, 60.0)
	planted.emit(z, u)


func tick_defuse(u: Combatant, delta: float) -> bool:
	if state != "planted":
		return false
	if defuser != u:
		if defuser != null and is_instance_valid(defuser) and defuser.is_alive():
			return false
		defuser = u
		defuse_progress = defuse_checkpoint
		Sfx.play_at("device_tick", global_position + Vector3(0, 0.5, 0), -2.0, 40.0)
	defuse_progress += delta
	if defuse_progress >= GameConst.DEFUSE_TIME * 0.5 and defuse_checkpoint == 0.0:
		defuse_checkpoint = GameConst.DEFUSE_TIME * 0.5
		Sfx.play_at("ability_ready", global_position + Vector3(0, 0.5, 0), -4.0, 30.0, 0.0)
	if defuse_progress >= GameConst.DEFUSE_TIME:
		state = "defused"
		defuser = null
		_core_mat.emission = GameConst.COLOR_CYAN
		_light.light_color = GameConst.COLOR_CYAN
		Sfx.play_at("device_defused", global_position + Vector3(0, 0.5, 0), 2.0, 80.0, 0.0)
		defused.emit(u)
	return true


func cancel_defuse(u: Combatant) -> void:
	if defuser == u:
		defuser = null
		defuse_progress = defuse_checkpoint


func plant_fraction() -> float:
	return plant_progress / GameConst.PLANT_TIME


func defuse_fraction() -> float:
	return defuse_progress / GameConst.DEFUSE_TIME


func _physics_process(delta: float) -> void:
	if state != "planted":
		return
	if MatchManager.instance == null or MatchManager.instance.phase != "planted":
		return
	time_left -= delta
	_beep_t -= delta
	var interval := clampf(time_left / GameConst.DEVICE_TIME, 0.0, 1.0)
	interval = lerpf(0.12, 1.1, interval * interval)
	if _beep_t <= 0.0:
		_beep_t = interval
		Sfx.play_at("device_beep", global_position + Vector3(0, 0.5, 0), -2.0, 60.0, 0.0)
		_core_mat.emission_energy_multiplier = 8.0
		_light.light_energy = 3.5
	if time_left <= 0.0:
		state = "detonated"
		visible = false
		Fx.explosion(global_position)
		Sfx.play_at("device_explode", global_position + Vector3(0, 1.0, 0), 6.0, 200.0, 0.0, 20.0)
		# Resolve the round first so blast casualties are not counted as an elimination win.
		detonated.emit()
		for u in MatchManager.all_units():
			if not u.is_alive():
				continue
			var d: float = u.global_position.distance_to(global_position)
			if d < GameConst.DEVICE_BLAST_RADIUS:
				u.health.apply_damage({"amount": lerpf(400.0, 30.0, d / GameConst.DEVICE_BLAST_RADIUS), "attacker": null,
					"part": "blast", "weapon": "Phase Charge", "position": global_position, "direction": (u.global_position - global_position).normalized()})


func _process(delta: float) -> void:
	_t += delta
	if not visible:
		return
	_ring.rotation.y += delta * (6.0 if state == "planted" else 1.5)
	_ring.position.y = 0.6 + sin(_t * 3.0) * 0.04
	_core_mat.emission_energy_multiplier = lerpf(_core_mat.emission_energy_multiplier, 2.5, clampf(delta * 6.0, 0, 1))
	_light.light_energy = lerpf(_light.light_energy, 1.0, clampf(delta * 6.0, 0, 1))
