class_name WeaponManager
extends Node
## The player's weapons: firing, spread/recoil, reloads, switching, ADS and the fully procedural
## first-person animation (sway, bob, sprint pose, recoil kick, reload choreography).
## The viewmodel is drawn by an overlay camera so it never clips into walls.

signal fired(weapon: WeaponData)
signal hit_confirmed(part: String, killed: bool)
signal weapon_changed(weapon: WeaponData)
signal reload_started(duration: float)

const WEAPON_FILES := ["res://assets/weapons/lancet.tres", "res://assets/weapons/hornet.tres", "res://assets/weapons/kite.tres"]

const HIP := {"lancet": Vector3(0.15, -0.165, -0.34), "hornet": Vector3(0.14, -0.155, -0.33), "kite": Vector3(0.12, -0.135, -0.38)}
const HIP_ROT := {"lancet": Vector3(0.0, 0.045, 0.0), "hornet": Vector3(0.0, 0.045, 0.0), "kite": Vector3(0.02, 0.06, 0.0)}

var player: Node                 # PlayerController
var camera: Camera3D
var weapons: Array = []          # [{data, mag, reserve, rig}]
var current := 0
var spread := 0.0                # current cone half-angle (radians), for the crosshair
var ads := 0.0
var reloading := false
var reload_t := 0.0
var reload_dur := 1.0
var reload_empty := false
var equip_t := 1.0
var next_fire := 0.0
var bloom := 0.0
var shots_in_spray := 0
var last_shot := -9.0
var trigger_latched := false
var _press_time := -9.0
var enabled := true

var vm_root: Node3D
var vm_sway: Node3D
var vm_camera: Camera3D
var vm_viewport: SubViewport
var vm_rect: TextureRect
var vm_layer: CanvasLayer
var vm_sun: DirectionalLight3D
var vm_flash: OmniLight3D
var _sunlit := 1.0
var _sun_check := 0.0
var _flash_nodes: Array = []
var _flash_t := 0.0
var _kick := Vector3.ZERO        # x = back offset, y = pitch, z = roll
var _kick_v := Vector3.ZERO
var _sway := Vector2.ZERO
var _sway_target := Vector2.ZERO
var _time := 0.0
var _reload_sounds := []
var _slide_t := 0.0
var _throw_t := 0.0
var _air := 0.0


func setup(p: Node, cam: Camera3D) -> void:
	player = p
	camera = cam
	for path in WEAPON_FILES:
		var d: WeaponData = load(path)
		weapons.append({"data": d, "mag": d.mag_size, "reserve": d.reserve, "rig": null})
	_build_overlay()
	for w in weapons:
		var rig := ViewmodelBuilder.build(w.data.id)
		rig.visible = false
		vm_sway.add_child(rig)
		w.rig = rig
		var gun: Node3D = rig.get_node("Gun")
		for n in ["Mag", "Bolt", "HandL"]:
			var nd := gun.get_node_or_null(n)
			if nd:
				nd.set_meta("base", nd.position)
				nd.set_meta("base_rot", nd.rotation)
	_select(0, true)


