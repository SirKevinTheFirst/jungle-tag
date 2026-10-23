class_name GameMode
extends Node
## Round flow and rules for Classic Tag, Infection and Jungle Hide and Seek.
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

var world: Node
var mode := Game.MODE_CLASSIC
var round_time := 180.0

# mirrored on all peers
var phase := "warmup"     # warmup, hide, play, end
var time_left := 0.0
var roles := {}           # id -> role
var stats := {}           # id -> {"tags": int, "it_time": float, "survived": float}
var last_result := ""

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
		stats[id] = {"tags": 0, "it_time": 0.0, "survived": 0.0}
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
	var chosen := int(Game.config.get("taggers", 0))
	if chosen > 0:
		special_count = chosen
	special_count = clampi(special_count, 1, maxi(1, ids.size() - 1))
	for i in ids.size():
		roles[ids[i]] = special if i < special_count else base_role
	for i in special_count:
		if i < ids.size():
			_infect_order.append(ids[i])
	phase = "warmup"
	time_left = WARMUP_TIME
	# everyone back to a spawn point
	var spawns: Array = world.jungle.spawn_points.duplicate()
	spawns.shuffle()
	var i := 0
	var spawn_map := {}
	for id in world.gorillas:
		spawn_map[id] = spawns[i % spawns.size()]
		i += 1
	Net.broadcast_event("respawn_all", {"spawns": spawn_map})
	_broadcast_state()


func _broadcast_state() -> void:
	Net.broadcast_event("round_state", {"phase": phase, "time": time_left, "roles": roles, "mode": mode})


## Applied on every peer.
func apply_state(d: Dictionary) -> void:
	var old_phase := phase
	phase = d.phase
	time_left = d.time
	mode = d.mode
	roles = d.roles
	for id in roles:
		var g: Gorilla = world.gorillas.get(id)
		if g:
			g.set_role(roles[id])
			g.frozen = phase == "hide" and roles[id] == "seeker"
			if phase == "warmup":
				g.frozen = true
	if old_phase != phase:
		_announce_phase()


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
	return "Don't get tagged!"


func _physics_process(delta: float) -> void:
	if world == null:
		return
	time_left = maxf(0.0, time_left - delta)
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
		Net.broadcast_event("timer", {"time": time_left, "stats": stats})
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
			_check_end()
		"end":
			if time_left <= 0.0:
				start_round()


func _accumulate_stats(delta: float) -> void:
	for id in roles:
		if not stats.has(id):
			stats[id] = {"tags": 0, "it_time": 0.0, "survived": 0.0}
		if roles[id] in ["it", "infected", "seeker"]:
			stats[id].it_time += delta
		else:
			stats[id].survived += delta


func _check_tags() -> void:
	var taggers := []
	var targets := []
	for id in world.gorillas:
		var r: String = roles.get(id, "runner")
		if r in ["it", "infected", "seeker"]:
			taggers.append(id)
		else:
			targets.append(id)
	for t_id in taggers:
		var tg: Gorilla = world.gorillas[t_id]
		if tg.stun_time > 0.0 or tg.frozen:
			continue
		var reach := TAG_RADIUS + (SWIPE_BONUS if _swipe.has(t_id) else 0.0)
		var tp := tg.global_position + Vector3(0, 0.8, 0)
		for v_id in targets:
			if _immune.has(v_id):
				continue
			# no tag-backs: you have to get someone other than the gorilla who got you
			if _no_tagback.get(t_id, -1) == v_id and targets.size() > 1:
				continue
			var vg: Gorilla = world.gorillas[v_id]
			if (vg.global_position + Vector3(0, 0.8, 0)).distance_to(tp) < reach:
				_do_tag(t_id, v_id)
				return


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
	Net.broadcast_event("tag", {"tagger": tagger, "target": target, "roles": roles, "stun": stun, "mode": mode})


## Applied on every peer when a tag happens.
func apply_tag(d: Dictionary) -> void:
	roles = d.roles
	var tagger: Gorilla = world.gorillas.get(d.tagger)
	var target: Gorilla = world.gorillas.get(d.target)
	for id in roles:
		var g: Gorilla = world.gorillas.get(id)
		if g:
			g.set_role(roles[id])
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
	var verb := "tagged"
	if d.mode == Game.MODE_INFECTION:
		verb = "infected"
	elif d.mode == Game.MODE_HIDE_SEEK:
		verb = "found"
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


func server_swipe(id: int) -> void:
	_swipe[id] = 0.3


## A gorilla left the match; make sure the round still has a tagger.
func on_player_left(id: int) -> void:
	roles.erase(id)
	stats.erase(id)
	if not is_host() or phase == "end":
		return
	var has_tagger := false
	for r in roles.values():
		if r in ["it", "infected", "seeker"]:
			has_tagger = true
	if not has_tagger and roles.size() > 0:
		var ids := roles.keys()
		var pick: int = ids[randi() % ids.size()]
		roles[pick] = "it" if mode == Game.MODE_CLASSIC else ("infected" if mode == Game.MODE_INFECTION else "seeker")
		_broadcast_state()
	elif roles.size() <= 1:
		_check_end()
