extends Node3D
## Autoload "Fx": pooled combat effects — tracers, impacts, bullet decals, shell casings,
## muzzle lights and explosions. Everything is pooled so sustained fire stays cheap.

const TRACER_POOL := 48
const SPARK_POOL := 24
const DUST_POOL := 16
const DECAL_POOL := 72
const SHELL_POOL := 40
const LIGHT_POOL := 6

var decals_enabled := true

var _tracers: Array = []          # [{mesh, from, to, dist, travelled, len, active}]
var _ti := 0
var _sparks: Array[CPUParticles3D] = []
var _si := 0
var _unit_sparks: Array[CPUParticles3D] = []
var _usi := 0
var _dust: Array[CPUParticles3D] = []
var _di := 0
var _decals: Array[Decal] = []
var _dci := 0
var _shells: Array = []           # [{mesh, vel, spin, life, bounced}]
var _shi := 0
var _lights: Array = []           # [{light, life}]
var _li := 0
var _transient: Array = []        # [{node, life, max, kind, data}]

var _tracer_mat_ally: StandardMaterial3D
var _tracer_mat_enemy: StandardMaterial3D
var _tex_hole: Texture2D
var _tex_scorch: Texture2D
var _tex_puff: Texture2D
var _tex_glow: Texture2D


func _ready() -> void:
	_tex_hole = _tex("bullet_hole.png")
	_tex_scorch = _tex("scorch.png")
	_tex_puff = _tex("smoke_puff.png")
	_tex_glow = _tex("glow.png")
	_tracer_mat_ally = _additive(Color(1.0, 0.86, 0.55), 4.0)
	_tracer_mat_enemy = _additive(Color(1.0, 0.55, 0.4), 4.0)
	var tracer_mesh := BoxMesh.new()
	tracer_mesh.size = Vector3(0.022, 0.022, 1.0)
	for i in TRACER_POOL:
		var m := MeshInstance3D.new()
		m.mesh = tracer_mesh
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.layers = GameConst.VIS_WORLD
		m.visible = false
		add_child(m)
		_tracers.append({"mesh": m, "active": false})
	for i in SPARK_POOL:
		_sparks.append(_make_sparks(Color(1.0, 0.75, 0.35)))
	for i in 12:
		_unit_sparks.append(_make_sparks(Color(0.5, 1.0, 0.95)))
	for i in DUST_POOL:
		_dust.append(_make_dust())
	for i in DECAL_POOL:
		var d := Decal.new()
		d.texture_albedo = _tex_hole
		d.size = Vector3(0.13, 0.12, 0.13)
		d.cull_mask = GameConst.VIS_WORLD
		d.upper_fade = 0.2
		d.lower_fade = 0.2
		d.visible = false
		add_child(d)
		_decals.append(d)
	var shell_mesh := CylinderMesh.new()
	shell_mesh.top_radius = 0.0055
	shell_mesh.bottom_radius = 0.0055
	shell_mesh.height = 0.028
	shell_mesh.radial_segments = 6
	shell_mesh.rings = 1
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.85, 0.62, 0.25)
	brass.metallic = 0.9
	brass.roughness = 0.3
	shell_mesh.material = brass
	for i in SHELL_POOL:
		var s := MeshInstance3D.new()
		s.mesh = shell_mesh
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.visible = false
		add_child(s)
		_shells.append({"mesh": s, "life": 0.0, "vel": Vector3.ZERO, "spin": Vector3.ZERO, "bounced": false})
	for i in LIGHT_POOL:
		var l := OmniLight3D.new()
		l.omni_range = 6.0
		l.light_energy = 0.0
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		_lights.append({"light": l, "life": 0.0, "max": 0.05, "energy": 2.0})


func _tex(file: String) -> Texture2D:
	var path := "res://assets/textures/" + file
	if ResourceLoader.exists(path):
		return load(path)
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 1))
	grad.set_color(1, Color(0, 0, 0, 0))
	g.gradient = grad
	return g


func _additive(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = color * energy
	m.albedo_color.a = 1.0
	m.disable_receive_shadows = true
	return m


func _make_sparks(color: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 10
	p.lifetime = 0.35
	p.explosiveness = 1.0
	p.local_coords = false
	p.direction = Vector3(0, 1, 0)
	p.spread = 40.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 8.5
	p.gravity = Vector3(0, -14, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var q := QuadMesh.new()
	q.size = Vector2(0.025, 0.025)
	var mat := _additive(color, 3.0)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = _tex_glow
	q.material = mat
	p.mesh = q
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	add_child(p)
	return p


func _make_dust() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 5
	p.lifetime = 0.9
	p.explosiveness = 0.95
	p.local_coords = false
	p.direction = Vector3(0, 1, 0)
	p.spread = 30.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0, 0.3, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.4
	var q := QuadMesh.new()
	q.size = Vector2(0.3, 0.3)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = _tex_puff
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	q.material = mat
	p.mesh = q
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.5))
	grow.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = grow
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.75, 0.72, 0.68, 0.55))
	ramp.set_color(1, Color(0.75, 0.72, 0.68, 0.0))
	p.color_ramp = ramp
	add_child(p)
	return p


