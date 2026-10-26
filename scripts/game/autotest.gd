extends Node
## Developer validation driver (only created with command-line flags):
##   -- --autotest [--rounds=N] [--timeout=S]   bot-only match, logs results, exits with status
##   -- --shots=/abs/dir                         scripted gameplay screenshots of every screen

var main: Node
var t := 0.0
var timeout := 900.0
var rounds := 3
var shots_dir := ""
var kills := 0
var _done := false


func begin(m: Node) -> void:
	main = m
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rounds="):
			rounds = int(a.substr(9))
		elif a.begins_with("--timeout="):
			timeout = float(a.substr(10))
		elif a.begins_with("--shots="):
			shots_dir = a.substr(8)
	var mm: MatchManager = main.match_manager
	mm.kill_event.connect(func(info: Dictionary) -> void:
		kills += 1
		var k: Combatant = info.killer
		print("[kill] %s -> %s (%s%s)" % [k.unit_name if k else "blast", info.victim.unit_name, info.weapon, ", head" if info.headshot else ""]))
	mm.round_ended.connect(func(w: int, reason: String) -> void:
		print("[round %d] winner team %d (%s) — %s  score %s" % [mm.round_number, w, mm.side_of(w), reason, str(mm.scores)]))
	mm.phase_changed.connect(func(p: String) -> void: print("[phase] ", p, " t=", snappedf(mm.clock, 0.1)))
	mm.device_event.connect(func(kind: String) -> void: print("[device] ", kind, " site=", mm.device.site))
	mm.match_ended.connect(func(w: int) -> void:
		print("[match] winner team %d final %s kills=%d" % [w, str(mm.scores), kills])
		if shots_dir == "":
			_finish(0))
	if "--combattest" in OS.get_cmdline_user_args():
		PlayerController.force_active = true
		_run_combattest()
	elif "--movetest" in OS.get_cmdline_user_args():
		PlayerController.force_active = true
		_run_movetest()
	elif shots_dir != "":
		PlayerController.force_active = true
		_run_shots()
	else:
		main.start_match({"side": "attack", "rounds_to_win": rounds}, false)


func _process(delta: float) -> void:
	t += delta
	if t > timeout and not _done:
		print("[autotest] TIMEOUT after %.0f s, score %s" % [t, str(main.match_manager.scores)])
		_finish(2)


func _finish(code: int) -> void:
	_done = true
	var mm: MatchManager = main.match_manager
	for u in mm.units:
		print("  %s team %d K/D/A %d/%d/%d score %d" % [u.unit_name, u.team, u.kills, u.deaths, u.assists, u.score])
	get_tree().quit(code)


# ------------------------------------------------------------------ screenshots
func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


## Waits on game state instead of wall-clock time (software rendering slows the simulation).
func _wait_until(cond: Callable, max_sec := 60.0) -> void:
	var waited := 0.0
	while not cond.call() and waited < max_sec:
		await _wait(0.1)
		waited += 0.1


func _wait_game(sec: float) -> void:
	var mm: MatchManager = main.match_manager
	var target := mm.clock + sec
	await _wait_until(func() -> bool: return mm.clock >= target, sec * 40.0 + 5.0)


func _shot(name: String) -> void:
	for i in 3:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(shots_dir + "/" + name + ".png")
	print("[shot] ", name)


func _place(p: PlayerController, pos: Vector3, yaw_deg: float, pitch_deg := 0.0) -> void:
	p.global_position = pos
	p._cur_pos = pos
	p._prev_pos = pos
	p.velocity = Vector3.ZERO
	p.yaw = deg_to_rad(yaw_deg)
	p.pitch = deg_to_rad(pitch_deg)


