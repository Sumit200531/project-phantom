class_name Minimap
extends Control
## North-up minimap drawn from the real level layout: allies, the player's view cone, enemies
## spotted by the team (or revealed by Echo Pulse), the Phase Charge, sites and active utility.

var level: FacilityBuilder
var _tex: ImageTexture
var _pulse := 0.0


func setup(p_level: FacilityBuilder) -> void:
	level = p_level
	if level.minimap_image:
		_tex = ImageTexture.create_from_image(level.minimap_image)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func _process(delta: float) -> void:
	_pulse += delta
	if is_visible_in_tree():
		queue_redraw()


func _to_px(pos: Vector3) -> Vector2:
	var uv := level.world_to_minimap(pos)
	return Vector2(uv.x * size.x, uv.y * size.y)


func _draw() -> void:
	if level == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.045, 0.055, 0.82))
	if _tex:
		draw_texture_rect(_tex, Rect2(Vector2.ZERO, size), false, Color(1, 1, 1, 0.92))
	var f := UIKit.font("display")
	for s in ["A", "B"]:
		if level.site_centers.has(s):
			var p := _to_px(level.site_centers[s])
			draw_string(f, p + Vector2(-7, 8), s, HORIZONTAL_ALIGNMENT_CENTER, -1, 22, Color(1.0, 0.75, 0.35, 0.85))
	var mm := MatchManager.instance
	if mm == null or not mm.running and mm.phase != "match_end":
		return
	var viewer := MatchManager.viewer_team()
	for n in get_tree().get_nodes_in_group("smoke_fields"):
		var r: float = n.radius * size.x / (level.cols * level.CELL)
		draw_circle(_to_px(n.global_position), r, Color(0.78, 0.8, 0.9, 0.55))
	for n in get_tree().get_nodes_in_group("ability_objects"):
		if n is EnergyBarrier:
			var xf: Transform3D = n.global_transform
			var a := _to_px(xf * Vector3(-3, 0, 0))
			var b := _to_px(xf * Vector3(3, 0, 0))
			draw_line(a, b, GameConst.COLOR_CYAN if n.team == viewer else GameConst.COLOR_ENEMY, 3.0)
	var dev: ObjectiveDevice = mm.device
	if dev and (dev.state == "dropped" or dev.state == "planted"):
		var dp := _to_px(dev.global_position)
		var k := 7.0 + (sin(_pulse * 8.0) * 2.0 if dev.state == "planted" else 0.0)
		draw_colored_polygon(PackedVector2Array([dp + Vector2(0, -k), dp + Vector2(k, 0), dp + Vector2(0, k), dp + Vector2(-k, 0)]), GameConst.COLOR_AMBER)
	for u in mm.units:
		if not u.is_alive():
			if u.team == viewer:
				var xp := _to_px(u.global_position)
				draw_line(xp + Vector2(-4, -4), xp + Vector2(4, 4), Color(1, 1, 1, 0.35), 2.0)
				draw_line(xp + Vector2(-4, 4), xp + Vector2(4, -4), Color(1, 1, 1, 0.35), 2.0)
			continue
		var p := _to_px(u.global_position)
		if u.team == viewer:
			var fwd: Vector3 = u.aim_direction()
			var ang := atan2(fwd.z, fwd.x)
			if u.is_player:
				var cone := PackedVector2Array([p])
				for i in 9:
					var t := ang - 0.55 + 1.1 * i / 8.0
					cone.append(p + Vector2(cos(t), sin(t)) * 34.0)
				draw_colored_polygon(cone, Color(1, 1, 1, 0.12))
				var tri := PackedVector2Array([p + Vector2(cos(ang), sin(ang)) * 9.0, p + Vector2(cos(ang + 2.5), sin(ang + 2.5)) * 6.0, p + Vector2(cos(ang - 2.5), sin(ang - 2.5)) * 6.0])
				draw_colored_polygon(tri, Color(1, 1, 1))
			else:
				draw_circle(p, 5.0, Color(0, 0, 0, 0.6))
				draw_circle(p, 4.0, GameConst.COLOR_ALLY)
				draw_line(p, p + Vector2(cos(ang), sin(ang)) * 9.0, GameConst.COLOR_ALLY, 2.0)
			if u.carrying_device:
				draw_arc(p, 8.0, 0, TAU, 16, GameConst.COLOR_AMBER, 2.0)
		else:
			var rec = mm.team_intel[viewer].get(u)
			var seen: bool = rec != null and mm.clock - rec.time < 1.2
			if seen or u.is_revealed_to(viewer):
				var ep: Vector2 = _to_px(rec.pos) if seen and not u.is_revealed_to(viewer) else p
				draw_circle(ep, 5.5, Color(0, 0, 0, 0.6))
				draw_circle(ep, 4.5, GameConst.COLOR_ENEMY)
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.14), false, 1.0)
