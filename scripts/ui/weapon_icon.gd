class_name WeaponIcon
extends Control
## Vector silhouette of the equipped weapon for the HUD.

var weapon_id := "lancet"
var tint := Color(0.93, 0.95, 0.96)


func _ready() -> void:
	custom_minimum_size = Vector2(150, 48)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_weapon(id: String) -> void:
	weapon_id = id
	queue_redraw()


func _draw() -> void:
	var k := size.y / 48.0
	var o := Vector2(size.x - 150.0 * k, 0)
	var polys := []
	match weapon_id:
		"lancet":
			polys = [
				[Vector2(4, 18), Vector2(30, 16), Vector2(34, 12), Vector2(96, 12), Vector2(100, 15), Vector2(146, 15), Vector2(146, 21), Vector2(100, 21), Vector2(96, 26), Vector2(30, 26), Vector2(8, 30), Vector2(4, 28)],
				[Vector2(46, 26), Vector2(58, 26), Vector2(64, 44), Vector2(54, 46)],
				[Vector2(30, 26), Vector2(40, 26), Vector2(36, 40), Vector2(28, 38)],
				[Vector2(54, 6), Vector2(78, 6), Vector2(78, 12), Vector2(54, 12)],
				[Vector2(88, 26), Vector2(96, 26), Vector2(96, 36), Vector2(88, 36)],
			]
		"hornet":
			polys = [
				[Vector2(30, 14), Vector2(104, 14), Vector2(104, 18), Vector2(132, 18), Vector2(132, 24), Vector2(104, 24), Vector2(104, 28), Vector2(30, 28)],
				[Vector2(64, 28), Vector2(74, 28), Vector2(76, 46), Vector2(66, 46)],
				[Vector2(36, 28), Vector2(46, 28), Vector2(42, 42), Vector2(34, 40)],
				[Vector2(6, 16), Vector2(30, 16), Vector2(30, 19), Vector2(10, 19), Vector2(10, 26), Vector2(6, 26)],
				[Vector2(60, 8), Vector2(78, 8), Vector2(78, 14), Vector2(60, 14)],
			]
		"kite":
			polys = [
				[Vector2(54, 12), Vector2(124, 12), Vector2(124, 24), Vector2(54, 24)],
				[Vector2(58, 24), Vector2(76, 24), Vector2(72, 46), Vector2(58, 44)],
				[Vector2(76, 24), Vector2(92, 24), Vector2(90, 30), Vector2(78, 30)],
			]
	for p in polys:
		var pts := PackedVector2Array()
		for v in p:
			pts.append(o + v * k)
		draw_colored_polygon(pts, tint)
