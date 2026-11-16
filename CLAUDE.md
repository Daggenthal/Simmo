# Simmo: notes for Claude Code

Simmo is an offline "fake MMO" in Godot 4.7: MapleStory-style side view, simulated players (the owner calls them **Simmos**; `SimPlayer` in code) who party, guild and trade with you, and idle progress while you're away. Repo: github.com/Daggenthal/Simmo. The full design lives in the design doc "Simulated MMO Idle Game: Design Doc" (ask the owner for the link if you need it).

Current state: milestone M1. Everything is drawn and synthesized in code (no art or audio files). Rendering: 640x360 world units drawn at window resolution (`canvas_items` stretch, integer scale): 720p / 1080p / 1440p / 4K are exact 2x / 3x / 4x / 6x. The window defaults to the biggest that fits the screen (Settings: window size, fullscreen, VSync, FPS cap, FPS counter). FPS is uncapped by default; gameplay runs on the fixed 60 Hz physics tick with physics interpolation, and `tests/fps_probe.gd` proves 30 / 60 / 144 / 240 fps play out identically.
- Start: class select (Warrior / Mage / Rogue), then a MapleStory-style character creator (gender, skin, face, eyes, hair style and color, top, bottom, shoes, hat, cape, name).
- Combat: class-locked weapons, four skills per class, a 60 s ultimate each, STR / DEX / INT / LUK with AP and auto-assign, element combos, auto-battle with nav-graph pathing (mages fight from range), auto-potions, auto-advance to the next map.
- World: four maps with portals and a .hack-style warp, mobs and XP scaled by level, zone bosses after 30 kills (HP bar, enrage timer, telegraphed slams) that drop Diablo-style rarity chests with equippable gear. Day / night, rain, storms, snow that builds up and takes footprints, ponds with ripple physics, bridges, swaying grass and trees, 2D lights with shadows and rim light on characters.
- Party: 3 Simmos (tank, healer, ranged) share the auto-battle brain, follow you across platforms and through portals, assist your target, dodge boss slams, use ultimates, carry potions, trade with you, chat in party chat and speech bubbles. Roster with invite and kick.
- UI: HUD with cooldown timers, chat box with tabs and colored channels, inventory (I), stats (K), trade (T), Esc pause menu (settings with volume sliders, inventory and equipment, party).
- Sound: every effect and ambience synthesized at runtime (`Sfx` autoload).

## How to work on this repo

**The loop:** Reproduce, write a failing test, fix, run the full suite several times, look at a screenshot when anything visual changed. Every bug fixed so far got a regression test first; keep doing that. When a test passes without your fix, the test is not reproducing the bug yet (this happened twice; see Gotchas).

```
./run.sh test     # all twelve headless suites, about a minute, exit 0 = pass
./run.sh rendercheck   # draws every screen for real, fails on engine errors (needs a display)
SIMMO_SEED=3 ./run.sh test   # same with another seed; loop a few seeds to catch flaky checks
./run.sh          # play
./run.sh debug    # hitboxes, debug overlay, full logging
./run.sh editor   # Godot editor
```

Run the suite at least 5 times after AI or physics changes, with different `SIMMO_SEED` values (the tests use fixed seeds, so plain reruns repeat the same game); flaky checks are bugs (in the game or the test).

