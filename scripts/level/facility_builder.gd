class_name FacilityBuilder
extends Node3D
## Builds "Helix Research Facility": the playable map, its lighting, navigation mesh and the
## tactical data bots use (spawns, plant sites, routes, hold spots, cover points, callouts).
##
## The layout is a 28 x 34 grid of 4 m cells (north = -Z, defenders spawn north):
##   #  building / solid        .  concrete floor       m  metal floor      t  lab tiles
##   g  grass (outdoor)         a  asphalt              S  attacker spawn   D  defender spawn
##   A  plant zone A            B  plant zone B         H  raised platform (2.4 m)
##   ^ v < >  ramp or stairs rising toward north / south / west / east

signal navigation_ready

const CELL := 4.0
const X0 := -56.0
const Z0 := -68.0
const PLATFORM_H := 2.4
const ROOF_Y := 5.0

const LAYOUT := [
	"############################",
	"##########DDDDDDDD##########",
	"######mmmmDDDDDDDDmmmm######",
	"######mmmmDDDDDDDDmmmm######",
	"#HHtttttt###mmmm###mmmmmmHH#",
	"#HHtttttt###mmmm###mmmmmmHH#",
	"#^tAAAAtt###mmmm###mmBBBBm^#",
	"#ttAAAAtt###mmmm###mmBBBBmm#",
	"#ttAAAAtt##mmmmmm##mmBBBBmm#",
	"#ttAAAAtt..mmmmmm..mmBBBBmm#",
	"#tttttttt..mmmmmm..mmmmmmmm#",
	"#tttttttt##mmmmmm##mmmmmmmm#",
	"#tttttttt#gggggggg#mmmmmmmm#",
	"#....#####HHggggHH#####....#",
	"#....#####HHggggHH#####....#",
	"#....#####g^gggg^g#####....#",
	"#....#####gggggggg#####....#",
	"#....mmmmmggggggggmmmmm....#",
	"#....mmmmmggggggggmmmmm....#",
	"#....#####gggggggg#####....#",
	"#HH..#####gggggggg#####..HH#",
	"#HH..#####gggggggg#####..HH#",
	"#HH..#######....#######..HH#",
	"#^...#######....#######...^#",
	"#....#######....#######....#",
	"#gg..#######....#######..gg#",
	"#gg..#######....#######..gg#",
	"#....#######....#######....#",
	"#aaaaaaaaaaaaaaaaaaaaaaaaaa#",
	"#aaaaaaaaaaaaaaaaaaaaaaaaaa#",
	"#ggaaaaaaaSSSSSSSSaaaaaaagg#",
	"#ggaaaaaaaSSSSSSSSaaaaaaagg#",
	"#gggggggggSSSSSSSSggggggggg#",
	"############################",
]

## Cells with an interior ceiling at ROOF_Y (tunnels, corridors, server hall).
const ROOFED := [
	Rect2i(5, 17, 5, 2), Rect2i(18, 17, 5, 2),      # A / B tunnels
	Rect2i(6, 2, 4, 2), Rect2i(18, 2, 4, 2),        # defender corridors
	Rect2i(9, 9, 2, 2), Rect2i(17, 9, 2, 2),        # A / B links
	Rect2i(11, 8, 6, 4),                            # server hall
]

const AREAS := [
	["Attacker Yard", Rect2i(1, 28, 26, 5)], ["A Main", Rect2i(1, 13, 4, 15)], ["A Tunnel", Rect2i(5, 17, 5, 2)],
	["Site A", Rect2i(1, 4, 8, 9)], ["A Link", Rect2i(9, 9, 2, 2)], ["Server Hall", Rect2i(11, 8, 6, 4)],
	["Mid Path", Rect2i(12, 4, 4, 4)], ["Atrium", Rect2i(10, 12, 8, 10)], ["Market", Rect2i(12, 22, 4, 6)],
	["B Tunnel", Rect2i(18, 17, 5, 2)], ["B Link", Rect2i(17, 9, 2, 2)], ["B Main", Rect2i(23, 13, 4, 15)],
	["Site B", Rect2i(19, 4, 8, 9)], ["Command Deck", Rect2i(10, 1, 8, 3)], ["West Corridor", Rect2i(6, 2, 4, 2)],
	["East Corridor", Rect2i(18, 2, 4, 2)],
]

var cols := 28
var rows := 34
var matlib := MaterialLib.new()
var batch := GeoBatch.new()
var rng := RandomNumberGenerator.new()
var font: Font
var nav_region: NavigationRegion3D
var visuals: Node3D
var dynamic_root: Node3D
var sun: DirectionalLight3D
var environment: Environment
var probes: Array = []
var spawn_walls := {}
var nav_ready := false

var _bodies := {}
var _rect_height := {}        # Vector2i cell -> wall height
var _roof_cells := {}

# --- tactical data used by bots / match ---
var spawns := {"attack": [], "defend": []}
var plant_zones := {}
var site_centers := {}
var site_positions := {"A": [], "B": []}
var attack_routes := {"A": [], "B": []}
var defend_holds := {"A": [], "B": [], "MID": []}
var plant_spots := {"A": [], "B": []}
var site_watch := {"A": [], "B": []}
var cover_points: Array = []
var obstacles: Array = []     # AABBs of cover-worthy props
var minimap_image: Image
var props: PropsBuilder


func _ready() -> void:
	rng.seed = 90210
	if ResourceLoader.exists("res://assets/fonts/ChakraPetch-Bold.ttf"):
		font = load("res://assets/fonts/ChakraPetch-Bold.ttf")
	for r in ROOFED:
		for x in range(r.position.x, r.position.x + r.size.x):
			for y in range(r.position.y, r.position.y + r.size.y):
				_roof_cells[Vector2i(x, y)] = true


# ============================================================ helpers
func cell(c: int, r: int) -> String:
	if c < 0 or r < 0 or c >= cols or r >= rows:
		return "#"
	return LAYOUT[r][c]


func is_walkable_char(ch: String) -> bool:
	return ch != "#"


func is_ramp(ch: String) -> bool:
	return ch in ["^", "v", "<", ">"]


func P(cx: float, cz: float, y := 0.0) -> Vector3:
	return Vector3(X0 + cx * CELL, y, Z0 + cz * CELL)


func cell_of(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor((pos.x - X0) / CELL)), int(floor((pos.z - Z0) / CELL)))