# ------------------------------------------------------------------ public API
func tracer(from: Vector3, to: Vector3, enemy := false) -> void:
	var dist := from.distance_to(to)
	if dist < 1.0:
		return
	var t = _tracers[_ti]
	_ti = (_ti + 1) % TRACER_POOL
	var m: MeshInstance3D = t.mesh
	m.material_override = _tracer_mat_enemy if enemy else _tracer_mat_ally
	t.from = from
	t.to = to
	t.dist = dist
	t.travelled = 0.0
	t.len = minf(5.0, dist * 0.5)
	t.active = true
	m.visible = true
	_place_tracer(t)


func impact(pos: Vector3, normal: Vector3, surface := "concrete", on_unit := false) -> void:
	if on_unit:
		var us := _unit_sparks[_usi]
		_usi = (_usi + 1) % _unit_sparks.size()
		_emit(us, pos, normal)
		return
	var sp := _sparks[_si]
	_si = (_si + 1) % SPARK_POOL
	sp.amount = 14 if surface == "metal" else 7
	_emit(sp, pos, normal)
	if surface != "metal":
		var d := _dust[_di]
		_di = (_di + 1) % DUST_POOL
		var c := Color(0.45, 0.5, 0.3, 0.5) if surface == "grass" else Color(0.78, 0.74, 0.68, 0.55)
		d.color_ramp.set_color(0, c)
		d.color_ramp.set_color(1, Color(c.r, c.g, c.b, 0.0))
		_emit(d, pos, normal)


func _emit(p: CPUParticles3D, pos: Vector3, normal: Vector3) -> void:
	p.global_position = pos + normal * 0.02
	p.direction = normal
	p.restart()
	p.emitting = true


func bullet_hole(pos: Vector3, normal: Vector3, scorch := false) -> void:
	if not decals_enabled:
		return
	var d := _decals[_dci]
	_dci = (_dci + 1) % DECAL_POOL
	d.texture_albedo = _tex_scorch if scorch else _tex_hole
	var s := 3.5 if scorch else randf_range(0.11, 0.15)
	d.size = Vector3(s, 0.12 if not scorch else 1.0, s)
	var up := normal.normalized()
	var ref := Vector3.UP if absf(up.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(up).normalized()
	var z := x.cross(up).normalized()
	var b := Basis(x, up, z).rotated(up, randf() * TAU)
	d.global_transform = Transform3D(b, pos)
	d.visible = true


func shell(pos: Vector3, vel: Vector3) -> void:
	var s = _shells[_shi]
	_shi = (_shi + 1) % SHELL_POOL
	var m: MeshInstance3D = s.mesh
	m.global_position = pos
	m.rotation = Vector3(randf() * TAU, randf() * TAU, 0)
	s.vel = vel
	s.spin = Vector3(randf_range(-20, 20), randf_range(-20, 20), randf_range(-20, 20))
	s.life = 2.5
	s.bounced = false
	m.visible = true


func flash_light(pos: Vector3, color := Color(1.0, 0.75, 0.4), energy := 2.2, duration := 0.05, light_range := 6.0) -> void:
	var l = _lights[_li]
	_li = (_li + 1) % LIGHT_POOL
	var light: OmniLight3D = l.light
	light.global_position = pos
	light.light_color = color
	light.omni_range = light_range
	light.light_energy = energy
	light.visible = true
	l.life = duration
	l.max = duration
	l.energy = energy


func explosion(pos: Vector3) -> void:
	flash_light(pos + Vector3.UP * 2.0, Color(1.0, 0.6, 0.3), 16.0, 0.9, 40.0)
	var sphere := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sphere.mesh = sm
	var mat := _additive(Color(1.0, 0.55, 0.25), 2.0)
	sphere.material_override = mat
	sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sphere)
	sphere.global_position = pos + Vector3.UP
	_transient.append({"node": sphere, "life": 1.1, "max": 1.1, "kind": "shock", "mat": mat})
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.0
	ring.mesh = tm
	var rmat := _additive(Color(0.4, 0.95, 1.0), 2.5)
	ring.material_override = rmat
	add_child(ring)
	ring.global_position = pos + Vector3.UP * 0.3
	_transient.append({"node": ring, "life": 1.4, "max": 1.4, "kind": "ring", "mat": rmat})
	var debris := _make_sparks(Color(1.0, 0.7, 0.3))
	debris.amount = 80
	debris.lifetime = 1.4
	debris.spread = 180.0
	debris.initial_velocity_min = 6.0
	debris.initial_velocity_max = 22.0
	(debris.mesh as QuadMesh).size = Vector2(0.12, 0.12)
	_emit(debris, pos + Vector3.UP, Vector3.UP)
	_transient.append({"node": debris, "life": 1.6, "max": 1.6, "kind": "free", "mat": null})
	var smoke := _make_dust()
	smoke.amount = 26
	smoke.lifetime = 3.0
	smoke.spread = 180.0
	smoke.initial_velocity_min = 2.0
	smoke.initial_velocity_max = 7.0
	(smoke.mesh as QuadMesh).size = Vector2(3.0, 3.0)
	smoke.color_ramp.set_color(0, Color(0.25, 0.22, 0.2, 0.8))
	smoke.color_ramp.set_color(1, Color(0.25, 0.22, 0.2, 0.0))
	_emit(smoke, pos + Vector3.UP, Vector3.UP)
	_transient.append({"node": smoke, "life": 3.2, "max": 3.2, "kind": "free", "mat": null})
	bullet_hole(pos + Vector3.UP * 0.05, Vector3.UP, true)


