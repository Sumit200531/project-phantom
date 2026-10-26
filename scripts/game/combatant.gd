class_name Combatant
extends CharacterBody3D
## Shared base for the human player and bots: team, health, hitboxes, footsteps, abilities,
## reveal state and per-match statistics.

signal died(info: Dictionary)
signal took_damage(info: Dictionary)

var team := 0
var unit_name := "Operative"
var is_player := false
var health: HealthComponent
var abilities: AbilityKit
var hitboxes: Array[Hitbox] = []
var revealed_until := {0: -99.0, 1: -99.0}
var carrying_device := false
var surface := "concrete"
var gravity := 16.0
var invulnerable := false        # used by the screenshot driver only

# Stats
var kills := 0
var deaths := 0
var assists := 0
var damage_dealt := 0.0
var score := 0
var headshots := 0
var shots_hit := 0
var _damage_log := {}           # attacker -> last time they damaged us

var _step_accum := 0.0
var _was_on_floor := true
var _fall_speed := 0.0


func _setup_combatant() -> void:
	collision_layer = GameConst.LAYER_UNITS
	collision_mask = GameConst.UNIT_MOVE_MASK
	floor_max_angle = deg_to_rad(46.0)
	floor_snap_length = 0.45
	floor_constant_speed = true
	floor_block_on_wall = true
	health = HealthComponent.new()
	health.name = "Health"
	add_child(health)
	health.died.connect(_on_health_died)
	abilities = AbilityKit.new()
	abilities.name = "Abilities"
	add_child(abilities)
	abilities.setup(self)
	add_to_group("combatants")


func is_alive() -> bool:
	return health != null and health.alive


func eye_position() -> Vector3:
	return global_position + Vector3(0, 1.6, 0)


func head_position() -> Vector3:
	return global_position + Vector3(0, 1.62, 0)


func chest_position() -> Vector3:
	return global_position + Vector3(0, 1.2, 0)


func aim_direction() -> Vector3:
	return -global_transform.basis.z


func hitbox_rids() -> Array[RID]:
	var out: Array[RID] = []
	for hb in hitboxes:
		out.append(hb.get_rid())
	return out


func set_hitboxes_enabled(on: bool) -> void:
	for hb in hitboxes:
		hb.set_enabled(on)


func is_revealed_to(viewer_team: int) -> bool:
	return revealed_until.get(viewer_team, -99.0) > MatchManager.now()


func reveal_to(viewer_team: int, duration: float) -> void:
	revealed_until[viewer_team] = maxf(revealed_until.get(viewer_team, -99.0), MatchManager.now() + duration)


## Entry point for all damage (bullets, explosions).
func receive_damage(info: Dictionary) -> void:
	if not is_alive():
		return
	if not MatchManager.combat_enabled() or invulnerable:
		return
	var attacker = info.get("attacker")
	if attacker is Combatant and attacker != self:
		if attacker.team == team:
			return
		_damage_log[attacker] = MatchManager.now()
	var dealt := health.apply_damage(info)
	if attacker is Combatant and attacker != self:
		attacker.damage_dealt += dealt
		attacker.score += int(dealt)
	took_damage.emit(info)
	if is_alive():
		_on_hit_reaction(info)


func recent_damagers(window := 5.0) -> Array:
	var out := []
	var now := MatchManager.now()
	for a in _damage_log:
		if is_instance_valid(a) and now - _damage_log[a] <= window:
			out.append(a)
	return out


func reset_for_round(xf: Transform3D) -> void:
	global_transform = xf
	velocity = Vector3.ZERO
	health.reset(true)
	set_hitboxes_enabled(true)
	revealed_until = {0: -99.0, 1: -99.0}
	carrying_device = false
	_damage_log.clear()
	abilities.reset_for_round()
	_was_on_floor = true


func _on_health_died(info: Dictionary) -> void:
	set_hitboxes_enabled(false)
	_on_death(info)
	died.emit(info)


# --- virtual hooks ---
func _on_hit_reaction(_info: Dictionary) -> void:
	pass


func _on_death(_info: Dictionary) -> void:
	pass


# --- movement helpers shared by player and bots ---
func detect_surface() -> String:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.3, 0), global_position + Vector3(0, -0.6, 0), GameConst.LAYER_WORLD)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return surface
	var col: Object = hit.collider
	if col and col.has_meta("surface"):
		return col.get_meta("surface")
	return "concrete"


## Called every physics frame after move_and_slide. Plays footsteps / landing and reports noise.
func update_footsteps(delta: float, loudness: float, interval: float) -> void:
	var on_floor := is_on_floor()
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if on_floor and not _was_on_floor and _fall_speed > 3.0:
		surface = detect_surface()
		var vol := clampf(-14.0 + _fall_speed * 1.2, -18.0, -2.0)
		_play_step("land_" + surface, vol)
		_on_landed(_fall_speed)
		if loudness > 0.0:
			MatchManager.report_sound(global_position, team, 16.0)
	if not on_floor:
		_fall_speed = maxf(_fall_speed, -velocity.y)
	else:
		_fall_speed = 0.0
	_was_on_floor = on_floor
	if not on_floor or hspeed < 1.2:
		_step_accum = interval * 0.6
		return
	_step_accum += hspeed * delta
	if _step_accum >= interval:
		_step_accum = 0.0
		surface = detect_surface()
		if loudness > 0.0:
			_play_step("step_" + surface, linear_to_db(loudness) - 6.0)
			MatchManager.report_sound(global_position, team, 9.0 + 12.0 * loudness)


func _play_step(sound: String, vol_db: float) -> void:
	if is_player:
		Sfx.play(sound, vol_db - 4.0, 0.08)
	else:
		Sfx.play_at(sound, global_position, vol_db + 2.0, 32.0, 0.1, 3.0)


func _on_landed(_speed: float) -> void:
	pass
