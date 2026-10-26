class_name BotController
extends Combatant
## Tactical bot. Perceives enemies by distance, field of view and line of sight (blocked by
## walls and obscuring fields), hears gunfire/footsteps, and follows team plans: attackers
## gather on a route, execute onto a site with utility, plant and guard; defenders hold
## angles, peek, rotate on intel, then retake and defuse. In fights it reacts with a delay,
## aims with decaying error, fires in bursts, strafes and falls back to cover.

const DIFFICULTY := [
	{"name": "Easy", "react": 0.6, "turn": 4.0, "err": 0.075, "spread": 2.0, "head": 0.06, "pause": 0.55, "fov": 55.0},
	{"name": "Normal", "react": 0.38, "turn": 6.5, "err": 0.042, "spread": 1.4, "head": 0.12, "pause": 0.36, "fov": 62.0},
	{"name": "Hard", "react": 0.24, "turn": 9.5, "err": 0.024, "spread": 1.0, "head": 0.24, "pause": 0.24, "fov": 70.0},
]
const RUN_SPEED := 5.3
const SIGHT_RANGE := 75.0

var model: BotModel
var agent: NavigationAgent3D
var level: FacilityBuilder
var weapon: WeaponData
var mag := 0
var reserve := 0
var reload_until := -1.0
var next_shot := 0.0
var burst_left := 0
var bloom := 0.0
var diff: Dictionary = DIFFICULTY[1]

# Aim / perception
var aim_yaw := 0.0
var aim_pitch := 0.0
var aim_err := Vector2.ZERO
var aim_head := false
var target: Combatant = null
var target_visible := false
var reaction_at := 0.0
var last_seen_pos := Vector3.ZERO
var last_seen_time := -99.0
var alert_until := -99.0
var heard_pos := Vector3.ZERO
var heard_time := -99.0
var look_point := Vector3.INF
var _think := 0.0
var _last_sound_check := 0.0

# Tactics
var side := "attack"
var state := "idle"
var goal := Vector3.INF
var goal_speed := 1.0
var route: Array = []
var route_i := 0
var staged := false
var entry_spot := Vector3.INF
var hold: Dictionary = {}
var hold_site := ""
var rotated := false
var cover_spot := Vector3.INF
var cover_until := -1.0
var guard_spot := Vector3.INF
var plant_spot := Vector3.INF
var peek_spot := Vector3.INF
var peek_until := -1.0
var next_peek := 0.0
var used_entry_util := false
var strafe_dir := 0.0
var strafe_until := 0.0
var wants_plant := false
var wants_defuse := false
var _safe_vel := Vector3.ZERO
var _has_safe_vel := false
var _stuck_t := 0.0
var _stuck_pos := Vector3.ZERO
var _flash_mesh: MeshInstance3D
var _flash_t := 0.0
var _moving_back := false
var frozen := false             # test hook: keeps the body (and hitboxes) but stops the brain


func _ready() -> void:
	_setup_combatant()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.36
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 0.7
	agent.target_desired_distance = 0.6
	agent.path_max_distance = 2.5
	agent.radius = 0.45
	agent.height = 1.8
	agent.avoidance_enabled = true
	agent.neighbor_distance = 6.0
	agent.max_neighbors = 6
	agent.time_horizon_agents = 0.8
	agent.max_speed = 7.0
	add_child(agent)
	agent.velocity_computed.connect(func(v: Vector3) -> void:
		_safe_vel = v
		_has_safe_vel = true)


