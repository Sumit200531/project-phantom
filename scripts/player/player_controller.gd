class_name PlayerController
extends Combatant
## First-person player: responsive acceleration-based movement, sprint, crouch, jump with
## coyote time + buffering, landing feedback, interpolated camera with bob/tilt, recoil,
## abilities and objective interaction.

signal interact_progress(kind: String, fraction: float)
signal landed_hard(strength: float)

const WALK_SPEED := 5.6
const SPRINT_SPEED := 7.4
const CROUCH_SPEED := 2.9
const GROUND_ACCEL := 58.0
const GROUND_DECEL := 50.0
const AIR_ACCEL := 9.0
const JUMP_VELOCITY := 5.9
const COYOTE := 0.11
const JUMP_BUFFER := 0.13
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.2
const EYE_STAND := 1.62
const EYE_CROUCH := 1.06
const RADIUS := 0.36

var camera_rig: Node3D
var camera: Camera3D
var weapons: WeaponManager
var collision: CollisionShape3D
var capsule: CapsuleShape3D
var hitbox_root: Node3D
var _hb_head: Hitbox
var _hb_body: Hitbox
var _hb_legs: Hitbox

var yaw := 0.0
var pitch := 0.0
var recoil := Vector2.ZERO          # aim offset (pitch, yaw) from recoil, recovers over time
var punch := Vector2.ZERO           # visual-only camera punch
var _punch_v := Vector2.ZERO
var _smooth_target := Vector2.ZERO
var _last_recoil_t := -9.0

var move_amount := 0.0              # 0..1 for bob intensity
var sprint_amount := 0.0
var crouch_amount := 0.0
var strafe_amount := 0.0
var bob_phase := 0.0
var land_offset := 0.0
var _land_v := 0.0
var _coyote := 0.0
var _jump_buffer := 0.0
var _prev_pos := Vector3.ZERO
var _cur_pos := Vector3.ZERO
var _fov_current := 74.0
var _tilt := 0.0
var input_locked := false
var spectate_target: Combatant = null
var death_time := -9.0
var killer: Combatant = null
static var force_active := false   # set by the autotest driver (no mouse capture there)


func _ready() -> void:
	is_player = true
	unit_name = "You"
	_setup_combatant()
	collision = CollisionShape3D.new()
	capsule = CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = STAND_HEIGHT
	collision.shape = capsule
	collision.position.y = STAND_HEIGHT * 0.5
	add_child(collision)
	hitbox_root = Node3D.new()
	hitbox_root.name = "Hitboxes"
	add_child(hitbox_root)
	var head_shape := SphereShape3D.new()
	head_shape.radius = 0.17
	_hb_head = Hitbox.create(self, "head", head_shape, Vector3(0, 1.62, 0))
	var body_shape := BoxShape3D.new()
	body_shape.size = Vector3(0.5, 0.58, 0.32)
	_hb_body = Hitbox.create(self, "body", body_shape, Vector3(0, 1.15, 0))
	var legs_shape := BoxShape3D.new()
	legs_shape.size = Vector3(0.38, 0.86, 0.3)
	_hb_legs = Hitbox.create(self, "legs", legs_shape, Vector3(0, 0.44, 0))
	for hb in [_hb_head, _hb_body, _hb_legs]:
		hitbox_root.add_child(hb)
		hitboxes.append(hb)
	camera_rig = Node3D.new()
	camera_rig.name = "CameraRig"
	camera_rig.top_level = true
	add_child(camera_rig)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.cull_mask = GameConst.VIS_WORLD_ONLY_MASK
	camera.near = 0.04
	camera.far = 450.0
	camera.fov = Settings.fov
	camera_rig.add_child(camera)
	weapons = WeaponManager.new()
	weapons.name = "Weapons"
	add_child(weapons)
	weapons.setup(self, camera)
	_cur_pos = global_position
	_prev_pos = global_position


func activate_camera() -> void:
	camera.make_current()


func can_act() -> bool:
	return is_alive() and not input_locked and not MatchManager.is_interacting(self)


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func eye_height() -> float:
	return lerpf(EYE_STAND, EYE_CROUCH, crouch_amount)


func eye_position() -> Vector3:
	return global_position + Vector3(0, eye_height(), 0)


