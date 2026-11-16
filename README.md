# Simmo

An offline fake MMO: MapleStory-style side view, simulated players, guilds that keep playing while you're away. This is milestone M1: combat, four maps joined by portals, and a party of three SimPlayers, all with placeholder art drawn in code.

## Run it

Needs Godot 4.7 or newer: `brew install --cask godot`

```
./run.sh          # play
./run.sh debug    # play with debug mode (hitboxes, overlay, full logging)
./run.sh editor   # open in the Godot editor
./run.sh test     # all headless test suites
```

## Controls

| Action | Keyboard | Controller |
| --- | --- | --- |
| Move | Arrows or WASD | Left stick or D-pad |
| Jump | Alt or Space | A / Cross |
| Attack | Ctrl or J | X / Square |
| Drop through platform | Down + Jump | Down + A |
| Switch weapon | 1 / 2 / 3 / 4, or E to cycle | RB / R1 |
| Fireball / Frost Bolt / Venom Glob / Chain Lightning | Z / X / C / V | B / LB / L3 / R3 |
| Auto-battle on/off | Q or Tab (or the AUTO button) | Y / Triangle |
| Show / hide controls | F1 | Start / Options |
| Debug overlay | F3 | Back / Share |
| Enter a portal | Stand on it + Up | Up |
| Party on / off | P | |
| Respawn all mobs | F5 | |

## What's in M0

