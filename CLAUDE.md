# Simmo: notes for Claude Code

Simmo is an offline "fake MMO" in Godot 4.7: MapleStory-style side view, simulated players (SimPlayers) who party, guild and trade with you, and idle progress while you're away. Repo: github.com/Daggenthal/Simmo. The full design lives in the design doc "Simulated MMO Idle Game: Design Doc" (ask the owner for the link if you need it).

Current state: milestone M1 (placeholder art drawn in code). Movement, melee weapons, thrown kunai, four spells with status effects and combos, auto-battle with nav-graph pathing. Four maps joined by portals (`data/maps.json`), mob stats and XP scale by level, XP drops off on low mobs. A party of 3 SimPlayers (tank, healer, ranged) shares the auto-battle brain, follows the player across platforms and through portals, and splits kill XP. Portals warn about under-leveled maps without blocking. Inventory with potions and XP tonics, loot from party kills, auto-potions during auto-battle.

## How to work on this repo

**The loop:** Reproduce, write a failing test, fix, run the full suite several times, look at a screenshot when anything visual changed. Every bug fixed so far got a regression test first; keep doing that. When a test passes without your fix, the test is not reproducing the bug yet (this happened twice; see Gotchas).

```
./run.sh test     # all five headless suites, ~10 s total, exit 0 = pass
SIMMO_SEED=3 ./run.sh test   # same with another seed; loop a few seeds to catch flaky checks
./run.sh          # play
./run.sh debug    # hitboxes, debug overlay, full logging
./run.sh editor   # Godot editor
```

Run the suite at least 5 times after AI or physics changes, with different `SIMMO_SEED` values (the tests use fixed seeds, so plain reruns repeat the same game); flaky checks are bugs (in the game or the test).

