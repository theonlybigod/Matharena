#!/usr/bin/env bash
#
# Installs MathArena's Studio plugins into this machine's Roblox Studio
# Plugins folder (macOS).
#
# Roblox Studio loads plugins from a fixed per-user folder on disk, NOT from
# the game and NOT through Rojo - a plugin runs inside Studio itself rather
# than inside the place, so it cannot be synced in like normal game code.
# Every developer therefore needs a copy on their own machine; this script
# is what puts it there.
#
# Run once after cloning, and again whenever the plugin changes (it
# overwrites in place). Only ever writes into the Studio Plugins folder -
# never the repo, never the game.
#
# Usage:
#   ./tools/StudioPlugins/install.sh
#   ./tools/StudioPlugins/install.sh --dry-run

set -euo pipefail

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
	DRY_RUN=1
fi

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# macOS Studio reads plugins from ~/Documents/Roblox/Plugins.
PLUGINS_DIR="$HOME/Documents/Roblox/Plugins"

if [[ "$(uname -s)" != "Darwin" ]]; then
	echo "This script targets macOS. On Windows use install.ps1 instead:" >&2
	echo "  powershell -ExecutionPolicy Bypass -File tools\\StudioPlugins\\install.ps1" >&2
	exit 1
fi

shopt -s nullglob
plugins=("$SOURCE_DIR"/*.lua)
shopt -u nullglob

if [[ ${#plugins[@]} -eq 0 ]]; then
	echo "No .lua plugin files found in $SOURCE_DIR" >&2
	exit 1
fi

if [[ ! -d "$PLUGINS_DIR" ]]; then
	echo "Plugins folder doesn't exist yet - creating $PLUGINS_DIR"
	[[ $DRY_RUN -eq 0 ]] && mkdir -p "$PLUGINS_DIR"
fi

installed=0
for plugin in "${plugins[@]}"; do
	name="$(basename "$plugin")"
	destination="$PLUGINS_DIR/$name"

	if [[ -f "$destination" ]]; then
		echo "Updating $name -> $destination"
	else
		echo "Installing $name -> $destination"
	fi

	if [[ $DRY_RUN -eq 0 ]]; then
		cp -f "$plugin" "$destination"
		installed=$((installed + 1))
	fi
done

echo ""
if [[ $DRY_RUN -eq 1 ]]; then
	echo "Dry run - nothing was copied."
else
	echo "Done - $installed plugin(s) installed to $PLUGINS_DIR"
	echo "Restart Roblox Studio if the change doesn't appear automatically."
fi
