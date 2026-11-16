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
| Switch weapon | 1 / 2 / 3, or E to cycle | RB / R1 |
| Auto-battle on/off | Q or Tab (or the AUTO button) | Y / Triangle |
| Debug overlay | F3 | Back / Share |
| Respawn all mobs | F5 | |

## What's in M0

- Side-view movement: acceleration, coyote time, jump buffering, short hops, one-way platforms you can jump up through and drop down from
- Three weapons with real trade-offs (hold attack to keep swinging at the weapon's speed):

| Weapon | Speed | Swing delay | Damage per hit | Hits up to | Notes |
| --- | --- | --- | --- | --- | --- |
| Dagger | Fast | 0.30 s | 6 to 9 | 1 enemy | Short reach, light knockback |
| Short Sword | Normal | 0.50 s | 11 to 15 | 2 enemies | Starting weapon |
| Iron Hammer | Slow | 0.95 s | 24 to 32 | 4 enemies | 0.18 s wind-up, long reach, big knockback |

  Damage per second stays within about 20% across weapons, and the level bonus scales with swing time so slow weapons keep up as you level. All of it lives in `data/balance.json`.
- Crits, knockback and floating damage numbers
- Three mob types (Green Slime, Blue Slime, Grumpy Stump) that wander, aggro when hit and respawn
- Auto-battle: runs to the nearest reachable enemy, jumps up or drops down to its platform and attacks. Any manual input takes over, and auto resumes 1.5 s after you let go
- XP, leveling, HP growth, death and respawn in town
- Bottom status bar, wider screens show more of the world (fixed 360 px height, width expands)

## Layout

| Path | What |
| --- | --- |
| `data/balance.json` | All tuning numbers: player stats, mobs, respawn time |
| `scripts/` | Game code (player, mob, world, HUD, logging, input) |
| `tests/smoke_test.gd` | Headless test that walks, jumps, drops through a platform and fights |
| `tools/screenshot.gd` | Renders screenshots at any resolution for layout checks |

## Logging and debug mode

Colored terminal output: red errors, yellow warnings, green success, cyan traces. Plain text in saved logs. `SIMMO_NO_COLOR=1` turns colors off. Debug mode (`SIMMO_DEBUG=1`, `./run.sh debug` or F3) shows hitboxes and the overlay, logs every hit, and keeps running through errors.

## License

MIT