func head_position() -> Vector3:
	return _hb_head.global_position


func chest_position() -> Vector3:
	return _hb_body.global_position


func aim_direction() -> Vector3:
	return -camera.global_transform.basis.z


func add_recoil(p: float, y: float, kick: float) -> void:
	recoil += Vector2(p, y)
	recoil.x = minf(recoil.x, 0.2)
	_last_recoil_t = MatchManager.now()
	_punch_v += Vector2(0.9 * kick, randf_range(-0.4, 0.4) * kick)


func reset_for_round(xf: Transform3D) -> void:
	super.reset_for_round(xf)
	yaw = xf.basis.get_euler().y
	pitch = 0.0
	recoil = Vector2.ZERO
	punch = Vector2.ZERO
	crouch_amount = 0.0
	sprint_amount = 0.0
	capsule.height = STAND_HEIGHT
	collision.position.y = STAND_HEIGHT * 0.5
	_cur_pos = global_position
	_prev_pos = global_position
	spectate_target = null
	killer = null
	weapons.reset_for_round()
	weapons.set_viewmodel_visible(true)
	weapons.enabled = true
	activate_camera()


# ================================================================== input
func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not force_active:
		return
	if event is InputEventMouseMotion:
		if not is_alive():
			return
		var rel: Vector2 = event.screen_relative
		var sens := Settings.sensitivity_radians() * lerpf(1.0, weapons.data().ads_fov_mult, weapons.ads)
		var dy := rel.y * (-1.0 if Settings.invert_y else 1.0)
		if Settings.mouse_smoothing > 0.01:
			_smooth_target += Vector2(-rel.x * sens, -dy * sens)
		else:
			yaw -= rel.x * sens
			pitch = clampf(pitch - dy * sens, -1.55, 1.55)
		weapons.on_mouse_motion(rel)
		return
	if not is_alive():
		if event.is_action_pressed("fire"):
			MatchManager.instance.cycle_spectate()
		return
	if not can_act():
		return
	weapons.handle_input_event(event)
	for i in 3:
		if event.is_action_pressed(AbilityKit.DEFS[i].action):
			if abilities.use(i, eye_position(), aim_direction()):
				weapons.notify_ability_cast()
			elif not abilities.is_ready(i) or not MatchManager.abilities_allowed():
				Sfx.play("ability_denied", -6.0, 0.0)