func setup(p_team: int, p_name: String, ally: bool, p_level: FacilityBuilder, difficulty: int, weapon_path: String) -> void:
	team = p_team
	unit_name = p_name
	level = p_level
	diff = DIFFICULTY[clampi(difficulty, 0, 2)]
	weapon = load(weapon_path)
	model = BotModel.new()
	model.name = "Model"
	add_child(model)
	model.build(GameConst.COLOR_ALLY if ally else GameConst.COLOR_ENEMY, ally, p_name)
	var head_shape := SphereShape3D.new()
	head_shape.radius = 0.17
	var hb_head := Hitbox.create(self, "head", head_shape, Vector3(0, 0.04, -0.01))
	model.head.add_child(hb_head)
	var body_shape := BoxShape3D.new()
	body_shape.size = Vector3(0.5, 0.58, 0.34)
	var hb_body := Hitbox.create(self, "body", body_shape, Vector3(0, -0.05, 0))
	model.chest.add_child(hb_body)
	var legs_shape := BoxShape3D.new()
	legs_shape.size = Vector3(0.4, 0.9, 0.3)
	var hb_legs := Hitbox.create(self, "legs", legs_shape, Vector3(0, -0.47, 0))
	model.hips.add_child(hb_legs)
	hitboxes.append_array([hb_head, hb_body, hb_legs])
	_flash_mesh = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.32, 0.32)
	_flash_mesh.mesh = q
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	if ResourceLoader.exists("res://assets/textures/muzzle_flash.png"):
		fm.albedo_texture = load("res://assets/textures/muzzle_flash.png")
	fm.albedo_color = Color(1.5, 1.2, 0.8)
	_flash_mesh.material_override = fm
	_flash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash_mesh.visible = false
	model.muzzle.add_child(_flash_mesh)


func reset_for_round(xf: Transform3D) -> void:
	super.reset_for_round(xf)
	collision_layer = GameConst.LAYER_UNITS
	aim_yaw = xf.basis.get_euler().y
	rotation.y = aim_yaw
	aim_pitch = 0.0
	mag = weapon.mag_size
	reserve = weapon.reserve * 3
	reload_until = -1.0
	next_shot = 0.0
	burst_left = 0
	bloom = 0.0
	target = null
	target_visible = false
	last_seen_time = -99.0
	alert_until = -99.0
	heard_time = -99.0
	look_point = Vector3.INF
	state = "idle"
	goal = Vector3.INF
	route = []
	route_i = 0
	staged = false
	entry_spot = Vector3.INF
	hold = {}
	hold_site = ""
	rotated = false
	cover_spot = Vector3.INF
	guard_spot = Vector3.INF
	plant_spot = Vector3.INF
	used_entry_util = false
	wants_plant = false
	wants_defuse = false
	next_peek = MatchManager.now() + randf_range(8.0, 14.0)
	_last_sound_check = MatchManager.now()
	model.reset_pose()
	model.set_carrying(false)
	if team == MatchManager.viewer_team():
		model.show_marker(true, GameConst.COLOR_ALLY)
	else:
		model.show_marker(false, GameConst.COLOR_ENEMY)
	if model.name_label:
		model.name_label.visible = true
	agent.target_position = global_position


func eye_position() -> Vector3:
	return global_position + Vector3(0, 1.6, 0)


## Aim points follow the animated hitboxes so aiming (by anyone) matches what bullets test.
func head_position() -> Vector3:
	return hitboxes[0].global_position if hitboxes.size() > 0 else global_position + Vector3(0, 1.66, 0)


func chest_position() -> Vector3:
	return hitboxes[1].global_position if hitboxes.size() > 1 else global_position + Vector3(0, 1.2, 0)


func aim_direction() -> Vector3:
	return Vector3(-sin(aim_yaw) * cos(aim_pitch), sin(aim_pitch), -cos(aim_yaw) * cos(aim_pitch))


# ================================================================== main loop
func _physics_process(delta: float) -> void:
	if not is_alive():
		velocity = Vector3(0, velocity.y - gravity * delta, 0)
		if not is_on_floor():
			move_and_slide()
		model.animate(delta, 0.0, 0.0, false)
		return
	if frozen:
		model.animate(delta, 0.0, aim_pitch, false)
		return
	var now := MatchManager.now()
	if reload_until > 0.0 and now >= reload_until:
		var take := mini(weapon.mag_size - mag, reserve)
		mag += take
		reserve -= take
		reload_until = -1.0
	_think -= delta
	if _think <= 0.0:
		_think = randf_range(0.1, 0.16)
		_perceive(now)
		_decide(now)
	_objective_ticks(delta)
	_move(delta, now)
	_aim_and_shoot(delta, now)
	var hs := Vector2(velocity.x, velocity.z).length()
	update_footsteps(delta, 0.0 if goal_speed < 0.7 else 0.95, 2.4)
	model.animate(delta, hs, aim_pitch, _moving_back)
	model.set_carrying(carrying_device)
	if team != MatchManager.viewer_team():
		var rev := is_revealed_to(MatchManager.viewer_team())
		model.set_revealed(rev)
		model.show_marker(rev, GameConst.COLOR_ENEMY)
	if _flash_t > 0.0:
		_flash_t -= delta
		_flash_mesh.visible = _flash_t > 0.0


