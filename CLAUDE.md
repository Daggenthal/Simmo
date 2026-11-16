# Simmo: notes for Claude Code

Simmo is an offline "fake MMO" in Godot 4.7: MapleStory-style side view, simulated players (SimPlayers) who party, guild and trade with you, and idle progress while you're away. Repo: github.com/Daggenthal/Simmo. The full design lives in the design doc "Simulated MMO Idle Game: Design Doc" (ask the owner for the link if you need it).

Current state: milestone M0+ (single player, placeholder art drawn in code). Movement, melee weapons, thrown kunai, four spells with status effects and combos, auto-battle with nav-graph pathing. No SimPlayers yet.

## How to work on this repo

**The loop:** Reproduce, write a failing test, fix, run the full suite several times, look at a screenshot when anything visual changed. Every bug fixed so far got a regression test first; keep doing that. When a test passes without your fix, the test is not reproducing the bug yet (this happened twice; see Gotchas).

```
./run.sh test     # both headless suites, ~5 s total, exit 0 = pass
./run.sh          # play
./run.sh debug    # hitboxes, debug overlay, full logging
./run.sh editor   # Godot editor
```

Run the suite at least 5 times after AI or physics changes; flaky checks are bugs (in the game or the test).

Screenshots for layout checks (needs a display; on macOS just run it, on Linux use `xvfb-run -a`):
```
godot --path . --rendering-driver opengl3 --script res://tools/screenshot.gd -- 1280x720   # also 2560x1080, weapon=iron_hammer
godot --path . --rendering-driver opengl3 --script res://tools/screenshot_magic.gd          # staged status effects
```
Output goes to `screenshots/` (gitignored). Software rendering is slow: if mobs look white/frozen in a shot, it was captured too early, wait more frames.

## Owner's conventions (follow these)

- **Identity:** The owner is "Daggenthal" in anything public (commits, README, credits). Never use another name.
- **Commits:** Leave changes uncommitted. The owner signs commits with SSH, so suggest the command instead, e.g.
  `git add -A && git commit -S -m "..." -m "Co-Authored-By: Claude <noreply@anthropic.com>" && git push`
  (keep the Co-Authored-By trailer so Claude shows as a contributor).
- **License:** Everything is MIT.
- **Writing (README, docs, comments):** Direct, no AI flair, no em-dashes, capitalize the first letter after a colon. Emojis are fine.
- **Terminal output:** Colored via `Log` (scripts/log.gd): red = errors/failures, bold red = crash headers, cyan = traces/stack frames, yellow = warnings and known-expected issues, green = success. Colors only on a terminal, plain in saved logs, `SIMMO_NO_COLOR=1` turns them off. Use `Log.ok/warn/error/crash/trace/dbg`, not bare print, in game code.
- **Debug mode:** `SIMMO_DEBUG=1`, `-- --debug-game`, or F3 in game. Full logging, keep running through errors (`Log.check()` instead of `assert`) so one pass shows every problem.
- **Long work:** Give a progress update roughly every 10 minutes (what works, what doesn't, what's being tested and why it fails).
- **Big decisions:** When a change is complicated, lay out the approaches, the trade-offs, and why you picked one.
- **Tuning numbers** go in `data/balance.json`, not code.

## Layout

| Path | What |
| --- | --- |
| `main.tscn`, `scripts/main.gd` | Entry: loads balance, builds world, player, camera, HUD; global hotkeys |
| `scripts/player.gd` | Player: movement intents, weapons, spells, mana, auto-battle brain (`_auto_think`, `_pick_target`, `_auto_pick_spell`) |
| `scripts/mob.gd` | Mobs: wander/aggro, knockback clamped to their platform, status effects (burn, chill, freeze, poison) and their visuals |
| `scripts/combat.gd` | All damage, element and combo rules. Every hit goes through `Combat.hit()` |
| `scripts/nav.gd` | Nav graph: surfaces + links (jump_up, jump_across, walk_off, drop), Dijkstra routes |
| `scripts/world.gd` | Test map (platforms and spawns are consts here for now), respawn queue |
| `scripts/projectile.gd`, `scripts/fx.gd` | Bolts, lobs, kunai; lightning and burst effects |
| `scripts/hud.gd` | Bottom bar, skill bar, controls panel (F1), debug overlay |
| `scripts/game_input.gd` | All key and controller bindings in one place |
| `data/balance.json` | Every tuning number: player, weapons, mobs, spells, elements |
| `tests/smoke_test.gd` | Movement, platforms, weapons, auto-battle, pathing, target focus |
| `tests/magic_test.gd` | Statuses, combos, spells, mana, pacing, kunai, weaving |