# ================================================================== physics
func _physics_process(delta: float) -> void:
	_prev_pos = _cur_pos
	if not is_alive():
		velocity.x = move_toward(velocity.x, 0, GROUND_DECEL * delta)
		velocity.z = move_toward(velocity.z, 0, GROUND_DECEL * delta)
		velocity.y -= gravity * delta
		move_and_slide()
		_cur_pos = global_position
		return
	var active := can_act() and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or force_active)
	var input_dir := Vector2.ZERO
	if active:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var basis_flat := Basis(Vector3.UP, yaw)
	var wish := basis_flat * Vector3(input_dir.x, 0, input_dir.y)
	if wish.length() > 1.0:
		wish = wish.normalized()
	# Crouch with headroom check
	var want_crouch := active and Input.is_action_pressed("crouch")
	if not want_crouch and crouch_amount > 0.0:
		var extra := (STAND_HEIGHT - capsule.height) + 0.02
		if test_move(global_transform, Vector3(0, extra, 0)):
			want_crouch = true
	crouch_amount = move_toward(crouch_amount, 1.0 if want_crouch else 0.0, delta * 8.0)
	var h := lerpf(STAND_HEIGHT, CROUCH_HEIGHT, crouch_amount)
	capsule.height = h
	collision.position.y = h * 0.5
	hitbox_root.position.y = (h - STAND_HEIGHT) * 0.9
	# Sprint: forward-ish input, not crouched, not aiming, not firing
	var forward_k := -input_dir.y
	var firing := MatchManager.now() - weapons.last_shot < 0.25
	var want_sprint := active and Input.is_action_pressed("sprint") and forward_k > 0.3 and crouch_amount < 0.3 and weapons.ads < 0.2 and not firing and is_on_floor()
	sprint_amount = move_toward(sprint_amount, 1.0 if want_sprint else 0.0, delta * (6.0 if want_sprint else 9.0))
	var target_speed := lerpf(WALK_SPEED, SPRINT_SPEED, sprint_amount)
	# Crouch speed applies as soon as crouch is held (the camera still blends smoothly).
	target_speed = lerpf(target_speed, CROUCH_SPEED, 1.0 if want_crouch else crouch_amount)
	target_speed *= weapons.data().move_speed_mult * lerpf(1.0, 0.72, weapons.ads)
	if MatchManager.is_interacting(self):
		target_speed = 0.0
	var target_vel := wish * target_speed
	var hv := Vector3(velocity.x, 0, velocity.z)
	if is_on_floor():
		var accel := GROUND_ACCEL if wish.length() > 0.01 else GROUND_DECEL
		# Snappier direction changes (counter-strafing feels crisp)
		if wish.length() > 0.01 and hv.dot(target_vel) < 0.0:
			accel *= 1.6
		hv = hv.move_toward(target_vel, accel * delta)
		_coyote = COYOTE
	else:
		hv = hv.move_toward(target_vel, AIR_ACCEL * delta) if wish.length() > 0.01 else hv
		_coyote -= delta
	velocity.x = hv.x
	velocity.z = hv.z
	# Jump (buffered + coyote)
	if active and Input.is_action_just_pressed("jump"):
		_jump_buffer = JUMP_BUFFER
	else:
		_jump_buffer -= delta
	if _jump_buffer > 0.0 and _coyote > 0.0 and crouch_amount < 0.5:
		velocity.y = JUMP_VELOCITY
		_jump_buffer = 0.0
		_coyote = 0.0
		Sfx.play("jump", -10.0)
		MatchManager.report_sound(global_position, team, 10.0)
	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()
	_cur_pos = global_position
	# Footsteps: sprinting is loud, walking normal, crouching silent.
	var loud := lerpf(0.75, 1.0, sprint_amount) * (1.0 - crouch_amount)
	update_footsteps(delta, loud, lerpf(2.3, 2.9, sprint_amount))
	# Bob/tilt drivers
	var hs := horizontal_speed()
	move_amount = clampf(hs / WALK_SPEED, 0.0, 1.4) if is_on_floor() else lerpf(move_amount, 0.0, delta * 6.0)
	bob_phase += delta * hs * lerpf(1.45, 1.25, sprint_amount)
	var right := basis_flat.x
	strafe_amount = lerpf(strafe_amount, clampf(hv.dot(right) / WALK_SPEED, -1, 1), delta * 8.0)
	rotation.y = yaw
	# Recoil recovery
	if MatchManager.now() - _last_recoil_t > 0.09:
		recoil = recoil.lerp(Vector2.ZERO, clampf(delta * weapons.data().recoil_recovery, 0, 1))
	weapons.physics_update(delta, active)
	# Interaction must not depend on can_act(): planting/defusing itself locks other actions.
	var can_interact := is_alive() and not input_locked and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or force_active)
	MatchManager.instance.player_interaction(self, delta, can_interact and Input.is_action_pressed("interact"))


func _on_landed(speed: float) -> void:
	var strength := clampf((speed - 3.0) / 9.0, 0.0, 1.0)
	_land_v -= 0.6 + strength * 1.6
	landed_hard.emit(strength)


