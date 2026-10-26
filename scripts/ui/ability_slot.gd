class_name AbilitySlot
extends Control
## One ability icon with keybind badge, radial cooldown sweep, countdown and ready pulse.

var index := 0
var kit: AbilityKit
var _pulse := 0.0
var _ready_flash := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(68, 68)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func flash_ready() -> void:
	_ready_flash = 1.0


func _process(delta: float) -> void:
	_pulse += delta
	_ready_flash = maxf(0.0, _ready_flash - delta * 1.5)
	queue_redraw()


func _draw() -> void:
	var s := size
	var c := s * 0.5
	var ready := kit == null or kit.is_ready(index)
	var frac := kit.fraction(index) if kit else 1.0
	var bg := Color(0.04, 0.06, 0.075, 0.85)
	draw_rect(Rect2(Vector2.ZERO, s), bg)
	var border := GameConst.COLOR_ALLY if ready else Color(1, 1, 1, 0.12)
	if ready:
		border.a = 0.55 + 0.25 * sin(_pulse * 3.0)
	draw_rect(Rect2(Vector2(1, 1), s - Vector2(2, 2)), border, false, 2.0)
	var icon_col := Color(0.93, 0.97, 0.98) if ready else Color(0.55, 0.6, 0.64)
	_draw_icon(c, icon_col)
	if not ready:
		var pts := PackedVector2Array([c])
		var start := -PI * 0.5 + TAU * frac
		var steps := 32
		for i in steps + 1:
			var a := start + (TAU * (1.0 - frac)) * i / steps
			pts.append(c + Vector2(cos(a), sin(a)) * s.x)
		draw_colored_polygon(_clip_square(pts, s), Color(0, 0, 0, 0.55))
		var f := UIKit.font("display")
		var txt := str(ceili(kit.remaining(index)))
		draw_string(f, Vector2(0, c.y + 9), txt, HORIZONTAL_ALIGNMENT_CENTER, s.x, 26, Color(1, 1, 1, 0.95))
	if _ready_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.3, 1.0, 0.9, 0.35 * _ready_flash))
	var key: String = AbilityKit.DEFS[index].bind
	var kb := Rect2(Vector2(s.x * 0.5 - 12, -12), Vector2(24, 22))
	draw_rect(kb, Color(0.02, 0.03, 0.04, 0.95))
	draw_rect(kb, Color(1, 1, 1, 0.35), false, 1.0)
	draw_string(UIKit.font("display"), Vector2(kb.position.x, kb.position.y + 17), key, HORIZONTAL_ALIGNMENT_CENTER, 24, 16, Color(1, 1, 1))


func _clip_square(pts: PackedVector2Array, s: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(Vector2(clampf(p.x, 0, s.x), clampf(p.y, 0, s.y)))
	return out


func _draw_icon(c: Vector2, col: Color) -> void:
	match AbilityKit.DEFS[index].id:
		"shroud":
			draw_circle(c + Vector2(-9, 4), 9.0, col)
			draw_circle(c + Vector2(4, -3), 12.0, col)
			draw_circle(c + Vector2(12, 7), 7.0, col)
			draw_rect(Rect2(c + Vector2(-17, 6), Vector2(34, 7)), col)
		"aegis":
			var pts := PackedVector2Array()
			for i in 6:
				var a := TAU * i / 6.0 + PI / 6.0
				pts.append(c + Vector2(cos(a), sin(a)) * 18.0)
			pts.append(pts[0])
			draw_polyline(pts, col, 3.0, true)
			draw_line(c + Vector2(-9, 0), c + Vector2(9, 0), col, 3.0)
			draw_line(c + Vector2(0, -10), c + Vector2(0, 10), col, 3.0)
		"echo":
			draw_circle(c, 4.0, col)
			for r in [10.0, 17.0, 24.0]:
				draw_arc(c, r, -0.9, 0.9, 12, col, 2.5, true)
				draw_arc(c, r, PI - 0.9, PI + 0.9, 12, col, 2.5, true)