func zone_of(c: int, r: int) -> String:
	if r <= 3:
		return "command"
	if r <= 12 and c <= 9:
		return "lab"
	if r <= 12 and c >= 18:
		return "reactor"
	if r <= 11:
		return "server"
	if r >= 28:
		return "yard"
	if c <= 9:
		return "greenway"
	if c >= 18:
		return "pipeline"
	return "atrium" if r <= 21 else "market"


func area_name_at(pos: Vector3) -> String:
	var c := cell_of(pos)
	for a in AREAS:
		var rect: Rect2i = a[1]
		if rect.has_point(c):
			return a[0]
	return ""


func ground_height_at(pos: Vector3) -> float:
	var c := cell_of(pos)
	return PLATFORM_H if cell(c.x, c.y) == "H" else 0.0


func _hash(c: int, r: int, salt := 0) -> int:
	return absi((c * 73856093) ^ (r * 19349663) ^ (salt * 83492791)) % 1000


func body(surface: String) -> StaticBody3D:
	if not _bodies.has(surface):
		var b := StaticBody3D.new()
		b.name = "Static_" + surface
		b.collision_layer = GameConst.LAYER_WORLD
		b.collision_mask = 0
		b.set_meta("surface", surface)
		nav_region.add_child(b)
		_bodies[surface] = b
	return _bodies[surface]


func collider_box(surface: String, center: Vector3, size: Vector3, basis := Basis()) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.transform = Transform3D(basis, center)
	body(surface).add_child(cs)


func collider_cylinder(surface: String, center: Vector3, radius: float, height: float) -> void:
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	cs.shape = shape
	cs.position = center
	body(surface).add_child(cs)


func add_obstacle(center: Vector3, size: Vector3) -> void:
	if size.y >= 0.95:
		obstacles.append(AABB(center - size * 0.5, size))


func label(text: String, pos: Vector3, rot_y_deg: float, size := 128, color := Color(1, 1, 1), pixel := 0.01, flat := false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	if font:
		l.font = font
	l.font_size = size
	l.pixel_size = pixel
	l.modulate = color
	l.outline_size = 0
	l.double_sided = false
	l.shaded = false
	l.position = pos
	l.rotation_degrees = Vector3(-90 if flat else 0, rot_y_deg, 0)
	visuals.add_child(l)
	return l


# ============================================================ build
func build() -> void:
	visuals = Node3D.new()
	visuals.name = "Visuals"
	add_child(visuals)
	dynamic_root = Node3D.new()
	dynamic_root.name = "Dynamic"
	add_child(dynamic_root)
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Navigation"
	add_child(nav_region)
	_build_environment()
	_build_floors()
	_build_walls()
	_build_roofs()
	_build_platforms()
	_build_ramps()
	props = PropsBuilder.new(self)
	props.build_all()
	_build_site_markers()
	_build_signage()
	_build_spawn_walls()
	set_spawn_walls(false)
	_build_probes()
	batch.commit(visuals, matlib)
	_define_tactics()
	_generate_cover_points()
	_build_minimap_image()
	_bake_navigation()


# ------------------------------------------------------------ environment & lighting
func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.2, 0.4, 0.62)
	sky_mat.sky_horizon_color = Color(0.98, 0.72, 0.5)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_horizon_color = Color(0.72, 0.56, 0.44)
	sky_mat.ground_bottom_color = Color(0.22, 0.2, 0.18)
	sky_mat.sun_angle_max = 25.0
	sky_mat.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.75
	environment.ambient_light_sky_contribution = 0.85
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.05
	environment.tonemap_white = 6.0
	environment.ssao_enabled = true
	environment.ssao_radius = 1.4
	environment.ssao_intensity = 1.6
	environment.ssao_power = 1.4
	environment.ssao_detail = 0.6
	environment.glow_enabled = true
	environment.glow_intensity = 0.55
	environment.glow_strength = 0.9
	environment.glow_bloom = 0.04
	environment.glow_hdr_threshold = 1.1
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	environment.set_glow_level(0, 0.0)
	environment.set_glow_level(2, 0.8)
	environment.set_glow_level(4, 0.6)
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.86, 0.74, 0.62)
	environment.fog_light_energy = 0.9
	environment.fog_sun_scatter = 0.25
	environment.fog_density = 0.0028
	environment.fog_aerial_perspective = 0.35
	environment.fog_sky_affect = 0.25
	environment.volumetric_fog_density = 0.008
	environment.volumetric_fog_albedo = Color(1.0, 0.9, 0.8)
	environment.volumetric_fog_anisotropy = 0.55
	environment.volumetric_fog_length = 60.0
	environment.volumetric_fog_sky_affect = 0.0
	environment.ssr_max_steps = 48
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.12
	environment.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = environment
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.78, 0.56)
	sun.light_energy = 1.75
	sun.rotation_degrees = Vector3(-30, -38, 0)
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 140.0
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.18
	sun.directional_shadow_split_3 = 0.45
	sun.light_angular_distance = 0.6
	add_child(sun)
	# Cool sky fill from the opposite direction so shadowed walls keep shape.
	var fill := DirectionalLight3D.new()
	fill.name = "SkyFill"
	fill.light_color = Color(0.55, 0.72, 0.95)
	fill.light_energy = 0.22
	fill.rotation_degrees = Vector3(-55, 140, 0)
	fill.shadow_enabled = false
	add_child(fill)
	Settings.register_world(environment, sun, probes)


# ------------------------------------------------------------ floors
func _floor_mat(ch: String, c: int, r: int) -> String:
	match ch:
		"t", "A": return "tiles"
		"m": return "metal_floor_teal" if zone_of(c, r) == "server" else "metal_floor"
		"B": return "metal_floor"
		"D": return "metal_floor_teal"
		"g": return "grass"
		"a", "S": return "asphalt"
	return "concrete_floor"


func _surface_for_mat(mat: String) -> String:
	if mat.begins_with("metal"):
		return "metal"
	if mat == "grass":
		return "grass"
	return "concrete"


func _greedy_rects(predicate: Callable) -> Array:
	var used := {}
	var out := []
	for r in rows:
		for c in cols:
			if used.has(Vector2i(c, r)) or not predicate.call(c, r):
				continue
			var w := 1
			while c + w < cols and not used.has(Vector2i(c + w, r)) and predicate.call(c + w, r):
				w += 1
			var h := 1
			var ok := true
			while ok and r + h < rows:
				for x in range(c, c + w):
					if used.has(Vector2i(x, r + h)) or not predicate.call(x, r + h):
						ok = false
						break
				if ok:
					h += 1
			for y in range(r, r + h):
				for x in range(c, c + w):
					used[Vector2i(x, y)] = true
			out.append(Rect2i(c, r, w, h))
	return out


