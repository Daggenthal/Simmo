# Simmo

An offline fake MMO: MapleStory-style side view, simulated players (Simmos) who party, chat and trade with you, and guilds that keep playing while you're away. Milestone M1: classes and character creation, four maps with portals, a party of Simmos, zone bosses with loot, weather and day / night, all drawn and synthesized in code (no art or audio files).

## Run it

Needs Godot 4.7 or newer: `brew install --cask godot`

```
./run.sh          # play
./run.sh debug    # play with debug mode (hitboxes, overlay, full logging)
./run.sh editor   # open in the Godot editor
./run.sh test     # all headless test suites (SIMMO_SEED=n to vary the seed)
```

## Controls

| Action | Keyboard | Controller |
| --- | --- | --- |
| Move | Arrows or WASD | Left stick or D-pad |
| Jump | Alt or Space | A / Cross |
| Attack | Ctrl or J | X / Square |
| Drop through platform | Down + Jump | Down + A |
| Class skills 1 to 4 | Z / X / C / V | B / LB / L3 / R3 |
| Ultimate (60 s cooldown) | G | |
| Switch weapon (your class's) | 1 / 2, or E to cycle | RB / R1 |
| Auto-battle on / off | Q or Tab (or the AUTO button) | Y / Triangle |
| Enter a portal, open a chest | Stand on it + Up | Up |
| HP potion / MP potion | R / F | |
| Inventory window (click to use or equip) | I | |
| Stats window (spend AP, auto-assign) | K | |
| Trade with a party member | T | |
| Chat tabs (All / Chat / Combat) | Y | |
| Party on / off | P | |
| Pause menu (settings, inventory, party) | Esc | |
| Show / hide controls | F1 | Start / Options |
| Debug overlay | F3 | Back / Share |
| Respawn all mobs | F5 | |

## Starting out

1. Pick a class. The select screen lists each class's weapons (and how they attack) and all four skills.
2. Create your character: name, gender, skin, face, eyes, hair style and color, top, bottom, shoes, hat, cape and their colors. The preview blinks, walks and shows hair and cloth in the wind.
3. Play. Auto-battle (Q) fights, drinks potions and moves on to the next map once you reach its level.

## Classes

Each class only uses its own weapons, has four skills and an ultimate:

| Class | Main stat | Weapons | Skills | Ultimate |
| --- | --- | --- | --- | --- |
| Warrior | STR | Short Sword (start), Iron Hammer | Power Strike, Ground Slam, War Cry (+25% damage), Charge (dash through mobs) | Titan's Wrath: leap and quake, stuns everything nearby, then Berserk (+50% damage) |
| Mage | INT | Oak Staff (+20% spell damage) | Fireball, Frost Bolt, Venom Glob, Chain Lightning | Arcane Cataclysm: a short channel, then a fire cone and lightning on every mob on the map |
| Rogue | DEX | Dagger (start, stabs), Throwing Kunai | Lucky Seven (2 kunai), Venom Glob, Flurry (3 stabs), Haste (+30% attack speed) | Shadow Dance: vanish and blink between up to 8 mobs, 3 strikes each |

Mages fight from range: they keep their distance and only walk in to melee when every spell is on cooldown. Skill slots show the seconds left on each cooldown.

Stats: STR, DEX, INT, LUK. Every attack scales with its own stat; STR adds HP, INT adds MP, DEX and LUK add crit, LUK raises item drops. Each level gives 5 AP; auto-assign (on by default) spends 4 on the main stat and 1 on the secondary. Turn it off in the stats window (K) to spend them yourself.

Magic combos: frost on a frozen mob crits more; lightning on a frozen mob always crits, splashes and shatters the ice; fire on a poisoned mob ignites the poison. Kunai carry the element of your last spell at half strength.

## Maps and mobs

| Map | Levels | Mobs | Boss |
| --- | --- | --- | --- |
| Mossy Meadow (town) | 1 to 5 | Green Slime, Blue Slime, Grumpy Stump | Slime Monarch (Lv 7) |
| Mushroom Grove | 6 to 12 | Orange Shroom, Horny Shroom, Wild Boar | Elder Sporecap (Lv 13) |
| Ember Crags | 13 to 20 | Fire Imp (resists fire), Lava Slime, Rock Golem | Cinder Colossus (Lv 21) |
| Frostpeak Ruins | 21 to 30 | Frost Slime (resists frost), Skeleton (resists poison), Ice Golem | Bone Warden (Lv 31) |

Portals show the destination's level range in a color for your level, and entering a map above you shows "Warning! Mobs here are N levels above you". Travel is a .hack-style warp: rings around the party, a shimmering sound, then the new map.

Mob HP grows with player damage, so a mob at your level always takes about the same number of hits. XP drops off on mobs more than 3 levels under you and grows a little on mobs above you. Kills per level start around 8 and grow slowly.

## Zone bosses

After 30 kills on a map its boss appears: big, with an HP bar and an enrage timer across the top. Beat it in 90 seconds or it enrages (much harder hits, faster, more slams). It telegraphs a ground slam with a red ring; jump to dodge it (auto-battle and Simmos do). Bosses ignore freeze and stun. A full party takes about a minute.

The boss drops a chest that glows in the color of its best item. Loot is Diablo style:

| Rarity | Color | Bonuses |
| --- | --- | --- |
| Junk | Gray | None, vendor trash |
| Common | White | Base bonus only |
| Magic | Blue | +1 affix |
| Rare | Yellow | +2 affixes |
| Epic | Purple | +3 affixes |
| Legendary | Orange | +4 affixes, a unique name and a special bonus |

Gear (weapons for your class, rings, amulets) rolls STR / DEX / INT / LUK, damage %, crit %, HP and MP, stronger from higher-level bosses. Click it in your bag to equip.

## Party (Simmos)

Three Simmos join you: Brannoc (Warrior tank), Liriel (Mage healer with Heal and Sanctuary) and xXKunaiXx (Rogue ranged). They follow you across platforms and through portals, fight by role (the tank in front, ranged and healer on your target, the ranged climbing onto platforms), use their ultimates, drink their own potions and ask for more when they run out. Kill XP is split with a party bonus. Invite and kick from the pause menu's Party tab; Goldvein and Fennick wait on the roster.

Trade with T: click your items to offer, theirs to ask. Simmos accept gifts and fair deals and keep a couple of potions for themselves. They talk in party chat and in speech bubbles, without spamming.

## Items

24-slot bag, potions and tonics stack. Red / White Potions (HP), Blue Potion (MP), Scholar's Tonic (+20% XP for 10 min), Sage's Elixir (+50% XP). Mobs drop potions and tonics; bosses drop gear. Auto-battle drinks a potion under 35% HP or 20% MP.

## Chat

Bottom left, with tabs: All (no damage spam), Chat, Combat. Colors: white local (passers-by), blue party, yellow system, green XP, cyan loot (gear in its rarity color), orange your damage and kills, pink trades, red warnings.

## World

Day and night (8 minutes), with sun, moon and stars. Weather cycles through clear, cloudy, rain and storms with lightning and thunder; Frostpeak snows. Snow builds up on the ground and platforms and takes footprints. Ponds ripple when you wade through them (slower), rivers and lava have plank bridges. Grass and trees sway in the wind, and hair, capes and skirts move with it too. Lights: spells carry their own light, lightning lights its path, lamps glow at night, platforms cast shadows, and light catches the edges of characters.

Characters blink now and then, walk with a swing, tuck their legs when jumping, and have hair and cloth physics.

## Sound

Every sound is synthesized in code: hits, crits, swings, footsteps, jumps, landings, spell casts by element, potions, loot, level ups, ultimates, warps, splashes, boss roars, the chest, thunder, and rain and wind ambience. The pause menu has master, effects and ambient volume and mute.

## Layout

| Path | What |
| --- | --- |
| `data/balance.json` | Tuning: player, classes, weapons, skills, mobs and bosses, scaling, party, Simmo roster, environment |
| `data/maps.json` | Maps: platforms, spawns, portals, water, lamps, trees, climate, colors |
| `data/items.json` | Potions, tonics, loot table, starter kits, trade rules |
| `data/loot.json` | Boss loot: rarities, gear bases, affixes, legendary names |
| `data/appearance.json` | Character creator options |
| `data/chat.json` | Fake chat lines and chat colors |
| `scripts/` | Game code (see CLAUDE.md for the map of files) |
| `tests/` | Headless test suites, run by `./run.sh test` |
| `tools/` | Screenshots, soak run, boss balance probe |

## Logging and debug mode

Colored terminal output: red errors, yellow warnings, green success, cyan traces. Plain text in saved logs. `SIMMO_NO_COLOR=1` turns colors off. Debug mode (`SIMMO_DEBUG=1`, `./run.sh debug` or F3) shows hitboxes and the overlay, logs every hit, and keeps running through errors.

## License

MIT
