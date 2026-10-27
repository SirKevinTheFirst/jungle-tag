class_name GameMode
extends Node
## Round flow and rules for every mode (Classic, Infection, Hide and Seek, Maze Run,
## Freeze, Elimination, Bomb, Hunt, Paintbrawl, Casual).
## The host runs the rules; every peer mirrors phase, timer and roles for the HUD.

signal round_message(text: String, sub: String)
signal tag_feed(text: String)

const TAG_RADIUS := 1.75
const SWIPE_BONUS := 0.7
const WARMUP_TIME := 5.0
const HIDE_TIME := 25.0
const END_TIME := 9.0
const CLASSIC_STUN := 2.0
const TAG_IMMUNITY := 3.0
const BOMB_FUSE := 25.0
const PAINT_LIVES := 3

var world: Node
var mode := Game.MODE_CLASSIC
var round_time := 180.0

# mirrored on all peers
var phase := "warmup"     # warmup, hide, play, end
var time_left := 0.0
var roles := {}           # id -> role
var stats := {}           # id -> {"tags": int, "it_time": float, "survived": float}
var last_result := ""
var extra := {}           # per-mode state: "targets" (hunt), "lives" (paintbrawl), "fuse" (bomb)

# host only
var _immune := {}         # id -> seconds of tag immunity left
var _no_tagback := {}     # tagger id -> the gorilla who tagged them (can't be tagged straight back)
var _swipe := {}          # id -> seconds of extended reach left
var _sync_timer := 0.0
var _infect_order: Array = []


func setup(p_world: Node) -> void:
	world = p_world
	mode = int(Game.config.mode)
	round_time = float(Game.config.round_time)


func is_host() -> bool:
	return Net.is_host()


func start_round() -> void:
	if not is_host():
		return
	var ids: Array = world.gorillas.keys()
	ids.shuffle()
	roles.clear()
	stats.clear()
	_immune.clear()
	_no_tagback.clear()
	_infect_order.clear()
	for id in ids:
		stats[id] = {"tags": 0, "it_time": 0.0, "survived": 0.0, "escapes": 0}
	var base_role := "runner"
	var special := "it"
	var special_count := 1
	match mode:
		Game.MODE_INFECTION:
			special = "infected"
			special_count = 2 if ids.size() >= 10 else 1
		Game.MODE_HIDE_SEEK:
			base_role = "hider"
			special = "seeker"
			special_count = maxi(1, ids.size() / 6)
		Game.MODE_FREEZE:
			special_count = maxi(1, ids.size() / 5)
	var chosen := int(Game.config.get("taggers", 0))
	if chosen > 0:
		special_count = chosen
	special_count = clampi(special_count, 1, maxi(1, ids.size() - 1))
	if mode in [Game.MODE_MAZE, Game.MODE_HUNT, Game.MODE_PAINT, Game.MODE_CASUAL]:
		special_count = 0   # no IT (in maze run the Shadow is the only tagger)
	if mode == Game.MODE_BOMB:
		special_count = 1
	for i in ids.size():
		roles[ids[i]] = special if i < special_count else base_role
	extra = {}
	match mode:
		Game.MODE_HUNT:
			# a circle: everyone hunts the next gorilla and is hunted by the one before
			var targets := {}
			for i in ids.size():
				roles[ids[i]] = "hunter"
				targets[ids[i]] = ids[(i + 1) % ids.size()]
			extra.targets = targets
		Game.MODE_PAINT:
			var lives := {}
			for i in ids.size():
				roles[ids[i]] = "red" if i % 2 == 0 else "blue"
				lives[ids[i]] = PAINT_LIVES
			extra.lives = lives
		Game.MODE_BOMB:
			extra.fuse = BOMB_FUSE
	for i in special_count:
		if i < ids.size():
			_infect_order.append(ids[i])
	phase = "warmup"
	time_left = WARMUP_TIME
	# everyone back to a spawn point
	var spawns: Array = world.jungle.spawn_points.duplicate()
	if mode == Game.MODE_MAZE:
		spawns = world.maze_spawns()
	spawns.shuffle()
	var i := 0
	var spawn_map := {}
	for id in world.gorillas:
		spawn_map[id] = spawns[i % spawns.size()]
		i += 1
	if mode == Game.MODE_PAINT:
		# each team starts on its own side of the jungle
		var by_x := spawns.duplicate()
		by_x.sort_custom(func(p, q): return p.x < q.x)
		var n := {"red": 0, "blue": 0}
		for id in world.gorillas:
			var team: String = roles.get(id, "red")
			var k: int = n[team] % by_x.size()
			spawn_map[id] = by_x[k] if team == "red" else by_x[by_x.size() - 1 - k]
			n[team] += 1
	Net.broadcast_event("respawn_all", {"spawns": spawn_map})
	if mode == Game.MODE_MAZE:
		world.start_maze_round()
	_broadcast_state()