func _build_floors() -> void:
	var mats := {}
	for r in rows:
		for c in cols:
			var ch := cell(c, r)
			if ch == "#" or ch == "H":
				continue
			var m := _floor_mat(ch, c, r)
			if is_ramp(ch):
				m = "concrete_floor"
			mats[Vector2i(c, r)] = m
	var kinds := {}
	for k in mats.values():
		kinds[k] = true
	for mat in kinds:
		var rects := _greedy_rects(func(c, r): return mats.get(Vector2i(c, r), "") == mat)
		for rect: Rect2i in rects:
			var mn := P(rect.position.x, rect.position.y, -0.3)
			var size := Vector3(rect.size.x * CELL, 0.3, rect.size.y * CELL)
			batch.box_at(mat, mn, size)
			collider_box(_surface_for_mat(mat), mn + size * 0.5, size)
	# Curbs where grass meets hard floor; painted lines in the yard and on spawn.
	for r in rows:
		for c in cols:
			if cell(c, r) != "g":
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n := cell(c + d.x, r + d.y)
				if n == "#" or n == "g" or n == "H" or is_ramp(n):
					continue
				var center := P(c + 0.5 + d.x * 0.5, r + 0.5 + d.y * 0.5, 0.06)
				var along := Vector3(absf(d.y), 0, absf(d.x))
				var size := along * CELL + Vector3(absf(d.x), 0, absf(d.y)) * 0.22 + Vector3(0, 0.12, 0)
				batch.box("concrete_plain", Transform3D(Basis(), center), size)
	for i in 13:
		var x := X0 + 6.0 + i * 8.0
		batch.box("paint_white", Transform3D(Basis(), Vector3(x, 0.005, 47.8)), Vector3(3.0, 0.01, 0.18))
	for r in [30, 31, 32]:
		for c in range(10, 18):
			if (c + r) % 2 == 0:
				batch.box("paint_amber", Transform3D(Basis(), P(c + 0.5, r + 0.5, 0.004)), Vector3(3.6, 0.008, 0.12))


# ------------------------------------------------------------ buildings / walls
func _zone_height(zone: String) -> float:
	match zone:
		"command": return 10.0
		"lab": return 9.0
		"reactor": return 12.0
		"server": return 8.0
		"greenway": return 10.0
		"pipeline": return 11.0
		"atrium": return 9.0
		"market": return 8.0
		"yard": return 11.0
	return 9.0


func _build_walls() -> void:
	var rects := _greedy_rects(func(c, r): return cell(c, r) == "#")
	for rect: Rect2i in rects:
		var cc := rect.position + rect.size / 2
		var on_border := rect.position.x == 0 or rect.position.y == 0 or rect.end.x == cols or rect.end.y == rows
		var h := _zone_height(zone_of(cc.x, cc.y)) + (5.0 if on_border else 0.0) + float(_hash(rect.position.x, rect.position.y) % 3)
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				_rect_height[Vector2i(x, y)] = h
		var mn := P(rect.position.x, rect.position.y)
		var size := Vector3(rect.size.x * CELL, h, rect.size.y * CELL)
		collider_box("concrete", mn + size * 0.5, size)
		batch.quad("roof", mn + Vector3(0, h, 0), mn + Vector3(size.x, h, 0), mn + Vector3(size.x, h, size.z), mn + Vector3(0, h, size.z), Vector3.UP)
		if not on_border and rect.size.x * rect.size.y >= 4:
			_rooftop_details(rect, h)
	var dirs := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	for r in rows:
		for c in cols:
			if cell(c, r) != "#":
				continue
			var h: float = _rect_height[Vector2i(c, r)]
			for d in dirs:
				var nc: int = c + d.x
				var nr: int = r + d.y
				if nc < 0 or nr < 0 or nc >= cols or nr >= rows:
					continue
				var n := cell(nc, nr)
				if n != "#":
					_wall_face(c, r, d, h, zone_of(nc, nr))
				else:
					var nh: float = _rect_height.get(Vector2i(nc, nr), h)
					if nh < h - 0.01:
						_plain_face(c, r, d, nh, h, zone_of(c, r))


## Frame for a wall face: x = along face, y = up, z = outward normal; origin = face bottom centre.
func _face_frame(c: int, r: int, d: Vector2i, base_y := 0.0) -> Transform3D:
	var n := Vector3(d.x, 0, d.y)
	var center := P(c + 0.5 + d.x * 0.5, r + 0.5 + d.y * 0.5, base_y)
	var right := Vector3.UP.cross(n)
	return Transform3D(Basis(right, Vector3.UP, n), center)


func _fbox(f: Transform3D, mat: String, u: float, v: float, w: float, size: Vector3) -> void:
	batch.box(mat, f * Transform3D(Basis(), Vector3(u, v, w)), size, false)


func _fcyl(f: Transform3D, mat: String, u: float, v: float, w: float, radius: float, height: float, horizontal := false) -> void:
	var b := Basis()
	if horizontal:
		b = Basis(Vector3(0, 0, 1), PI * 0.5)
	batch.cylinder(mat, f * Transform3D(b, Vector3(u, v, w)), radius, radius, height, 10)


func _face_quad(f: Transform3D, mat: String, y0: float, y1: float, half_w := 2.0, w := 0.0) -> void:
	var a := f * Vector3(-half_w, y0, w)
	var b := f * Vector3(half_w, y0, w)
	var c2 := f * Vector3(half_w, y1, w)
	var d := f * Vector3(-half_w, y1, w)
	batch.quad(mat, a, b, c2, d, f.basis.z)


func _plain_face(c: int, r: int, d: Vector2i, y0: float, y1: float, zone: String) -> void:
	var f := _face_frame(c, r, d)
	_face_quad(f, _face_material(zone, c, r), y0, y1)


