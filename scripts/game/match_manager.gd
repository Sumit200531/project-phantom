class_name MatchManager
extends Node
## Round-based attack/defence match: preparation → live → (planted) → round end, halftime side
## swap, first to `rounds_to_win`. Owns the units, the objective device, team intel, sound
## events and statistics. Exposes static helpers so gameplay code can query the match cheaply.

signal phase_changed(phase: String)
signal round_started(round_number: int)
signal round_ended(winner_team: int, reason: String)
signal kill_event(info: Dictionary)
signal match_ended(winner_team: int)
signal announcement(title: String, subtitle: String, color: Color)
signal device_event(kind: String)

static var instance: MatchManager

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const BOT_SCENE := "res://scenes/ai/bot.tscn"
const ALLY_NAMES := ["Juno", "Rook", "Vex", "Ash", "Nova"]
const ENEMY_NAMES := ["Grit", "Moth", "Cinder", "Lark", "Quill"]

var level: FacilityBuilder
var units_root: Node3D
var abilities_node: Node3D
var player: PlayerController
var units: Array = []
var device: ObjectiveDevice
var clock := 0.0
var phase := "idle"
var phase_time := 0.0
var round_number := 0
var scores := [0, 0]
var attack_team := 0
var rounds_to_win := 5
var player_enabled := true
var attack_plan := {}
var team_intel := [{}, {}]
var sound_events: Array = []
var history: Array = []
var running := false
var interact_prompt := ""
var _spectate_i := 0
var _hitbox_cache := {0: [] as Array[RID], 1: [] as Array[RID]}


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


# ================================================================== static helpers
static func now() -> float:
	return instance.clock if instance else Time.get_ticks_msec() / 1000.0


static func combat_enabled() -> bool:
	return instance != null and instance.phase in ["prep", "live", "planted"]


static func abilities_allowed() -> bool:
	return instance != null and instance.phase in ["prep", "live", "planted"]


static func viewer_team() -> int:
	return 0


static func ability_root() -> Node3D:
	return instance.abilities_node


static func team_hitbox_rids(t: int) -> Array[RID]:
	if instance == null:
		return [] as Array[RID]
	return instance._hitbox_cache[t]


static func all_units() -> Array:
	return instance.units if instance else []


static func enemies_of(t: int) -> Array:
	var out := []
	if instance:
		for u in instance.units:
			if u.team != t:
				out.append(u)
	return out


static func report_sound(pos: Vector3, team: int, radius: float) -> void:
	if instance:
		instance.sound_events.append({"pos": pos, "team": team, "radius": radius, "time": instance.clock})


static func sound_events_since(t: float) -> Array:
	var out := []
	if instance:
		for ev in instance.sound_events:
			if ev.time > t:
				out.append(ev)
	return out


static func report_enemy_seen(team: int, unit: Combatant) -> void:
	if instance:
		instance.team_intel[team][unit] = {"pos": unit.global_position, "time": instance.clock}


static func is_interacting(u: Combatant) -> bool:
	if instance == null or instance.device == null:
		return false
	return instance.device.planter == u or instance.device.defuser == u


# ================================================================== setup
func defender_team() -> int:
	return 1 - attack_team


func side_of(t: int) -> String:
	return "attack" if t == attack_team else "defend"


