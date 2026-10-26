class_name BotChat
extends Node
## Host only: makes the AI gorillas chat like real online players. Each bot gets a typing
## style (all caps, no caps, typos, spammy...), reacts to what happens in the match,
## trash talks, answers players and keeps a conversation going with whoever talked to it.

const STYLES := ["chill", "hype", "tryhard", "noob", "troll"]

## topic -> keywords. Checked in order, first hit wins.
const TOPICS := [
	["greet", ["hi", "hello", "hey", "yo", "sup", "hii", "helo", "wsg"]],
	["bye", ["bye", "gtg", "cya", "leaving", "brb"]],
	["gg", ["gg", "good game", "ggs"]],
	["howru", ["how are you", "how r u", "hru", "wassup", "whats up", "what's up", "wyd"]],
	["age", ["how old", "age", "grade"]],
	["where_from", ["where are you from", "where u from", "wya", "what country"]],
	["who_it", ["who is it", "whos it", "who's it", "who it", "tagger"]],
	["where", ["where", "exit", "find", "lost"]],
	["help", ["help", "save me", "save"]],
	["banana", ["banana"]],
	["shadow", ["shadow", "maze", "black hole", "hole"]],
	["cave", ["cave", "waterfall", "secret", "tunnel"]],
	["insult", ["noob", "bad", "trash", "ez", "loser", "bot", "slow"]],
	["nice", ["nice", "good", "cool", "pro", "wow", "goat", "insane"]],
	["laugh", ["lol", "haha", "lmao", "xd", "lmfao", "hehe"]],
	["tagged", ["you're it", "ur it", "tag", "got you", "gotcha", "got u"]],
	["friend", ["friend", "team", "duo", "follow me", "squad"]],
	["name", ["your name", "ur name", "who are you", "who r u"]],
	["yes", ["yes", "yeah", "ya", "yep", "ok", "okay", "k"]],
	["no", ["no", "nah", "nope"]],
	["question", ["?"]],
]

const LINES := {
	"greet": ["hiii %s", "yo %s", "sup", "hey!!", "heyyy", "wsg %s", "hi %s :)", "hello fellow monke"],
	"bye": ["byeee", "cya %s", "noooo dont go", "bye %s!!", "ok bye lol"],
	"gg": ["gg", "ggs", "gg wp", "gg ez", "ggs that was fun", "gg %s"],
	"howru": ["good wbu", "im chillin", "running for my life lol", "pretty good hbu", "bored ngl", "vibing"],
	"age": ["why do u wanna know lol", "old enough", "not telling", "11 and a half", "older than u"],
	"where_from": ["the jungle obviously", "earth", "not telling lol", "the banana kingdom"],
	"who_it": ["%i is it", "%i is it RUN", "idk but not me", "pretty sure %i"],
	"where": ["idk lol", "follow the green light", "near the big tree", "try the waterfall", "im lost too", "left then right then left lol"],
	"help": ["omw %s", "coming!!", "cant the shadow is on me", "nah ur on ur own lol", "where r u"],
	"banana": ["bananas >>>", "eat 10 then press F", "i got like 7 bananas", "theres some in the cave", "BANANA"],
	"shadow": ["the shadow is so creepy", "i hate the shadow", "the maze is so hard", "just jump in the hole its fun", "the shadow got me 3 times lol"],
	"cave": ["the cave is behind the waterfall", "theres crystals in there", "i found a secret tunnel", "the cave is so cool"],
	"insult": ["no u", "ur the noob lol", "ok buddy", "cope", "says the one who got tagged", "skill issue", "bro what"],
	"nice": ["ty ty", "thanks %s", "ikr", "im built different", "W"],
	"laugh": ["lol", "LMAO", "lolol", "haha", "bruh", "skull"],
	"tagged": ["NOOO", "bruh", "not fair", "ur so fast", "im coming for u %s", "how"],
	"friend": ["sure lets duo", "ok im following u", "best friends %s", "squad up"],
	"name": ["im %b", "%b duh", "its %b lol"],
	"yes": ["ok", "bet", "W", "fr", "ye"],
	"no": ["ok fine", "why not", "bruh", "rude"],
	"question": ["idk", "maybe", "yes", "no", "idk ask %i", "why", "hmm"],
	"any": ["fr", "true", "lol ok", "real", "bruh", "wait what", "cant talk running", "ok %s", "same", "W", "who asked lol", "facts", "ong"],
	# match events
	"got_tagged": ["NOOO", "bruh", "how did u get me", "lag", "that didnt count", "ok who tagged me", "im it now rip"],
	"tagged_someone": ["got u %t", "ur it %t", "too easy", "tag ur it", "sorry %t lol", "ez"],
	"saw_tag": ["RUN", "%t is it", "lol %t got tagged", "stay away from %t", "%t is coming"],
	"is_it": ["im coming for u all", "who wants to be it", "hide all u want", "ready or not"],
	"in_hole": ["AAAAA", "IM IN THE HOLE", "wheeeee", "uh oh", "brb maze"],
	"escaped": ["IM OUT", "escaped ez", "made it out", "W", "freedom"],
	"caught": ["the shadow got me", "NOOO the shadow", "bro the shadow is so fast", "back to start rip"],
	"boost": ["ZOOM", "im so fast", "banana power", "catch me now lol", "speeeed"],
	"rain": ["its raining again", "rain lol", "i love the rain", "wet monke"],
	"sun": ["sun is back", "finally sun", "its sunny now"],
	"round_start": ["lets goo", "gl everyone", "ok im ready", "here we go", "i call not it"],
	"round_end": ["gg", "ggs", "gg wp", "rematch?", "again again"],
	"idle": ["anyone wanna duo", "this map is huge", "where is everyone", "who's it", "im hiding dont tell",
		"come catch me", "i found a secret spot", "lag", "anyone seen the cave", "brb", "im so good at this",
		"bananas are op", "i love this game", "whos the best here (me)", "can we play maze run next"],
}

