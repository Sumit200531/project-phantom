class_name HUD
extends Control
## In-match heads-up display.

var mm: MatchManager
var player: PlayerController
var level: FacilityBuilder

var crosshair: Crosshair
var minimap: Minimap
var area_label: Label
var score_ally: Label
var score_enemy: Label
var side_ally: Label
var side_enemy: Label
var timer_label: Label
var round_label: Label
var roster: Control
var killfeed: VBoxContainer
var hp_label: Label
var armor_label: Label
var vitals: Control
var ability_slots: Array[AbilitySlot] = []
var ability_names: Array[Label] = []
var weapon_icon: WeaponIcon
var weapon_name: Label
var ammo_label: Label
var reserve_label: Label
var slots_label: RichTextLabel
var carry_chip: PanelContainer
var prompt_label: Label
var progress: Control
var banner: VBoxContainer
var banner_title: Label
var banner_sub: Label
var result: VBoxContainer
var result_title: Label
var result_sub: Label
var death_label: Label
var spectate_label: Label
var fps_label: Label
var smoke_overlay: ColorRect
var vignette: TextureRect
var _banner_tween: Tween
var _result_tween: Tween
var _hurt := 0.0
var _progress_frac := 0.0
var _progress_kind := ""
var _timer_pulse := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UIKit.theme()
	_build()
	visible = false


func bind(p_mm: MatchManager, p_level: FacilityBuilder) -> void:
	mm = p_mm
	level = p_level
	player = mm.player
	minimap.setup(level)
	for c in killfeed.get_children():
		c.queue_free()
	if not mm.kill_event.is_connected(_on_kill):
		mm.kill_event.connect(_on_kill)
		mm.announcement.connect(_on_announcement)
		mm.round_ended.connect(_on_round_ended)
		mm.round_started.connect(_on_round_started)
	if player:
		player.weapons.hit_confirmed.connect(func(part: String, killed: bool) -> void: crosshair.hit(part, killed))
		player.took_damage.connect(_on_player_damaged)
		player.weapons.weapon_changed.connect(func(w: WeaponData) -> void: weapon_icon.set_weapon(w.id))
		for i in 3:
			ability_slots[i].kit = player.abilities
		player.abilities.became_ready.connect(func(i: int) -> void: ability_slots[i].flash_ready())
		weapon_icon.set_weapon(player.weapons.data().id)


# ================================================================== construction
func _anchor(c: Control, preset: int, pos: Vector2, sz: Vector2) -> void:
	add_child(c)
	place(c, preset, pos, sz)


## Anchors `c` with `preset` and sets offsets relative to that anchor point.
static func place(c: Control, preset: int, pos: Vector2, sz: Vector2) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = pos.x
	c.offset_top = pos.y
	c.offset_right = pos.x + sz.x
	c.offset_bottom = pos.y + sz.y


