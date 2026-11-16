class_name Scaling
extends RefCounted
## Level math in one place: mob stats by level, XP by level difference, party XP share.
## Every number comes from data/balance.json (mob_scaling, party).
##
## Mob stats follow the player's growth curves, so a mob at your level always takes
## about the same number of hits and hurts about the same share of your HP:
##   hp(L)     = type hp     * (1 + hp_per_level * (L - 1))     / (1 + hp_per_level * (type level - 1))
##   damage(L) = type damage * (1 + damage_per_level * (L - 1)) / (same at type level)
##   xp(L)     = type xp     * (L / type level) ^ xp_exponent

## A copy of mob type `base` scaled to `level`.
static func mob_stats(base: Dictionary, level: int, cfg: Dictionary) -> Dictionary:
	var d := base.duplicate(true)
	var base_level := maxi(int(base.get("level", 1)), 1)
	level = maxi(level, 1)
	var hp_k := float(cfg.get("hp_per_level", 0.0))
	var dmg_k := float(cfg.get("damage_per_level", 0.0))
	var hp_curve := (1.0 + hp_k * (level - 1)) / (1.0 + hp_k * (base_level - 1))
	var dmg_curve := (1.0 + dmg_k * (level - 1)) / (1.0 + dmg_k * (base_level - 1))
	var xp_curve := pow(float(level) / base_level, float(cfg.get("xp_exponent", 1.0)))
	d.level = level
	d.hp = maxi(1, int(round(float(base.hp) * hp_curve)))
	d.touch_damage = int(round(float(base.touch_damage) * dmg_curve))
	d.xp = maxi(1, int(round(float(base.xp) * xp_curve)))
	return d

## XP multiplier for killing a mob of `mob_level` at `player_level`.
## Within the grace window: full XP. Below it: less per level, down to a floor.
## Above your level: a small bonus per level, up to a cap.
static func xp_mult(mob_level: int, player_level: int, cfg: Dictionary) -> float:
	var diff := mob_level - player_level
	if diff >= 0:
		return minf(1.0 + float(cfg.get("xp_bonus_per_level", 0.0)) * diff, float(cfg.get("xp_max_mult", 1.0)))
	var under := -diff - int(cfg.get("xp_grace_levels", 0))
	if under <= 0:
		return 1.0
	return maxf(1.0 - float(cfg.get("xp_penalty_per_level", 0.0)) * under, float(cfg.get("xp_min_mult", 0.0)))

## Share of a kill's XP each party member gets when `members` are on the map.
static func party_share(members: int, cfg: Dictionary) -> float:
	members = maxi(members, 1)
	return (1.0 + float(cfg.get("xp_bonus_per_member", 0.0)) * (members - 1)) / members

## Color for a mob's level label as seen by a player of `player_level`.
static func level_color(mob_level: int, player_level: int) -> Color:
	var diff := mob_level - player_level
	if diff >= 5:
		return Color("#ff5a5a")
	if diff >= 2:
		return Color("#ffb347")
	if diff <= -6:
		return Color("#9a9a9a")
	return Color("#ffffff")