Screenshots for layout checks (needs a display; on macOS just run it, on Linux use `xvfb-run -a`):
```
godot --path . --rendering-driver opengl3 --script res://tools/screenshot.gd -- 1280x720   # also 2560x1080, weapon=iron_hammer, map=ember_crags, level=15
godot --path . --rendering-driver opengl3 --script res://tools/screenshot_magic.gd          # staged status effects
```
Soak run (real game, party + auto-battle, 60 s per map; look for SCRIPT ERROR and the per-map kill/level lines):
```
godot --headless --fixed-fps 60 --path . --script res://tools/soak.gd
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
| `main.tscn`, `scripts/main.gd` | Entry: loads balance, builds world, player, party, camera, sky; follows map changes; global hotkeys (Up = portal, P = party) |
| `scripts/actor.gd` | `Actor`: the body shared by player and sims. Movement from an intent dict, weapons, spells (incl. heal), HP/MP/XP, paper-doll drawing from `look` |
| `scripts/player.gd` | `Player extends Actor`: keyboard/controller input, auto-battle toggle and manual override, inventory use (`use_item`, `use_best`), auto-potions |
| `scripts/inventory.gd`, `scripts/inventory_ui.gd` | `Inventory` (slots, stacking, item defs) and `InventoryUI` (I window, click to use, item icons) |
| `data/items.json` | Items, loot table, starter kit, inventory size, use cooldown |
| `scripts/sim_player.gd` | `SimPlayer extends Actor`: role setup from `sim_roles`, knockout and revive next to the leader |
| `scripts/brain.gd` | `Brain`: auto-battle (`think`, `_pick_target`, `pick_spell`), nav routing, follow-the-leader, roles (tank front, healer heals, ranged perches) |
| `scripts/scaling.gd` | `Scaling`: mob stats by level, XP by level difference, party XP share, level label colors |
| `scripts/mob.gd` | Mobs: wander/aggro (aggro_range), knockback clamped to their platform (knockback_mult), resists, status effects, shapes and level label |
| `scripts/combat.gd` | All damage, element, resist and combo rules. Every hit goes through `Combat.hit()` |
| `scripts/nav.gd` | Nav graph: surfaces + links (jump_up, jump_across, walk_off, drop), Dijkstra routes |
| `scripts/world.gd` | Loads maps from `data/maps.json`, portals and travel, respawn queue, party list, kill XP (`award_xp`) |
| `data/maps.json` | Maps: platforms, spawns, portals, level range, theme colors and decor |
| `scripts/projectile.gd`, `scripts/fx.gd` | Bolts, lobs, kunai; lightning and burst effects |
| `scripts/hud.gd` | Bottom bar, skill bar, controls panel (F1), debug overlay |
| `scripts/game_input.gd` | All key and controller bindings in one place |
| `data/balance.json` | Every tuning number: player, weapons, mobs, spells, elements |
| `tests/smoke_test.gd` | Movement, platforms, weapons, auto-battle, pathing, target focus |
| `tests/magic_test.gd` | Statuses, combos, spells, mana, pacing, kunai, weaving |
| `tests/world_test.gd` | Every map's data (reachable, connected, valid spawns, two-way portals), portal travel, scaling, XP rules, resists |
| `tests/party_test.gd` | Sims: spawn, follow onto platforms, role positions, heal, ranged perch, XP share, loot, fighting, knockout, portal |
| `tests/items_test.gd` | Inventory stacking, potions, best-potion pick, XP tonics and expiry, loot and min_level, auto-potions, R hotkey, I window clicks |

## Gotchas learned the hard way

- **Tests must not name game classes directly** (`Mob`, `World`, `Combat`, ...). A `--script` SceneTree compiles them before the `Log` autoload exists, and everything fails with "Identifier not found: Log". Use untyped vars, or `load("res://scripts/x.gd")` at runtime (see magic_test.gd).
- **New `class_name` scripts** need a re-import before running from the terminal. `run.sh` does this automatically when a .gd is newer than `.godot/global_script_class_cache.cfg`; in CI run `godot --headless --import --path .` first.
- **Run tests with `--fixed-fps 60`.** Without it headless runs in real time (a 1.5 s suite becomes a minute).
- **GDScript `:=` can't infer from Variants** (dictionary values, `lerp`, `max` on mixed types). Use explicit types (`var x: float = ...`) or the typed functions (`lerpf`, `maxf`, `signf`).
- **Reusing a mob in a test:** Clear `world._respawn_queue` first, or a pending respawn from an earlier death resets it mid-test. Also reset `max_hp`, since earlier phases set some to 99999.
- **Camera2D offsets ignore limits.** Don't use `offset` to frame the ground; use `limit_bottom`.
- **HUD Control under a CanvasLayer** needs `set_anchors_and_offsets_preset(PRESET_FULL_RECT)`, or anchored children end up off screen.
- **Keep the screen center clear:** The camera centers the player, so HUD pieces go to the edges.
- **Mob test dummies:** Set `data.speed`, `data.hop_velocity` and `data.touch_damage` to 0 on a duplicated `data` dict, then `set_bounds(world.nav)` and `respawn()`. If sims are around, also set `data.knockback_mult = 0` or the tank's hammer pushes the dummy out of the test.
- **Solo tests:** Set `_main.spawn_sims = false` before `root.add_child(_main)`, or the sims steal kills and XP.
- **Map changes are deferred:** `world.travel()` runs at the end of the frame (freeing physics bodies mid-physics is unsafe). Wait a few frames before checking. Map pieces live under `World/Map`; anything else under World that isn't in the `persist` group (actors, debug draw) is freed on travel.
- **Mob levels are rolled** (`level_spread`), so a test that needs an exact level should set `mob.data = world.mob_data(id, level)` and `mob.level` itself.
- **Fixed seeds hide flakes:** A check that passes on the default seed can fail on others (happened twice in M1: a mob parked next to a mid-jump player, and combo dummies that were only "tough" for a level 1 player). Loop `SIMMO_SEED`.

## Rules the game currently follows (keep them unless the owner changes them)

- Auto-battle: manual input takes over movement but auto keeps swinging at anything in front; resumes 0.4 s after input stops with a fresh target; sticks to wounded targets; finishes wounded mobs first; gives up on unreachable ones after 5 s; routes with the nav graph; weaves weapon attacks between spells; combo finishers (lightning on frozen, fire on 3+ poison) beat a weapon swing; with a thrown weapon it closes to 60% of max range.
- Spells: 1 s global cooldown, per-spell cooldowns (4 / 5 / 3 / 9 s), a cast locks the weapon 0.4 s, attacking locks casting 0.3 s.
- Weapon DPS stays within about 30% across weapons at levels 1, 10 and 30 (tested).
- Knockback never pushes mobs off their platform.
- Every platform must be reachable by a real jump, on every map (tested).
- Mobs keep their map's level; they don't scale to the player. Stats follow the player's curves, so same-level fights feel the same at every level (tested). XP: full within 3 levels under, then -15% per level down to 10%; +5% per level above, up to +30%.
- Kills per level on fitting mobs start around 8 and grow slowly, 45 at most by Lv 21 (tested). Player curve: `32 * L^1.8`. A full auto party gains about 3 levels in its first minute, then about 1 level a minute or less by the Grove. Listed mob XP follows `4 * level^1.3 * toughness`; keep that rule for new mobs.
- Portals never block travel. Under the map's minimum level the label and hint turn orange; 5+ under turns them red; entering shows a warning banner.
- XP buffs multiply kill XP and don't stack (one "xp" buff; a weaker one is refused). Loot from any party kill goes to the player's inventory.
- Party XP: each member on the map gets `xp * (1 + 0.2 * (n - 1)) / n`, adjusted for their own level.
- Sims stay within 220 px of the leader, only fight mobs within 260 px of the leader, heal under 65% HP, and revive next to the leader 5 s after a knockout.

## Backlog, in order

1. **Items follow-ups:** Ground drops with pickup (auto-battle would need to path to them); a potion shop in town and mesos/currency; equipment (weapons as items, stats); sims with their own inventories and potions; save the inventory (with M2 save/load).
2. **M1 follow-ups:** Mob aggro should prefer the tank (taunt); sims chat lines; more hair styles, hats and outfits for paper dolls; name tags overlap when sims bunch up; the party frames don't show MP; sims don't pick up the player's weapon or level changes after joining beyond XP.
3. **Away loop (M2):** Save/load (versioned, autosave), abstract simulation tick for off-screen sims, offline progress = abstract ticks for elapsed time (clamped), guild report screen.
4. **Mobile:** Touch controls (virtual stick, jump, attack, skill buttons, AUTO), safe areas, Android export first, then iOS. Test on the Galaxy Z Fold 6 (folded and unfolded) and iPhone 17 Pro Max.
5. **Maps:** Town services (shops, NPCs) in Mossy Meadow; a boss room at the end of Frostpeak; portals on platforms (supported in data via `y`, not used yet).
6. **Polish found while testing:** Projectiles ignore platforms (they only stop at the target's floor height); lobbed globs can't splash on a platform with no mob on it; controller spell bindings (B / LB / L3 / R3) are temporary until a skill menu exists; the bottom bar is tight at 640 px wide.
7. Later (see design doc): Guild system, trading with sims, chat (quick-chat + intent parser), tavern bartender mini-game, raids, world bosses, fake patch days.
