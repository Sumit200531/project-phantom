class_name Ballistics
## Hitscan resolution shared by the player and bots: ray query against world, hitboxes and the
## opposing team's energy barriers, then damage, impact effects and decals.


static func fire(shooter: Combatant, origin: Vector3, dir: Vector3, w: WeaponData, tracer_from := Vector3.INF, show_tracer := true) -> Dictionary:
	var result := {"hit": false, "unit": null, "part": "", "killed": false, "position": origin + dir * w.max_range, "damage": 0.0}
	var space := shooter.get_world_3d().direct_space_state
	var to := origin + dir * w.max_range
	var q := PhysicsRayQueryParameters3D.create(origin, to, GameConst.bullet_mask(shooter.team))
	q.collide_with_areas = true
	q.collide_with_bodies = true
	var exclude: Array[RID] = [shooter.get_rid()]
	exclude.append_array(MatchManager.team_hitbox_rids(shooter.team))
	q.exclude = exclude
	var hit := space.intersect_ray(q)
	var end := to
	if not hit.is_empty():
		end = hit.position
		result.position = end
		var col: Object = hit.collider
		var normal: Vector3 = hit.normal
		if col is Hitbox:
			var hb := col as Hitbox
			var target: Combatant = hb.unit
			if target and target.is_alive():
				var dist := origin.distance_to(end)
				var dmg := w.damage_for(hb.part, dist)
				var was_alive := target.is_alive()
				target.receive_damage({"amount": dmg, "attacker": shooter, "part": hb.part, "weapon": w.display_name,
					"position": end, "direction": dir, "headshot": hb.part == "head"})
				result.hit = true
				result.unit = target
				result.part = hb.part
				result.damage = dmg
				result.killed = was_alive and not target.is_alive()
				shooter.shots_hit += 1
				Fx.impact(end, -dir, "flesh", true)
				Sfx.play_at("impact_flesh", end, -6.0, 30.0)
		elif col is EnergyBarrier:
			(col as EnergyBarrier).take_hit(w.damage, end)
			Fx.impact(end, normal, "metal", true)
		else:
			var surf := "concrete"
			if col and col.has_meta("surface"):
				surf = col.get_meta("surface")
			Fx.impact(end, normal, surf, false)
			Fx.bullet_hole(end, normal)
			if randf() < 0.45:
				Sfx.play_at("impact_metal" if surf == "metal" else "impact_concrete", end, -10.0, 26.0, 0.15, 3.0)
	if show_tracer:
		var start := tracer_from if tracer_from != Vector3.INF else origin
		Fx.tracer(start, end, not shooter.is_player and shooter.team != MatchManager.viewer_team())
	return result


## Line-of-sight test used by perception: world geometry (and optionally obscuring fields).
static func has_los(from: Vector3, to: Vector3, world: World3D, through_smoke := false) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, GameConst.LAYER_WORLD)
	q.collide_with_areas = false
	var hit := world.direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		return false
	if not through_smoke and SmokeField.blocks_segment(from, to):
		return false
	return true