## A random spawn point on a Paintbrawl team's side (red west, blue east).
func _team_spawn(team: String) -> Vector3:
	var by_x: Array = world.jungle.spawn_points.duplicate()
	by_x.sort_custom(func(p, q): return p.x < q.x)
	var k := randi() % maxi(1, by_x.size() / 3)
	return by_x[k] if team == "red" else by_x[by_x.size() - 1 - k]


func _broadcast_state() -> void:
	Net.broadcast_event("round_state", {"phase": phase, "time": time_left, "roles": roles, "mode": mode, "extra": extra})


## Applied on every peer.
func apply_state(d: Dictionary) -> void:
	var old_phase := phase
	phase = d.phase
	time_left = d.time
	mode = d.mode
	roles = d.roles
	extra = d.get("extra", {})
	_apply_roles()
	if old_phase != phase:
		_announce_phase()


## Every peer: show roles on the gorillas and freeze whoever must stand still.
func _apply_roles() -> void:
	for id in roles:
		var g: Gorilla = world.gorillas.get(id)
		if g:
			g.set_role(roles[id])
			g.frozen = phase == "warmup" or (phase == "hide" and roles[id] == "seeker") or roles[id] == "frozen"


## Can gorilla a tag gorilla b right now under this mode's rules?
func can_tag(a: int, b: int) -> bool:
	if a == b:
		return false
	var ra: String = roles.get(a, "")
	var rb: String = roles.get(b, "")
	match mode:
		Game.MODE_MAZE, Game.MODE_CASUAL:
			return false
		Game.MODE_INFECTION:
			return ra == "infected" and rb == "runner"
		Game.MODE_HIDE_SEEK:
			return ra == "seeker" and rb == "hider"
		Game.MODE_HUNT:
			return ra == "hunter" and rb == "hunter" and int(extra.get("targets", {}).get(a, -1)) == b
		Game.MODE_PAINT:
			return ra in ["red", "blue"] and rb in ["red", "blue"] and ra != rb
	return ra == "it" and rb == "runner"


## The gorilla this one has to hunt (Hunt mode), or -1.
func hunt_target(id: int) -> int:
	return int(extra.get("targets", {}).get(id, -1))


func lives(id: int) -> int:
	return int(extra.get("lives", {}).get(id, 0))


func _announce_phase() -> void:
	var me: int = Net.my_id()
	var my_role: String = roles.get(me, "runner")
	match phase:
		"warmup":
			round_message.emit(Game.mode_name(mode), _role_hint(my_role))
			Sfx.play("beep")
		"hide":
			if my_role == "seeker":
				round_message.emit("You are a SEEKER", "Wait while the gorillas hide...")
			else:
				round_message.emit("HIDE!", "Climb, camouflage, find a hiding spot")
			Sfx.play("round_start")
		"play":
			if mode == Game.MODE_HIDE_SEEK:
				round_message.emit("Ready or not!", "Seekers are coming")
			else:
				round_message.emit("GO!", _role_hint(my_role))
			Sfx.play("round_start")
		"end":
			round_message.emit("Round over", last_result)
			Sfx.play("round_end")


