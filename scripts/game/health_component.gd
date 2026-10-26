class_name HealthComponent
extends Node
## Health + armour. Armour absorbs a share of incoming damage until it is depleted.

signal damaged(info: Dictionary)
signal died(info: Dictionary)
signal healed(amount: float)

const ARMOR_ABSORB := 0.66

@export var max_health := 100.0
@export var max_armor := 50.0

var health := 100.0
var armor := 0.0
var alive := true


func reset(with_armor := true) -> void:
	health = max_health
	armor = max_armor if with_armor else 0.0
	alive = true


## Applies damage described by `info` (keys: amount, attacker, part, weapon, position, direction).
## Returns the total damage actually dealt (health + armour).
func apply_damage(info: Dictionary) -> float:
	if not alive:
		return 0.0
	var amount: float = info.get("amount", 0.0)
	var absorbed := minf(armor, amount * ARMOR_ABSORB)
	armor -= absorbed
	var hp_loss := minf(amount - absorbed, health)
	health -= hp_loss
	info["dealt"] = hp_loss + absorbed
	damaged.emit(info)
	if health <= 0.01:
		health = 0.0
		alive = false
		died.emit(info)
	return hp_loss + absorbed


func heal(amount: float) -> void:
	if not alive:
		return
	var before := health
	health = minf(max_health, health + amount)
	if health > before:
		healed.emit(health - before)