func _run_shots() -> void:
	await _wait(1.0)
	await _shot("01_menu")
	main.main_menu.open_setup()
	await _wait(0.3)
	await _shot("02_menu_setup")
	main._open_settings("menu")
	await _wait(0.3)
	await _shot("03_settings")
	main.settings_menu._close()
	main.start_match({"side": "attack", "rounds_to_win": 2})
	var mm: MatchManager = main.match_manager
	var p: PlayerController = mm.player
	p.invulnerable = true
	await _wait(1.2)
	await _shot("04_prep_phase")
	mm.phase_time = 0.05
	await _wait(0.5)
	var fac: FacilityBuilder = main.facility
	_place(p, fac.P(4.5, 12.6), 10.0, -4.0)
	await _wait(0.8)
	await _shot("05_site_a_hip")
	Input.action_press("aim")
	await _wait(0.45)
	await _shot("06_ads")
	Input.action_release("aim")
	await _wait(0.3)
	Input.action_press("fire")
	await _wait_until(func() -> bool: return p.weapons.state().mag <= 22)
	await _shot("07_firing")
	# Hold one muzzle flash on screen so the effect can be inspected in a slow software render.
	Input.action_release("fire")
	await _wait_game(0.1)
	p.weapons._flash_t = 5.0
	for f in p.weapons._flash_nodes:
		f.visible = true
	await _shot("07b_muzzle_flash")
	p.weapons._flash_t = 0.01
	await _wait(0.3)
	Input.action_release("fire")
	await _wait(0.2)
	p.weapons.start_reload()
	await _wait_until(func() -> bool: return p.weapons.reload_t > 0.75)
	await _shot("08_reload")
	await _wait_until(func() -> bool: return not p.weapons.reloading)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _wait_until(func() -> bool: return p.sprint_amount > 0.95)
	await _shot("09_sprint")
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await _wait(0.4)
	_place(p, fac.P(14.0, 24.5), 0.0, -6.0)
	await _wait(0.3)
	p.abilities.use(0, p.eye_position(), p.aim_direction())
	await _wait_until(func() -> bool:
		for n in get_tree().get_nodes_in_group("smoke_fields"):
			if n.radius >= SmokeField.MAX_RADIUS:
				return true
		return false, 120.0)
	await _wait_game(0.4)
	await _shot("10_shroud")
	_place(p, fac.P(13.0, 20.5), 25.0, -3.0)
	await _wait(0.2)
	p.abilities.use(1, p.eye_position(), p.aim_direction())
	await _wait_game(0.7)
	await _shot("11_aegis_wall")
	var enemy: Combatant = null
	for u in mm.units:
		if u.team != p.team and u.is_alive():
			enemy = u
			break
	if enemy:
		_place(p, fac.P(14.0, 13.0), 0.0, 0.0)
		enemy.global_position = fac.P(14.0, 11.6)
		await _wait(0.1)
		p.abilities.use(2, p.eye_position(), p.aim_direction())
		await _wait_game(0.6)
		await _shot("12_echo_reveal")
	p.weapons._select(1)
	await _wait_until(func() -> bool: return p.weapons.equip_t >= 1.0)
	await _wait_game(0.2)
	await _shot("13_smg")
	p.weapons._select(2)
	await _wait_until(func() -> bool: return p.weapons.equip_t >= 1.0)
	await _wait_game(0.2)
	await _shot("14_sidearm")
	p.weapons._select(0)
	Input.action_press("scoreboard")
	await _wait(0.4)
	await _shot("15_scoreboard")
	Input.action_release("scoreboard")
	# Let the bots fight for a while from the player's point of view.
	_place(p, fac.P(13.0, 18.0), 0.0, -2.0)
	await _wait_game(10.0)
	await _shot("16_live_combat")
	main.pause()
	await _wait(0.3)
	await _shot("17_pause")
	main.resume()
	mm.scores[0] = mm.rounds_to_win - 1
	mm._end_round(0, "Screenshot run")
	var waited := 0.0
	while not main.match_end.visible and waited < 120.0:
		await _wait(0.5)
		waited += 0.5
	await _wait(0.6)
	await _shot("18_match_end")
	get_tree().quit(0)