func _role_hint(r: String) -> String:
	match r:
		"it":
			return "You are IT. Tag someone!"
		"infected":
			return "You are INFECTED. Spread it!"
		"seeker":
			return "You are a SEEKER. Find them all!"
		"hider":
			return "Hide from the seekers!"
		"frozen":
			return "You're FROZEN! Wait for a friend to touch you"
		"out":
			return "You're out. Watch until the next round"
		"hunter":
			return "Hunt your target - and watch your back!"
		"red", "blue":
			return "You're on the %s team. Tag the other team!" % r.to_upper()
	match mode:
		Game.MODE_FREEZE:
			return "Don't get frozen - unfreeze your friends!"
		Game.MODE_BOMB:
			return "Stay away from the bomb!"
		Game.MODE_CASUAL:
			return "No tagging - just have fun!"
	if mode == Game.MODE_MAZE:
		return "Find the green EXIT as many times as you can - dodge the Shadow!"
	return "Don't get tagged!"


func _physics_process(delta: float) -> void:
	if world == null:
		return
	time_left = maxf(0.0, time_left - delta)
	if mode == Game.MODE_BOMB and phase == "play" and extra.has("fuse"):
		extra.fuse = maxf(0.0, float(extra.fuse) - delta)
	if not is_host():
		return
	for id in _immune.keys():
		_immune[id] -= delta
		if _immune[id] <= 0.0:
			_immune.erase(id)
	for id in _swipe.keys():
		_swipe[id] -= delta
		if _swipe[id] <= 0.0:
			_swipe.erase(id)
	_sync_timer -= delta
	if _sync_timer <= 0.0:
		_sync_timer = 1.0
		Net.broadcast_event("timer", {"time": time_left, "stats": stats, "extra": extra})
	match phase:
		"warmup":
			if time_left <= 0.0:
				if mode == Game.MODE_HIDE_SEEK:
					phase = "hide"
					time_left = HIDE_TIME
				else:
					phase = "play"
					time_left = round_time
				_broadcast_state()
		"hide":
			if time_left <= 0.0:
				phase = "play"
				time_left = round_time
				_broadcast_state()
		"play":
			_accumulate_stats(delta)
			_check_tags()
			if mode == Game.MODE_FREEZE:
				_check_unfreeze()
			if mode == Game.MODE_BOMB and float(extra.get("fuse", 1.0)) <= 0.0:
				_explode()
			_check_end()
		"end":
			if time_left <= 0.0:
				start_round()


func _accumulate_stats(delta: float) -> void:
	for id in roles:
		if not stats.has(id):
			stats[id] = {"tags": 0, "it_time": 0.0, "survived": 0.0, "escapes": 0}
		if roles[id] in ["it", "infected", "seeker"]:
			stats[id].it_time += delta
		elif roles[id] != "out":
			stats[id].survived += delta


func _check_tags() -> void:
	for t_id in world.gorillas:
		var tg: Gorilla = world.gorillas[t_id]
		if tg.stun_time > 0.0 or tg.frozen:
			continue
		var victims := []
		for v_id in world.gorillas:
			if can_tag(t_id, v_id):
				victims.append(v_id)
		var reach := TAG_RADIUS + (SWIPE_BONUS if _swipe.has(t_id) else 0.0)
		var tp := tg.global_position + Vector3(0, 0.8, 0)
		for v_id in victims:
			if _immune.has(v_id):
				continue
			# no tag-backs: you have to get someone other than the gorilla who got you
			if _no_tagback.get(t_id, -1) == v_id and victims.size() > 1:
				continue
			var vg: Gorilla = world.gorillas[v_id]
			if (vg.global_position + Vector3(0, 0.8, 0)).distance_to(tp) < reach:
				_do_tag(t_id, v_id)
				return


## Freeze Tag: a free gorilla touching a frozen one thaws them out.
func _check_unfreeze() -> void:
	for f_id in roles:
		if roles[f_id] != "frozen" or not world.gorillas.has(f_id):
			continue
		var fp: Vector3 = world.gorillas[f_id].global_position
		for r_id in roles:
			if roles[r_id] == "runner" and world.gorillas.has(r_id) and world.gorillas[r_id].global_position.distance_to(fp) < TAG_RADIUS:
				roles[f_id] = "runner"
				_immune[f_id] = 2.0
				Net.broadcast_event("unfreeze", {"id": f_id, "by": r_id, "roles": roles})
				return


