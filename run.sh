#!/usr/bin/env bash
# Simmo runner.
#   ./run.sh            play the game
#   ./run.sh debug      play with debug mode on (full logging, hitboxes, F3 overlay)
#   ./run.sh editor     open the project in the Godot editor
#   ./run.sh test       run the headless smoke test
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
		for t in smoke_test magic_test; do
			"$GODOT_BIN" --headless --fixed-fps 60 --path . --script "res://tests/$t.gd"
			c=$?
			if [[ $c -eq 0 ]]; then echo "${GREEN}$t passed${RESET}"; else echo "${RED}$t failed (exit $c)${RESET}"; code=1; fi
		done
		exit $code ;;
	*) echo "${YELLOW}Unknown command '$1'.${RESET} Use: play, debug, editor, test"; exit 2 ;;
esac