func _build() -> void:
	# Overlays (bottom-most)
	smoke_overlay = ColorRect.new()
	smoke_overlay.color = Color(0.74, 0.76, 0.84, 0.0)
	smoke_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	smoke_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(smoke_overlay)
	vignette = TextureRect.new()
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.05, 0.5)
	var grad := Gradient.new()
	grad.set_color(0, Color(0.7, 0.05, 0.05, 0.0))
	grad.add_point(0.55, Color(0.7, 0.05, 0.05, 0.0))
	grad.set_color(grad.get_point_count() - 1, Color(0.75, 0.05, 0.05, 0.85))
	g.gradient = grad
	g.width = 256
	g.height = 256
	vignette.texture = g
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.modulate.a = 0.0
	add_child(vignette)
	crosshair = Crosshair.new()
	add_child(crosshair)

	# --- Score cluster (top centre)
	var top := Control.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(top, Control.PRESET_CENTER_TOP, Vector2(-280, 14), Vector2(560, 104))
	var ally_bg := Panel.new()
	ally_bg.add_theme_stylebox_override("panel", UIKit.box(Color(0.06, 0.22, 0.22, 0.85), 2, Color(0.2, 0.86, 0.8, 0.55), 1, 0.25))
	ally_bg.position = Vector2(0, 0)
	ally_bg.size = Vector2(170, 62)
	ally_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(ally_bg)
	score_ally = UIKit.shadowed(UIKit.label("0", 40, UIKit.ALLY, "display", HORIZONTAL_ALIGNMENT_RIGHT))
	score_ally.position = Vector2(80, 2)
	score_ally.size = Vector2(76, 50)
	top.add_child(score_ally)
	side_ally = UIKit.label("ATTACK", 14, Color(0.7, 0.95, 0.92), "display_semi")
	side_ally.position = Vector2(22, 10)
	top.add_child(side_ally)
	var you := UIKit.label("YOUR TEAM", 12, UIKit.DIM, "body_bold")
	you.position = Vector2(22, 30)
	top.add_child(you)
	var timer_bg := Panel.new()
	timer_bg.add_theme_stylebox_override("panel", UIKit.box(Color(0.03, 0.04, 0.05, 0.9), 2, UIKit.LINE, 1))
	timer_bg.position = Vector2(184, 0)
	timer_bg.size = Vector2(192, 62)
	timer_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(timer_bg)
	timer_label = UIKit.shadowed(UIKit.label("1:45", 36, UIKit.TEXT, "display", HORIZONTAL_ALIGNMENT_CENTER))
	timer_label.position = Vector2(184, -2)
	timer_label.size = Vector2(192, 46)
	top.add_child(timer_label)
	round_label = UIKit.label("ROUND 1", 13, UIKit.DIM, "body_bold", HORIZONTAL_ALIGNMENT_CENTER)
	round_label.position = Vector2(184, 40)
	round_label.size = Vector2(192, 18)
	top.add_child(round_label)
	var enemy_bg := Panel.new()
	enemy_bg.add_theme_stylebox_override("panel", UIKit.box(Color(0.24, 0.07, 0.06, 0.85), 2, Color(1.0, 0.36, 0.26, 0.55), 1, -0.25))
	enemy_bg.position = Vector2(390, 0)
	enemy_bg.size = Vector2(170, 62)
	enemy_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(enemy_bg)
	score_enemy = UIKit.shadowed(UIKit.label("0", 40, UIKit.ENEMY, "display"))
	score_enemy.position = Vector2(404, 2)
	score_enemy.size = Vector2(76, 50)
	top.add_child(score_enemy)
	side_enemy = UIKit.label("DEFENSE", 14, Color(1.0, 0.75, 0.68), "display_semi", HORIZONTAL_ALIGNMENT_RIGHT)
	side_enemy.position = Vector2(440, 10)
	side_enemy.size = Vector2(98, 20)
	top.add_child(side_enemy)
	var them := UIKit.label("OPPONENTS", 12, UIKit.DIM, "body_bold", HORIZONTAL_ALIGNMENT_RIGHT)
	them.position = Vector2(440, 30)
	them.size = Vector2(98, 18)
	top.add_child(them)
	roster = Control.new()
	roster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	roster.position = Vector2(0, 70)
	roster.size = Vector2(560, 30)
	roster.draw.connect(_draw_roster)
	top.add_child(roster)

	# --- Minimap (top left)
	minimap = Minimap.new()
	_anchor(minimap, Control.PRESET_TOP_LEFT, Vector2(20, 20), Vector2(224, 272))
	area_label = UIKit.shadowed(UIKit.label("", 17, UIKit.TEXT, "display_semi"))
	_anchor(area_label, Control.PRESET_TOP_LEFT, Vector2(22, 298), Vector2(224, 24))

	# --- Kill feed (top right)
	killfeed = VBoxContainer.new()
	killfeed.alignment = BoxContainer.ALIGNMENT_BEGIN
	killfeed.add_theme_constant_override("separation", 4)
	killfeed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(killfeed, Control.PRESET_TOP_RIGHT, Vector2(-470, 20), Vector2(450, 300))
	fps_label = UIKit.label("", 13, UIKit.DIM, "body_bold", HORIZONTAL_ALIGNMENT_RIGHT)
	_anchor(fps_label, Control.PRESET_TOP_RIGHT, Vector2(-120, 2), Vector2(110, 18))

	# --- Vitals (bottom left)
	vitals = Control.new()
	vitals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vitals.draw.connect(_draw_vitals)
	_anchor(vitals, Control.PRESET_BOTTOM_LEFT, Vector2(24, -118), Vector2(330, 96))
	hp_label = UIKit.shadowed(UIKit.label("100", 50, UIKit.TEXT, "display"))
	hp_label.position = Vector2(14, 4)
	hp_label.size = Vector2(120, 60)
	vitals.add_child(hp_label)
	armor_label = UIKit.label("50", 20, Color(0.75, 0.9, 1.0), "display_semi")
	armor_label.position = Vector2(150, 26)
	vitals.add_child(armor_label)

	# --- Abilities (bottom centre)
	var abil := HBoxContainer.new()
	abil.add_theme_constant_override("separation", 14)
	abil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(abil, Control.PRESET_CENTER_BOTTOM, Vector2(-122, -112), Vector2(244, 96))
	for i in 3:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var slot := AbilitySlot.new()
		slot.index = i
		col.add_child(slot)
		var nm := UIKit.label(String(AbilityKit.DEFS[i].name).to_upper(), 12, UIKit.DIM, "body_bold", HORIZONTAL_ALIGNMENT_CENTER)
		nm.custom_minimum_size = Vector2(68, 0)
		col.add_child(nm)
		abil.add_child(col)
		ability_slots.append(slot)
		ability_names.append(nm)

	# --- Weapon (bottom right)
	var wpanel := Panel.new()
	wpanel.add_theme_stylebox_override("panel", UIKit.box(Color(0.03, 0.045, 0.055, 0.72), 3, UIKit.LINE, 1))
	wpanel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(wpanel, Control.PRESET_BOTTOM_RIGHT, Vector2(-372, -132), Vector2(348, 112))
	weapon_icon = WeaponIcon.new()
	weapon_icon.position = Vector2(14, 10)
	weapon_icon.size = Vector2(150, 48)
	wpanel.add_child(weapon_icon)
	weapon_name = UIKit.label("LANCET", 15, UIKit.DIM, "display_semi")
	weapon_name.position = Vector2(16, 62)
	wpanel.add_child(weapon_name)
	ammo_label = UIKit.shadowed(UIKit.label("25", 50, UIKit.TEXT, "display", HORIZONTAL_ALIGNMENT_RIGHT))
	ammo_label.position = Vector2(180, 0)
	ammo_label.size = Vector2(90, 62)
	wpanel.add_child(ammo_label)
	reserve_label = UIKit.label("/ 75", 22, UIKit.DIM, "display_semi")
	reserve_label.position = Vector2(276, 20)
	wpanel.add_child(reserve_label)
	slots_label = RichTextLabel.new()
	slots_label.bbcode_enabled = true
	slots_label.fit_content = true
	slots_label.scroll_active = false
	slots_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slots_label.add_theme_font_override("normal_font", UIKit.font("body_bold"))
	slots_label.add_theme_font_size_override("normal_font_size", 13)
	slots_label.position = Vector2(16, 84)
	slots_label.size = Vector2(320, 22)
	wpanel.add_child(slots_label)
	carry_chip = UIKit.panel(Color(0.3, 0.2, 0.05, 0.85), 2)
	var chip_l := UIKit.label("PHASE CHARGE", 13, UIKit.AMBER, "display_semi")
	carry_chip.add_child(chip_l)
	_anchor(carry_chip, Control.PRESET_BOTTOM_RIGHT, Vector2(-372, -166), Vector2(140, 28))

	# --- Centre prompts
	prompt_label = UIKit.shadowed(UIKit.label("", 20, UIKit.TEXT, "body_bold", HORIZONTAL_ALIGNMENT_CENTER))
	_anchor(prompt_label, Control.PRESET_CENTER, Vector2(-300, 70), Vector2(600, 28))
	progress = Control.new()
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress.draw.connect(_draw_progress)
	_anchor(progress, Control.PRESET_CENTER, Vector2(-160, 104), Vector2(320, 40))

	# --- Banners
	banner = VBoxContainer.new()
	banner.alignment = BoxContainer.ALIGNMENT_CENTER
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(banner, Control.PRESET_CENTER_TOP, Vector2(-450, 150), Vector2(900, 100))
	banner_title = UIKit.shadowed(UIKit.label("", 46, UIKit.TEXT, "display", HORIZONTAL_ALIGNMENT_CENTER), 0.7)
	banner_sub = UIKit.shadowed(UIKit.label("", 21, UIKit.TEXT, "body_bold", HORIZONTAL_ALIGNMENT_CENTER), 0.7)
	banner.add_child(banner_title)
	banner.add_child(banner_sub)
	banner.modulate.a = 0.0
	result = VBoxContainer.new()
	result.alignment = BoxContainer.ALIGNMENT_CENTER
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(result, Control.PRESET_CENTER, Vector2(-500, -170), Vector2(1000, 140))
	result_title = UIKit.shadowed(UIKit.label("", 74, UIKit.TEXT, "display", HORIZONTAL_ALIGNMENT_CENTER), 0.8)
	result_sub = UIKit.shadowed(UIKit.label("", 22, UIKit.TEXT, "body_bold", HORIZONTAL_ALIGNMENT_CENTER), 0.8)
	result.add_child(result_title)
	result.add_child(result_sub)
	result.modulate.a = 0.0

	# --- Death / spectate
	death_label = UIKit.shadowed(UIKit.label("", 26, UIKit.ENEMY, "display", HORIZONTAL_ALIGNMENT_CENTER), 0.8)
	_anchor(death_label, Control.PRESET_CENTER_BOTTOM, Vector2(-400, -230), Vector2(800, 36))
	spectate_label = UIKit.shadowed(UIKit.label("", 18, UIKit.TEXT, "body_bold", HORIZONTAL_ALIGNMENT_CENTER), 0.8)
	_anchor(spectate_label, Control.PRESET_CENTER_BOTTOM, Vector2(-400, -196), Vector2(800, 28))