## Bomb Tag: the fuse ran out, whoever holds the bomb is out and someone new gets one.
func _explode() -> void:
	var boom := []
	for id in roles:
		if roles[id] == "it":
			roles[id] = "out"
			boom.append(id)
	var alive := []
	for id in roles:
		if roles[id] == "runner":
			alive.append(id)
	if alive.size() >= 2:
		roles[alive[randi() % alive.size()]] = "it"
	_no_tagback.clear()
	extra.fuse = BOMB_FUSE
	Net.broadcast_event("boom", {"ids": boom, "roles": roles, "extra": extra})


func _do_tag(tagger: int, target: int) -> void:
	stats[tagger].tags += 1
	var stun := 0.0
	match mode:
		Game.MODE_CLASSIC:
			roles[tagger] = "runner"
			roles[target] = "it"
			_no_tagback.erase(tagger)
			_no_tagback[target] = tagger
			_immune[tagger] = TAG_IMMUNITY
			stun = CLASSIC_STUN
		Game.MODE_INFECTION:
			roles[target] = "infected"
			_infect_order.append(target)
			stun = 0.8
		Game.MODE_HIDE_SEEK:
			roles[target] = "seeker"
			stun = 1.5
		Game.MODE_FREEZE:
			roles[target] = "frozen"
		Game.MODE_ELIMINATION:
			roles[target] = "out"
		Game.MODE_BOMB:
			roles[tagger] = "runner"
			roles[target] = "it"
			_no_tagback.erase(tagger)
			_no_tagback[target] = tagger
			_immune[tagger] = 1.5
			stun = 0.6
		Game.MODE_HUNT:
			# take over your victim's target
			var targets: Dictionary = extra.targets
			roles[target] = "out"
			targets[tagger] = targets.get(target, tagger)
			targets.erase(target)
		Game.MODE_PAINT:
			var lv: Dictionary = extra.lives
			lv[target] = int(lv.get(target, 1)) - 1
			_immune[target] = TAG_IMMUNITY
			stun = 1.0
			if lv[target] <= 0:
				roles[target] = "out"
			else:
				# splatted: back to your own side after a moment
				var team: String = roles[target]
				get_tree().create_timer(stun).timeout.connect(func():
					if roles.get(target, "") == team and phase == "play":
						Net.broadcast_event("respawn_all", {"spawns": {target: _team_spawn(team)}}))
	Net.broadcast_event("tag", {"tagger": tagger, "target": target, "roles": roles, "stun": stun, "mode": mode, "extra": extra})


## Applied on every peer when a tag happens.
func apply_tag(d: Dictionary) -> void:
	roles = d.roles
	extra = d.get("extra", extra)
	var tagger: Gorilla = world.gorillas.get(d.tagger)
	var target: Gorilla = world.gorillas.get(d.target)
	_apply_roles()
	if target:
		target.stun_time = d.stun
		target.flash()
		var snd: String = "infect" if d.mode == Game.MODE_INFECTION else "tag"
		Sfx.play_at(snd, target.global_position + Vector3(0, 1, 0), 2.0)
		if target.control == Gorilla.Ctrl.LOCAL:
			Sfx.play(snd, -2.0)
	if tagger:
		tagger.tags += 1
	var tn: String = tagger.display_name if tagger else "?"
	var vn: String = target.display_name if target else "?"
	var verb: String = {Game.MODE_INFECTION: "infected", Game.MODE_HIDE_SEEK: "found", Game.MODE_FREEZE: "froze",
		Game.MODE_ELIMINATION: "eliminated", Game.MODE_BOMB: "passed the bomb to", Game.MODE_HUNT: "hunted down",
		Game.MODE_PAINT: "splatted"}.get(int(d.mode), "tagged")
	tag_feed.emit("%s %s %s" % [tn, verb, vn])
	var me: int = Net.my_id()
	if d.target == me:
		match int(d.mode):
			Game.MODE_CLASSIC:
				round_message.emit("You're IT!", "Tag someone else - no tag-backs!")
			Game.MODE_INFECTION:
				round_message.emit("INFECTED!", "Spread the infection")
			Game.MODE_HIDE_SEEK:
				round_message.emit("FOUND!", "Now help seek the others")
			Game.MODE_FREEZE:
				round_message.emit("FROZEN!", "Wait for a friend to touch you")
			Game.MODE_ELIMINATION, Game.MODE_HUNT:
				round_message.emit("YOU'RE OUT!", "Watch until the next round")
			Game.MODE_BOMB:
				round_message.emit("YOU'VE GOT THE BOMB!", "Tag someone before it blows up!")
			Game.MODE_PAINT:
				var left := lives(me)
				round_message.emit("SPLAT!", "%d live%s left" % [left, "" if left == 1 else "s"] if left > 0 else "You're out of lives")
	elif d.tagger == me and int(d.mode) == Game.MODE_HUNT:
		var t: Gorilla = world.gorillas.get(hunt_target(me))
		round_message.emit("Got them!", "New target: %s" % (t.display_name if t else "?"))


