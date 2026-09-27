#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_path="$project_root/builds/game-debug.apk"
android_sdk_path="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Android}}"

if command -v godot >/dev/null 2>&1; then
	engine=(godot)
elif command -v godot4 >/dev/null 2>&1; then
	engine=(godot4)
elif command -v flatpak >/dev/null 2>&1 && flatpak info org.godotengine.Godot >/dev/null 2>&1; then
	if [[ ! -f "$android_sdk_path/platform-tools/adb" ]]; then
		printf 'Android SDK not found at %s; set ANDROID_SDK_ROOT.\n' "$android_sdk_path" >&2
		exit 1
	fi
	engine=(flatpak run --env=JAVA_HOME=/usr/lib/sdk/openjdk17/jvm/openjdk-17 --env=ANDROID_HOME="$android_sdk_path" org.godotengine.Godot)
else
	printf 'Godot 4 was not found in PATH or Flatpak.\n' >&2
	exit 127
fi

mkdir -p "$project_root/builds"
"${engine[@]}" --headless --path "$project_root" --export-debug Android "$output_path"
if [[ ! -s "$output_path" ]]; then
	printf 'Godot did not produce a nonempty debug APK.\n' >&2
	exit 1
fi
printf 'Debug APK: %s\n' "$output_path"
