class_name MaterialLib
extends RefCounted
## Central library of the facility's PBR materials.
## Each material is loaded from assets/materials/<name>.tres when present (so artists can tweak
## them in the editor) and otherwise built in code from the generated textures.

const TEX := "res://assets/textures/"
const MAT_DIR := "res://assets/materials/"

var _cache := {}
var _tex_cache := {}


func get_mat(mat_name: String) -> Material:
	if _cache.has(mat_name):
		return _cache[mat_name]
	var m: Material = null
	var path := MAT_DIR + mat_name + ".tres"
	if ResourceLoader.exists(path):
		m = load(path)
	if m == null:
		m = build(mat_name)
	_cache[mat_name] = m
	return m


func tex(file: String) -> Texture2D:
	if _tex_cache.has(file):
		return _tex_cache[file]
	var t: Texture2D = null
	if ResourceLoader.exists(TEX + file):
		t = load(TEX + file)
	_tex_cache[file] = t
	return t


func _pbr(albedo_tex: String, color: Color, rough: float, metal: float, scale: float, normal_strength := 1.0, rough_tex := "") -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	var at := tex(albedo_tex + "_albedo.png")
	if at:
		m.albedo_texture = at
	var nt := tex(albedo_tex + "_normal.png")
	if nt:
		m.normal_enabled = true
		m.normal_texture = nt
		m.normal_scale = normal_strength
	if rough_tex != "":
		var rt := tex(rough_tex + "_rough.png")
		if rt:
			m.roughness_texture = rt
			m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
	m.roughness = rough
	m.metallic = metal
	m.metallic_specular = 0.5
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3.ONE / scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _flat(color: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m


func _emit(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color * 0.35
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 0.4
	return m


func _glass(color: Color, alpha: float, rough := 0.05) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.roughness = rough
	m.metallic = 0.2
	m.metallic_specular = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func build(mat_name: String) -> Material:
	match mat_name:
		# --- structural surfaces (triplanar, world space) ---
		"concrete_wall": return _pbr("concrete_wall", Color(0.95, 0.9, 0.84), 1.0, 0.0, 8.0, 1.0, "concrete_wall")
		"concrete_dark": return _pbr("concrete_wall", Color(0.55, 0.53, 0.52), 1.0, 0.0, 8.0, 1.0, "concrete_wall")
		"concrete_floor": return _pbr("concrete_floor", Color(0.92, 0.9, 0.86), 1.0, 0.0, 6.0, 0.8, "concrete_floor")
		"concrete_plain": return _pbr("concrete_wall", Color(0.82, 0.8, 0.76), 1.0, 0.0, 3.0, 1.0, "concrete_wall")
		"roof": return _pbr("concrete_floor", Color(0.5, 0.5, 0.5), 1.0, 0.0, 8.0, 0.8)
		"metal_floor": return _pbr("metal_floor", Color(0.85, 0.88, 0.9), 1.0, 0.65, 2.5, 1.0, "metal_floor")
		"metal_floor_teal": return _pbr("metal_floor", Color(0.55, 0.78, 0.78), 1.0, 0.6, 2.5, 1.0, "metal_floor")
		"metal_panel": return _pbr("metal_panel", Color(0.34, 0.38, 0.42), 1.0, 0.45, 4.0, 1.0, "metal_panel")
		"metal_panel_teal": return _pbr("metal_panel", Color(0.17, 0.4, 0.42), 1.0, 0.4, 4.0, 1.0, "metal_panel")
		"metal_panel_white": return _pbr("metal_panel", Color(0.86, 0.89, 0.9), 1.0, 0.25, 4.0, 1.0, "metal_panel")
		"metal_panel_dark": return _pbr("metal_panel", Color(0.16, 0.18, 0.2), 1.0, 0.5, 4.0, 1.0, "metal_panel")
		"tiles": return _pbr("tiles", Color(0.95, 0.98, 0.97), 1.0, 0.0, 4.0, 0.8, "tiles")
		"asphalt": return _pbr("asphalt", Color(0.95, 0.95, 0.95), 1.0, 0.0, 8.0, 0.9, "asphalt")
		"grass": return _pbr("grass", Color(1, 1, 1), 0.95, 0.0, 5.0, 1.0)
		"hazard": return _pbr("hazard", Color(1, 1, 1), 0.6, 0.3, 1.6, 0.6)
		"facade_sand": return _pbr("facade", Color(0.93, 0.8, 0.64), 0.95, 0.0, 8.0, 1.0)
		"facade_terracotta": return _pbr("facade", Color(0.82, 0.48, 0.34), 0.95, 0.0, 8.0, 1.0)
		"facade_gray": return _pbr("facade", Color(0.7, 0.72, 0.72), 0.95, 0.0, 8.0, 1.0)
		"corrugated_orange": return _pbr("corrugated", Color(0.92, 0.45, 0.16), 1.0, 0.35, 4.0, 1.0, "corrugated")
		"corrugated_teal": return _pbr("corrugated", Color(0.16, 0.48, 0.5), 1.0, 0.35, 4.0, 1.0, "corrugated")
		"corrugated_graphite": return _pbr("corrugated", Color(0.24, 0.26, 0.29), 1.0, 0.4, 4.0, 1.0, "corrugated")
		"corrugated_red": return _pbr("corrugated", Color(0.62, 0.17, 0.13), 1.0, 0.35, 4.0, 1.0, "corrugated")
		"corrugated_cream": return _pbr("corrugated", Color(0.88, 0.84, 0.74), 1.0, 0.3, 4.0, 1.0, "corrugated")
		"bark": return _pbr("bark", Color(1, 1, 1), 0.95, 0.0, 1.5, 1.0)
		"foliage": return _pbr("foliage", Color(1.0, 1.0, 1.0), 0.85, 0.0, 2.0, 1.0)
		"foliage_light": return _pbr("foliage", Color(1.2, 1.15, 0.7), 0.85, 0.0, 2.0, 1.0)
		"foliage_dark": return _pbr("foliage", Color(0.62, 0.78, 0.6), 0.85, 0.0, 2.0, 1.0)
		"soil": return _pbr("grass", Color(0.42, 0.3, 0.2), 1.0, 0.0, 2.0, 1.0)
		# --- props ---
		"crate_olive": return _crate(Color(0.5, 0.54, 0.36))
		"crate_navy": return _crate(Color(0.3, 0.4, 0.52))
		"crate_orange": return _crate(Color(0.95, 0.55, 0.2))
		"metal_dark": return _flat(Color(0.11, 0.12, 0.14), 0.45, 0.75)
		"metal_bare": return _flat(Color(0.6, 0.62, 0.65), 0.3, 0.95)
		"metal_trim": return _flat(Color(0.22, 0.24, 0.27), 0.4, 0.8)
		"paint_teal": return _flat(Color(0.12, 0.5, 0.52), 0.45, 0.4)
		"paint_amber": return _flat(Color(0.96, 0.6, 0.15), 0.45, 0.3)
		"paint_red": return _flat(Color(0.65, 0.15, 0.12), 0.45, 0.3)
		"paint_white": return _flat(Color(0.88, 0.9, 0.9), 0.4, 0.2)
		"paint_graphite": return _flat(Color(0.18, 0.2, 0.22), 0.5, 0.4)
		"rubber": return _flat(Color(0.05, 0.05, 0.055), 0.9, 0.0)
		"plastic_dark": return _flat(Color(0.08, 0.09, 0.1), 0.6, 0.0)
		"fabric_teal": return _flat(Color(0.15, 0.55, 0.55), 0.9, 0.0)
		"fabric_orange": return _flat(Color(0.95, 0.5, 0.18), 0.9, 0.0)
		"wood": return _pbr("bark", Color(0.85, 0.65, 0.45), 0.8, 0.0, 2.0, 0.4)
		# --- glass ---
		"glass": return _glass(Color(0.6, 0.85, 0.9), 0.22)
		"glass_dark": return _glass(Color(0.08, 0.13, 0.16), 0.82, 0.08)
		"glass_green": return _glass(Color(0.3, 0.9, 0.5), 0.35)
		# --- emissive ---
		"emit_cyan": return _emit(Color(0.3, 0.9, 1.0), 3.2)
		"emit_teal": return _emit(Color(0.2, 0.95, 0.8), 2.6)
		"emit_amber": return _emit(Color(1.0, 0.62, 0.18), 3.0)
		"emit_warm": return _emit(Color(1.0, 0.82, 0.55), 1.6)
		"emit_white": return _emit(Color(0.92, 0.96, 1.0), 3.0)
		"emit_green": return _emit(Color(0.45, 1.0, 0.45), 2.4)
		"emit_red": return _emit(Color(1.0, 0.22, 0.15), 3.0)
		"emit_screen": return _emit(Color(0.25, 0.65, 0.85), 1.4)
		"emit_window_cool": return _emit(Color(0.55, 0.78, 0.9), 0.7)
		"emit_window_warm": return _emit(Color(1.0, 0.78, 0.5), 0.9)
		"grass_card": return _grass_card()
	push_warning("MaterialLib: unknown material '%s'" % mat_name)
	return _flat(Color(1, 0, 1), 0.5, 0.0)


func _crate(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	var at := tex("crate_albedo.png")
	if at:
		m.albedo_texture = at
	var nt := tex("crate_normal.png")
	if nt:
		m.normal_enabled = true
		m.normal_texture = nt
	m.roughness = 0.75
	m.uv1_triplanar = true
	m.uv1_triplanar_sharpness = 8.0
	return m


func _grass_card() -> Material:
	var shader_path := "res://assets/materials/grass_wind.gdshader"
	if ResourceLoader.exists(shader_path):
		var sm := ShaderMaterial.new()
		sm.shader = load(shader_path)
		sm.set_shader_parameter("tex", tex("grass_tuft.png"))
		return sm
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex("grass_tuft.png")
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