## Every peer: someone in Freeze Tag got thawed.
func apply_unfreeze(d: Dictionary) -> void:
	roles = d.roles
	_apply_roles()
	var g: Gorilla = world.gorillas.get(d.id)
	var by: Gorilla = world.gorillas.get(d.by)
	if g and by:
		tag_feed.emit("%s unfroze %s" % [by.display_name, g.display_name])
		Sfx.play_at("beep", g.global_position, 0.0)
	if d.id == Net.my_id():
		round_message.emit("UNFROZEN!", "Go go go!")


## Every peer: the bomb went off.
func apply_boom(d: Dictionary) -> void:
	roles = d.roles
	extra = d.extra
	_apply_roles()
	var names := []
	for id in d.ids:
		var g: Gorilla = world.gorillas.get(id)
		if g:
			names.append(g.display_name)
			g.flash()
			Sfx.play_at("thunder", g.global_position, 4.0)
	tag_feed.emit("BOOM! %s blew up" % ", ".join(names))
	var me: int = Net.my_id()
	if d.ids.has(me):
		round_message.emit("BOOM!", "You blew up - you're out")
	elif roles.get(me, "") == "it":
		round_message.emit("YOU'VE GOT THE BOMB!", "Tag someone before it blows up!")


func _check_end() -> void:
	var result := ""
	var winners: Array = []
	match mode:
		Game.MODE_CLASSIC:
			if time_left <= 0.0:
				# least time spent as IT wins
				var best := INF
				for id in stats:
					if stats[id].it_time < best:
						best = stats[id].it_time
				for id in stats:
					if absf(stats[id].it_time - best) < 0.01:
						winners.append(id)
				result = "%s spent the least time as IT" % _names(winners)
		Game.MODE_INFECTION:
			var survivors := []
			for id in roles:
				if roles[id] != "infected":
					survivors.append(id)
			if survivors.size() == 0:
				var last: int = _infect_order[-1] if _infect_order.size() > 0 else -1
				winners = [last] if last != -1 else []
				result = "Everyone is infected! %s was the last survivor" % _names(winners)
			elif survivors.size() == 1 and roles.size() > 1 and time_left > 0.0:
				pass  # keep playing until the last one is caught or time runs out
			if survivors.size() > 0 and time_left <= 0.0:
				winners = survivors
				result = "Survivors win: %s" % _names(winners)
		Game.MODE_HIDE_SEEK:
			var hiders := []
			for id in roles:
				if roles[id] == "hider":
					hiders.append(id)
			if hiders.is_empty():
				for id in roles:
					winners.append(id)
				result = "All gorillas were found. Seekers win!"
			elif time_left <= 0.0:
				winners = hiders
				result = "Hiders win: %s" % _names(winners)
		Game.MODE_MAZE:
			if time_left <= 0.0:
				var best := -1
				for id in stats:
					best = maxi(best, int(stats[id].get("escapes", 0)))
				for id in stats:
					if int(stats[id].get("escapes", 0)) == best:
						winners.append(id)
				result = "%s escaped the most (%d time%s)" % [_names(winners), best, "" if best == 1 else "s"]
		Game.MODE_FREEZE:
			var free := []
			for id in roles:
				if roles[id] == "runner":
					free.append(id)
			if free.is_empty():
				for id in roles:
					if roles[id] == "it":
						winners.append(id)
				result = "Everyone is frozen! %s win%s" % [_names(winners), "s" if winners.size() == 1 else ""]
			elif time_left <= 0.0:
				winners = free
				result = "Still free: %s" % _names(winners)
		Game.MODE_ELIMINATION, Game.MODE_BOMB, Game.MODE_HUNT:
			var alive := []
			for id in roles:
				if roles[id] != "out" and (mode != Game.MODE_ELIMINATION or roles[id] == "runner"):
					alive.append(id)
			if mode == Game.MODE_ELIMINATION and alive.is_empty():
				for id in roles:
					if roles[id] == "it":
						winners.append(id)
				result = "%s got everyone!" % _names(winners)
			elif mode != Game.MODE_ELIMINATION and alive.size() <= 1:
				winners = alive
				result = "%s is the last gorilla standing!" % _names(winners)
			elif time_left <= 0.0:
				winners = alive
				result = "Survivors: %s" % _names(winners)
		Game.MODE_PAINT:
			var team_lives := {"red": 0, "blue": 0}
			for id in roles:
				if roles[id] in ["red", "blue"]:
					team_lives[roles[id]] += lives(id)
			var win := ""
			if team_lives.red == 0 or team_lives.blue == 0:
				win = "red" if team_lives.red > 0 else "blue"
			elif time_left <= 0.0:
				win = "red" if team_lives.red > team_lives.blue else ("blue" if team_lives.blue > team_lives.red else "tie")
			if win == "tie":
				result = "It's a tie!"
			elif win != "":
				for id in roles:
					if roles[id] == win:
						winners.append(id)
				result = "%s TEAM WINS! (%d li%s left)" % [win.to_upper(), team_lives[win], "fe" if team_lives[win] == 1 else "ves"]
		Game.MODE_CASUAL:
			if time_left <= 0.0:
				result = "Thanks for hanging out!"
	if result != "":
		phase = "end"
		time_left = END_TIME
		Net.broadcast_event("round_end", {"text": result, "winners": winners, "stats": stats})
		_broadcast_state()


