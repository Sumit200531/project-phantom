class_name ReconPulse
extends Node3D
## "Echo Pulse" — a sonar sweep that reveals every enemy within RADIUS (through walls) to the
## caster's team for REVEAL_TIME seconds. Revealed enemies glow through geometry and appear on
## the minimap; bots on the caster's team receive their positions as intel.

const RADIUS := 28.0
const REVEAL_TIME := 4.0

var team := 0
var caster: Combatant
var _t := 0.0
var _done := false
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D


static func emit(owner_unit: Combatant) -> void:
	var p: ReconPulse = load("res://scenes/abilities/recon_pulse.tscn").instantiate()
	p.team = owner_unit.team
	p.caster = owner_unit
	# The ability root sits at the world origin, so a local position is a world position.
	p.position = owner_unit.global_position + Vector3(0, 0.05, 0)
	MatchManager.ability_root().add_child(p)


func _ready() -> void:
	add_to_group("ability_objects")
	var color := GameConst.COLOR_CYAN if team == MatchManager.viewer_team() else Color(1.0, 0.45, 0.25)
	Sfx.play_at("recon_pulse", global_position + Vector3(0, 1.2, 0), 0.0, 60.0)
	MatchManager.report_sound(global_position, team, 30.0)
	Fx.pulse_sphere(global_position + Vector3(0, 1.0, 0), RADIUS, color, 1.1)
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.96
	tm.outer_radius = 1.0
	tm.rings = 64
	tm.ring_segments = 6
	_ring.mesh = tm
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ring_mat.albedo_color = Color(color.r * 2.0, color.g * 2.0, color.b * 2.0, 1.0)
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.scale = Vector3(0.1, 0.4, 0.1)
	add_child(_ring)


func _process(delta: float) -> void:
	_t += delta
	var k := clampf(_t / 1.1, 0.0, 1.0)
	var r := lerpf(0.5, RADIUS, ease(k, 0.6))
	_ring.scale = Vector3(r, 0.4, r)
	_ring_mat.albedo_color.a = 1.0 - k
	if not _done and _t >= 0.35:
		_done = true
		var revealed := 0
		for u in MatchManager.all_units():
			if u.team == team or not u.is_alive():
				continue
			if u.global_position.distance_to(global_position) <= RADIUS:
				u.reveal_to(team, REVEAL_TIME)
				MatchManager.report_enemy_seen(team, u)
				revealed += 1
		if revealed > 0 and team == MatchManager.viewer_team():
			Sfx.play("reveal_tick", -4.0, 0.0)
	if _t >= 1.3:
		queue_free()
