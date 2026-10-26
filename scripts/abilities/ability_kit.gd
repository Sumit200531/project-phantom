class_name AbilityKit
extends Node
## The operative's three abilities with cooldowns. Shared by the player and bots.

signal used(index: int)
signal became_ready(index: int)

const DEFS := [
	{"id": "shroud", "name": "Shroud", "action": "ability_1", "bind": "Q", "cooldown": 30.0,
		"desc": "Throw a canister that blooms into an obscuring field for 14 seconds."},
	{"id": "aegis", "name": "Aegis Wall", "action": "ability_2", "bind": "E", "cooldown": 38.0,
		"desc": "Raise an energy barrier that stops enemy bullets for 15 seconds."},
	{"id": "echo", "name": "Echo Pulse", "action": "ability_3", "bind": "C", "cooldown": 42.0,
		"desc": "Emit a pulse that reveals enemies within 28 metres for 4 seconds."},
]

var unit: Combatant
var ready_at := [0.0, 0.0, 0.0]
var _was_ready := [true, true, true]


func setup(u: Combatant) -> void:
	unit = u


func reset_for_round() -> void:
	var now := MatchManager.now()
	for i in ready_at.size():
		ready_at[i] = now
		_was_ready[i] = true


func is_ready(i: int) -> bool:
	return MatchManager.now() >= ready_at[i]


func remaining(i: int) -> float:
	return maxf(0.0, ready_at[i] - MatchManager.now())


func fraction(i: int) -> float:
	return 1.0 - remaining(i) / DEFS[i].cooldown


func _process(_delta: float) -> void:
	for i in ready_at.size():
		var r := is_ready(i)
		if r and not _was_ready[i]:
			became_ready.emit(i)
			if unit and unit.is_player:
				Sfx.play("ability_ready", -8.0, 0.0)
		_was_ready[i] = r


## origin/dir: where the caster is aiming. target: optional world point (bots aim abilities at spots).
func use(i: int, origin: Vector3, dir: Vector3, target := Vector3.INF) -> bool:
	if not unit or not unit.is_alive() or not is_ready(i):
		return false
	if not MatchManager.abilities_allowed():
		return false
	match DEFS[i].id:
		"shroud":
			var vel: Vector3
			if target != Vector3.INF:
				vel = SmokeField.solve_throw(origin, target)
			else:
				vel = dir * 17.0 + Vector3.UP * 3.0
			SmokeField.throw(unit, origin + dir * 0.4, vel)
		"aegis":
			if not EnergyBarrier.deploy(unit, origin, dir):
				return false
		"echo":
			ReconPulse.emit(unit)
	ready_at[i] = MatchManager.now() + DEFS[i].cooldown
	_was_ready[i] = false
	used.emit(i)
	return true