# ================================================================== perception
func _perceive(now: float) -> void:
	var world := get_world_3d()
	var eye := eye_position()
	var fwd := Vector3(-sin(aim_yaw), 0, -cos(aim_yaw))
	var alert := now < alert_until
	var best: Combatant = null
	var best_score := INF
	var best_head := false
	var blackout := MatchManager.instance.phase == "round_end"
	if not blackout:
		for e in MatchManager.enemies_of(team):
			if not e.is_alive():
				continue
			var to: Vector3 = e.global_position - global_position
			var d := to.length()
			if d > SIGHT_RANGE:
				continue
			var flat := Vector3(to.x, 0, to.z)
			if flat.length() > 0.01:
				flat = flat.normalized()
			var ang := rad_to_deg(acos(clampf(fwd.dot(flat), -1.0, 1.0)))
			var fov: float = diff.fov * (1.6 if alert else 1.0)
			if ang > fov and d > 3.5:
				continue
			var head_vis := Ballistics.has_los(eye, e.head_position(), world)
			var body_vis := head_vis or Ballistics.has_los(eye, e.chest_position(), world)
			if not body_vis:
				continue
			var score := d - (10.0 if e == target else 0.0)
			if score < best_score:
				best = e
				best_score = score
				best_head = head_vis
	if best:
		if best != target or not target_visible:
			var dist := best.global_position.distance_to(global_position)
			# A defender already holding a still angle reacts faster and steadier (peeker vs holder).
			var holding := side == "defend" and state == "hold" and Vector2(velocity.x, velocity.z).length() < 0.6
			var hold_k := 0.7 if holding else 1.0
			reaction_at = now + diff.react * (0.65 if alert else 1.0) * hold_k * randf_range(0.85, 1.25)
			aim_err = Vector2(randf_range(-1, 1), randf_range(-0.6, 0.6)).normalized() * diff.err * (1.0 + dist / 35.0) * hold_k
			burst_left = 0
		target = best
		target_visible = true
		if not best_head:
			aim_head = false
		last_seen_pos = best.global_position
		last_seen_time = now
		alert_until = now + 6.0
		MatchManager.report_enemy_seen(team, best)
	else:
		target_visible = false
		if target and not target.is_alive():
			target = null
	for ev in MatchManager.sound_events_since(_last_sound_check):
		if ev.team == team:
			continue
		var dd: float = ev.pos.distance_to(global_position)
		if dd < ev.radius:
			alert_until = now + 5.0
			heard_pos = ev.pos
			heard_time = now
	_last_sound_check = now


# ================================================================== decisions
func _decide(now: float) -> void:
	var mm := MatchManager.instance
	wants_plant = false
	if mm.phase == "prep" or mm.phase == "round_end" or mm.phase == "match_end":
		goal = Vector3.INF
		state = "idle"
		if mm.phase == "prep":
			look_point = _prep_look()
		return
	var dev: ObjectiveDevice = mm.device
	if target_visible and target and target.is_alive():
		_decide_combat(now, dev)
		return
	if dev.defuser == self and dev.state == "planted":
		wants_defuse = true
		goal = Vector3.INF
		return
	wants_defuse = false
	# Recently lost sight: hold the angle briefly, then push carefully.
	if target and target.is_alive() and now - last_seen_time < 3.2 and not carrying_device:
		look_point = last_seen_pos + Vector3(0, 1.4, 0)
		if now - last_seen_time > 1.3 and (side == "attack" or global_position.distance_to(last_seen_pos) < 16.0):
			goal = last_seen_pos
			goal_speed = 0.55
		else:
			goal = Vector3.INF
		state = "pursue"
		return
	if side == "attack":
		_decide_attack(now, dev)
	else:
		_decide_defend(now, dev)
	# React to noise when idle-ish.
	if now - heard_time < 1.5 and look_point == Vector3.INF:
		look_point = heard_pos + Vector3(0, 1.4, 0)


