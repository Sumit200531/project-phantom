class_name Crosshair
extends Control
## Dynamic crosshair (gap follows real weapon spread), hit markers and damage-direction arcs.

var spread := 0.0
var color := Color(0.6, 1.0, 0.95)
var hidden_by_ads := false
var _hit_t := 0.0
var _hit_color := Color.WHITE
var _hit_size := 1.0
var _damage: Array = []   # [{angle, t}]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func hit(part: String, killed: bool) -> void:
	_hit_t = 0.22 if not killed else 0.4
	_hit_color = Color(1.0, 0.3, 0.25) if killed else (GameConst.COLOR_AMBER if part == "head" else Color(1, 1, 1))
	_hit_size = 1.35 if killed else 1.0


func damage_from(angle: float) -> void:
	_damage.append({"angle": angle, "t": 1.2})


func _process(delta: float) -> void:
	_hit_t = maxf(0.0, _hit_t - delta)
	for d in _damage:
		d.t -= delta
	_damage = _damage.filter(func(d): return d.t > 0.0)
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var gap := 4.0 + spread * 700.0
	var length := 7.0
	var w := 2.0
	if not hidden_by_ads:
		for dir in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			var a: Vector2 = c + dir * gap
			var b: Vector2 = c + dir * (gap + length)
			draw_line(a, b, Color(0, 0, 0, 0.55), w + 2.0)
		for dir in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			draw_line(c + dir * gap, c + dir * (gap + length), color, w)
		draw_rect(Rect2(c - Vector2(1.5, 1.5), Vector2(3, 3)), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(c - Vector2(1, 1), Vector2(2, 2)), color)
	else:
		draw_circle(c, 2.0, Color(0, 0, 0, 0.5))
		draw_circle(c, 1.3, color)
	if _hit_t > 0.0:
		var a := clampf(_hit_t / 0.22, 0.0, 1.0)
		var s := (10.0 + (1.0 - a) * 4.0) * _hit_size
		var col := Color(_hit_color.r, _hit_color.g, _hit_color.b, a)
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(c + d * s * 0.45, c + d * s, Color(0, 0, 0, a * 0.5), 4.0)
			draw_line(c + d * s * 0.45, c + d * s, col, 2.2)
	for d in _damage:
		var alpha := clampf(d.t / 0.6, 0.0, 1.0)
		var ang: float = d.angle - PI * 0.5
		var r := 120.0
		var pts := PackedVector2Array()
		for i in 13:
			var t := ang - 0.32 + 0.64 * i / 12.0
			pts.append(c + Vector2(cos(t), sin(t)) * r)
		draw_polyline(pts, Color(1.0, 0.25, 0.2, 0.85 * alpha), 6.0, true)
		var tip := c + Vector2(cos(ang), sin(ang)) * (r + 14.0)
		draw_colored_polygon(PackedVector2Array([tip, c + Vector2(cos(ang - 0.09), sin(ang - 0.09)) * (r + 2.0), c + Vector2(cos(ang + 0.09), sin(ang + 0.09)) * (r + 2.0)]), Color(1.0, 0.25, 0.2, 0.9 * alpha))