func _build_overlay() -> void:
	vm_layer = CanvasLayer.new()
	vm_layer.layer = -1
	vm_layer.name = "ViewmodelLayer"
	player.add_child(vm_layer)
	vm_viewport = SubViewport.new()
	vm_viewport.transparent_bg = true
	vm_viewport.msaa_3d = Viewport.MSAA_4X
	vm_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vm_viewport.positional_shadow_atlas_size = 0
	# The viewmodel lives in its own tiny world: no duplicate shadow pass of the level.
	vm_viewport.own_world_3d = true
	vm_layer.add_child(vm_viewport)
	vm_rect = TextureRect.new()
	vm_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vm_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vm_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vm_rect.stretch_mode = TextureRect.STRETCH_SCALE
	vm_rect.texture = vm_viewport.get_texture()
	vm_layer.add_child(vm_rect)
	vm_camera = Camera3D.new()
	vm_camera.cull_mask = GameConst.VIS_VIEWMODEL
	vm_camera.fov = 56.0
	vm_camera.near = 0.01
	vm_camera.far = 5.0
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.66)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	var world_env: Environment = Settings.world_environment()
	if world_env and world_env.sky:
		env.sky = world_env.sky
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	vm_camera.environment = env
	vm_viewport.add_child(vm_camera)
	vm_sun = DirectionalLight3D.new()
	vm_sun.shadow_enabled = false
	vm_sun.light_cull_mask = GameConst.VIS_VIEWMODEL
	vm_viewport.add_child(vm_sun)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.55, 0.72, 0.95)
	fill.light_energy = 0.25
	fill.rotation_degrees = Vector3(-20, 160, 0)
	fill.light_cull_mask = GameConst.VIS_VIEWMODEL
	vm_viewport.add_child(fill)
	vm_flash = OmniLight3D.new()
	vm_flash.omni_range = 1.2
	vm_flash.light_color = Color(1.0, 0.75, 0.45)
	vm_flash.light_energy = 0.0
	vm_flash.light_cull_mask = GameConst.VIS_VIEWMODEL
	vm_viewport.add_child(vm_flash)
	# Everything in this world is expressed in camera space (camera at the origin).
	vm_root = Node3D.new()
	vm_root.name = "ViewmodelRoot"
	vm_viewport.add_child(vm_root)
	vm_sway = Node3D.new()
	vm_root.add_child(vm_sway)
	get_window().size_changed.connect(_resize_overlay)
	_resize_overlay()


func _resize_overlay() -> void:
	if vm_viewport:
		var s := get_window().size
		vm_viewport.size = Vector2i(maxi(s.x, 64), maxi(s.y, 64))


func data() -> WeaponData:
	return weapons[current].data


func state() -> Dictionary:
	return weapons[current]


func reset_for_round() -> void:
	for w in weapons:
		w.mag = w.data.mag_size
		w.reserve = w.data.reserve
	reloading = false
	bloom = 0.0
	shots_in_spray = 0
	_select(0, true)


func set_viewmodel_visible(v: bool) -> void:
	if vm_rect:
		vm_rect.visible = v


func _select(index: int, instant := false) -> void:
	if index < 0 or index >= weapons.size():
		return
	if index == current and not instant:
		return
	reloading = false
	_reload_sounds.clear()
	for i in weapons.size():
		weapons[i].rig.visible = i == index
	var gun: Node3D = weapons[index].rig.get_node("Gun")
	for n in ["Mag", "Bolt", "HandL"]:
		var nd: Node3D = gun.get_node_or_null(n)
		if nd:
			nd.position = nd.get_meta("base")
			nd.rotation = nd.get_meta("base_rot")
			nd.visible = true
	current = index
	equip_t = 1.0 if instant else 0.0
	_build_flash()
	if not instant:
		Sfx.play("weapon_switch", -6.0)
	weapon_changed.emit(data())


func _build_flash() -> void:
	for f in _flash_nodes:
		if is_instance_valid(f):
			f.queue_free()
	_flash_nodes.clear()
	var muzzle: Node3D = weapons[current].rig.get_node("Gun/Muzzle")
	var tex: Texture2D = load("res://assets/textures/muzzle_flash.png") if ResourceLoader.exists("res://assets/textures/muzzle_flash.png") else null
	var side_tex: Texture2D = load("res://assets/textures/muzzle_side.png") if ResourceLoader.exists("res://assets/textures/muzzle_side.png") else null
	var make := func(t: Texture2D, billboard: bool) -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# Normal alpha blending: additive blending writes no alpha, so it would vanish when the
		# transparent viewmodel overlay is composited onto the screen.
		m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_texture = t
		m.albedo_color = Color(1.0, 0.9, 0.7)
		if billboard:
			m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		return m
	var size := 0.17 if data().id != "kite" else 0.12
	var front := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	front.mesh = q
	front.material_override = make.call(tex, true)
	front.layers = GameConst.VIS_VIEWMODEL
	front.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	front.position = Vector3(0, 0, -0.02)
	muzzle.add_child(front)
	_flash_nodes.append(front)
	for k in 2:
		var side := MeshInstance3D.new()
		var q2 := QuadMesh.new()
		q2.size = Vector2(size * 0.7, size * 2.2)
		side.mesh = q2
		side.material_override = make.call(side_tex, false)
		side.layers = GameConst.VIS_VIEWMODEL
		side.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		side.rotation = Vector3(PI * 0.5, PI * 0.5 * k, 0)
		side.position = Vector3(0, 0, -size)
		muzzle.add_child(side)
		_flash_nodes.append(side)
	for f in _flash_nodes:
		f.visible = false