# ================================================================== camera (render rate, interpolated)
func _process(delta: float) -> void:
	if Settings.mouse_smoothing > 0.01:
		var k := clampf(delta * lerpf(60.0, 12.0, Settings.mouse_smoothing), 0, 1)
		var step := _smooth_target * k
		_smooth_target -= step
		yaw += step.x
		pitch = clampf(pitch + step.y, -1.55, 1.55)
	# Springs: landing dip and visual punch.
	var steps := clampi(ceili(delta / 0.004), 1, 60)
	var h := delta / steps
	for _i in steps:
		_land_v += (-land_offset * 120.0 - _land_v * 14.0) * h
		land_offset += _land_v * h
		_punch_v += (-punch * 180.0 - _punch_v * 20.0) * h
		punch += _punch_v * h * 0.02
	land_offset = clampf(land_offset, -0.25, 0.25)
	if not is_alive():
		_update_spectator_camera(delta)
		weapons.set_viewmodel_visible(false)
		return
	var frac := Engine.get_physics_interpolation_fraction()
	var body_pos := _prev_pos.lerp(_cur_pos, frac)
	var bob_scale := Settings.head_bob * lerpf(1.0, 0.25, weapons.ads) * (1.0 - 0.5 * crouch_amount)
	var bob := Vector3(sin(bob_phase) * 0.028, -absf(cos(bob_phase)) * 0.042 * (1.0 + 0.5 * sprint_amount), 0) * move_amount * bob_scale
	camera_rig.global_position = body_pos + Vector3(0, eye_height() + land_offset * 0.5, 0)
	camera_rig.rotation = Vector3(pitch + recoil.x, yaw + recoil.y, 0)
	_tilt = lerpf(_tilt, -strafe_amount * deg_to_rad(1.3) + sin(bob_phase) * 0.004 * move_amount * bob_scale, clampf(delta * 10.0, 0, 1))
	camera.position = bob
	camera.rotation = Vector3(punch.x * 0.02 + land_offset * -0.2, punch.y * 0.01, _tilt)
	var target_fov := Settings.fov * lerpf(1.0, weapons.data().ads_fov_mult, ease(weapons.ads, -1.8)) + 5.0 * sprint_amount
	_fov_current = lerpf(_fov_current, target_fov, clampf(delta * 12.0, 0, 1))
	camera.fov = _fov_current
	weapons.process_update(delta)


func _update_spectator_camera(delta: float) -> void:
	var t := MatchManager.now() - death_time
	if t < 2.2 or spectate_target == null or not is_instance_valid(spectate_target) or not spectate_target.is_alive():
		# Death cam: drift up and look toward the killer.
		var base := _cur_pos + Vector3(0, 1.0 + minf(t, 2.0) * 0.6, 0)
		camera_rig.global_position = camera_rig.global_position.lerp(base, clampf(delta * 3.0, 0, 1))
		if killer and is_instance_valid(killer):
			var to := killer.global_position + Vector3(0, 1.3, 0) - camera_rig.global_position
			if to.length() > 0.5:
				var target_yaw := atan2(-to.x, -to.z)
				var target_pitch := atan2(to.y, Vector2(to.x, to.z).length())
				yaw = lerp_angle(yaw, target_yaw, clampf(delta * 3.0, 0, 1))
				pitch = lerpf(pitch, target_pitch, clampf(delta * 3.0, 0, 1))
		camera_rig.rotation = Vector3(pitch, yaw, 0)
		camera.position = Vector3.ZERO
		camera.rotation = Vector3(0, 0, lerpf(camera.rotation.z, 0.25, clampf(delta * 2.0, 0, 1)))
		if t >= 2.2 and (spectate_target == null or not spectate_target.is_alive()):
			MatchManager.instance.cycle_spectate()
		return
	var tgt := spectate_target
	var eye := tgt.eye_position()
	var fwd := tgt.aim_direction()
	var desired := eye - Vector3(fwd.x, 0, fwd.z).normalized() * 2.4 + Vector3(0, 0.5, 0)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(eye, desired, GameConst.LAYER_WORLD)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		desired = hit.position + (eye - desired).normalized() * 0.3
	camera_rig.global_position = camera_rig.global_position.lerp(desired, clampf(delta * 8.0, 0, 1))
	var look := eye + fwd * 6.0 - camera_rig.global_position
	camera_rig.rotation = Vector3(atan2(look.y, Vector2(look.x, look.z).length()), atan2(-look.x, -look.z), 0)
	camera.position = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	camera.fov = lerpf(camera.fov, Settings.fov, clampf(delta * 6.0, 0, 1))


func _on_death(info: Dictionary) -> void:
	death_time = MatchManager.now()
	killer = info.get("attacker") if info.get("attacker") is Combatant else null
	weapons.cancel_reload()
	weapons.enabled = false
	weapons.set_viewmodel_visible(false)
	velocity.y = 2.0
	Sfx.play("hurt", 0.0, 0.0)


func _on_hit_reaction(info: Dictionary) -> void:
	Sfx.play("hurt", -6.0, 0.08)
	# Small view punch only: no knockback or aim displacement, which keeps duels fair.
	_punch_v += Vector2(randf_range(-0.6, 0.6), randf_range(-0.8, 0.8)) * (2.0 if info.get("part") == "head" else 1.0)