func start_match(config: Dictionary) -> void:
	clear_match()
	level = config.level
	units_root = config.units_root
	rounds_to_win = config.get("rounds_to_win", 5)
	player_enabled = config.get("player", true)
	attack_team = 0 if config.get("side", "attack") == "attack" else 1
	abilities_node = Node3D.new()
	abilities_node.name = "Abilities"
	units_root.add_child(abilities_node)
	device = load("res://scenes/game/phase_charge.tscn").instantiate()
	device.name = "PhaseCharge"
	units_root.add_child(device)
	device.setup(level)
	device.planted.connect(_on_planted)
	device.defused.connect(_on_defused)
	device.detonated.connect(_on_detonated)
	device.dropped.connect(func() -> void: device_event.emit("dropped"))
	device.picked_up.connect(func(u: Combatant) -> void:
		if u == player:
			Sfx.play("device_pickup", -2.0, 0.0)
		device_event.emit("picked_up"))
	var diff := Settings.bot_difficulty
	if player_enabled:
		player = load(PLAYER_SCENE).instantiate()
		player.team = 0
		units_root.add_child(player)
		units.append(player)
	var weapons := ["res://assets/weapons/lancet.tres", "res://assets/weapons/lancet.tres", "res://assets/weapons/hornet.tres"]
	var ally_count := GameConst.TEAM_SIZE - (1 if player_enabled else 0)
	for i in ally_count:
		_add_bot(0, ALLY_NAMES[i], diff, weapons[i % weapons.size()])
	for i in GameConst.TEAM_SIZE:
		_add_bot(1, ENEMY_NAMES[i], diff, weapons[(i + 1) % weapons.size()])
	for u in units:
		u.died.connect(_on_unit_died.bind(u))
	scores = [0, 0]
	round_number = 0
	history.clear()
	clock = 0.0
	running = true
	_start_round()


func _add_bot(t: int, n: String, diff: int, weapon_path: String) -> void:
	var b: BotController = load(BOT_SCENE).instantiate()
	units_root.add_child(b)
	b.setup(t, n, t == viewer_team(), level, diff, weapon_path)
	units.append(b)


func clear_match() -> void:
	running = false
	phase = "idle"
	for u in units:
		if is_instance_valid(u):
			u.queue_free()
	units.clear()
	player = null
	if is_instance_valid(device):
		device.queue_free()
	device = null
	if is_instance_valid(abilities_node):
		abilities_node.queue_free()
	abilities_node = null
	Fx.clear_dynamic()


# ================================================================== round flow
func _start_round() -> void:
	round_number += 1
	var swapped := false
	if round_number == rounds_to_win and round_number > 1:
		attack_team = 1 - attack_team
		swapped = true
	for n in abilities_node.get_children():
		n.queue_free()
	Fx.clear_dynamic()
	team_intel = [{}, {}]
	sound_events.clear()
	device.reset()
	for t in 2:
		var spawn_key := "attack" if t == attack_team else "defend"
		var spots: Array = level.spawns[spawn_key].duplicate()
		var team_units := units.filter(func(u): return u.team == t)
		for i in team_units.size():
			var u: Combatant = team_units[i]
			u.reset_for_round(spots[i % spots.size()])
			if u is BotController:
				(u as BotController).side = spawn_key
	_plan_round()
	var attackers := units.filter(func(u): return u.team == attack_team)
	var carrier: Combatant = null
	if player_enabled and player.team == attack_team:
		carrier = player
	else:
		carrier = attackers.pick_random()
	device.give_to(carrier)
	level.set_spawn_walls(true)
	_rebuild_hitbox_cache()
	phase = "prep"
	phase_time = GameConst.PREP_TIME
	round_started.emit(round_number)
	phase_changed.emit(phase)
	var side_name := "ATTACK" if attack_team == viewer_team() else "DEFENSE"
	var sub := "Plant the Phase Charge on site A or B" if attack_team == viewer_team() else "Hold sites A and B"
	if swapped:
		announcement.emit("SWITCHING SIDES", "Round %d  ·  %s" % [round_number, side_name], GameConst.COLOR_AMBER)
	else:
		announcement.emit("ROUND %d" % round_number, "%s  ·  %s" % [side_name, sub], GameConst.COLOR_TEXT)


func _plan_round() -> void:
	var site: String = ["A", "B"].pick_random()
	attack_plan = {"site": site, "executing": false, "exec_time": randf_range(16.0, 32.0), "echo_used": false}
	var routes: Array = level.attack_routes[site].duplicate()
	routes.shuffle()
	var ri := 0
	var hold_plan := ["A", "B", "MID", "A", "B"]
	hold_plan.shuffle()
	var used := {"A": [], "B": [], "MID": []}
	var hi := 0
	for u in units:
		if not (u is BotController):
			continue
		var b := u as BotController
		if b.team == attack_team:
			var r: Array = routes[ri % routes.size()]
			ri += 1
			var jitter := Vector3(randf_range(-1.2, 1.2), 0, randf_range(-1.2, 1.2))
			b.route = r.map(func(p): return p + jitter)
			b.route_i = 0
		else:
			var k: String = hold_plan[hi % hold_plan.size()]
			hi += 1
			var options: Array = level.defend_holds[k]
			var pick: Dictionary = options[0]
			for o in options:
				if not used[k].has(o):
					pick = o
					break
			used[k].append(pick)
			b.hold = pick
			b.hold_site = k