func _face_material(zone: String, c: int, r: int) -> String:
	match zone:
		"lab": return "metal_panel_white"
		"reactor": return "concrete_wall"
		"server": return "metal_panel_teal"
		"command": return "metal_panel_dark"
		"greenway": return "facade_sand"
		"atrium": return "facade_terracotta"
		"market": return "facade_sand"
		"pipeline": return "corrugated_orange" if (c + r) % 5 < 3 else "corrugated_graphite"
		"yard": return "corrugated_cream" if c < 14 else "corrugated_teal"
	return "concrete_wall"


func _window(f: Transform3D, u: float, v: float, w: float, h: float, lit: String) -> void:
	_fbox(f, "metal_trim", u, v + h * 0.5 + 0.06, 0.06, Vector3(w + 0.24, 0.12, 0.12))
	_fbox(f, "concrete_dark", u, v - h * 0.5 - 0.07, 0.1, Vector3(w + 0.3, 0.14, 0.2))
	_fbox(f, "metal_trim", u - w * 0.5 - 0.06, v, 0.06, Vector3(0.12, h + 0.24, 0.12))
	_fbox(f, "metal_trim", u + w * 0.5 + 0.06, v, 0.06, Vector3(0.12, h + 0.24, 0.12))
	_fbox(f, lit, u, v, 0.012, Vector3(w, h, 0.02))
	_fbox(f, "glass_dark", u, v, 0.04, Vector3(w, h, 0.02))
	_fbox(f, "metal_trim", u, v, 0.05, Vector3(0.05, h, 0.04))


func _vent(f: Transform3D, u: float, v: float) -> void:
	_fbox(f, "metal_trim", u, v, 0.06, Vector3(1.2, 0.8, 0.12))
	for i in 4:
		_fbox(f, "metal_dark", u, v - 0.27 + i * 0.18, 0.13, Vector3(1.05, 0.05, 0.06))


func _wall_face(c: int, r: int, d: Vector2i, h: float, zone: String) -> void:
	var f := _face_frame(c, r, d)
	var hs := _hash(c, r, d.x * 3 + d.y * 7)
	var roofed := _roof_cells.has(Vector2i(c + d.x, r + d.y))
	_face_quad(f, _face_material(zone, c, r), 0.0, h)
	if zone != "atrium" or hs % 3 != 0:
		_fbox(f, "metal_trim", 0, 0.25, 0.04, Vector3(4.0, 0.5, 0.08))
	_fbox(f, "concrete_dark" if zone in ["greenway", "atrium", "market", "reactor"] else "metal_trim", 0, h - 0.2, 0.12, Vector3(4.24, 0.4, 0.24))
	match zone:
		"lab":
			_fbox(f, "emit_cyan", 0, 2.7, 0.03, Vector3(4.0, 0.07, 0.06))
			_fbox(f, "metal_trim", -1.85, h * 0.5, 0.1, Vector3(0.3, h, 0.2))
			if not roofed and hs % 2 == 0 and h > 6.5:
				_window(f, 0.2, 4.7, 3.0, 1.6, "emit_window_cool")
			elif hs % 3 == 1:
				_fbox(f, "metal_dark", 0.3, 1.5, 0.04, Vector3(1.8, 1.0, 0.06))
				_fbox(f, "emit_screen", 0.3, 1.5, 0.075, Vector3(1.6, 0.85, 0.02))
		"reactor":
			if hs % 2 == 0:
				_fbox(f, "hazard", 0, 0.9, 0.025, Vector3(4.0, 0.7, 0.05))
			_fbox(f, "emit_amber", 0, 3.3, 0.03, Vector3(4.0, 0.06, 0.06))
			if hs % 3 == 0:
				_fcyl(f, "metal_bare", 1.2, h * 0.5, 0.32, 0.16, h)
				for y in [1.5, 4.0, 6.5]:
					if y < h - 0.5:
						_fbox(f, "metal_trim", 1.2, y, 0.16, Vector3(0.44, 0.12, 0.32))
			if hs % 4 == 1:
				_vent(f, -0.8, 1.7)
		"server", "command":
			_fbox(f, "emit_cyan", 0, 0.62, 0.025, Vector3(4.0, 0.05, 0.05))
			if not roofed:
				_fbox(f, "emit_teal", 0, 3.6, 0.025, Vector3(4.0, 0.05, 0.05))
			_fbox(f, "metal_dark", -1.9, h * 0.5, 0.08, Vector3(0.2, h, 0.16))
			if hs % 3 == 0:
				_fbox(f, "metal_dark", 0, 2.1, 0.04, Vector3(2.4, 1.4, 0.06))
				_fbox(f, "emit_screen", 0, 2.1, 0.075, Vector3(2.2, 1.2, 0.02))
			elif hs % 3 == 1:
				_vent(f, 0.5, 1.6)
		"greenway", "atrium", "market":
			if h > 5.5 and not roofed:
				for u in [-1.0, 1.0]:
					var lit := "emit_window_warm" if (hs + int(u * 10)) % 3 == 0 else ("emit_window_cool" if hs % 2 == 0 else "glass_dark")
					_window(f, u, 3.6, 1.3, 1.7, lit)
					if h > 8.5:
						_window(f, u, 6.6, 1.3, 1.7, "emit_window_warm" if (hs + int(u * 7)) % 4 == 0 else "glass_dark")
			if hs % 4 == 0:
				_fbox(f, "metal_dark", 0, 1.35, 0.03, Vector3(1.6, 2.7, 0.06))
				_fbox(f, "emit_amber", 0, 2.95, 0.12, Vector3(0.6, 0.08, 0.18))
				_fbox(f, "concrete_dark", 0, 3.05, 0.35, Vector3(2.2, 0.12, 0.7))
			elif zone == "greenway" and hs % 3 == 0:
				_fbox(f, "concrete_dark", 0, 0.3, 0.35, Vector3(3.0, 0.6, 0.7))
				for i in 4:
					batch.blob("foliage" if i % 2 == 0 else "foliage_dark", f * Vector3(-1.1 + i * 0.75, 0.75, 0.35), Vector3(0.5, 0.42, 0.4), rng)
			if hs % 5 == 1 and h > 6.0:
				_fbox(f, "paint_white", 1.3, 5.2, 0.3, Vector3(1.0, 0.7, 0.55))
				_fcyl(f, "metal_dark", 1.3, 5.2, 0.58, 0.26, 0.04)
		"pipeline":
			_fcyl(f, "paint_teal", 0, 1.3, 0.34, 0.22, 4.0, true)
			_fcyl(f, "metal_bare", 0, 2.1, 0.3, 0.13, 4.0, true)
			_fbox(f, "metal_trim", -1.6, 1.7, 0.2, Vector3(0.12, 1.4, 0.4))
			_fbox(f, "hazard", 0, 0.25, 0.05, Vector3(4.0, 0.5, 0.06))
			if hs % 4 == 0:
				_fcyl(f, "paint_red", 0.8, 1.3, 0.62, 0.28, 0.05)
			if hs % 3 == 0 and h > 6:
				_vent(f, -0.6, 4.2)
		"yard":
			if hs % 3 == 0:
				_fbox(f, "metal_trim", 0, 1.9, 0.08, Vector3(3.6, 3.8, 0.12))
				_fbox(f, "corrugated_graphite", 0, 1.8, 0.14, Vector3(3.2, 3.6, 0.06))
				_fbox(f, "emit_warm", 0, 4.15, 0.25, Vector3(0.7, 0.12, 0.35))
				_fbox(f, "metal_dark", 0, 4.3, 0.2, Vector3(0.9, 0.2, 0.4))
			elif hs % 3 == 1:
				_fcyl(f, "metal_bare", -1.7, h * 0.5, 0.2, 0.1, h)
			if hs % 4 == 2 and h > 7:
				_vent(f, 0.6, 6.0)