# ================================================================== events
func _on_kill(info: Dictionary) -> void:
	var killer: Combatant = info.killer
	var victim: Combatant = info.victim
	var viewer := MatchManager.viewer_team()
	var involved := (killer != null and killer.is_player) or victim.is_player
	var entry := PanelContainer.new()
	var style := UIKit.box(Color(0.03, 0.045, 0.055, 0.82), 2, UIKit.AMBER if involved else Color(0, 0, 0, 0), 1 if involved else 0)
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	entry.add_theme_stylebox_override("panel", style)
	entry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry.size_flags_horizontal = Control.SIZE_SHRINK_END
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	entry.add_child(row)
	if killer:
		row.add_child(UIKit.label(killer.unit_name.to_upper(), 17, UIKit.ALLY if killer.team == viewer else UIKit.ENEMY, "display_semi"))
	var wlabel := UIKit.label(String(info.weapon).to_upper(), 13, UIKit.DIM, "body_bold")
	row.add_child(wlabel)
	if info.headshot:
		var hs := UIKit.panel(Color(1.0, 0.71, 0.28, 0.9), 2)
		var hl := UIKit.label("HEAD", 11, Color(0.1, 0.07, 0.02), "display")
		hs.add_child(hl)
		row.add_child(hs)
	row.add_child(UIKit.label(victim.unit_name.to_upper(), 17, UIKit.ALLY if victim.team == viewer else UIKit.ENEMY, "display_semi"))
	killfeed.add_child(entry)
	while killfeed.get_child_count() > 6:
		var old := killfeed.get_child(0)
		killfeed.remove_child(old)
		old.queue_free()
	var tw := entry.create_tween()
	entry.modulate.a = 0.0
	tw.tween_property(entry, "modulate:a", 1.0, 0.15)
	tw.tween_interval(6.0)
	tw.tween_property(entry, "modulate:a", 0.0, 0.5)
	tw.tween_callback(entry.queue_free)
	if victim.is_player:
		death_label.text = "ELIMINATED BY %s" % (killer.unit_name.to_upper() if killer else "THE BLAST")
	elif killer and killer.is_player:
		_on_announcement("", "ELIMINATED  %s" % victim.unit_name.to_upper(), UIKit.ENEMY)