func _prep_look() -> Vector3:
	if side == "attack" and not route.is_empty():
		return route[0] + Vector3(0, 1.5, 0)
	if not hold.is_empty():
		return hold.pos + Vector3(0, 1.5, 0)
	return Vector3.INF


func _decide_combat(now: float, dev: ObjectiveDevice) -> void:
	state = "combat"
	wants_defuse = false
	if dev.planter == self:
		dev.cancel_plant(self)
	if dev.defuser == self:
		var keep := dev.defuse_fraction() > 0.75 and dev.time_left > GameConst.DEFUSE_TIME * (1.0 - dev.defuse_fraction()) + 0.5
		if keep:
			wants_defuse = true
			goal = Vector3.INF
			return
		dev.cancel_defuse(self)
	var d := global_position.distance_to(target.global_position)
	if abilities.is_ready(1) and d > 9.0 and health.health < 80.0 and randf() < 0.25:
		var dir := (target.global_position - global_position).normalized()
		abilities.use(1, eye_position(), dir)
	if (health.health < 35.0 or (mag == 0 and reload_until > now)) and now > cover_until:
		var c := _find_cover(target.global_position)
		if c != Vector3.INF:
			cover_spot = c
			cover_until = now + 3.5
	if now < cover_until and cover_spot != Vector3.INF:
		goal = cover_spot
		goal_speed = 1.0
		return
	goal = Vector3.INF


func _decide_attack(now: float, dev: ObjectiveDevice) -> void:
	var mm := MatchManager.instance
	var plan: Dictionary = mm.attack_plan
	look_point = Vector3.INF
	if dev.state == "dropped" and mm.nearest_alive_bot(team, dev.global_position) == self:
		state = "pickup"
		goal = dev.global_position
		goal_speed = 1.0
		return
	if dev.state == "planted":
		state = "post_plant"
		if guard_spot == Vector3.INF or guard_spot.distance_to(dev.global_position) > 18.0:
			guard_spot = _pick_guard_spot(dev.global_position, 5.0, 14.0)
		goal = guard_spot
		goal_speed = 1.0
		if global_position.distance_to(guard_spot) < 2.0:
			look_point = dev.global_position + Vector3(0, 1.0, 0)
		return
	var site: String = plan.get("site", "A")
	if route_i < route.size():
		goal = route[route_i]
		goal_speed = 1.0
		if global_position.distance_to(goal) < 2.6:
			route_i += 1
		if plan.get("executing", false) and not used_entry_util and route_i >= route.size() - 1:
			_entry_utility(site)
		state = "advance"
		return
	staged = true
	if not plan.get("executing", false):
		state = "staged"
		goal = Vector3.INF
		look_point = level.site_centers[site] + Vector3(0, 1.4, 0)
		return
	if not used_entry_util:
		_entry_utility(site)
	if carrying_device:
		state = "plant"
		if plant_spot == Vector3.INF:
			plant_spot = level.plant_spots[site].pick_random()
		goal = plant_spot
		goal_speed = 1.0
		if global_position.distance_to(plant_spot) < 1.6 and dev.zone_at(global_position) != "" and now - last_seen_time > 0.8:
			goal = Vector3.INF
			wants_plant = true
			look_point = level.site_watch[site].pick_random() + Vector3(0, 1.4, 0)
		return
	state = "entry"
	if entry_spot == Vector3.INF:
		entry_spot = level.site_positions[site].pick_random()
	goal = entry_spot
	goal_speed = 1.0
	if global_position.distance_to(entry_spot) < 2.0:
		look_point = level.site_watch[site][0] + Vector3(0, 1.4, 0) if randf() < 0.5 else level.site_watch[site][1] + Vector3(0, 1.4, 0)
		if abilities.is_ready(2) and randf() < 0.15:
			abilities.use(2, eye_position(), aim_direction())


func _entry_utility(site: String) -> void:
	used_entry_util = true
	var mm := MatchManager.instance
	if abilities.is_ready(0) and randf() < 0.8:
		var h: Dictionary = level.defend_holds[site].pick_random()
		abilities.use(0, eye_position(), aim_direction(), h.pos + Vector3(0, 0.3, 0))
	if abilities.is_ready(2) and not mm.attack_plan.get("echo_used", false):
		mm.attack_plan["echo_used"] = true
		abilities.use(2, eye_position(), aim_direction())