func _names(ids: Array) -> String:
	var n := []
	for id in ids:
		var g: Gorilla = world.gorillas.get(id)
		if g:
			n.append(g.display_name)
	if n.is_empty():
		return "Nobody"
	return ", ".join(n)


func on_round_end(d: Dictionary) -> void:
	last_result = d.text
	stats = d.stats


func on_timer(d: Dictionary) -> void:
	time_left = d.time
	stats = d.stats
	if d.has("extra"):
		extra = d.extra


func server_swipe(id: int) -> void:
	_swipe[id] = 0.3


## A gorilla left the match; make sure the round still has a tagger.
func on_player_left(id: int) -> void:
	roles.erase(id)
	stats.erase(id)
	if not is_host() or phase == "end":
		return
	match mode:
		Game.MODE_MAZE, Game.MODE_PAINT, Game.MODE_CASUAL:
			_check_end()
			return
		Game.MODE_HUNT:
			# whoever was hunting them takes over their target
			var targets: Dictionary = extra.get("targets", {})
			for h in targets.keys():
				if int(targets[h]) == id:
					targets[h] = targets.get(id, h)
			targets.erase(id)
			_broadcast_state()
			_check_end()
			return
	var has_tagger := false
	for r in roles.values():
		if r in ["it", "infected", "seeker"]:
			has_tagger = true
	var free := roles.keys().filter(func(i): return roles[i] in ["runner", "hider"])
	if not has_tagger and free.size() > 1:
		var pick: int = free[randi() % free.size()]
		roles[pick] = "infected" if mode == Game.MODE_INFECTION else ("seeker" if mode == Game.MODE_HIDE_SEEK else "it")
		_broadcast_state()
	_check_end()
