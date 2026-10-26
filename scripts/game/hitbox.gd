class_name Hitbox
extends Area3D
## A damageable region of a combatant (head / body / legs). Hitscan rays query these areas.

var part := "body"
var unit: Node = null


static func create(owner_unit: Node, hit_part: String, shape: Shape3D, local_pos: Vector3) -> Hitbox:
	var hb := Hitbox.new()
	hb.part = hit_part
	hb.unit = owner_unit
	hb.name = "Hitbox_" + hit_part
	hb.collision_layer = GameConst.LAYER_HITBOX
	hb.collision_mask = 0
	hb.monitoring = false
	hb.monitorable = true
	hb.input_ray_pickable = false
	var cs := CollisionShape3D.new()
	cs.shape = shape
	hb.add_child(cs)
	hb.position = local_pos
	return hb


func set_enabled(on: bool) -> void:
	collision_layer = GameConst.LAYER_HITBOX if on else 0