# ================================================================== input & firing (physics)
func on_mouse_motion(rel: Vector2) -> void:
	_sway_target += rel * 0.00055
	_sway_target = _sway_target.clamp(Vector2(-0.07, -0.05), Vector2(0.07, 0.05))


func handle_input_event(event: InputEvent) -> void:
	if not enabled:
		return
	if event.is_action_pressed("weapon_1"):
		_select(0)
	elif event.is_action_pressed("weapon_2"):
		_select(1)
	elif event.is_action_pressed("weapon_3"):
		_select(2)
	elif event.is_action_pressed("weapon_next"):
		_select((current + 1) % weapons.size())
	elif event.is_action_pressed("weapon_prev"):
		_select((current - 1 + weapons.size()) % weapons.size())
	elif event.is_action_pressed("reload"):
		start_reload()
	elif event.is_action_pressed("fire"):
		_press_time = MatchManager.now()


func start_reload() -> void:
	var w = state()
	if reloading or w.mag >= w.data.mag_size or w.reserve <= 0 or equip_t < 1.0:
		return
	reloading = true
	reload_empty = w.mag == 0
	reload_dur = w.data.reload_empty_time if reload_empty else w.data.reload_time
	reload_t = 0.0
	_reload_sounds = [[0.2, "reload_mag_out"], [0.62, "reload_mag_in"]]
	if reload_empty:
		_reload_sounds.append([0.84, "reload_bolt"])
	reload_started.emit(reload_dur)


func cancel_reload() -> void:
	reloading = false
	_reload_sounds.clear()


func physics_update(delta: float, can_fire: bool) -> void:
	var w = state()
	var d: WeaponData = w.data
	var now := MatchManager.now()
	# Reload progress
	if reloading:
		reload_t += delta
		var k := reload_t / reload_dur
		while not _reload_sounds.is_empty() and k >= _reload_sounds[0][0]:
			Sfx.play(_reload_sounds[0][1], -5.0)
			_reload_sounds.pop_front()
		if reload_t >= reload_dur:
			var take: int = mini(d.mag_size - w.mag, w.reserve)
			w.mag += take
			w.reserve -= take
			reloading = false
	if equip_t < 1.0:
		equip_t = minf(1.0, equip_t + delta / d.equip_time)
	# Spread model
	var hspeed: float = player.horizontal_speed()
	var move_k := clampf((hspeed - 1.6) / 3.8, 0.0, 1.0)
	var base := d.spread_base + d.spread_move * move_k
	if not player.is_on_floor():
		base += d.spread_air
	if player.crouch_amount > 0.5:
		base *= 0.85
	if now - last_shot > 0.06:
		bloom = maxf(0.0, bloom - delta * d.spread_max / d.spread_recovery)
		if now - last_shot > 0.32:
			shots_in_spray = 0
	spread = (base + bloom) * lerpf(1.0, d.ads_spread_mult, ads)
	# Trigger
	var want: bool = Input.is_action_pressed("fire") if d.automatic else (now - _press_time) < 0.16
	if not can_fire or not enabled:
		return
	if want and w.mag <= 0 and not reloading:
		if not trigger_latched:
			Sfx.play("dry_fire", -8.0)
			trigger_latched = true
			if w.reserve > 0:
				start_reload()
		return
	if not Input.is_action_pressed("fire"):
		trigger_latched = false
	if want and not reloading and equip_t >= 1.0 and w.mag > 0 and now >= next_fire and player.sprint_amount < 0.35:
		if now - next_fire > 1.0 / d.fire_rate:
			next_fire = now
		_press_time = -9.0
		_shoot(w, d, now)
		next_fire += 1.0 / d.fire_rate