func _decide_defend(now: float, dev: ObjectiveDevice) -> void:
	var mm := MatchManager.instance
	look_point = Vector3.INF
	if dev.state == "planted":
		state = "retake"
		var dpos := dev.global_position
		var dist := global_position.distance_to(dpos)
		var someone := dev.defuser != null and dev.defuser != self
		var nearest := mm.nearest_alive_bot(team, dpos) == self
		var urgent := dev.time_left < GameConst.DEFUSE_TIME + 3.0
		# Regroup before retaking: wait for a second defender unless time is short.
		var near := 0
		for u in mm.team_units(team):
			if u.is_alive() and u.global_position.distance_to(dpos) < 24.0:
				near += 1
		var alive_def := mm.alive_count(team)
		if near < mini(2, alive_def) and dev.time_left > 20.0 and dist > 16.0:
			state = "regroup"
			if guard_spot == Vector3.INF or guard_spot.distance_to(dpos) < 16.0 or guard_spot.distance_to(dpos) > 26.0:
				guard_spot = _pick_guard_spot(dpos, 16.0, 24.0)
			goal = guard_spot
			goal_speed = 1.0
			look_point = dpos + Vector3(0, 1.2, 0)
			return
		if nearest and not someone and (now - last_seen_time > 1.5 or urgent):
			if dist < 1.3:
				goal = Vector3.INF
				wants_defuse = true
				look_point = level.site_watch[dev.site].pick_random() + Vector3(0, 1.4, 0)
			else:
				goal = dpos
				goal_speed = 1.0
		else:
			if guard_spot == Vector3.INF or guard_spot.distance_to(dpos) > 14.0:
				guard_spot = _pick_guard_spot(dpos, 4.0, 11.0)
			goal = guard_spot
			goal_speed = 1.0
			if global_position.distance_to(guard_spot) < 2.0:
				look_point = dpos + Vector3(0, 1.0, 0)
		if dist < 26.0 and abilities.is_ready(2) and randf() < 0.3:
			abilities.use(2, eye_position(), aim_direction())
		return
	var hot := mm.hot_site(team)
	if hot != "" and hot != hold_site and not rotated and randf() < 0.65:
		rotated = true
		hold = level.defend_holds[hot].pick_random()
		hold_site = hot
	if hold.is_empty():
		return
	var hp: Vector3 = hold.pos
	var dist_hold := global_position.distance_to(hp)
	state = "hold"
	goal = hp
	goal_speed = 1.0 if dist_hold > 6.0 else 0.55
	if dist_hold < 1.5:
		look_point = hold.look + Vector3(0, 1.4, 0)
		if now > next_peek:
			next_peek = now + randf_range(8.0, 14.0)
			peek_until = now + randf_range(1.2, 2.2)
			var side_dir := Vector3(cos(aim_yaw), 0, -sin(aim_yaw)) * (1.0 if randf() < 0.5 else -1.0)
			peek_spot = level.closest_nav_point(hp + side_dir * 2.2)
		if now < peek_until and peek_spot != Vector3.INF:
			goal = peek_spot
			goal_speed = 0.55
		if now - heard_time < 2.0 and abilities.is_ready(2) and heard_pos.distance_to(global_position) < 26.0 and randf() < 0.5:
			abilities.use(2, eye_position(), aim_direction())
		if now - heard_time < 2.0 and abilities.is_ready(0) and heard_pos.distance_to(global_position) < 22.0 and heard_pos.distance_to(global_position) > 8.0 and randf() < 0.25:
			abilities.use(0, eye_position(), aim_direction(), heard_pos)


func _objective_ticks(delta: float) -> void:
	var dev: ObjectiveDevice = MatchManager.instance.device
	if wants_plant and carrying_device and not target_visible:
		dev.tick_plant(self, delta)
	elif dev.planter == self:
		dev.cancel_plant(self)
	if wants_defuse and dev.state == "planted" and global_position.distance_to(dev.global_position) < 1.8:
		dev.tick_defuse(self, delta)
	elif dev.defuser == self:
		dev.cancel_defuse(self)


