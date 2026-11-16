#!/usr/bin/env bash
# Simmo runner.
#   ./run.sh            play the game
#   ./run.sh debug      play with debug mode on (full logging, hitboxes, F3 overlay)
#   ./run.sh editor     open the project in the Godot editor
#   ./run.sh test       run all headless test suites (SIMMO_SEED=n to vary the seed)
#   ./run.sh rendercheck  draw every screen for real and fail on engine errors (needs a display)
# Env: GODOT=/path/to/godot to pick a binary, SIMMO_NO_COLOR=1 for plain output.

set -uo pipefail
cd "$(dirname "$0")"

if [[ -t 1 && -z "${SIMMO_NO_COLOR:-}" ]]; then
	RED=$'\e[31m'; YELLOW=$'\e[33m'; GREEN=$'\e[32m'; CYAN=$'\e[36m'; RESET=$'\e[0m'
else
	RED=""; YELLOW=""; GREEN=""; CYAN=""; RESET=""
	export SIMMO_NO_COLOR=1
fi

find_godot() {
	if [[ -n "${GODOT:-}" ]]; then echo "$GODOT"; return; fi
	for c in godot godot4; do
		if command -v "$c" >/dev/null 2>&1; then command -v "$c"; return; fi
	done
	for c in "/Applications/Godot.app/Contents/MacOS/Godot" "$HOME/Applications/Godot.app/Contents/MacOS/Godot"; do
		if [[ -x "$c" ]]; then echo "$c"; return; fi
	done
}

GODOT_BIN="$(find_godot)"
if [[ -z "$GODOT_BIN" ]]; then
	echo "${RED}Godot not found.${RESET} Install it with: ${CYAN}brew install --cask godot${RESET}"
	echo "${YELLOW}Or set GODOT=/path/to/Godot${RESET}"
	exit 1
fi
echo "${GREEN}Using Godot:${RESET} $GODOT_BIN ($("$GODOT_BIN" --version 2>/dev/null | head -1))"

# Import on first run, and again whenever a script is newer than Godot's class cache,
# so new class_name scripts resolve when running from the terminal.
CACHE=.godot/global_script_class_cache.cfg
if [[ ! -f "$CACHE" ]] || [[ -n "$(find . -name '*.gd' -newer "$CACHE" -not -path './.godot/*' -print -quit)" ]]; then
	echo "${YELLOW}Scripts changed, re-importing project...${RESET}"
	"$GODOT_BIN" --headless --import --path . >/dev/null 2>&1
	touch "$CACHE"
fi

case "${1:-play}" in
	play)   exec "$GODOT_BIN" --path . ;;
	debug)  SIMMO_DEBUG=1 exec "$GODOT_BIN" --path . -- --debug-game ;;
	editor) exec "$GODOT_BIN" --editor --path . ;;
	test)
		code=0
		for t in smoke_test magic_test world_test party_test items_test class_test combat_ai_test social_test environment_test menu_test boss_test; do
			"$GODOT_BIN" --headless --fixed-fps 60 --path . --script "res://tests/$t.gd"
			c=$?
			if [[ $c -eq 0 ]]; then echo "${GREEN}$t passed${RESET}"; else echo "${RED}$t failed (exit $c)${RESET}"; code=1; fi
		done
		# Frame rate independence: the same scenario must end exactly the same at any FPS.
		ref=""
		fps_ok=1
		for fps in 30 60 144 240; do
			fp="$("$GODOT_BIN" --headless --fixed-fps $fps --path . --script res://tests/fps_probe.gd 2>&1 | grep '^FINGERPRINT')"
			if [[ -z "$ref" ]]; then ref="$fp"; elif [[ "$fp" != "$ref" ]]; then
				fps_ok=0
				echo "${RED}fps $fps differs:${RESET} $fp"
				echo "${YELLOW}  vs 30 fps:${RESET} $ref"
			fi
		done
		if [[ -n "$ref" && $fps_ok -eq 1 ]]; then echo "${GREEN}fps_probe passed (30 / 60 / 144 / 240 fps play out identically)${RESET}"; else echo "${RED}fps_probe failed${RESET}"; code=1; fi
		exit $code ;;
	rendercheck)
		# Draws every screen for real (needs a display; on Linux: xvfb-run -a ./run.sh rendercheck)
		# and fails on any engine error, e.g. a polygon the renderer can't fill. Headless tests can't see these.
		code=0
		runs=("screenshot.gd -- 1280x720 start" "screenshot_creator.gd" "screenshot_dolls.gd" "screenshot_boss.gd" "screenshot_menu.gd" "screenshot_items.gd" "screenshot_warp.gd" "screenshot_portal.gd")
		for sc in day_pond night_lights storm snow; do runs+=("screenshot_world.gd -- $sc"); done
		for r in "${runs[@]}"; do
			read -r tool rest <<< "$r"
			out="$("$GODOT_BIN" --path . --rendering-driver opengl3 --script "res://tools/$tool" $rest 2>&1)"
			n=$(printf '%s\n' "$out" | grep -c '^ERROR:')
			if [[ $n -eq 0 ]]; then echo "${GREEN}$r: clean${RESET}"; else
				echo "${RED}$r: $n engine errors${RESET}"
				printf '%s\n' "$out" | grep -A4 '^ERROR:' | grep -E '^ERROR|\[0\]' | sort | uniq -c | head -6
				code=1
			fi
		done
		exit $code ;;
	*) echo "${YELLOW}Unknown command '$1'.${RESET} Use: play, debug, editor, test, rendercheck"; exit 2 ;;
esac