Screenshots for layout checks (needs a display; on macOS just run it, on Linux use `xvfb-run -a`):
```
godot --path . --rendering-driver opengl3 --script res://tools/screenshot.gd -- 1280x720   # also 2560x1080, weapon=dagger, class=mage, map=ember_crags, level=15, start (class select screen)
godot --path . --rendering-driver opengl3 --script res://tools/screenshot_magic.gd          # staged status effects
godot --path . --rendering-driver opengl3 --script res://tools/screenshot_world.gd -- night_lights   # also day_pond, storm, snow
godot ... screenshot_dolls.gd (characters, zoomed) / screenshot_creator.gd / screenshot_warp.gd / screenshot_menu.gd / screenshot_boss.gd / screenshot_items.gd / screenshot_portal.gd
```
Boss balance probe (full auto party vs each boss at its level; kill time vs the 90 s enrage, knockouts, deaths):
```
SIMMO_CLASS=mage godot --headless --fixed-fps 60 --path . --script res://tools/boss_probe.gd
```
Soak run (real game, party + auto-battle, 60 s per map; look for SCRIPT ERROR and the per-map kill/level lines):
```
godot --headless --fixed-fps 60 --path . --script res://tools/soak.gd
```
Output goes to `screenshots/` (gitignored), now at the window's full resolution. Software rendering is slow: if mobs look white/frozen in a shot, it was captured too early, wait more frames. A screenshot window takes keyboard focus while it runs; keys typed elsewhere can land in the game.

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
| `main.tscn`, `scripts/main.gd` | Entry: class select -> creator -> `start_game` builds weather, world, player, party, camera, sky, HUD, chat, trade, pause menu; global hotkeys; invite / kick |
| `scripts/actor.gd` | `Actor`: body shared by player and Simmos. Intent-driven movement, class (`set_class`), stats / AP / gear (`stat`, `gear_mod`, `equip_slot`), skills (bolt, lob, chain, heal, strike, slam, volley, dash, buff), ultimates (channel, cataclysm, quake, shadow, sanctuary), buffs, inventory and items, warp, footsteps, speech bubbles, damage tracking |
| `scripts/doll.gd` | `Doll`: paper-doll renderer at 2x density, spring chains for hair and cloth (wind + motion), blinking, walk cycle, rim light from `Lighting` |
| `scripts/player.gd` | `Player extends Actor`: input, auto-battle toggle and override, auto-potions, chest looting, auto-advance |
| `scripts/sim_player.gd` | `SimPlayer extends Actor`: role setup (class, weapon, skills, ultimate), knockout and revive, own potions |
| `scripts/brain.gd` | `Brain`: auto-battle (`think`, `_pick_target`, `pick_spell`), nav routing, follow, roles (tank front, healer heals, ranged perches and prefers targets in reach), assist the leader's target, caster range play, ultimates, boss focus, slam dodging |
| `scripts/mob.gd` | Mobs: aggro, resists, knockback, statuses, stun, shapes, level label; bosses (chase, slam telegraph, enrage) |
| `scripts/combat.gd` | All damage, element, resist and combo rules; hit sounds, combat log, damage_dealt. Every hit goes through `Combat.hit()` |
| `scripts/world.gd` | Maps from `data/maps.json`, portals and warp travel, respawns, party, kill XP and loot, boss spawning, chests, platform light occluders |
| `scripts/environment.gd` | `MapEnvironment`: trees, grass, snow height field and footprints, water wave sim and wading, bridges, lamps, rain and snow particles |
| `scripts/weather.gd`, `scripts/weather_state.gd`, `scripts/sky_art.gd` | Time of day, weather state machine, wind, world tint (CanvasModulate), lightning; sun, moon, stars |
| `scripts/lighting.gd` | `Lighting`: PointLight2D helpers (`add`, `flash`), registry for rim light (`near`), darkness |
| `scripts/sfx.gd` | `Sfx` autoload: every sound synthesized (hits, steps, casts, warps, thunder, rain / wind loops), volumes |
| `scripts/nav.gd`, `scripts/scaling.gd` | Nav graph and Dijkstra routes; mob stats, XP rules, party share |
| `scripts/inventory.gd`, `scripts/inventory_ui.gd` | `Inventory` (stacks and one-of-a-kind items) and the I window (use / equip, icons, tooltips) |
| `scripts/gear.gd`, `scripts/chest.gd` | Diablo-style loot generation (rarities, affixes, legendaries) and the boss chest |
| `scripts/trade.gd`, `scripts/trade_ui.gd` | Trade rules (`sim_verdict`, all-or-nothing `execute`) and the T window |
| `scripts/chat_log.gd`, `scripts/chat_box.gd`, `scripts/chatter.gd` | Chat store and channels, the chat box with tabs, fake chat and Simmo reactions |
| `scripts/start_screen.gd`, `scripts/creator_screen.gd` | Class select and character creator |
| `scripts/hud.gd`, `scripts/stats_ui.gd`, `scripts/pause_menu.gd` | HUD (bars, skills with cooldown timers, ultimate, party frames, boss bar, banners, flash), K window, Esc menu (settings saved to user://settings.cfg) |
| `scripts/projectile.gd`, `scripts/fx.gd`, `scripts/float_text.gd` | Bolts, lobs, kunai (with lights, target leading); lightning, bursts, cones, afterimages, warp rings |
| `scripts/game_input.gd`, `scripts/log.gd` | Key and controller bindings; colored logging |
| `data/*.json` | `balance` (tuning), `maps`, `items`, `loot`, `appearance`, `chat` |
| `assets/sprites/<name>/` | PixelLab sprites: stills (`east.png`, `west.png`, `south.png`) and east-facing clips in `anims/<anim>/frame_NNN.png` (idle, walk, jump, attack_slash / _stab / _throw / _cast; west mirrors). A look with `"sprite": "<name>"` draws them instead of the code-drawn doll (creator rows "Sprite (test)" and "Sprite hair") |
| `tests/*.gd` | smoke, magic, world, party, items, class, combat_ai, social, environment, menu, boss, sprite |
| `tools/*.gd` | Screenshots, `soak.gd`, `boss_probe.gd` |

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
- **The start screen:** Tests and tools must set `_main.show_start_screen = false` and `_main.start_class` before `add_child`, or `player` and `world` stay null. Use `player.switch_to_weapon_class(id)` to test a weapon outside the current class.
- **Stats come from AP:** Setting `player.level` directly leaves stats (and damage) at the old level. Use `player.set_level(n)`, which re-spends AP and refills HP/MP.
- **Map changes are deferred:** `world.travel()` runs at the end of the frame (freeing physics bodies mid-physics is unsafe). Wait a few frames before checking. Map pieces live under `World/Map`; anything else under World that isn't in the `persist` group (actors, debug draw) is freed on travel.
- **Mob levels are rolled** (`level_spread`), so a test that needs an exact level should set `mob.data = world.mob_data(id, level)` and `mob.level` itself.
- **Saved settings:** Tests and tools set `_main.load_user_settings = false`: the user's saved settings don't change their results, and `pause_menu.persist` is off so they never write `user://settings.cfg` (this once overwrote the owner's settings file). A test that checks saving must use its own `settings_path` and turn `persist` off again before it closes the menu.
- **Kills are last hits:** The player often lands the last hit, so judge Simmo contribution by `damage_dealt`, not `kills`.
- **Warp travel takes time:** Portals warp out for `warp.out_time` (1.2 s) before the map changes; wait about 90 frames after pressing Up.
- **Doll chains need points before drawing:** `Doll.set_look` lays chains out immediately; a new chain added elsewhere must call `_reset_chains()`.
- **Typed loop vars:** `for side in [-1.0, 1.0]` gives a Variant; `var a := side * x` then fails to parse. Write `for side: float in [...]`.
- **Headless tests can't see render errors.** Polygons the renderer can't fill ("Invalid polygon data, triangulation failed") only show up when drawing for real. Run `./run.sh rendercheck` (needs a display) after visual changes, and don't filter `ERROR:` lines out of screenshot output. Cloth from physics chains must be drawn as quad strips (`Doll._ribbon`), never one polygon: chains cross when cloth folds.
- **"ObjectDB instances were leaked at exit" from the screenshot tools** is audio playbacks still running when a tool quits mid-sound (engine shutdown order). Harmless and tool-only; the game's normal exit is clean.
- **Frame rate independence:** Anything that changes game state runs in `_physics_process` (fixed 60 Hz). `_process` is for visuals only and must never touch the global RNG (use a private `RandomNumberGenerator`, like `Chatter.rng` and `MapEnvironment._rng`), or frame rate shifts every later crit and loot roll. After a teleport call `reset_physics_interpolation()`. `./run.sh test` runs the FPS probe at four rates and compares fingerprints.
- **Doll art:** MapleStory style built from convex pieces: `_shape` (fill + antialiased outline in `_ol(color)`), `_ellipse`, `_capsule`, `_rrect`, `_lock` for hair locks, `_strand` for physics hair, `_ribbon` for cloth. Keep every filled polygon convex or simple; anything built from physics points goes through `_ribbon` or `_strand`. Hair and hats must stop above the eyes (cap hairline at y -6 on the face side).
- **PixelLab sprites:** Generated with the PixelLab MCP (side view, standard mode, 64 px = 1 generation; the owner's trial has 40). They come with a near-white fringe from background removal; `Doll._clean_sprite` turns near-white edge pixels into the dark outline at load. Drawn at 0.5 world px per sprite px (64 px tall = 32 world px), so they're pixel-exact at 1440p and 4K and slightly uneven at 1080p. `run.sh` re-imports when a .png is newer than the class cache.
- **Sprite animations:** `Doll` picks the clip from state (attack by weapon via `Actor.sprite_attack()`: thrown = throw, `motion: thrust` = stab, `spell_power` = cast, else slash; then jump by `vy`, walk by `walk` phase, idle). Each clip anchors at the feet of its own first frame, because v3 clips come on bigger canvases (112 px). Squash / stretch and lean are code-side springs (`_tick_sprite`, `jolt`). Sprites never get the drawn weapon (`draws_weapon()`); slashes and stabs get a fading trail. `sprite_hair` is a palette swap over the hair's hue window (0.94 to 0.985, saturation 0.3 to 0.72, value 0.55+), tuned so the dress and boots stay put; a new sprite needs its own window. Check `tools/screenshot_sprite_anims.gd` after adding clips: PixelLab templates sometimes turn the character around (the fireball wind-up did; those frames were dropped).
- **PixelLab budget:** The trial runs one job at a time (queue the next after `wait_for_jobs`). Template clips cost 1 per direction, v3 at this size 1 to 2; generate east only and mirror. `create_character_state` (outfits) costs 10, a new `create_character` 1.
- **Fixed seeds hide flakes:** A check that passes on the default seed can fail on others (happened twice in M1: a mob parked next to a mid-jump player, and combo dummies that were only "tough" for a level 1 player). Loop `SIMMO_SEED`.

## Rules the game currently follows (keep them unless the owner changes them)

- Auto-battle: manual input takes over movement but auto keeps swinging at anything in front; resumes 0.4 s after input stops with a fresh target; sticks to wounded targets; finishes wounded mobs first; gives up on unreachable ones after 5 s; routes with the nav graph; weaves weapon attacks between spells; combo finishers (lightning on frozen, fire on 3+ poison) beat a weapon swing; with a thrown weapon it closes to 60% of max range.
- Spells: 1 s global cooldown, per-spell cooldowns (4 / 5 / 3 / 9 s), a cast locks the weapon 0.4 s, attacking locks casting 0.3 s.
- Weapon DPS stays within about 30% across weapons at levels 1, 10 and 30, each in the hands of its own class with auto-assigned stats (tested). Staffs are excluded: they hit softly and boost INT spells by `spell_power`.
- Classes: only a class's own weapons can be equipped. Damage bonus = points of the attack's stat above the class start x `damage_per_point` (1.25) x cooldown / 0.8; auto-assign (4 main + 1 secondary per level) reproduces the old 5-per-level curve, so mob scaling still lines up.
- Auto-advance: with auto-battle on and `auto_advance_zones` true, reaching the next map's minimum level walks to its portal. Only forward, never back.
- Knockback never pushes mobs off their platform.
- Every platform must be reachable by a real jump, on every map (tested).
- Mobs keep their map's level; they don't scale to the player. Stats follow the player's curves, so same-level fights feel the same at every level (tested). XP: full within 3 levels under, then -15% per level down to 10%; +5% per level above, up to +30%.
- Kills per level on fitting mobs start around 8 and grow slowly, 45 at most by Lv 21 (tested). Player curve: `32 * L^1.8`. A full auto party gains about 3 levels in its first minute, then about 1 level a minute or less by the Grove. Listed mob XP follows `4 * level^1.3 * toughness`; keep that rule for new mobs.
- Portals never block travel. Under the map's minimum level the label and hint turn orange; 5+ under turns them red; entering shows a warning banner.
- XP buffs multiply kill XP and don't stack (one "xp" buff; a weaker one is refused). Loot from any party kill goes to the player's inventory.
- Party XP: each member on the map gets `xp * (1 + 0.2 * (n - 1)) / n`, adjusted for their own level.
- Sims stay within 220 px of the leader, only fight mobs within 260 px of the leader (bosses anywhere), heal under 65% HP, and revive next to the leader 5 s after a knockout. Ranged and healer assist the leader's target; ranged prefer targets already in reach and only climb to a perch that's a short hop away.
- Priest (role healer, Simmo or player): Prayer when 2+ allies are under 70%, Heal under 55%, Renew (HoT) under 90% if it isn't on them; otherwise Smite the leader's target from where it stands. Stays ~95 px back, steps away from close mobs, never melees. Everyone in a party assists the leader's target, and every non-healer swings at a mob in front whenever its weapon is ready.
- Mages (INT classes) keep ~110 px from their target and back off under 70 px; they melee only when every attack spell is on cooldown or out of MP.
- Ultimates: 60 s cooldown, G only (not Shift: too easy to hit by accident). Auto-battle fires them on 3+ mobs nearby or a target with 6+ hits of HP left; the healer's Sanctuary fires when someone drops under 25% or two under 50%. Damage scales with `scale_cooldown`, not the 60 s.
- Bosses: spawn after 30 kills on the map, immune to freeze and stun, enrage at 90 s (x2.5 damage, x1.6 speed, slams twice as often). A full auto party at the boss's level kills it in about 60-80 s (`tools/boss_probe.gd`). Auto-battle loots the chest and won't auto-advance while a boss or chest is pending.
- Loot rarity weights: junk 28, common 30, magic 24, rare 12, epic 5, legendary 1. Gear base: 60% a weapon of the player's class. Gear can't be traded yet.
- Chat: party lines are rate-limited (8 s per Simmo, 2.5 s party-wide) except forced events (join, level up, ultimate, map, out of potions).

## Backlog, in order

1. **Loot follow-ups:** Unequip; a vendor to sell junk and buy potions (currency); trading gear with Simmos; Simmos wearing gear; equipment shown on the paper doll; gear saved with M2.
2. **Party follow-ups:** Taunt (boss aggro on the tank); Simmos sometimes idle in fast trash fights because the player outpaces them; party frames don't show MP; mage parties kill trash faster than the other classes (map-wide ultimate).
3. **Away loop (M2):** Save/load (versioned, autosave) including look, class, gear, inventory and settings; abstract simulation tick for off-screen Simmos; offline progress; guild report screen.
4. **Mobile:** Touch controls (virtual stick, jump, attack, skills, ultimate, AUTO), safe areas, Android first, then iOS. Test on the Galaxy Z Fold 6 (folded and unfolded) and iPhone 17 Pro Max. Check lighting and shadows' cost on phones (`Lighting.enabled` turns lights off).
5. **Maps:** Town services and NPCs; a dark cave map to show off lighting; boss rooms; portals on platforms (supported in data via `y`).
6. **Polish found while testing:** Projectiles ignore platforms; controller bindings for the ultimate, trade and menus; chat typing (Enter to talk, Simmos answer); more hair styles, hats and outfits.
7. Later (see design doc): Guild system, chat intent parser, tavern bartender mini-game, raids, world bosses, fake patch days.