func _physics_process(delta: float) -> void:
	if not running:
		return
	clock += delta
	while not sound_events.is_empty() and clock - sound_events[0].time > 2.5:
		sound_events.pop_front()
	phase_time -= delta
	match phase:
		"prep":
			if phase_time <= 0.0:
				phase = "live"
				phase_time = GameConst.ROUND_TIME
				level.set_spawn_walls(false)
				Sfx.play("round_start", -4.0, 0.0)
				phase_changed.emit(phase)
				announcement.emit("ROUND START", "", GameConst.COLOR_AMBER)
		"live":
			_update_attack_plan()
			_check_pickups()
			if phase_time <= 0.0:
				_end_round(defender_team(), "Time expired")
		"planted":
			pass
		"round_end":
			if phase_time <= 0.0:
				if scores[0] >= rounds_to_win or scores[1] >= rounds_to_win:
					_end_match()
				else:
					_start_round()


func _update_attack_plan() -> void:
	if attack_plan.get("executing", false):
		return
	var alive := 0
	var staged := 0
	for u in units:
		if u is BotController and u.team == attack_team and u.is_alive():
			alive += 1
			if u.staged:
				staged += 1
	var elapsed := GameConst.ROUND_TIME - phase_time
	var enough := alive > 0 and staged >= ceili(alive * 0.6)
	if (enough and elapsed > attack_plan.exec_time * 0.6) or elapsed > attack_plan.exec_time + 14.0 or phase_time < 38.0 or alive == 0:
		attack_plan["executing"] = true


func _check_pickups() -> void:
	if device.state != "dropped":
		return
	for u in units:
		if u.team == attack_team and u.is_alive() and u.global_position.distance_to(device.global_position) < 1.4:
			device.give_to(u)
			return


func _on_unit_died(info: Dictionary, unit: Combatant) -> void:
	var killer = info.get("attacker")
	unit.deaths += 1
	var headshot: bool = info.get("part", "") == "head"
	if killer is Combatant and killer != unit and killer.team != unit.team:
		killer.kills += 1
		killer.score += 150
		if headshot:
			killer.headshots += 1
	var assister: Combatant = null
	for a in unit.recent_damagers():
		if a != killer and a.team != unit.team:
			a.assists += 1
			a.score += 50
			assister = a
	kill_event.emit({"killer": killer if killer is Combatant else null, "victim": unit, "weapon": info.get("weapon", ""),
		"headshot": headshot, "assister": assister})
	if device.carrier == unit:
		device.drop(unit.global_position)
		if attack_team == viewer_team():
			announcement.emit("", "Phase Charge dropped", GameConst.COLOR_AMBER)
	if unit == player:
		_spectate_i = 0
	_check_elimination()


func _check_elimination() -> void:
	if not (phase in ["prep", "live", "planted"]):
		return
	var atk := 0
	var def := 0
	for u in units:
		if u.is_alive():
			if u.team == attack_team:
				atk += 1
			else:
				def += 1
	if phase == "planted":
		if def == 0:
			_end_round(attack_team, "Defenders eliminated")
	elif atk == 0:
		_end_round(defender_team(), "Attackers eliminated")
	elif def == 0:
		_end_round(attack_team, "Defenders eliminated")


func _on_planted(site: String, unit: Combatant) -> void:
	phase = "planted"
	phase_time = GameConst.DEVICE_TIME
	phase_changed.emit(phase)
	device_event.emit("planted")
	var col := GameConst.COLOR_ALLY if unit.team == viewer_team() else GameConst.COLOR_ENEMY
	announcement.emit("PHASE CHARGE PLANTED", "Site %s  ·  %d seconds" % [site, int(GameConst.DEVICE_TIME)], col)
	unit.score += 50
	_check_elimination()


