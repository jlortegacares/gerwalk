#!/usr/bin/env bash
# Launch Gerwalk from anywhere in this repository.
#
#   ./run.sh              run the game
#   ./run.sh --editor     open the editor on this project
#   ./run.sh --headless   run without a window (CI, smoke tests)
#
# Override the engine with GODOT_BIN=/path/to/godot ./run.sh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

find_godot() {
	if [[ -n "${GODOT_BIN:-}" ]]; then
		printf '%s' "$GODOT_BIN"
		return 0
	fi

	local name
	for name in godot godot4; do
		if command -v "$name" >/dev/null 2>&1; then
			command -v "$name"
			return 0
		fi
	done

	local candidate
	for candidate in \
		"/Applications/Godot.app/Contents/MacOS/Godot" \
		"$HOME/Applications/Godot.app/Contents/MacOS/Godot" \
		"/usr/local/bin/godot" \
		"/usr/bin/godot"; do
		if [[ -x "$candidate" ]]; then
			printf '%s' "$candidate"
			return 0
		fi
	done

	return 1
}

if ! GODOT="$(find_godot)"; then
	cat >&2 <<-'EOF'
	Godot was not found.

	Install it, add it to PATH, or point this script at it:

	    GODOT_BIN=/path/to/godot ./run.sh
	EOF
	exit 1
fi

if [[ "${1:-}" == "--editor" ]]; then
	shift
	exec "$GODOT" --editor --path "$PROJECT_DIR" "$@"
fi

exec "$GODOT" --path "$PROJECT_DIR" "$@"
