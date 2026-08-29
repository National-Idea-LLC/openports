#!/bin/bash
# Copies the Icon Composer source from brand/ into the app target, normalising two
# keys that Xcode 26.6's actool cannot parse.
#
# Icon Composer writes a newer schema than actool accepts. Two fields crash it
# (it aborts with "attempt to insert nil object" rather than reporting an error):
#
#   * top-level "features": ["refractivity", "specular-location"]
#   * per-group "specular": "outside"  — actool expects a boolean
#
# Both must be normalised together; fixing only one still crashes. Re-exporting
# from Icon Composer reintroduces them, so run this script after every re-export
# rather than hand-editing the copy under Squatter/Resources.
#
# Run: scripts/sync-app-icon.sh
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_icon="$repo_root/brand/app_icon/icon/Squatter App Icon.icon"
target_icon="$repo_root/Squatter/Resources/AppIcon.icon"

if [[ ! -d "$source_icon" ]]; then
    echo "error: no Icon Composer source at $source_icon" >&2
    exit 1
fi

rm -rf "$target_icon"
cp -R "$source_icon" "$target_icon"

python3 - "$target_icon/icon.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path) as handle:
    icon = json.load(handle)

icon.pop("features", None)
for group in icon.get("groups", []):
    if isinstance(group.get("specular"), str):
        group["specular"] = True

with open(path, "w") as handle:
    json.dump(icon, handle, indent=2, sort_keys=True, ensure_ascii=False)
    handle.write("\n")
PY

echo "Synced app icon -> ${target_icon#"$repo_root"/}"
