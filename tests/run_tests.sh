#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if command -v godot >/dev/null 2>&1; then
	engine=(godot)
elif command -v godot4 >/dev/null 2>&1; then
	engine=(godot4)
elif command -v flatpak >/dev/null 2>&1 && flatpak info org.godotengine.Godot >/dev/null 2>&1; then
	engine=(flatpak run org.godotengine.Godot)
else
	printf 'Godot 4 was not found in PATH or Flatpak.\n' >&2
	exit 127
fi

# Godot can continue running a SceneTree script after a dependency compile error.
# Check compilation separately so any parser failure makes this command fail.
"${engine[@]}" --headless --path "$project_root" --check-only --script res://tests/test_runner.gd
"${engine[@]}" --headless --path "$project_root" --script res://tests/test_runner.gd

# A scene can log a startup error while Godot still exits with status zero.
if ! startup_output=$("${engine[@]}" --headless --path "$project_root" --quit-after 5 2>&1); then
	printf '%s\n' "$startup_output" >&2
	exit 1
fi
printf '%s\n' "$startup_output"
if [[ "$startup_output" == *"ERROR:"* ]]; then
	exit 1
fi