func _shoot(w: Dictionary, d: WeaponData, now: float) -> void:
	w.mag -= 1
	last_shot = now
	var pat := d.pattern(shots_in_spray)
	shots_in_spray += 1
	var cam_xf := camera.global_transform
	var origin := cam_xf.origin
	var a := randf() * TAU
	var r := spread * sqrt(randf())
	var local_dir := Vector3(cos(a) * r, sin(a) * r, -1.0).normalized()
	var dir := (cam_xf.basis * local_dir).normalized()
	var muzzle: Node3D = w.rig.get_node("Gun/Muzzle")
	var muzzle_world := to_world(muzzle.global_position)
	var tracer_from := muzzle_world + dir * 1.2
	var show_tracer := d.tracer_every > 0 and (shots_in_spray % d.tracer_every == 1 or d.tracer_every == 1)
	var res := Ballistics.fire(player, origin, dir, d, tracer_from, show_tracer)
	if res.hit:
		hit_confirmed.emit(res.part, res.killed)
		if res.killed:
			Sfx.play("kill_confirm", -2.0, 0.0)
		elif res.part == "head":
			Sfx.play("hit_head", -3.0, 0.0)
		else:
			Sfx.play("hit_body", -6.0, 0.02)
	bloom = minf(d.spread_max, bloom + d.spread_per_shot)
	var ads_k := lerpf(1.0, 0.75, ads)
	player.add_recoil(d.recoil_pitch * pat.x * ads_k, d.recoil_yaw * (pat.y + randf_range(-0.35, 0.35)) * ads_k, d.view_kick)
	Sfx.play(d.sound, -1.5, 0.03)
	MatchManager.report_sound(origin, player.team, 48.0)
	# Viewmodel feedback
	var kick := d.view_kick * lerpf(1.0, 0.45, ads)
	_kick_v += Vector3(1.9 * kick, 3.2 * kick, randf_range(-1.6, 1.6) * kick)
	_flash_t = 0.04
	for f in _flash_nodes:
		f.visible = true
	if _flash_nodes.size() > 0:
		_flash_nodes[0].rotation.z = randf() * TAU
		var s := randf_range(0.8, 1.25)
		_flash_nodes[0].scale = Vector3(s, s, s)
	Fx.flash_light(muzzle_world + dir * 0.3, Color(1.0, 0.75, 0.45), 2.4, 0.05, 7.0)
	vm_flash.position = muzzle.global_position + Vector3(0, 0.05, 0.1)
	vm_flash.light_energy = 3.0
	_slide_t = 0.06
	var ej: Node3D = w.rig.get_node("Gun/Ejector")
	var right := cam_xf.basis.x
	Fx.shell(to_world(ej.global_position) + right * 0.08, right * randf_range(2.2, 3.2) + cam_xf.basis.y * randf_range(1.2, 2.0) + cam_xf.basis.z * 0.6)
	fired.emit(d)


## Converts a point from viewmodel (camera) space into the game world.
func to_world(p: Vector3) -> Vector3:
	return camera.global_transform * p


## Keeps the viewmodel's private sun aligned with the real one, dimmed when the player stands
## in shade or under a roof, so the gun matches its surroundings without a second shadow pass.
func _update_vm_light(delta: float) -> void:
	var level_sun: DirectionalLight3D = Settings.world_sun()
	if level_sun == null:
		return
	vm_sun.basis = camera.global_transform.basis.inverse() * level_sun.global_transform.basis
	vm_sun.light_color = level_sun.light_color
	_sun_check -= delta
	if _sun_check <= 0.0:
		_sun_check = 0.12
		var to_sun := level_sun.global_transform.basis.z.normalized()
		var from := camera.global_position
		var q := PhysicsRayQueryParameters3D.create(from, from + to_sun * 80.0, GameConst.LAYER_WORLD)
		var lit: bool = player.get_world_3d().direct_space_state.intersect_ray(q).is_empty()
		_sunlit = 1.0 if lit else 0.3
	vm_sun.light_energy = lerpf(vm_sun.light_energy, level_sun.light_energy * _sunlit, clampf(delta * 6.0, 0, 1))
	vm_flash.light_energy = maxf(0.0, vm_flash.light_energy - delta * 60.0)