## Gotchas learned the hard way

- **Tests must not name game classes directly** (`Mob`, `World`, `Combat`, ...). A `--script` SceneTree compiles them before the `Log` autoload exists, and everything fails with "Identifier not found: Log". Use untyped vars, or `load("res://scripts/x.gd")` at runtime (see magic_test.gd).
- **New `class_name` scripts** need a re-import before running from the terminal. `run.sh` does this automatically when a .gd is newer than `.godot/global_script_class_cache.cfg`; in CI run `godot --headless --import --path .` first.
- **Run tests with `--fixed-fps 60`.** Without it headless runs in real time (a 1.5 s suite becomes a minute).
- **GDScript `:=` can't infer from Variants** (dictionary values, `lerp`, `max` on mixed types). Use explicit types (`var x: float = ...`) or the typed functions (`lerpf`, `maxf`, `signf`).
- **Reusing a mob in a test:** Clear `world._respawn_queue` first, or a pending respawn from an earlier death resets it mid-test. Also reset `max_hp`, since earlier phases set some to 99999.
- **Camera2D offsets ignore limits.** Don't use `offset` to frame the ground; use `limit_bottom`.
- **HUD Control under a CanvasLayer** needs `set_anchors_and_offsets_preset(PRESET_FULL_RECT)`, or anchored children end up off screen.
- **Keep the screen center clear:** The camera centers the player, so HUD pieces go to the edges.
- **Mob test dummies:** Set `data.speed`, `data.hop_velocity` and `data.touch_damage` to 0 on a duplicated `data` dict, then `set_bounds(world.nav)` and `respawn()`.

## Rules the game currently follows (keep them unless the owner changes them)

- Auto-battle: manual input takes over movement but auto keeps swinging at anything in front; resumes 0.4 s after input stops with a fresh target; sticks to wounded targets; finishes wounded mobs first; gives up on unreachable ones after 5 s; routes with the nav graph; weaves weapon attacks between spells; combo finishers (lightning on frozen, fire on 3+ poison) beat a weapon swing; with a thrown weapon it closes to 60% of max range.
- Spells: 1 s global cooldown, per-spell cooldowns (4 / 5 / 3 / 9 s), a cast locks the weapon 0.4 s, attacking locks casting 0.3 s.
- Weapon DPS stays within about 30% across weapons at levels 1, 10 and 30 (tested).
- Knockback never pushes mobs off their platform.
- Every platform must be reachable by a real jump (tested).

## Backlog, in order

1. **SimPlayers (M1):** Pull the auto-battle brain out of `player.gd` into a reusable brain/actor component so player and SimPlayers share it. Spawn 3 SimPlayers who follow the player across platforms (nav graph) and fight by role (tank in front, healer behind, ranged on platforms). Paper-doll-ready drawing (layers, palette swaps).
2. **Away loop (M2):** Save/load (versioned, autosave), abstract simulation tick for off-screen sims, offline progress = abstract ticks for elapsed time (clamped), guild report screen.
3. **Mobile:** Touch controls (virtual stick, jump, attack, skill buttons, AUTO), safe areas, Android export first, then iOS. Test on the Galaxy Z Fold 6 (folded and unfolded) and iPhone 17 Pro Max.
4. **Map data:** Move platforms and spawns from consts in world.gd to data files; a second map with a portal.
5. **Polish found while testing:** Projectiles ignore platforms (they only stop at the target's floor height); lobbed globs can't splash on a platform with no mob on it; controller spell bindings (B / LB / L3 / R3) are temporary until a skill menu exists; the bottom bar is tight at 640 px wide.
6. Later (see design doc): Guild system, trading with sims, chat (quick-chat + intent parser), tavern bartender mini-game, raids, world bosses, fake patch days.
