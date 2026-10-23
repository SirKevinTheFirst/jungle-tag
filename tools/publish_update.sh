#!/usr/bin/env bash
# Publishes the current project as an update that every installed JungleTag.exe downloads on its next start.
#   1. bump application/config/build in project.godot
#   2. GODOT=/path/to/godot tools/publish_update.sh
# The update is game.pck + version.json on the "updates" branch (a single commit, replaced each time).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
BUILD=$(sed -n 's/^config\/build=\([0-9]*\)/\1/p' project.godot)
OUT=$(mktemp -d)
"$GODOT" --headless --path . --export-pack "Windows Desktop" "$OUT/game.pck"
echo "{\"build\": $BUILD}" > "$OUT/version.json"
REMOTE=$(git remote get-url origin)
(
	cd "$OUT"
	git init -q -b updates
	git add game.pck version.json
	git -c user.name="Jungle Tag updater" -c user.email="noreply@anthropic.com" commit -q -m "Game update, build $BUILD"
	git push -f "$REMOTE" updates:updates
)
rm -rf "$OUT"
echo "Published build $BUILD"