func _rooftop_details(rect: Rect2i, h: float) -> void:
	var count := clampi(rect.size.x * rect.size.y / 4, 1, 4)
	for i in count:
		var cx := rect.position.x + rng.randf_range(0.6, rect.size.x - 0.6)
		var cz := rect.position.y + rng.randf_range(0.6, rect.size.y - 0.6)
		var p := P(cx, cz, h)
		match rng.randi() % 3:
			0:
				batch.box("paint_white", Transform3D(Basis(), p + Vector3(0, 0.6, 0)), Vector3(2.4, 1.2, 1.6))
				batch.cylinder("metal_dark", Transform3D(Basis(), p + Vector3(0, 1.22, 0)), 0.55, 0.55, 0.06, 14)
			1:
				batch.cylinder("metal_trim", Transform3D(Basis(), p + Vector3(0, 1.6, 0)), 1.1, 1.1, 3.2, 14)
				batch.cylinder("metal_dark", Transform3D(Basis(), p + Vector3(0, 3.25, 0)), 1.15, 0.3, 0.3, 14)
			2:
				batch.cylinder("metal_bare", Transform3D(Basis(), p + Vector3(0, 3.0, 0)), 0.05, 0.03, 6.0, 6)
				batch.box("emit_red", Transform3D(Basis(), p + Vector3(0, 6.05, 0)), Vector3(0.15, 0.15, 0.15))


# ------------------------------------------------------------ roofs (interior ceilings)
func _build_roofs() -> void:
	for rect: Rect2i in ROOFED:
		var mn := P(rect.position.x, rect.position.y, ROOF_Y)
		var size := Vector3(rect.size.x * CELL, 0.5, rect.size.y * CELL)
		collider_box("metal", mn + size * 0.5, size)
		batch.box_at("metal_panel_dark", mn, size, false)
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var c := P(x + 0.5, y + 0.5, ROOF_Y - 0.04)
				batch.box("emit_white", Transform3D(Basis(), c), Vector3(2.6, 0.06, 0.22))
				batch.box("metal_trim", Transform3D(Basis(), c + Vector3(0, 0.02, 0)), Vector3(2.8, 0.05, 0.36))
				if (x + y) % 2 == 0:
					var l := OmniLight3D.new()
					l.light_color = Color(0.85, 0.95, 1.0)
					l.light_energy = 1.4
					l.omni_range = 7.5
					l.omni_attenuation = 1.2
					l.shadow_enabled = false
					l.position = c + Vector3(0, -0.4, 0)
					visuals.add_child(l)
				for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
					var n := Vector2i(x + d.x, y + d.y)
					if _roof_cells.has(n) or cell(n.x, n.y) == "#":
						continue
					var f := _face_frame(x, y, d)
					_fbox(f, "metal_trim", 0, ROOF_Y - 0.25, -0.2, Vector3(4.0, 0.7, 0.4))
					_fbox(f, "hazard", 0, ROOF_Y - 0.55, 0.005, Vector3(4.0, 0.16, 0.02))


# ------------------------------------------------------------ platforms
func _build_platforms() -> void:
	var rects := _greedy_rects(func(c, r): return cell(c, r) == "H")
	for rect: Rect2i in rects:
		var mn := P(rect.position.x, rect.position.y)
		var size := Vector3(rect.size.x * CELL, PLATFORM_H, rect.size.y * CELL)
		collider_box("metal", mn + size * 0.5, size)
		batch.quad("metal_floor", mn + Vector3(0, PLATFORM_H, 0), mn + Vector3(size.x, PLATFORM_H, 0),
			mn + Vector3(size.x, PLATFORM_H, size.z), mn + Vector3(0, PLATFORM_H, size.z), Vector3.UP)
	var dirs := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	for r in rows:
		for c in cols:
			if cell(c, r) != "H":
				continue
			for d in dirs:
				var n := cell(c + d.x, r + d.y)
				if n == "H" or n == "#":
					continue
				var f := _face_frame(c, r, d)
				_face_quad(f, "metal_panel_dark", 0.0, PLATFORM_H)
				_fbox(f, "hazard", 0, PLATFORM_H - 0.1, 0.02, Vector3(4.0, 0.2, 0.04))
				_fbox(f, "metal_trim", -1.8, PLATFORM_H * 0.5, 0.08, Vector3(0.25, PLATFORM_H, 0.16))
				_fbox(f, "emit_cyan", 0, 0.35, 0.02, Vector3(3.4, 0.05, 0.04))
				if is_ramp(n):
					continue
				_railing(f, PLATFORM_H, 4.0, -0.12)


## Railing segment along a face frame at height `base_y`, set `inset` metres in from the edge.
func _railing(f: Transform3D, base_y: float, length: float, inset: float) -> void:
	var posts := int(length / 1.33) + 1
	for i in posts:
		var u := -length * 0.5 + 0.1 + (length - 0.2) * i / maxf(posts - 1, 1)
		_fbox(f, "paint_amber", u, base_y + 0.53, inset, Vector3(0.06, 1.06, 0.06))
	_fbox(f, "paint_amber", 0, base_y + 1.06, inset, Vector3(length, 0.07, 0.07))
	_fbox(f, "paint_amber", 0, base_y + 0.56, inset, Vector3(length, 0.05, 0.05))
	_fbox(f, "metal_trim", 0, base_y + 0.06, inset, Vector3(length, 0.12, 0.03))
	var center := f * Vector3(0, base_y + 0.55, inset)
	collider_box("metal", center, Vector3(length, 1.1, 0.1).abs(), f.basis)