## Expanding translucent shell used by the recon pulse.
func pulse_sphere(pos: Vector3, radius: float, color: Color, duration := 1.0) -> void:
	var sphere := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 48
	sm.rings = 24
	sphere.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(color.r, color.g, color.b, 0.35)
	mat.rim_enabled = true
	sphere.material_override = mat
	sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sphere)
	sphere.global_position = pos
	_transient.append({"node": sphere, "life": duration, "max": duration, "kind": "pulse", "mat": mat, "radius": radius})


func clear_dynamic() -> void:
	for d in _decals:
		d.visible = false
	for s in _shells:
		s.mesh.visible = false
		s.life = 0.0
	for t in _tracers:
		t.active = false
		t.mesh.visible = false
	for tr in _transient:
		if is_instance_valid(tr.node):
			tr.node.queue_free()
	_transient.clear()


# ------------------------------------------------------------------ update
func _process(delta: float) -> void:
	for t in _tracers:
		if not t.active:
			continue
		t.travelled += 420.0 * delta
		if t.travelled - t.len >= t.dist:
			t.active = false
			t.mesh.visible = false
		else:
			_place_tracer(t)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state if get_world_3d() else null
	for s in _shells:
		if s.life <= 0.0:
			continue
		s.life -= delta
		var m: MeshInstance3D = s.mesh
		if s.life <= 0.0:
			m.visible = false
			continue
		if s.vel.length_squared() > 0.0001:
			s.vel += Vector3(0, -9.8, 0) * delta
			var next: Vector3 = m.global_position + s.vel * delta
			if space:
				var q := PhysicsRayQueryParameters3D.create(m.global_position, next, GameConst.LAYER_WORLD)
				var hit := space.intersect_ray(q)
				if not hit.is_empty():
					next = hit.position + hit.normal * 0.01
					if not s.bounced:
						s.bounced = true
						Sfx.play_at("shell", next, -16.0, 14.0, 0.15, 2.0)
						s.vel = s.vel.bounce(hit.normal) * 0.3
					else:
						s.vel = Vector3.ZERO
			m.global_position = next
			m.rotation += s.spin * delta
	for l in _lights:
		if l.life <= 0.0:
			continue
		l.life -= delta
		var light: OmniLight3D = l.light
		if l.life <= 0.0:
			light.visible = false
		else:
			light.light_energy = l.energy * (l.life / l.max)
	for i in range(_transient.size() - 1, -1, -1):
		var tr = _transient[i]
		tr.life -= delta
		var k: float = 1.0 - tr.life / tr.max
		if not is_instance_valid(tr.node) or tr.life <= 0.0:
			if is_instance_valid(tr.node):
				tr.node.queue_free()
			_transient.remove_at(i)
			continue
		match tr.kind:
			"shock":
				tr.node.scale = Vector3.ONE * lerpf(1.0, 13.0, ease(k, 0.4))
				tr.mat.albedo_color.a = 1.0 - k
			"ring":
				tr.node.scale = Vector3.ONE * lerpf(1.0, 22.0, ease(k, 0.35))
				tr.mat.albedo_color.a = 1.0 - k
			"pulse":
				tr.node.scale = Vector3.ONE * lerpf(0.5, tr.radius, ease(k, 0.6))
				tr.mat.albedo_color.a = 0.32 * (1.0 - k)


func _place_tracer(t: Dictionary) -> void:
	var dir: Vector3 = (t.to - t.from) / t.dist
	var head: float = minf(t.travelled, t.dist)
	var tail: float = maxf(0.0, t.travelled - t.len)
	var length := maxf(head - tail, 0.01)
	var mid: Vector3 = t.from + dir * ((head + tail) * 0.5)
	var m: MeshInstance3D = t.mesh
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
	m.global_transform = Transform3D(Basis.looking_at(dir, up) * Basis.from_scale(Vector3(1, 1, length)), mid)