func _on_defused(unit: Combatant) -> void:
	unit.score += 100
	device_event.emit("defused")
	_end_round(defender_team(), "Phase Charge defused by " + unit.unit_name)


func _on_detonated() -> void:
	device_event.emit("detonated")
	_end_round(attack_team, "Phase Charge detonated")


func _end_round(winner: int, reason: String) -> void:
	if phase in ["round_end", "match_end", "idle"]:
		return
	phase = "round_end"
	phase_time = GameConst.ROUND_END_TIME
	scores[winner] += 1
	history.append(winner)
	if device.planter:
		device.cancel_plant(device.planter)
	if device.defuser:
		device.cancel_defuse(device.defuser)
	Sfx.play("round_win" if winner == viewer_team() else "round_lose", -2.0, 0.0)
	round_ended.emit(winner, reason)
	phase_changed.emit(phase)


func _end_match() -> void:
	phase = "match_end"
	running = false
	var winner := 0 if scores[0] > scores[1] else 1
	Sfx.play("match_win" if winner == viewer_team() else "match_lose", 0.0, 0.0)
	phase_changed.emit(phase)
	match_ended.emit(winner)


# ================================================================== queries
func _rebuild_hitbox_cache() -> void:
	for t in 2:
		var arr: Array[RID] = []
		for u in units:
			if u.team == t:
				arr.append_array(u.hitbox_rids())
		_hitbox_cache[t] = arr


func alive_count(t: int) -> int:
	var n := 0
	for u in units:
		if u.team == t and u.is_alive():
			n += 1
	return n


func team_units(t: int) -> Array:
	return units.filter(func(u): return u.team == t)


func nearest_alive_bot(t: int, pos: Vector3) -> Combatant:
	var best: Combatant = null
	var bd := INF
	for u in units:
		if u.team == t and u.is_alive() and u is BotController:
			var d: float = u.global_position.distance_to(pos)
			if d < bd:
				bd = d
				best = u
	return best


func hot_site(t: int) -> String:
	var counts := {"A": 0, "B": 0}
	for e in team_intel[t]:
		var rec: Dictionary = team_intel[t][e]
		if clock - rec.time > 5.0 or not is_instance_valid(e) or not e.is_alive():
			continue
		for s in ["A", "B"]:
			if rec.pos.distance_to(level.site_centers[s]) < 24.0:
				counts[s] += 1
	if counts.A >= 2 or counts.B >= 2:
		return "A" if counts.A >= counts.B else "B"
	return ""


func time_display() -> float:
	if phase == "planted" and device:
		return maxf(device.time_left, 0.0)
	return maxf(phase_time, 0.0)


func cycle_spectate() -> void:
	if player == null:
		return
	var allies := units.filter(func(u): return u.team == player.team and u != player and u.is_alive())
	if allies.is_empty():
		player.spectate_target = null
		return
	_spectate_i = (_spectate_i + 1) % allies.size()
	player.spectate_target = allies[_spectate_i]


func player_interaction(p: Combatant, delta: float, holding: bool) -> void:
	interact_prompt = ""
	if not (phase in ["live", "planted"]):
		return
	if p.team == attack_team:
		if device.carrier == p and phase == "live":
			if device.zone_at(p.global_position) != "":
				interact_prompt = "Hold  F  to plant the Phase Charge"
				if holding:
					device.tick_plant(p, delta)
				else:
					device.cancel_plant(p)
			else:
				device.cancel_plant(p)
	else:
		if device.state == "planted" and p.global_position.distance_to(device.global_position) < 1.9:
			interact_prompt = "Hold  F  to defuse"
			if holding:
				if not device.tick_defuse(p, delta):
					interact_prompt = "A teammate is defusing"
			else:
				device.cancel_defuse(p)
		elif device.defuser == p:
			device.cancel_defuse(p)