# ------------------------------------------------------------ ramps & stairs
func _build_ramps() -> void:
	for r in rows:
		for c in cols:
			var ch := cell(c, r)
			if not is_ramp(ch):
				continue
			var yaw := 0.0
			match ch:
				"v": yaw = PI
				"<": yaw = PI * 0.5
				">": yaw = -PI * 0.5
			var basis := Basis(Vector3.UP, yaw)
			var center := P(c + 0.5, r + 0.5, PLATFORM_H * 0.5)
			var xf := Transform3D(basis, center)
			var size := Vector3(CELL, PLATFORM_H, CELL)
			# Collision: a smooth wedge so movement and navigation never snag on steps.
			var hx := size.x * 0.5
			var hz := size.z * 0.5
			var hy := size.y * 0.5
			var pts := PackedVector3Array([Vector3(-hx, -hy, hz), Vector3(hx, -hy, hz), Vector3(-hx, hy, -hz),
				Vector3(hx, hy, -hz), Vector3(-hx, -hy, -hz), Vector3(hx, -hy, -hz)])
			var cs := CollisionShape3D.new()
			var shape := ConvexPolygonShape3D.new()
			shape.points = pts
			cs.shape = shape
			cs.transform = xf
			body("metal").add_child(cs)
			var stairs := r == 6 or r == 23
			if stairs:
				var steps := 8
				for i in steps:
					var depth := CELL / steps
					var top := PLATFORM_H * (i + 1) / steps
					var z_local := hz - depth * (i + 0.5)
					batch.box("concrete_plain" if r == 23 else "metal_floor", xf * Transform3D(Basis(), Vector3(0, -hy + top * 0.5, z_local)), Vector3(CELL - 0.5, top, depth), false)
					batch.box("hazard", xf * Transform3D(Basis(), Vector3(0, -hy + top - 0.01, z_local + depth * 0.5 - 0.06)), Vector3(CELL - 0.5, 0.03, 0.12))
				for sx in [-1.0, 1.0]:
					batch.wedge("metal_trim", xf * Transform3D(Basis(), Vector3(sx * (hx - 0.12), 0.05, 0)), Vector3(0.24, PLATFORM_H + 0.1, CELL))
			else:
				batch.wedge("metal_floor", xf, size)
				batch.box("hazard", xf * Transform3D(Basis(), Vector3(0, -hy + 0.02, hz - 0.15)), Vector3(CELL, 0.04, 0.3))
			# Side rails where the ramp edge is open to a drop.
			for sd in [-1, 1]:
				var side_dir := (basis * Vector3(sd, 0, 0)).round()
				var nb := cell(c + int(side_dir.x), r + int(side_dir.z))
				if nb == "#" or nb == "H":
					continue
				for i in 3:
					var t := (i + 0.5) / 3.0
					var local := Vector3(sd * (hx - 0.1), -hy + PLATFORM_H * (1.0 - t) + 0.55, -hz + CELL * t)
					batch.box("paint_amber", xf * Transform3D(Basis(), local), Vector3(0.06, 1.1, 0.06))
				var rail_len := sqrt(CELL * CELL + PLATFORM_H * PLATFORM_H)
				var angle := atan2(PLATFORM_H, CELL)
				var rail_xf := xf * Transform3D(Basis(Vector3.RIGHT, angle), Vector3(sd * (hx - 0.1), 1.05, 0))
				batch.box("paint_amber", rail_xf, Vector3(0.07, 0.07, rail_len))


# ------------------------------------------------------------ objective sites
func _build_site_markers() -> void:
	for site in ["A", "B"]:
		var cells := []
		for r in rows:
			for c in cols:
				if cell(c, r) == site:
					cells.append(Vector2i(c, r))
		var mn := Vector2i(999, 999)
		var mx := Vector2i(-1, -1)
		for v in cells:
			mn = Vector2i(mini(mn.x, v.x), mini(mn.y, v.y))
			mx = Vector2i(maxi(mx.x, v.x), maxi(mx.y, v.y))
		var p0 := P(mn.x, mn.y)
		var p1 := P(mx.x + 1, mx.y + 1)
		plant_zones[site] = Rect2(Vector2(p0.x, p0.z), Vector2(p1.x - p0.x, p1.z - p0.z))
		site_centers[site] = (p0 + p1) * 0.5
		var w := p1.x - p0.x
		var d := p1.z - p0.z
		var y := 0.012
		for edge in [[Vector3(p0.x + w * 0.5, y, p0.z), Vector3(w, 0.02, 0.18)], [Vector3(p0.x + w * 0.5, y, p1.z), Vector3(w, 0.02, 0.18)],
				[Vector3(p0.x, y, p0.z + d * 0.5), Vector3(0.18, 0.02, d)], [Vector3(p1.x, y, p0.z + d * 0.5), Vector3(0.18, 0.02, d)]]:
			batch.box("emit_amber", Transform3D(Basis(), edge[0]), edge[1])
		for corner in [p0, Vector3(p1.x, 0, p0.z), Vector3(p0.x, 0, p1.z), p1]:
			batch.box("hazard", Transform3D(Basis(), Vector3(corner.x, 0.02, corner.z)), Vector3(1.2, 0.03, 1.2))
		label(site, Vector3(p0.x + w * 0.5 + (-4.5 if site == "A" else 4.5), 0.03, p0.z + d * 0.5 + 4.5), 0.0, 320, Color(1.0, 0.71, 0.28, 0.3), 0.02, true)


