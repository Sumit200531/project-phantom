class_name WeaponData
extends Resource
## Tuning for one weapon. Instances live in assets/weapons/*.tres.

@export var id := "lancet"
@export var display_name := "Lancet"
@export var category := "Rifle"
@export var slot := 1
@export_group("Damage")
@export var damage := 39.0
@export var head_mult := 4.0
@export var leg_mult := 0.85
@export var falloff_start := 30.0
@export var falloff_min := 0.85
@export var max_range := 180.0
@export_group("Handling")
@export var fire_rate := 9.75
@export var automatic := true
@export var mag_size := 25
@export var reserve := 75
@export var reload_time := 2.2
@export var reload_empty_time := 2.6
@export var equip_time := 0.7
@export var move_speed_mult := 0.95
@export_group("Accuracy")
@export var spread_base := 0.0025
@export var spread_move := 0.055
@export var spread_air := 0.16
@export var spread_per_shot := 0.006
@export var spread_max := 0.07
@export var spread_recovery := 0.45
@export var ads_fov_mult := 0.82
@export var ads_spread_mult := 0.55
@export_group("Recoil")
@export var recoil_pitch := 0.0105
@export var recoil_yaw := 0.0035
@export var recoil_pattern := PackedVector2Array()
@export var recoil_recovery := 7.0
@export var view_kick := 1.0
@export_group("Presentation")
@export var sound := "rifle_shot"
@export var tracer_every := 3
@export var bot_accuracy := 1.0
@export var bot_burst := Vector2i(3, 6)


func damage_for(part: String, distance: float) -> float:
	var mult := 1.0
	match part:
		"head": mult = head_mult
		"legs": mult = leg_mult
	var fall := 1.0
	if distance > falloff_start:
		fall = lerpf(1.0, falloff_min, clampf((distance - falloff_start) / 40.0, 0.0, 1.0))
	return damage * mult * fall


## Recoil multipliers (pitch, yaw) for the n-th consecutive shot.
func pattern(n: int) -> Vector2:
	if recoil_pattern.is_empty():
		return Vector2(1, 0)
	return recoil_pattern[mini(n, recoil_pattern.size() - 1)]
