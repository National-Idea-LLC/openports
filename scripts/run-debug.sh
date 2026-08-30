#!/bin/bash
# Build the Debug app, quit any running copy, and launch the fresh one.
#
# Squatter is LSUIElement — there is no Dock icon and no window at launch, so
# "did it work" means clicking the menu bar item. Relaunching after a UI change
# is how the owner sees that change; see AGENTS.md.
set -euo pipefail

cd "$(dirname "$0")/.."

xcodebuild -project Squatter.xcodeproj -scheme Squatter -configuration Debug build "$@" >/dev/null

products_dir=$(xcodebuild -project Squatter.xcodeproj -scheme Squatter -configuration Debug \
    -showBuildSettings 2>/dev/null |
    awk -F' = ' '/^ *BUILT_PRODUCTS_DIR = /{print $2; exit}')
app="$products_dir/Squatter.app"
[ -d "$app" ] || { echo "no app at $app" >&2; exit 1; }

# Quit the running copy first: two instances means two menu bar icons, and the
# stale one keeps scanning.
if pkill -x Squatter 2>/dev/null; then
    for _ in $(seq 20); do
        pgrep -x Squatter >/dev/null || break
        sleep 0.1
    done
fi

open "$app"
echo "launched $app"