## a player's message that names nobody goes to the bot they were last talking with, if recent
const CONVO_TIME := 25.0

var world
var _style := {}         # bot id -> style
var _partner := {}       # human id -> [bot id, time]
var _last_said := {}     # bot id -> time, so one bot doesn't spam
var _idle_timer := 20.0
var _time := 0.0


func setup(w) -> void:
	world = w


func _style_of(bot: int) -> String:
	if not _style.has(bot):
		_style[bot] = STYLES[(bot * 7 + randi() % 3) % STYLES.size()]
	return _style[bot]


func _process(delta: float) -> void:
	if not Net.is_host():
		return
	_time += delta
	_idle_timer -= delta
	if _idle_timer <= 0.0:
		_idle_timer = randf_range(18.0, 40.0)
		var bots := _bots()
		if not bots.is_empty():
			var b: int = bots[randi() % bots.size()]
			_say(b, "idle", {}, randf_range(0.0, 1.0))


func _bots(except := -1) -> Array:
	return world.gorillas.keys().filter(func(b): return Game.is_bot_id(b) and b != except)


func _name(id: int) -> String:
	var g = world.gorillas.get(id)
	return g.display_name if g else "someone"


## Someone said something in chat (host). depth stops bots replying to bots forever.
func on_chat(id: int, text: String, depth: int) -> void:
	var human := not Game.is_bot_id(id)
	if depth > 2 or (not human and randf() > 0.5):
		return
	var bot := _pick_replier(id, text)
	if bot == -1:
		return
	if human:
		_partner[id] = [bot, _time]
	var topic := topic_of(text)
	_say(bot, topic, {"s": _name(id)}, 0.0, depth + 1, human)
	# sometimes a second bot joins in
	if human and randf() < 0.3:
		var others := _bots(bot)
		if not others.is_empty():
			_say(others[randi() % others.size()], topic, {"s": _name(id)}, randf_range(1.5, 3.5), depth + 1)


func _pick_replier(speaker: int, text: String) -> int:
	var low := text.to_lower()
	for b in _bots(speaker):
		var first: String = _name(b).to_lower().split(" ")[0]
		if low.contains(_name(b).to_lower()) or (first.length() >= 3 and _words(low).has(first)):
			return b
	if _partner.has(speaker) and _time - float(_partner[speaker][1]) < CONVO_TIME and world.gorillas.has(_partner[speaker][0]):
		return _partner[speaker][0]
	var sg = world.gorillas.get(speaker)
	var best := -1
	var best_d := INF
	for b in _bots(speaker):
		var d: float = world.gorillas[b].global_position.distance_to(sg.global_position) if sg else 0.0
		if d < best_d:
			best_d = d
			best = b
	return best


static func _words(low: String) -> PackedStringArray:
	var clean := ""
	for c in low:
		clean += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "'" else " "
	return clean.split(" ", false)


static func topic_of(text: String) -> String:
	var low := text.to_lower()
	var words := _words(low)
	for t in TOPICS:
		for key: String in t[1]:
			var hit := false
			if not key.is_valid_identifier():
				hit = low.contains(key)
			else:
				for w in words:
					if w == key or (key.length() >= 4 and w.begins_with(key)):
						hit = true
			if hit:
				return t[0]
	return "any"