- Side-view movement: acceleration, coyote time, jump buffering, short hops, one-way platforms you can jump up through and drop down from
- Three weapons with real trade-offs (hold attack to keep swinging at the weapon's speed):

| Weapon | Speed | Swing delay | Damage per hit | Hits up to | Notes |
| --- | --- | --- | --- | --- | --- |
| Dagger | Fast | 0.55 s | 12 to 16 | 1 enemy | Short reach, light knockback |
| Short Sword | Normal | 0.80 s | 19 to 25 | 2 enemies | Starting weapon |
| Iron Hammer | Slow | 1.30 s | 34 to 44 | 4 enemies | 0.25 s wind-up, long reach, big knockback |
| Throwing Kunai | Normal | 0.70 s | 15 to 21 | 1 enemy | Thrown in an arc aimed at the target, 170 px range. 50% chance to carry your last spell's element at half strength |

  Damage per second stays within about 20% across weapons, and the level bonus scales with swing time so slow weapons keep up as you level. All of it lives in `data/balance.json`; `attack_speed_scale` under `player` slows or speeds up every weapon at once (1.2 = 20% slower).
- Magic (MP bar, regenerates over time; spells in `data/balance.json`):

| Spell | Key | Element | MP | Cooldown | Effect |
| --- | --- | --- | --- | --- | --- |
| Fireball | Z | Fire | 6 | 4 s | Bolt. Burns for 4 dmg/s over 4 s. Thaws frozen and chilled targets |
| Frost Bolt | X | Frost | 6 | 5 s | Bolt. Slows 45% for 3 s, 25% chance to freeze for 2 s |
| Venom Glob | C | Poison | 5 | 3 s | Lobbed, splashes. Poison stacks up to 5, 2 dmg/s per stack for 6 s |
| Chain Lightning | V | Lightning | 12 | 9 s | Instant. Hits the target and jumps to 3 more within 80 px, 25% less each jump |

  Combos:

| Combo | What happens |
| --- | --- |
| Frost on a frozen target | +50% crit chance |
| Lightning on a frozen target (conduct) | Always crits, splashes 60% damage to mobs within 50 px, shatters the ice |
| Fire on a poisoned target (ignite) | Poison bursts for 7 per stack to everything within 44 px |

  Frozen mobs can't move or hurt you by touch. Auto-battle uses spells too and sets up combos (freeze then lightning, stack poison then fire), weaving them between weapon attacks. Spells share a 1 s global cooldown; a cast locks the weapon for 0.4 s. With the kunai it closes to about 60% of max range and keeps moving in while the throw cools down. Statuses show as pips above each mob.
- Crits, knockback and floating damage numbers
- Four maps joined by portals (`data/maps.json`). Stand on a portal and press Up; your party comes along:

| Map | Levels | Mobs |
| --- | --- | --- |
| Mossy Meadow (town) | 1 to 5 | Green Slime, Blue Slime, Grumpy Stump |
| Mushroom Grove | 6 to 12 | Orange Shroom, Horny Shroom, Wild Boar |
| Ember Crags | 13 to 20 | Fire Imp (resists fire), Lava Slime, Rock Golem (hard to knock back) |
| Frostpeak Ruins | 21 to 30 | Frost Slime (resists frost), Skeleton (resists poison), Ice Golem |

  Mobs wander, aggro when hit (some aggro on sight), respawn, and stop at the edge of their platform when knocked back, MapleStory style. Each shows its level under its feet: white near your level, orange a few levels above, red dangerous, gray far below.
- Mob levels and XP (`mob_scaling` in `data/balance.json`): HP grows at the same rate as player damage and touch damage at the same rate as player HP, so a mob at your level always takes about the same number of hits. XP grows with the mob's level and toughness. Mobs more than 3 levels under you give less XP, down to 10%; mobs above you give up to 30% more. Progress comes from moving up to the next map.
- Party (M1): three SimPlayers join you and follow you across platforms and through portals, using the same auto-battle brain as your AUTO mode:

| Sim | Role | What it does |
| --- | --- | --- |
| Brannoc | Tank | Iron Hammer, 80% more HP, stands in front of you and goes for the mobs closest to you |
| Liriel | Healer | Heals whoever drops under 65% HP, stands behind you, Frost Bolt and a sword for close mobs |
| xXKunaiXx | Ranged | Throwing kunai plus Fireball and Venom Glob, climbs onto a platform above its target to throw from there |

  Kill XP is split across the party on the map, with a 20% bonus per extra member (a party of four gets 40% each). A sim at 0 HP is knocked out for 5 s and comes back next to you. Sims are drawn in paper-doll layers (hair style, hat, palette) from their `look` in `data/balance.json`. P sends them away or calls them back.
- Auto-battle: runs to the nearest reachable enemy, jumps up or drops down to its platform and attacks. Moving by hand takes over movement while auto keeps swinging at anything in front of you; 0.4 s after you let go it picks the nearest mob from where you are. It routes with a navigation graph (`scripts/nav.gd`): jump up, jump across gaps, walk off edges or drop through, picking the shortest real route and the nearest mob by travel distance. Once it has hit a mob it stays on it until it dies, and it finishes wounded mobs (like the extras a hammer swing clips) before starting on fresh ones. It gives up on a mob it can't reach after 5 s
- XP, leveling, HP growth, death and respawn at the map's entrance
- Bottom status bar, wider screens show more of the world (fixed 360 px height, width expands)

## Layout

| Path | What |
| --- | --- |
| `data/balance.json` | All tuning numbers: player stats, weapons, spells, mobs, mob scaling, party, sim roles and looks |
| `data/maps.json` | Maps: platforms, spawns, portals, level range, colors |
| `scripts/` | Game code (actor, player, SimPlayer, brain, mob, world, navigation, HUD, logging, input) |
| `tests/smoke_test.gd` | Headless test for movement, combat, weapons, auto-battle and pathing |
| `tests/magic_test.gd` | Headless test for every status effect, combo, spell, mana and the kunai |
| `tests/world_test.gd` | Headless test for map data, portals, mob scaling, XP rules and resists |
| `tests/party_test.gd` | Headless test for SimPlayers: following, roles, healing, perching, XP share, knockouts, portals |
| `scripts/combat.gd` | Damage, element and combo rules shared by every attack |
| `tools/screenshot.gd` | Renders screenshots at any resolution for layout checks |

## Logging and debug mode

Colored terminal output: red errors, yellow warnings, green success, cyan traces. Plain text in saved logs. `SIMMO_NO_COLOR=1` turns colors off. Debug mode (`SIMMO_DEBUG=1`, `./run.sh debug` or F3) shows hitboxes and the overlay, logs every hit, and keeps running through errors.

## License

MIT