# ------------------------------------------------------------ signage
func _build_signage() -> void:
	var amber := Color(1.0, 0.75, 0.35)
	var cyan := Color(0.5, 0.95, 1.0)
	# Site banners on the walls behind each site, with backing plates.
	for spec in [["SITE A", "HYDROPONICS LAB", P(4.5, 4.0)], ["SITE B", "REACTOR CORE", P(24.0, 4.0)]]:
		var p: Vector3 = spec[2]
		batch.box("metal_dark", Transform3D(Basis(), p + Vector3(0, 6.3, 0.04)), Vector3(8.6, 2.8, 0.06))
		batch.box("emit_amber", Transform3D(Basis(), p + Vector3(0, 4.88, 0.07)), Vector3(8.6, 0.06, 0.04))
		label(spec[0], p + Vector3(0, 6.75, 0.09), 0, 170, amber)
		label(spec[1], p + Vector3(0, 5.55, 0.09), 0, 72, cyan)
	label("ATRIUM", P(11.0, 21.98, 4.2), 180, 120, cyan)
	label("COMMAND DECK", P(14.0, 1.02, 4.4), 0, 110, cyan)
	# Wayfinding on the walls beside the yard exits (read from the yard, looking north).
	label("A MAIN", P(6.2, 28.02, 4.2), 0, 120, amber)
	label("MID", P(10.8, 28.02, 4.2), 0, 120, amber)
	label("B MAIN", P(21.8, 28.02, 4.2), 0, 120, amber)
	label("A MAIN  |  ATRIUM", P(7.5, 17.02, 3.4), 0, 60, amber)
	label("ATRIUM  |  B MAIN", P(20.5, 17.02, 3.4), 0, 60, amber)
	label("FREIGHT YARD", P(14.0, 32.98, 6.0), 180, 120, Color(0.95, 0.9, 0.8))
	# Hanging signs inside the link openings.
	for spec in [["A LINK", P(11.0, 10.0, 4.25), 90.0], ["B LINK", P(17.0, 10.0, 4.25), -90.0]]:
		var p2: Vector3 = spec[1]
		var yaw: float = deg_to_rad(spec[2])
		var b := Basis(Vector3.UP, yaw)
		batch.box("metal_dark", Transform3D(b, p2), Vector3(3.2, 0.7, 0.08))
		batch.box("metal_trim", Transform3D(b, p2 + Vector3(0, 0.55, 0)), Vector3(0.05, 0.4, 0.05))
		var off := b * Vector3(0, 0, 0.05)
		label(spec[0], p2 + off, spec[2], 64, amber)
		label(spec[0], p2 - off, spec[2] + 180.0, 64, amber)


# ------------------------------------------------------------ spawn barriers
func _build_spawn_walls() -> void:
	var defs := {
		"attack": [[Vector3(-44, 2.5, 44.0), Vector3(16, 5, 0.3)], [Vector3(0, 2.5, 44.0), Vector3(16, 5, 0.3)], [Vector3(44, 2.5, 44.0), Vector3(16, 5, 0.3)]],
		"defend": [[Vector3(-16.0, 2.5, -56), Vector3(0.3, 5, 8)], [Vector3(16.0, 2.5, -56), Vector3(0.3, 5, 8)], [Vector3(0, 2.5, -52.0), Vector3(16, 5, 0.3)]],
	}
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.62, 0.2, 0.22)
	for side in defs:
		var root := StaticBody3D.new()
		root.name = "SpawnWall_" + side
		root.collision_layer = GameConst.LAYER_SPAWN_WALL
		root.collision_mask = 0
		dynamic_root.add_child(root)
		for w in defs[side]:
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = w[1]
			cs.shape = shape
			cs.position = w[0]
			root.add_child(cs)
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = w[1] * Vector3(1, 1, 1) - Vector3(0, 0.0, 0)
			mi.mesh = bm
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = w[0]
			root.add_child(mi)
		spawn_walls[side] = root


func set_spawn_walls(active: bool) -> void:
	for side in spawn_walls:
		var root: StaticBody3D = spawn_walls[side]
		root.visible = active
		root.collision_layer = GameConst.LAYER_SPAWN_WALL if active else 0


func _build_probes() -> void:
	for spec in [[P(4.5, 8.0, 4.0), Vector3(32, 9, 36)], [P(22.5, 8.0, 4.0), Vector3(32, 9, 36)], [P(14.0, 17.0, 4.0), Vector3(32, 9, 40)], [P(14.0, 9.5, 2.5), Vector3(24, 5, 16)]]:
		var probe := ReflectionProbe.new()
		probe.position = spec[0]
		probe.size = spec[1]
		probe.box_projection = true
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
		probe.interior = false
		probe.intensity = 0.8
		probe.max_distance = 60.0
		visuals.add_child(probe)
		probes.append(probe)


# ============================================================ tactics
func _define_tactics() -> void:
	for p in [Vector2(11.0, 31.0), Vector2(12.5, 30.4), Vector2(14.0, 31.2), Vector2(15.5, 30.4), Vector2(17.0, 31.0)]:
		spawns["attack"].append(Transform3D(Basis(Vector3.UP, 0.0), P(p.x, p.y)))
	for p in [Vector2(11.0, 2.0), Vector2(12.5, 1.6), Vector2(14.0, 2.4), Vector2(15.5, 1.6), Vector2(17.0, 2.0)]:
		spawns["defend"].append(Transform3D(Basis(Vector3.UP, PI), P(p.x, p.y)))
	attack_routes["A"] = [
		[P(2.7, 27.0), P(3.6, 20.5), P(3.0, 14.2)],
		[P(14.0, 25.0), P(14.0, 19.5), P(13.5, 11.5), P(11.6, 9.9)],
		[P(2.7, 26.5), P(3.0, 19.0), P(7.5, 17.9), P(12.2, 15.6), P(13.0, 11.6), P(11.6, 9.9)],
	]
	attack_routes["B"] = [
		[P(25.2, 27.0), P(24.4, 20.5), P(25.0, 14.2)],
		[P(14.0, 25.0), P(14.0, 19.5), P(14.5, 11.5), P(16.4, 9.9)],
		[P(25.3, 26.5), P(25.0, 19.0), P(20.5, 17.9), P(15.8, 15.6), P(15.0, 11.6), P(16.4, 9.9)],
	]
	site_positions["A"] = [P(2.2, 8.2), P(4.2, 10.8), P(7.4, 6.3), P(7.6, 10.4), P(1.6, 4.6, PLATFORM_H), P(5.0, 5.0)]
	site_positions["B"] = [P(20.4, 6.0), P(25.6, 9.0), P(21.6, 11.2), P(25.6, 4.6, PLATFORM_H), P(19.8, 10.2), P(24.6, 5.4)]
	plant_spots["A"] = [P(4.6, 6.6), P(5.0, 8.2), P(4.6, 9.6), P(6.6, 9.6)]
	plant_spots["B"] = [P(21.7, 6.8), P(21.7, 9.3), P(24.3, 9.4), P(23.0, 6.4)]
	site_watch["A"] = [P(7.5, 3.4), P(9.6, 9.9)]
	site_watch["B"] = [P(20.0, 3.4), P(18.4, 9.9)]
	defend_holds["A"] = [
		{"pos": P(5.6, 5.0), "look": P(2.8, 13.0)},
		{"pos": P(1.6, 4.4, PLATFORM_H), "look": P(3.0, 13.0)},
		{"pos": P(7.6, 7.6), "look": P(10.0, 9.9)},
		{"pos": P(2.0, 9.0), "look": P(2.8, 14.0)},
	]
	defend_holds["B"] = [
		{"pos": P(22.4, 5.0), "look": P(25.0, 13.0)},
		{"pos": P(25.6, 4.4, PLATFORM_H), "look": P(25.0, 13.0)},
		{"pos": P(20.2, 7.6), "look": P(18.0, 9.9)},
		{"pos": P(26.0, 9.4), "look": P(25.2, 14.0)},
	]
	defend_holds["MID"] = [
		{"pos": P(13.0, 9.2), "look": P(14.0, 17.0)},
		{"pos": P(15.2, 8.6), "look": P(14.0, 18.0)},
		{"pos": P(11.0, 13.6, PLATFORM_H), "look": P(14.0, 21.5)},
		{"pos": P(17.0, 13.6, PLATFORM_H), "look": P(14.0, 21.5)},
	]


