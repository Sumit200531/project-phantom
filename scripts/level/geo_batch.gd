class_name GeoBatch
extends RefCounted
## Accumulates procedural geometry (boxes, cylinders, wedges, quads) per material and per
## spatial chunk, then commits one MeshInstance3D per (material, chunk). This keeps the
## detailed facility at a few hundred draw calls while still allowing frustum culling.

const CHUNK := 28.0

var _tools := {}     # "material|cx|cz" -> SurfaceTool
var _counts := {}    # same key -> vertex count


func _key(mat: String, at: Vector3) -> String:
	return "%s|%d|%d" % [mat, int(floor(at.x / CHUNK)), int(floor(at.z / CHUNK))]


func _st(mat: String, at: Vector3) -> SurfaceTool:
	var k := _key(mat, at)
	if not _tools.has(k):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[k] = st
		_counts[k] = 0
	_counts[k] += 1
	return _tools[k]


## Adds a triangle pair; fixes winding so the face points along `n` (Godot uses clockwise fronts).
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = d
		d = t
	var uv := _uv_axes(n)
	for v in [a, b, c, a, c, d]:
		st.set_normal(n)
		st.set_uv(Vector2(v.dot(uv[0]), v.dot(uv[1])))
		st.add_vertex(v)


## Quad with per-vertex normals (smooth shading). `facing` decides winding.
func _quad_smooth(st: SurfaceTool, v: Array, n: Array, facing: Vector3) -> void:
	var order := [0, 1, 2, 0, 2, 3]
	if (v[1] - v[0]).cross(v[2] - v[0]).dot(facing) > 0.0:
		order = [0, 3, 2, 0, 2, 1]
	var uv := _uv_axes(facing)
	for i in order:
		st.set_normal(n[i])
		st.set_uv(Vector2(v[i].dot(uv[0]), v[i].dot(uv[1])))
		st.add_vertex(v[i])


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
	var uv := _uv_axes(n)
	for v in [a, b, c]:
		st.set_normal(n)
		st.set_uv(Vector2(v.dot(uv[0]), v.dot(uv[1])))
		st.add_vertex(v)


func _uv_axes(n: Vector3) -> Array:
	var an := n.abs()
	if an.y >= an.x and an.y >= an.z:
		return [Vector3(1, 0, 0), Vector3(0, 0, 1)]
	if an.x >= an.z:
		return [Vector3(0, 0, -signf(n.x) if n.x != 0.0 else 1.0), Vector3(0, -1, 0)]
	return [Vector3(signf(n.z) if n.z != 0.0 else 1.0, 0, 0), Vector3(0, -1, 0)]


## Axis-aligned or rotated box. `xf` places the box centre; `size` is full extents.
func box(mat: String, xf: Transform3D, size: Vector3, skip_bottom := true, skip_top := false) -> void:
	var st := _st(mat, xf.origin)
	var h := size * 0.5
	var b := xf.basis
	var rb := b.orthonormalized()
	var p := func(x: float, y: float, z: float) -> Vector3: return xf * Vector3(x * h.x, y * h.y, z * h.z)
	var faces := [
		[Vector3(1, 0, 0), p.call(1, -1, -1), p.call(1, 1, -1), p.call(1, 1, 1), p.call(1, -1, 1)],
		[Vector3(-1, 0, 0), p.call(-1, -1, 1), p.call(-1, 1, 1), p.call(-1, 1, -1), p.call(-1, -1, -1)],
		[Vector3(0, 0, 1), p.call(1, -1, 1), p.call(1, 1, 1), p.call(-1, 1, 1), p.call(-1, -1, 1)],
		[Vector3(0, 0, -1), p.call(-1, -1, -1), p.call(-1, 1, -1), p.call(1, 1, -1), p.call(1, -1, -1)],
	]
	if not skip_top:
		faces.append([Vector3(0, 1, 0), p.call(-1, 1, -1), p.call(-1, 1, 1), p.call(1, 1, 1), p.call(1, 1, -1)])
	if not skip_bottom:
		faces.append([Vector3(0, -1, 0), p.call(-1, -1, 1), p.call(-1, -1, -1), p.call(1, -1, -1), p.call(1, -1, 1)])
	for f in faces:
		_quad(st, f[1], f[2], f[3], f[4], (rb * f[0]).normalized())


## Convenience: axis-aligned box from min corner + size.
func box_at(mat: String, min_corner: Vector3, size: Vector3, skip_bottom := true) -> void:
	box(mat, Transform3D(Basis(), min_corner + size * 0.5), size, skip_bottom)