func _on_announcement(title: String, sub: String, color: Color) -> void:
	banner_title.text = title
	banner_title.add_theme_color_override("font_color", color)
	banner_sub.text = sub
	banner_title.visible = title != ""
	if _banner_tween:
		_banner_tween.kill()
	_banner_tween = create_tween()
	banner.offset_top = 140
	banner.offset_bottom = 240
	_banner_tween.set_parallel(true)
	_banner_tween.tween_property(banner, "modulate:a", 1.0, 0.2)
	_banner_tween.tween_property(banner, "offset_top", 150.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_property(banner, "offset_bottom", 250.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_banner_tween.chain().tween_interval(2.4 if title != "" else 1.4)
	_banner_tween.chain().tween_property(banner, "modulate:a", 0.0, 0.4)


func _on_round_ended(winner: int, reason: String) -> void:
	var won := winner == MatchManager.viewer_team()
	result_title.text = "ROUND WON" if won else "ROUND LOST"
	result_title.add_theme_color_override("font_color", UIKit.ALLY if won else UIKit.ENEMY)
	result_sub.text = reason.to_upper()
	if _result_tween:
		_result_tween.kill()
	result.scale = Vector2(1.08, 1.08)
	result.pivot_offset = result.size * 0.5
	_result_tween = create_tween()
	_result_tween.set_parallel(true)
	_result_tween.tween_property(result, "modulate:a", 1.0, 0.25)
	_result_tween.tween_property(result, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_result_tween.chain().tween_interval(3.4)
	_result_tween.chain().tween_property(result, "modulate:a", 0.0, 0.5)


func _on_round_started(_n: int) -> void:
	death_label.text = ""
	spectate_label.text = ""
	_hurt = 0.0


func _on_player_damaged(info: Dictionary) -> void:
	_hurt = minf(1.0, _hurt + 0.45)
	var attacker = info.get("attacker")
	if attacker is Combatant and player:
		var to: Vector3 = attacker.global_position - player.global_position
		var local := Basis(Vector3.UP, player.yaw).inverse() * to
		crosshair.damage_from(atan2(local.x, -local.z))


# ================================================================== per frame
func _process(delta: float) -> void:
	if mm == null:
		return
	var viewer := MatchManager.viewer_team()
	score_ally.text = str(mm.scores[viewer])
	score_enemy.text = str(mm.scores[1 - viewer])
	side_ally.text = "ATTACK" if mm.attack_team == viewer else "DEFENSE"
	side_enemy.text = "DEFENSE" if mm.attack_team == viewer else "ATTACK"
	var t := mm.time_display()
	var planted := mm.phase == "planted"
	if planted:
		_timer_pulse += delta * (2.0 + (1.0 - t / GameConst.DEVICE_TIME) * 8.0)
		timer_label.text = "%d" % ceili(t)
		timer_label.add_theme_color_override("font_color", UIKit.AMBER.lerp(Color(1, 0.3, 0.2), 0.5 + 0.5 * sin(_timer_pulse)))
	else:
		timer_label.text = "%d:%02d" % [int(t) / 60, int(t) % 60]
		timer_label.add_theme_color_override("font_color", UIKit.ENEMY if (mm.phase == "live" and t < 10.0) else UIKit.TEXT)
	match mm.phase:
		"prep": round_label.text = "ROUND %d  ·  PREPARE" % mm.round_number
		"planted": round_label.text = "PHASE CHARGE  ·  SITE %s" % mm.device.site
		"round_end": round_label.text = "ROUND %d  ·  COMPLETE" % mm.round_number
		_: round_label.text = "ROUND %d  ·  FIRST TO %d" % [mm.round_number, mm.rounds_to_win]
	roster.queue_redraw()
	if Settings.show_fps:
		fps_label.text = "%d FPS" % Engine.get_frames_per_second()
	else:
		fps_label.text = ""
	if player == null:
		return
	var alive := player.is_alive()
	var cam_pos := player.camera.global_position
	area_label.text = level.area_name_at(player.global_position if alive else cam_pos).to_upper()
	hp_label.text = str(ceili(player.health.health))
	hp_label.add_theme_color_override("font_color", UIKit.ENEMY if player.health.health < 35 else UIKit.TEXT)
	armor_label.text = str(ceili(player.health.armor))
	vitals.queue_redraw()
	var w = player.weapons.state()
	var d: WeaponData = w.data
	weapon_name.text = d.display_name.to_upper() + "  ·  " + d.category.to_upper()
	ammo_label.text = str(w.mag)
	ammo_label.add_theme_color_override("font_color", UIKit.ENEMY if w.mag <= d.mag_size / 5 else UIKit.TEXT)
	reserve_label.text = "/ %d" % w.reserve
	var parts := []
	for i in player.weapons.weapons.size():
		var wd: WeaponData = player.weapons.weapons[i].data
		var col := "#eef3f5" if i == player.weapons.current else "#6f7b82"
		parts.append("[color=%s]%d  %s[/color]" % [col, i + 1, wd.display_name.to_upper()])
	slots_label.text = "    ".join(parts)
	carry_chip.visible = alive and player.carrying_device
	crosshair.spread = player.weapons.spread
	crosshair.color = Settings.crosshair_color
	crosshair.hidden_by_ads = player.weapons.ads > 0.6
	crosshair.visible = alive
	# Objective progress
	_progress_kind = ""
	if mm.device and mm.device.planter == player:
		_progress_kind = "PLANTING"
		_progress_frac = mm.device.plant_fraction()
	elif mm.device and mm.device.defuser == player:
		_progress_kind = "DEFUSING"
		_progress_frac = mm.device.defuse_fraction()
	if player.weapons.reloading:
		prompt_label.text = "RELOADING"
	else:
		prompt_label.text = mm.interact_prompt if _progress_kind == "" else ""
	progress.queue_redraw()
	# Overlays
	var dens := SmokeField.density_at(cam_pos)
	smoke_overlay.color.a = dens * 0.93
	_hurt = maxf(0.0, _hurt - delta * 1.4)
	var low := clampf((40.0 - player.health.health) / 40.0, 0.0, 1.0) if alive else 0.0
	vignette.modulate.a = clampf(_hurt * 0.8 + low * (0.45 + 0.15 * sin(Time.get_ticks_msec() * 0.006)), 0.0, 1.0)
	if not alive:
		var tgt := player.spectate_target
		spectate_label.text = ("SPECTATING  %s   ·   CLICK TO SWITCH" % tgt.unit_name.to_upper()) if tgt and tgt.is_alive() else ""
	else:
		death_label.text = ""
		spectate_label.text = ""


func _draw_roster() -> void:
	if mm == null:
		return
	var viewer := MatchManager.viewer_team()
	var f := UIKit.font("display")
	for t in 2:
		var team_units := mm.team_units(viewer if t == 0 else 1 - viewer)
		var col := UIKit.ALLY if t == 0 else UIKit.ENEMY
		for i in team_units.size():
			var u: Combatant = team_units[i]
			var x := (8.0 + i * 32.0) if t == 0 else (560.0 - 8.0 - 26.0 - i * 32.0)
			var r := Rect2(x, 2, 26, 22)
			var alive := u.is_alive()
			roster.draw_rect(r, Color(col.r, col.g, col.b, 0.85 if alive else 0.12))
			if not alive:
				roster.draw_rect(r, Color(col.r, col.g, col.b, 0.4), false, 1.0)
			var letter := u.unit_name.substr(0, 1).to_upper() if not u.is_player else "•"
			roster.draw_string(f, Vector2(x, 19), letter, HORIZONTAL_ALIGNMENT_CENTER, 26, 15, Color(0.03, 0.05, 0.06) if alive else Color(1, 1, 1, 0.35))
			if u.carrying_device and t == 0:
				roster.draw_rect(Rect2(x + 4, 26, 18, 3), UIKit.AMBER)


func _draw_vitals() -> void:
	if player == null:
		return
	var bg := UIKit.box(Color(0.03, 0.045, 0.055, 0.72), 3, UIKit.LINE, 1)
	vitals.draw_style_box(bg, Rect2(Vector2.ZERO, vitals.size))
	var hp := player.health.health / player.health.max_health
	var armor := player.health.armor / player.health.max_armor
	var bar := Rect2(14, 70, 300, 8)
	vitals.draw_rect(bar, Color(1, 1, 1, 0.1))
	var hp_col := UIKit.TEXT if hp > 0.35 else UIKit.ENEMY
	vitals.draw_rect(Rect2(bar.position, Vector2(bar.size.x * hp, bar.size.y)), hp_col)
	for i in range(1, 10):
		vitals.draw_rect(Rect2(bar.position.x + bar.size.x * i / 10.0 - 1, bar.position.y, 2, bar.size.y), Color(0.03, 0.045, 0.055, 0.9))
	var abar := Rect2(150, 54, 164, 6)
	vitals.draw_rect(abar, Color(1, 1, 1, 0.08))
	vitals.draw_rect(Rect2(abar.position, Vector2(abar.size.x * armor, abar.size.y)), Color(0.55, 0.85, 1.0))
	var f := UIKit.font("body_bold")
	vitals.draw_string(f, Vector2(200, 46), "SHIELD", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIKit.DIM)
	var sh := Vector2(136, 34)
	var shield := PackedVector2Array([sh + Vector2(0, -10), sh + Vector2(8, -6), sh + Vector2(7, 4), sh + Vector2(0, 10), sh + Vector2(-7, 4), sh + Vector2(-8, -6)])
	vitals.draw_colored_polygon(shield, Color(0.55, 0.85, 1.0, 0.9))


func _draw_progress() -> void:
	if _progress_kind == "":
		return
	var f := UIKit.font("display_semi")
	progress.draw_string(f, Vector2(0, 14), _progress_kind, HORIZONTAL_ALIGNMENT_CENTER, progress.size.x, 15, UIKit.AMBER)
	var r := Rect2(0, 22, progress.size.x, 8)
	progress.draw_rect(r, Color(0, 0, 0, 0.6))
	progress.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(_progress_frac, 0, 1), r.size.y)), UIKit.AMBER)
	if _progress_kind == "DEFUSING":
		progress.draw_rect(Rect2(r.position.x + r.size.x * 0.5 - 1, r.position.y - 3, 2, r.size.y + 6), Color(1, 1, 1, 0.8))