func _generate_cover_points() -> void:
	var grown := []
	for a in obstacles:
		grown.append(a.grow(0.42))
	for a in obstacles:
		var c: Vector3 = a.get_center()
		var hx: float = a.size.x * 0.5 + 0.8
		var hz: float = a.size.z * 0.5 + 0.8
		var base_y: float = a.position.y
		var cands := [
			[Vector3(c.x + hx, base_y, c.z), Vector3(-1, 0, 0)], [Vector3(c.x - hx, base_y, c.z), Vector3(1, 0, 0)],
			[Vector3(c.x, base_y, c.z + hz), Vector3(0, 0, -1)], [Vector3(c.x, base_y, c.z - hz), Vector3(0, 0, 1)],
		]
		for cand in cands:
			var p: Vector3 = cand[0]
			var cc := cell_of(p)
			var ch := cell(cc.x, cc.y)
			if ch == "#" or is_ramp(ch):
				continue
			p.y = PLATFORM_H if ch == "H" else 0.0
			if absf(p.y - base_y) > 0.5:
				continue
			var blocked := false
			for g in grown:
				if g.has_point(p + Vector3(0, 0.5, 0)):
					blocked = true
					break
			if not blocked:
				cover_points.append({"pos": p, "normal": cand[1], "height": a.size.y})


func _build_minimap_image() -> void:
	var ppm := 3
	var w := int(cols * CELL) * ppm
	var h := int(rows * CELL) * ppm
	minimap_image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	minimap_image.fill(Color(0, 0, 0, 0))
	var colors := {
		"g": Color(0.29, 0.4, 0.27), "a": Color(0.3, 0.32, 0.34), "S": Color(0.3, 0.36, 0.38), ".": Color(0.42, 0.42, 0.4),
		"m": Color(0.32, 0.38, 0.42), "t": Color(0.46, 0.5, 0.5), "D": Color(0.26, 0.4, 0.42), "H": Color(0.56, 0.6, 0.62),
		"A": Color(0.62, 0.5, 0.3), "B": Color(0.62, 0.5, 0.3),
	}
	for r in rows:
		for c in cols:
			var ch := cell(c, r)
			var col: Color = colors.get(ch, Color(0.45, 0.48, 0.5))
			if ch == "#":
				continue
			if _roof_cells.has(Vector2i(c, r)):
				col = col.darkened(0.25)
			minimap_image.fill_rect(Rect2i(c * 4 * ppm, r * 4 * ppm, 4 * ppm, 4 * ppm), col)
	for a in obstacles:
		var x0 := int((a.position.x - X0) * ppm)
		var z0 := int((a.position.z - Z0) * ppm)
		minimap_image.fill_rect(Rect2i(x0, z0, maxi(int(a.size.x * ppm), 2), maxi(int(a.size.z * ppm), 2)), Color(0.12, 0.14, 0.16))
	# Outline walkable space against walls.
	var outline := Color(0.75, 0.82, 0.85)
	for r in rows:
		for c in cols:
			if cell(c, r) == "#":
				continue
			var px := c * 4 * ppm
			var pz := r * 4 * ppm
			var s := 4 * ppm
			if cell(c, r - 1) == "#":
				minimap_image.fill_rect(Rect2i(px, pz, s, 2), outline)
			if cell(c, r + 1) == "#":
				minimap_image.fill_rect(Rect2i(px, pz + s - 2, s, 2), outline)
			if cell(c - 1, r) == "#":
				minimap_image.fill_rect(Rect2i(px, pz, 2, s), outline)
			if cell(c + 1, r) == "#":
				minimap_image.fill_rect(Rect2i(px + s - 2, pz, 2, s), outline)


func world_to_minimap(pos: Vector3) -> Vector2:
	return Vector2((pos.x - X0) / (cols * CELL), (pos.z - Z0) / (rows * CELL))


# ============================================================ navigation
func _bake_navigation() -> void:
	var nm := NavigationMesh.new()
	nm.cell_size = 0.25
	nm.cell_height = 0.2
	nm.agent_height = 1.8
	nm.agent_radius = 0.5
	nm.agent_max_climb = 0.4
	nm.agent_max_slope = 42.0
	nm.region_min_size = 4.0
	nm.edge_max_error = 1.0
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = GameConst.LAYER_WORLD
	nm.filter_baking_aabb = AABB(Vector3(X0, -1.0, Z0), Vector3(cols * CELL, 5.0, rows * CELL))
	nav_region.navigation_mesh = nm
	# bake_finished can be emitted from the worker thread; defer to the main thread.
	nav_region.bake_finished.connect(_on_bake_finished, CONNECT_ONE_SHOT | CONNECT_DEFERRED)
	nav_region.bake_navigation_mesh(true)


func _on_bake_finished() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	nav_ready = true
	navigation_ready.emit()


func nav_map() -> RID:
	return get_world_3d().navigation_map


func closest_nav_point(p: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(nav_map(), p)