func quad(mat: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	_quad(_st(mat, (a + c) * 0.5), a, b, c, d, n.normalized())


## Cylinder along local +Y, centred on xf.origin.
func cylinder(mat: String, xf: Transform3D, r_bottom: float, r_top: float, height: float, segments := 12, caps := true) -> void:
	var st := _st(mat, xf.origin)
	var rb := xf.basis.orthonormalized()
	var hh := height * 0.5
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var v0 := xf * (d0 * r_bottom + Vector3(0, -hh, 0))
		var v1 := xf * (d1 * r_bottom + Vector3(0, -hh, 0))
		var v2 := xf * (d1 * r_top + Vector3(0, hh, 0))
		var v3 := xf * (d0 * r_top + Vector3(0, hh, 0))
		var slope := (r_bottom - r_top) / maxf(height, 0.001)
		var n0 := (rb * (d0 + Vector3(0, slope, 0))).normalized()
		var n1 := (rb * (d1 + Vector3(0, slope, 0))).normalized()
		_quad_smooth(st, [v0, v1, v2, v3], [n0, n1, n1, n0], (n0 + n1).normalized())
		if caps:
			var top_c := xf * Vector3(0, hh, 0)
			var bot_c := xf * Vector3(0, -hh, 0)
			if r_top > 0.001:
				_tri(st, top_c, v3, v2, (rb * Vector3.UP).normalized())
			_tri(st, bot_c, v1, v0, (rb * Vector3.DOWN).normalized())


## Ramp wedge: footprint size.x by size.z, rising from 0 at local +Z edge to size.y at local -Z edge.
func wedge(mat: String, xf: Transform3D, size: Vector3) -> void:
	var st := _st(mat, xf.origin)
	var rb := xf.basis.orthonormalized()
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var y0 := -size.y * 0.5
	var y1 := size.y * 0.5
	var bl := xf * Vector3(-hx, y0, hz)
	var br := xf * Vector3(hx, y0, hz)
	var tl := xf * Vector3(-hx, y1, -hz)
	var tr := xf * Vector3(hx, y1, -hz)
	var bl2 := xf * Vector3(-hx, y0, -hz)
	var br2 := xf * Vector3(hx, y0, -hz)
	var slope_n := (rb * Vector3(0, size.z, size.y).normalized()).normalized()
	_quad(st, bl, br, tr, tl, slope_n)
	_quad(st, bl2, tl, tr, br2, (rb * Vector3(0, 0, -1)).normalized())
	_tri(st, bl, tl, bl2, (rb * Vector3(-1, 0, 0)).normalized())
	_tri(st, br, br2, tr, (rb * Vector3(1, 0, 0)).normalized())


## Low-poly irregular blob (foliage clusters, rocks).
func blob(mat: String, center: Vector3, radius: Vector3, rng: RandomNumberGenerator, rings := 5, segs := 7) -> void:
	var st := _st(mat, center)
	var pts := []
	for r in rings + 1:
		var row := []
		var lat := PI * r / rings
		for s in segs:
			var lon := TAU * s / segs + (0.3 if r % 2 == 1 else 0.0)
			var d := Vector3(sin(lat) * cos(lon), cos(lat), sin(lat) * sin(lon))
			var k := 1.0 if r == 0 or r == rings else rng.randf_range(0.82, 1.12)
			row.append(center + d * radius * k)
		pts.append(row)
	for r in rings:
		for s in segs:
			var a: Vector3 = pts[r][s]
			var b: Vector3 = pts[r][(s + 1) % segs]
			var c: Vector3 = pts[r + 1][(s + 1) % segs]
			var d: Vector3 = pts[r + 1][s]
			var n := ((a + b + c + d) * 0.25 - center).normalized()
			_quad(st, a, b, c, d, n)


func commit(parent: Node3D, matlib: MaterialLib, shadows := true) -> int:
	var made := 0
	for k in _tools:
		if _counts[k] == 0:
			continue
		var st: SurfaceTool = _tools[k]
		st.generate_tangents()
		var mesh := st.commit()
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var mat_name: String = k.split("|")[0]
		mi.material_override = matlib.get_mat(mat_name)
		mi.name = "Batch_" + k.replace("|", "_")
		var no_shadow := mat_name.begins_with("emit") or mat_name.begins_with("glass") or mat_name == "grass_card"
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (shadows and not no_shadow) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		made += 1
	_tools.clear()
	_counts.clear()
	return made