func notify_ability_cast() -> void:
	_throw_t = 0.45
	cancel_reload()


# ================================================================== animation (process)
func process_update(delta: float) -> void:
	_time += delta
	if not is_instance_valid(camera):
		return
	vm_root.transform = Transform3D.IDENTITY
	vm_camera.transform = Transform3D.IDENTITY
	_update_vm_light(delta)
	var want_ads: bool = Input.is_action_pressed("aim") and not reloading and player.sprint_amount < 0.3 and equip_t >= 1.0 and enabled and player.is_alive() and player.can_act()
	ads = move_toward(ads, 1.0 if want_ads else 0.0, delta * 7.5)
	var e_ads := ease(ads, -1.8)
	vm_camera.fov = lerpf(56.0, 46.0, e_ads)
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			for f in _flash_nodes:
				f.visible = false
	# Springs, integrated in fixed sub-steps so they stay stable at any frame rate.
	var k := 260.0
	var c := 26.0
	var steps := clampi(ceili(delta / 0.004), 1, 60)
	var h := delta / steps
	for _i in steps:
		_kick_v += (-_kick * k - _kick_v * c) * h
		_kick += _kick_v * h
	_sway = _sway.lerp(_sway_target, clampf(delta * 14.0, 0, 1))
	_sway_target = _sway_target.lerp(Vector2.ZERO, clampf(delta * 7.0, 0, 1))
	var w = state()
	var d: WeaponData = w.data
	var id := d.id
	var gun: Node3D = w.rig.get_node("Gun")
	var hip: Vector3 = HIP[id]
	var hip_rot: Vector3 = HIP_ROT[id]
	var sight: Node3D = gun.get_node("Sight")
	var ads_pos := Vector3(0, -sight.position.y, -0.12 - (0.14 if id == "kite" else 0.0))
	var pos := hip.lerp(ads_pos, e_ads)
	var rot := hip_rot.lerp(Vector3.ZERO, e_ads)
	var still := 1.0 - 0.8 * e_ads
	# Movement bob
	var move: float = player.move_amount
	var sprint: float = player.sprint_amount
	var phase: float = player.bob_phase
	var amp := (0.011 + 0.013 * sprint) * move * still
	pos.x += sin(phase) * amp
	pos.y -= absf(cos(phase)) * amp * 1.1
	rot.z += sin(phase) * 0.02 * move * still
	# Sprint pose
	var es := ease(sprint, -1.6)
	pos += Vector3(0.02, -0.035, 0.03) * es
	rot += Vector3(-0.22, 0.5, 0.24) * es
	# Airborne: the weapon floats up slightly and tilts back while jumping or falling.
	_air = move_toward(_air, 0.0 if player.is_on_floor() else 1.0, delta * 5.0)
	pos.y += 0.014 * _air * still
	rot.x += 0.06 * _air * still
	# Crouch, strafe lean, landing, breathing
	pos.y -= 0.012 * player.crouch_amount
	rot.z -= player.strafe_amount * 0.05 * still
	pos.y -= player.land_offset * 0.6
	rot.x -= player.land_offset * 1.5
	pos.y += sin(_time * 1.7) * 0.0016 * still
	rot.z += sin(_time * 0.9) * 0.006 * still
	# Mouse sway
	rot.y += _sway.x * 1.1 * lerpf(1.0, 0.3, e_ads)
	rot.x += _sway.y * 1.1 * lerpf(1.0, 0.3, e_ads)
	pos.x -= _sway.x * 0.06 * still
	# Recoil kick
	pos.z += _kick.x * 0.03
	rot.x += _kick.y * 0.035
	rot.z += _kick.z * 0.02
	# Equip
	var ee := ease(equip_t, 0.4)
	pos.y -= (1.0 - ee) * 0.22
	rot.x -= (1.0 - ee) * 0.9
	rot.z += (1.0 - ee) * 0.35
	# Ability throw gesture
	if _throw_t > 0.0:
		_throw_t -= delta
		var tk := sin(clampf(1.0 - _throw_t / 0.45, 0, 1) * PI)
		pos.y -= tk * 0.12
		rot.x -= tk * 0.5
		rot.z += tk * 0.3
	# Reload choreography
	var mag: Node3D = gun.get_node_or_null("Mag")
	var bolt: Node3D = gun.get_node_or_null("Bolt")
	var hand_l: Node3D = gun.get_node_or_null("HandL")
	var mag_base: Vector3 = mag.get_meta("base") if mag else Vector3.ZERO
	var hand_base: Vector3 = hand_l.get_meta("base") if hand_l else Vector3.ZERO
	var bolt_base: Vector3 = bolt.get_meta("base") if bolt else Vector3.ZERO
	var mag_off := Vector3.ZERO
	var mag_rot := 0.0
	var mag_vis := true
	var hand_pos := hand_base
	var bolt_off := 0.0
	if reloading:
		var t := clampf(reload_t / reload_dur, 0.0, 1.0)
		var tilt := smoothstep(0.0, 0.15, t) - smoothstep(0.78, 0.96, t)
		rot.z += 0.55 * tilt * (0.6 if id == "kite" else 1.0)
		rot.x += 0.14 * tilt
		pos.x -= 0.02 * tilt
		pos.y += 0.01 * tilt
		var drop := smoothstep(0.16, 0.38, t)
		var insert := smoothstep(0.44, 0.66, t)
		if t < 0.41:
			mag_off = Vector3(0, -0.5, 0.08) * drop * drop
			mag_rot = 0.35 * drop
		else:
			mag_off = Vector3(0, -0.32, 0.06).lerp(Vector3.ZERO, insert)
			mag_rot = 0.25 * (1.0 - insert)
		mag_vis = not (t > 0.38 and t < 0.44)
		var hold := mag_base + mag_off + Vector3(-0.03, -0.075, 0.02)
		var to_mag := smoothstep(0.1, 0.2, t)
		var back := smoothstep(0.68, 0.8, t)
		if reload_empty and bolt and id != "kite":
			var bolt_hold := bolt_base + Vector3(0.0, -0.02, 0.0)
			var to_bolt := smoothstep(0.66, 0.74, t) - smoothstep(0.88, 0.97, t)
			back = smoothstep(0.9, 0.98, t)
			bolt_off = 0.07 * (smoothstep(0.75, 0.8, t) - smoothstep(0.82, 0.86, t))
			hand_pos = hand_base.lerp(hold, to_mag * (1.0 - smoothstep(0.64, 0.7, t)))
			hand_pos = hand_pos.lerp(bolt_hold + Vector3(0, 0, bolt_off), to_bolt)
		else:
			hand_pos = hand_base.lerp(hold, to_mag * (1.0 - back))
		if id == "kite" and reload_empty:
			bolt_off = 0.03 * (1.0 - smoothstep(0.84, 0.9, t))
		pos.y -= 0.012 * (smoothstep(0.62, 0.65, t) - smoothstep(0.65, 0.72, t))
	elif id == "kite" and w.mag == 0:
		bolt_off = 0.03
	if _slide_t > 0.0:
		_slide_t -= delta
		if id == "kite":
			bolt_off = maxf(bolt_off, 0.03 * clampf(_slide_t / 0.06, 0, 1))
	if mag:
		mag.position = mag_base + mag_off
		mag.rotation = mag.get_meta("base_rot") + Vector3(mag_rot, 0, 0)
		mag.visible = mag_vis
	if hand_l:
		hand_l.position = hand_pos
	if bolt:
		bolt.position = bolt_base + Vector3(0, 0, bolt_off)
	vm_sway.position = pos
	vm_sway.rotation = rot