## Host: a match event happened; the bots involved (and a bystander) may react.
func on_event(type: String, d: Dictionary) -> void:
	match type:
		"tag":
			var tagger := int(d.get("tagger", -1))
			var target := int(d.get("target", -1))
			var names := {"t": _name(target)}
			if Game.is_bot_id(target) and randf() < 0.7:
				_say(target, "got_tagged", names, 0.5)
			if Game.is_bot_id(tagger) and randf() < 0.5:
				_say(tagger, "tagged_someone", names, 0.8)
			elif randf() < 0.35:
				var others := _bots(target)
				if not others.is_empty():
					_say(others[randi() % others.size()], "saw_tag", names, 1.5)
		"maze_enter":
			if Game.is_bot_id(int(d.id)) and randf() < 0.5:
				_say(int(d.id), "in_hole", {}, 0.3)
		"maze_exit":
			if Game.is_bot_id(int(d.id)) and randf() < 0.5:
				_say(int(d.id), "escaped", {}, 0.5)
		"maze_caught":
			if Game.is_bot_id(int(d.id)) and randf() < 0.6:
				_say(int(d.id), "caught", {}, 0.5)
		"banana_boost":
			if Game.is_bot_id(int(d.id)):
				_say(int(d.id), "boost", {}, 0.4)
		"weather":
			_random_bot_says("rain" if d.get("rain", false) else "sun", 0.6)
		"round_state":
			if d.get("phase", "") in ["play", "hide"]:
				_random_bot_says("round_start", 0.7)
				var roles: Dictionary = d.get("roles", {})
				for id in roles:
					if roles[id] == "it" and Game.is_bot_id(int(id)) and randf() < 0.6:
						_say(int(id), "is_it", {}, 2.5)
						break
		"round_end":
			for b in _bots():
				if randf() < 0.4:
					_say(b, "round_end", {}, randf_range(0.5, 3.0))


func _random_bot_says(topic: String, chance: float) -> void:
	var bots := _bots()
	if bots.is_empty() or randf() > chance:
		return
	_say(bots[randi() % bots.size()], topic, {}, randf_range(0.5, 2.0))


## Picks a line, styles it, waits like someone typing, then sends it.
func _say(bot: int, topic: String, names: Dictionary, delay: float, depth := 1, force := false) -> void:
	if not force and _time - float(_last_said.get(bot, -99.0)) < 4.0:
		return
	_last_said[bot] = _time
	var pool: Array = LINES.get(topic, LINES.any)
	var line := make_line(pool[randi() % pool.size()], names, _name(bot), _it_name(), _style_of(bot))
	var wait := delay + 0.6 + line.length() * randf_range(0.05, 0.11)
	get_tree().create_timer(wait).timeout.connect(func():
		if world.gorillas.has(bot):
			world.server_chat(bot, line, depth)
			# chatty ones sometimes add a quick follow-up
			if randf() < 0.15 and topic != "idle":
				var extra: Array = ["lol", "fr", "ong", "anyway", "bruh"]
				get_tree().create_timer(randf_range(0.8, 1.6)).timeout.connect(func():
					if world.gorillas.has(bot):
						world.server_chat(bot, extra[randi() % extra.size()], 99)))


func _it_name() -> String:
	for id in world.gorillas:
		if world.gorillas[id].role == "it":
			return _name(id)
	return "nobody"


## Fills in names and applies a typing style.
static func make_line(line: String, names: Dictionary, me: String, it: String, style: String) -> String:
	line = line.replace("%s", String(names.get("s", "bro"))).replace("%t", String(names.get("t", "bro")))
	line = line.replace("%b", me).replace("%i", it)
	match style:
		"hype":
			if randf() < 0.5:
				line = line.to_upper()
			if randf() < 0.5:
				line += ["!!", "!!!", " LETS GO", " W"][randi() % 4]
		"chill":
			line = line.to_lower().replace("!", "")
		"noob":
			line = _typo(line.to_lower())
			if randf() < 0.3:
				line += " lol"
		"troll":
			if randf() < 0.3:
				line += [" lol", " lmao", " get good", " ez"][randi() % 4]
		"tryhard":
			line = line.to_lower()
	return line


static func _typo(line: String) -> String:
	if line.length() < 4 or randf() > 0.6:
		return line
	var i := randi_range(1, line.length() - 2)
	var c := line[i]
	if c == " ":
		return line
	return line.substr(0, i) + line[i + 1] + c + line.substr(i + 2)   # swap two letters
