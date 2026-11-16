# Simmo

An offline fake MMO: MapleStory-style side view, simulated players, guilds that keep playing while you're away. This is milestone M0: movement and combat with placeholder art drawn in code.

## Run it

Needs Godot 4.7 or newer: `brew install --cask godot`

```
./run.sh          # play
./run.sh debug    # play with debug mode (hitboxes, overlay, full logging)
./run.sh editor   # open in the Godot editor
./run.sh test     # headless smoke test
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
| Debug overlay | F3 | Back / Share |
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
| Fireball | Z | Fire | 6 | 1.2 s | Bolt. Burns for 4 dmg/s over 4 s. Thaws frozen and chilled targets |
| Frost Bolt | X | Frost | 6 | 1.0 s | Bolt. Slows 45% for 3 s, 25% chance to freeze for 2 s |
| Venom Glob | C | Poison | 5 | 0.9 s | Lobbed, splashes. Poison stacks up to 5, 2 dmg/s per stack for 6 s |
| Chain Lightning | V | Lightning | 12 | 2.5 s | Instant. Hits the target and jumps to 3 more within 80 px, 25% less each jump |

  Combos:

| Combo | What happens |
| --- | --- |
| Frost on a frozen target | +50% crit chance |
| Lightning on a frozen target (conduct) | Always crits, splashes 60% damage to mobs within 50 px, shatters the ice |
| Fire on a poisoned target (ignite) | Poison bursts for 7 per stack to everything within 44 px |

  Frozen mobs can't move or hurt you by touch. Auto-battle uses spells too and sets up combos (freeze then lightning, stack poison then fire). Statuses show as pips above each mob.
- Crits, knockback and floating damage numbers
- Three mob types (Green Slime, Blue Slime, Grumpy Stump) that wander, aggro when hit and respawn. Knockback stops at the edge of their platform, MapleStory style
- Auto-battle: runs to the nearest reachable enemy, jumps up or drops down to its platform and attacks. Moving by hand takes over movement while auto keeps swinging at anything in front of you; 0.4 s after you let go it picks the nearest mob from where you are. It routes with a navigation graph (`scripts/nav.gd`): jump up, jump across gaps, walk off edges or drop through, picking the shortest real route and the nearest mob by travel distance. Once it has hit a mob it stays on it until it dies, and it finishes wounded mobs (like the extras a hammer swing clips) before starting on fresh ones. It gives up on a mob it can't reach after 5 s
- XP, leveling, HP growth, death and respawn in town
- Bottom status bar, wider screens show more of the world (fixed 360 px height, width expands)

## Layout

| Path | What |
| --- | --- |
| `data/balance.json` | All tuning numbers: player stats, mobs, respawn time |
| `scripts/` | Game code (player, mob, world, navigation, HUD, logging, input) |
| `tests/smoke_test.gd` | Headless test for movement, combat, weapons, auto-battle and pathing |
| `tests/magic_test.gd` | Headless test for every status effect, combo, spell, mana and the kunai |
| `scripts/combat.gd` | Damage, element and combo rules shared by every attack |
| `tools/screenshot.gd` | Renders screenshots at any resolution for layout checks |

## Logging and debug mode

Colored terminal output: red errors, yellow warnings, green success, cyan traces. Plain text in saved logs. `SIMMO_NO_COLOR=1` turns colors off. Debug mode (`SIMMO_DEBUG=1`, `./run.sh debug` or F3) shows hitboxes and the overlay, logs every hit, and keeps running through errors.

## License

MIT