# ================================================================== tactics helpers
func _find_cover(threat: Vector3) -> Vector3:
	var world := get_world_3d()
	var cands := []
	for c in level.cover_points:
		var p: Vector3 = c.pos
		var d := p.distance_to(global_position)
		if d > 14.0 or d < 1.0 or p.distance_to(threat) < 5.0:
			continue
		cands.append([d, p])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var checks := 0
	for c in cands:
		checks += 1
		if checks > 10:
			break
		if not Ballistics.has_los(threat + Vector3(0, 1.5, 0), c[1] + Vector3(0, 1.2, 0), world, true):
			return c[1]
	return Vector3.INF


func _pick_guard_spot(center: Vector3, min_d: float, max_d: float) -> Vector3:
	var options := []
	for c in level.cover_points:
		var d: float = c.pos.distance_to(center)
		if d >= min_d and d <= max_d:
			options.append(c.pos)
	if options.is_empty():
		return level.closest_nav_point(center + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)))
	return options.pick_random()


# ================================================================== movement
func _move(delta: float, now: float) -> void:
	var desired := Vector3.ZERO
	var speed := RUN_SPEED * weapon.move_speed_mult * goal_speed
	var dueling := target_visible and goal == Vector3.INF
	if wants_plant or wants_defuse or MatchManager.is_interacting(self):
		desired = Vector3.ZERO
	elif dueling:
		if now > strafe_until:
			var still_chance := 0.45 if weapon.automatic and weapon.id == "lancet" else 0.2
			strafe_dir = 0.0 if randf() < still_chance else (1.0 if randf() < 0.5 else -1.0)
			strafe_until = now + randf_range(0.25, 0.6)
		var right := Vector3(cos(aim_yaw), 0, -sin(aim_yaw))
		desired = right * strafe_dir * 3.4
	elif goal != Vector3.INF:
		if agent.target_position.distance_to(goal) > 0.4:
			agent.target_position = goal
		if not agent.is_navigation_finished():
			var next := agent.get_next_path_position()
			var dir := next - global_position
			dir.y = 0.0
			if dir.length() > 0.05:
				desired = dir.normalized() * speed
	agent.velocity = desired
	var use_vel := desired
	if _has_safe_vel and desired.length() > 0.1 and not dueling:
		use_vel = Vector3(_safe_vel.x, 0, _safe_vel.z)
	var hv := Vector3(velocity.x, 0, velocity.z).move_toward(use_vel, 32.0 * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	velocity.y = velocity.y - gravity * delta if not is_on_floor() else -0.5
	move_and_slide()
	var fwd := Vector3(-sin(aim_yaw), 0, -cos(aim_yaw))
	_moving_back = hv.length() > 0.5 and hv.normalized().dot(fwd) < -0.3
	# Stuck recovery
	if desired.length() > 1.0:
		_stuck_t += delta
		if _stuck_t > 1.4:
			if global_position.distance_to(_stuck_pos) < 0.5 and goal != Vector3.INF:
				agent.target_position = goal + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
				velocity += Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
			_stuck_t = 0.0
			_stuck_pos = global_position
	else:
		_stuck_t = 0.0
		_stuck_pos = global_position


# ================================================================== aiming & firing
func _aim_and_shoot(delta: float, now: float) -> void:
	var eye := eye_position()
	var want_yaw := aim_yaw
	var want_pitch := 0.0
	var aim_pt := Vector3.INF
	if target_visible and target and target.is_alive():
		aim_pt = target.head_position() if aim_head else target.chest_position()
		aim_err = aim_err.lerp(Vector2.ZERO, clampf(delta * 2.4, 0, 1))
	elif look_point != Vector3.INF:
		aim_pt = look_point
	if aim_pt != Vector3.INF:
		var to := aim_pt - eye
		want_yaw = atan2(-to.x, -to.z)
		want_pitch = atan2(to.y, Vector2(to.x, to.z).length())
		if target_visible:
			want_yaw += aim_err.x
			want_pitch += aim_err.y
	else:
		var hv := Vector2(velocity.x, velocity.z)
		if hv.length() > 1.0:
			want_yaw = atan2(-velocity.x, -velocity.z)
	var turn: float = diff.turn * (1.0 if target_visible else 0.7)
	var dyaw := wrapf(want_yaw - aim_yaw, -PI, PI)
	aim_yaw += clampf(dyaw, -turn * delta, turn * delta) if absf(dyaw) > 0.002 else dyaw
	aim_pitch = move_toward(aim_pitch, want_pitch, turn * 0.7 * delta)
	rotation.y = aim_yaw
	if not target_visible or target == null or not target.is_alive():
		bloom = maxf(0.0, bloom - delta * 0.1)
		if mag < weapon.mag_size * 0.4 and reload_until < 0.0 and reserve > 0:
			_start_reload(now)
		return
	if not MatchManager.combat_enabled() or now < reaction_at or reload_until > 0.0:
		return
	if mag <= 0:
		_start_reload(now)
		return
	if now < next_shot:
		return
	var aim_dir := aim_direction()
	var to_t := (aim_pt - eye).normalized()
	if aim_dir.angle_to(to_t) > 0.09 + bloom:
		return
	if burst_left <= 0:
		burst_left = randi_range(weapon.bot_burst.x, weapon.bot_burst.y)
		aim_head = randf() < diff.head
	_fire(now, aim_dir)
	burst_left -= 1
	next_shot = now + 1.0 / weapon.fire_rate
	if not weapon.automatic:
		next_shot += randf_range(0.08, 0.22)
	if burst_left <= 0:
		next_shot += diff.pause * randf_range(0.8, 1.3)
		bloom = 0.0


func _fire(now: float, aim_dir: Vector3) -> void:
	mag -= 1
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var spread: float = (weapon.spread_base + weapon.spread_move * clampf((hspeed - 1.6) / 3.8, 0, 1) + bloom) * diff.spread * weapon.bot_accuracy
	bloom = minf(weapon.spread_max, bloom + weapon.spread_per_shot)
	var basis := Basis.looking_at(aim_dir, Vector3.UP)
	var a := randf() * TAU
	var r := spread * sqrt(randf())
	var dir := (basis * Vector3(cos(a) * r, sin(a) * r, -1.0)).normalized()
	var muzzle_pos := model.muzzle.global_position
	Ballistics.fire(self, eye_position(), dir, weapon, muzzle_pos, true)
	var listener := get_viewport().get_camera_3d()
	var far := listener and listener.global_position.distance_to(global_position) > 45.0
	Sfx.play_at("rifle_shot_far" if far and weapon.id == "lancet" else weapon.sound, muzzle_pos, 2.0 if not far else 4.0, 140.0, 0.04, 9.0)
	Fx.flash_light(muzzle_pos, Color(1.0, 0.72, 0.4), 2.0, 0.05, 6.0)
	_flash_t = 0.045
	_flash_mesh.visible = true
	_flash_mesh.rotation.z = randf() * TAU
	model.fire_kick()
	MatchManager.report_sound(global_position, team, 48.0)


func _start_reload(now: float) -> void:
	if reload_until > 0.0 or reserve <= 0:
		return
	reload_until = now + weapon.reload_time
	model.start_reload(weapon.reload_time)
	Sfx.play_at("reload_mag_out", global_position + Vector3(0, 1.2, 0), -6.0, 16.0)


# ================================================================== reactions
func _on_hit_reaction(info: Dictionary) -> void:
	var dir: Vector3 = info.get("direction", Vector3.FORWARD)
	model.flinch(global_transform.basis.inverse() * dir, info.get("part") == "head")
	var attacker = info.get("attacker")
	if attacker is Combatant:
		alert_until = MatchManager.now() + 6.0
		heard_pos = attacker.global_position
		heard_time = MatchManager.now()
		if not target_visible:
			look_point = attacker.global_position + Vector3(0, 1.4, 0)


func _on_death(info: Dictionary) -> void:
	var dir: Vector3 = info.get("direction", Vector3.FORWARD)
	model.die(global_transform.basis.inverse() * dir)
	collision_layer = 0
	_flash_mesh.visible = false
	var dev: ObjectiveDevice = MatchManager.instance.device
	if dev.planter == self:
		dev.cancel_plant(self)
	if dev.defuser == self:
		dev.cancel_defuse(self)
