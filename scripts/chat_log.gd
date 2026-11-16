class_name ChatLog
extends RefCounted
## Every chat, system, XP, loot, trade and combat line in one place. Game code calls ChatLog.add();
## the chat box reads `lines`. Channels and their colors come from data/chat.json.
##   local    white   passers-by
##   party    blue    SimPlayers
##   system   yellow  level ups, maps, warnings
##   xp       green   XP gained
##   loot     cyan    items picked up
##   combat   orange  your damage and kills
##   trade    pink    trades
##   warning  red     danger notices

const MAX_LINES := 200
const CHAT_PATH := "res://data/chat.json"

static var lines: Array = []      # {channel, text, frame}
static var version := 0           # bumps on every add, so the UI knows to redraw
static var colors: Dictionary = {}

static func load_data() -> Dictionary:
	var f := FileAccess.open(CHAT_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	var d: Dictionary = parsed if parsed is Dictionary else {}
	colors = d.get("colors", {})
	return d

## col: optional color for this line only (loot in its rarity color).
static func add(channel: String, text: String, col := Color(0, 0, 0, 0)) -> void:
	lines.append({"channel": channel, "text": text, "frame": Engine.get_physics_frames(), "color": col})
	if lines.size() > MAX_LINES:
		lines.pop_front()
	version += 1
	Log.dbg("[%s] %s" % [channel, text])

static func color(channel: String) -> Color:
	return Color(colors.get(channel, "#ffffff"))

static func clear() -> void:
	lines.clear()
	version += 1

## Lines in `channel` (tests).
static func count(channel: String) -> int:
	var n := 0
	for l in lines:
		if l.channel == channel:
			n += 1
	return n

static func last(channel: String) -> String:
	for k in range(lines.size() - 1, -1, -1):
		if lines[k].channel == channel:
			return String(lines[k].text)
	return ""