# ------------------------------------------------------------------ movement test
func _hold(action: String, sec: float, p: PlayerController, sample: Callable = Callable()) -> void:
	Input.action_press(action)
	var mm: MatchManager = main.match_manager
	var end := mm.clock + sec
	while mm.clock < end:
		await get_tree().physics_frame
		if sample.is_valid():
			sample.call()
	Input.action_release(action)


func _run_movetest() -> void:
	main.start_match({"side": "attack", "rounds_to_win": 2})
	var mm: MatchManager = main.match_manager
	var p: PlayerController = mm.player
	p.invulnerable = true
	var fac: FacilityBuilder = main.facility
	mm.phase_time = 0.05
	await _wait_game(0.5)
	for u in mm.units:
		if u is BotController:
			u.process_mode = Node.PROCESS_MODE_DISABLED
	var ok := true
	# 1) Walk speed on flat ground (yard, heading north)
	_place(p, fac.P(14.0, 31.0), 0.0)
	await _wait_game(0.3)
	var speeds := []
	await _hold("move_forward", 1.5, p, func() -> void: speeds.append(p.horizontal_speed()))
	var walk: float = speeds.max()
	print("[move] walk top speed %.2f m/s (expected ~%.2f)" % [walk, PlayerController.WALK_SPEED * 0.94])
	ok = ok and walk > 5.0 and walk < 5.6
	# Time to reach 90% speed (acceleration feel)
	var t90 := 0
	for i in speeds.size():
		if speeds[i] >= walk * 0.9:
			t90 = i
			break
	print("[move] reached 90%% speed in %.3f s" % (t90 / 120.0))
	# 2) Sprint speed (heading west along the clear spawn lane)
	_place(p, fac.P(14.0, 31.0), 90.0)
	await _wait_game(0.3)
	speeds.clear()
	Input.action_press("sprint")
	await _hold("move_forward", 1.5, p, func() -> void: speeds.append(p.horizontal_speed()))
	Input.action_release("sprint")
	var sprint: float = speeds.max()
	print("[move] sprint top speed %.2f m/s, sprint blend %.2f" % [sprint, p.sprint_amount])
	ok = ok and sprint > 6.6
	# 3) Stop distance after release (deceleration)
	var stop_from := p.global_position
	await _wait_game(0.6)
	print("[move] stopped within %.2f m after releasing sprint" % stop_from.distance_to(p.global_position))
	# 4) Crouch speed
	_place(p, fac.P(14.0, 31.0), 0.0)
	await _wait_game(0.3)
	speeds.clear()
	Input.action_press("crouch")
	await _hold("move_forward", 1.5, p, func() -> void: speeds.append(p.horizontal_speed()))
	Input.action_release("crouch")
	var crouch: float = speeds.max()
	print("[move] crouch top speed %.2f m/s, capsule height %.2f" % [crouch, p.capsule.height])
	ok = ok and crouch < 3.2
	await _wait_game(0.4)
	# 5) Jump height
	_place(p, fac.P(14.0, 31.0), 0.0)
	await _wait_game(0.3)
	var base_y := p.global_position.y
	var top := base_y
	await _hold("jump", 0.1, p)
	for i in 120:
		await get_tree().physics_frame
		top = maxf(top, p.global_position.y)
	print("[move] jump apex %.2f m" % (top - base_y))
	ok = ok and top - base_y > 0.9
	# 6) Stairs up to the Site A deck (cell 1,6 rises north to the 2.4 m platform)
	_place(p, fac.P(1.5, 7.6), 0.0)
	await _wait_game(0.3)
	await _hold("move_forward", 2.2, p)
	print("[move] after climbing Site A stairs: y = %.2f (platform %.1f)" % [p.global_position.y, FacilityBuilder.PLATFORM_H])
	ok = ok and p.global_position.y > 2.2
	# 7) Ramp up to the Atrium walkway (cell 11,15 rises north)
	_place(p, fac.P(11.5, 16.6), 0.0)
	await _wait_game(0.3)
	await _hold("move_forward", 2.0, p)
	print("[move] after Atrium ramp: y = %.2f" % p.global_position.y)
	ok = ok and p.global_position.y > 2.2
	# 8) Wall collision: run into the yard's north wall at the truck side
	_place(p, fac.P(8.0, 28.4), 0.0)
	await _wait_game(0.3)
	await _hold("move_forward", 1.5, p)
	var wall_z := fac.P(8.0, 28.0).z
	print("[move] against wall: z = %.2f (wall face at %.2f)" % [p.global_position.z, wall_z])
	ok = ok and p.global_position.z >= wall_z - 0.05
	# 9) Crouch under the tunnel roof stays standing-capable (headroom check)
	_place(p, fac.P(7.0, 18.0), 90.0)
	await _wait_game(0.2)
	Input.action_press("crouch")
	await _wait_game(0.5)
	Input.action_release("crouch")
	await _wait_game(0.5)
	print("[move] stood back up under tunnel roof: crouch %.2f" % p.crouch_amount)
	print("[move] RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)


# ------------------------------------------------------------------ combat / objective test
func _aim_at(p: PlayerController, point: Vector3) -> void:
	var to := point - p.eye_position()
	p.yaw = atan2(-to.x, -to.z)
	p.pitch = atan2(to.y, Vector2(to.x, to.z).length())
	p.recoil = Vector2.ZERO
	await get_tree().process_frame
	await get_tree().process_frame


func _fresh_enemy(mm: MatchManager, pos: Vector3, yaw: float) -> BotController:
	for u in mm.units:
		if u is BotController and u.team != mm.player.team:
			var b: BotController = u
			b.reset_for_round(Transform3D(Basis(Vector3.UP, yaw), pos))
			b.frozen = true
			b.model.reset_pose()
			return b
	return null


func _run_combattest() -> void:
	main.start_match({"side": "attack", "rounds_to_win": 2})
	var mm: MatchManager = main.match_manager
	var p: PlayerController = mm.player
	var fac: FacilityBuilder = main.facility
	p.invulnerable = true
	mm.phase_time = 0.05
	await _wait_game(0.5)
	for u in mm.units:
		if u is BotController:
			u.frozen = true
	var ok := true
	var kills_before := kills
	# 1) Body shots kill a shielded enemy at 15 m.
	_place(p, fac.P(14.0, 31.0), 0.0)
	var e := _fresh_enemy(mm, fac.P(14.0, 31.0) + Vector3(0, 0, -15), PI)
	await _wait_game(0.2)
	var shots := 0
	while e.is_alive() and shots < 30:
		await _aim_at(p, e.chest_position())
		p.weapons.bloom = 0.0
		p.weapons._shoot(p.weapons.state(), p.weapons.data(), mm.clock)
		shots += 1
		await _wait_game(0.15)
	print("[combat] body shots to kill a shielded enemy at 15 m: %d (alive=%s)" % [shots, e.is_alive()])
	ok = ok and not e.is_alive() and shots <= 6
	# 2) One Lancet headshot kills through full shield.
	e = _fresh_enemy(mm, fac.P(14.0, 31.0) + Vector3(0, 0, -12), PI)
	await _wait_game(0.2)
	await _aim_at(p, e.head_position())
	p.weapons.bloom = 0.0
	var res := Ballistics.fire(p, p.eye_position(), p.aim_direction(), p.weapons.data())
	print("[combat] headshot: part=%s damage=%.0f killed=%s" % [res.part, res.damage, res.killed])
	var dq := PhysicsRayQueryParameters3D.create(p.eye_position(), p.eye_position() + p.aim_direction() * 40.0, GameConst.bullet_mask(p.team))
	dq.collide_with_areas = true
	dq.exclude = [p.get_rid()]
	var dh := p.get_world_3d().direct_space_state.intersect_ray(dq)
	print("[debug] eye=%s dir=%s enemy=%s head=%s hit=%s at %s" % [p.eye_position(), p.aim_direction(), e.global_position, e.head_position(), (dh.collider.name if not dh.is_empty() else "none"), (dh.position if not dh.is_empty() else Vector3.ZERO)])
	for hb in e.hitboxes:
		print("[debug] hitbox %s at %s layer %d" % [hb.part, hb.global_position, hb.collision_layer])
	ok = ok and res.part == "head" and res.killed
	# 3) An enemy Aegis Wall stops the player's bullets.
	e = _fresh_enemy(mm, fac.P(14.0, 31.0) + Vector3(0, 0, -14), PI)
	await _wait_game(0.1)
	e.abilities.reset_for_round()
	EnergyBarrier.deploy(e, e.eye_position(), Vector3(0, 0, 1))
	await _wait_game(0.5)
	await _aim_at(p, e.chest_position())
	res = Ballistics.fire(p, p.eye_position(), p.aim_direction(), p.weapons.data())
	print("[combat] shot into enemy barrier: hit_unit=%s stopped_at_z=%.2f enemy_hp=%.0f" % [res.hit, res.position.z, e.health.health])
	ok = ok and not res.hit and e.health.health == 100.0
	# 4) The player's own barrier lets the player's bullets through.
	for n in get_tree().get_nodes_in_group("ability_objects"):
		n.queue_free()
	await _wait_game(0.1)
	p.abilities.reset_for_round()
	p.abilities.use(1, p.eye_position(), p.aim_direction())
	await _wait_game(0.5)
	res = Ballistics.fire(p, p.eye_position(), p.aim_direction(), p.weapons.data())
	print("[combat] shot through own barrier: hit_unit=%s part=%s" % [res.hit, res.part])
	ok = ok and res.hit
	# 5) Shroud blocks line of sight (bot perception).
	for n in get_tree().get_nodes_in_group("ability_objects"):
		n.queue_free()
	await _wait_game(0.1)
	var mid := p.global_position + Vector3(0, 0, -7)
	SmokeField.throw(p, mid + Vector3(0, 1.0, 0), Vector3(0, -2, 0))
	await _wait_game(1.6)
	var blocked := not Ballistics.has_los(p.eye_position(), e.head_position(), p.get_world_3d())
	var clear_without := Ballistics.has_los(p.eye_position(), e.head_position(), p.get_world_3d(), true)
	print("[combat] smoke blocks sight: %s (clear when ignoring smoke: %s)" % [blocked, clear_without])
	ok = ok and blocked and clear_without
	# 6) Plant the Phase Charge on site A by holding interact.
	for n in get_tree().get_nodes_in_group("ability_objects"):
		n.queue_free()
	if mm.device.carrier != p:
		mm.device.give_to(p)
	_place(p, fac.P(5.0, 8.2), 0.0)
	await _wait_game(0.3)
	Input.action_press("interact")
	await _wait_game(GameConst.PLANT_TIME + 0.4)
	Input.action_release("interact")
	print("[combat] plant: state=%s site=%s phase=%s" % [mm.device.state, mm.device.site, mm.phase])
	ok = ok and mm.device.state == "planted" and mm.phase == "planted"
	# 7) Defuse as a defender: interrupt half-way (checkpoint keeps 50%), then finish.
	mm.attack_team = 1 - p.team
	_place(p, mm.device.global_position + Vector3(0.8, 0, 0), 0.0)
	await _wait_game(0.3)
	Input.action_press("interact")
	await _wait_game(GameConst.DEFUSE_TIME * 0.6)
	Input.action_release("interact")
	await _wait_game(0.3)
	var kept := mm.device.defuse_fraction()
	print("[combat] defuse interrupted at 60%%: progress kept %.0f%% (checkpoint 50%%)" % (kept * 100.0))
	ok = ok and absf(kept - 0.5) < 0.02
	Input.action_press("interact")
	await _wait_game(GameConst.DEFUSE_TIME * 0.5 + 0.4)
	Input.action_release("interact")
	print("[combat] defuse: state=%s phase=%s score=%s" % [mm.device.state, mm.phase, str(mm.scores)])
	ok = ok and mm.device.state == "defused" and mm.phase == "round_end"
	print("[combat] kills recorded by match: %d" % (kills - kills_before))
	print("[combat] RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
