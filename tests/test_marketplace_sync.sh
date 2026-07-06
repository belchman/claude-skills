#!/usr/bin/env bash
# Marketplace ↔ plugin-manifest ↔ README parity guard.
#
# Enforces, for every plugin in the marketplace:
#   1. plugins/<name>/.claude-plugin/plugin.json exists and parses
#   2. name / version / description identical in marketplace.json and plugin.json
#   3. the marketplace "source" directory exists
#   4. README.md carries an install line and a "### `<name>`" section
#   5. no plugin.json manifest is missing from marketplace.json
#   6. hooks use the canonical layout: hooks/hooks.json at the plugin root,
#      never an inline "hooks" key in plugin.json
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - <<'PY'
import json, pathlib, sys

root = pathlib.Path(".")
errors, passed = [], []

def ok(msg): passed.append(msg)
def bad(msg): errors.append(msg)

mp = json.loads((root / ".claude-plugin/marketplace.json").read_text())
entries = {p["name"]: p for p in mp["plugins"]}
readme = (root / "README.md").read_text()

manifests = {}
for pj in sorted(root.glob("plugins/*/.claude-plugin/plugin.json")):
    try:
        m = json.loads(pj.read_text())
    except json.JSONDecodeError as e:
        bad(f"{pj}: invalid JSON ({e})")
        continue
    manifests[m["name"]] = (pj, m)

for name, entry in entries.items():
    if name not in manifests:
        bad(f"marketplace lists '{name}' but plugins/{name}/.claude-plugin/plugin.json is missing")
        continue
    pj, manifest = manifests[name]

    src = root / entry.get("source", "")
    if src.is_dir():
        ok(f"{name}: source dir exists")
    else:
        bad(f"{name}: marketplace source '{entry.get('source')}' is not a directory")

    for field in ("version", "description"):
        if entry.get(field) == manifest.get(field):
            ok(f"{name}: {field} in sync")
        else:
            bad(f"{name}: {field} differs\n"
                f"      marketplace: {entry.get(field)!r}\n"
                f"      plugin.json: {manifest.get(field)!r}")

    if f"/plugin install {name}@belchman-claude-skills" in readme:
        ok(f"{name}: README install line present")
    else:
        bad(f"{name}: README.md is missing '/plugin install {name}@belchman-claude-skills'")

    if f"### `{name}`" in readme:
        ok(f"{name}: README section heading present")
    else:
        bad(f"{name}: README.md is missing a '### `{name}`' section")

    if "hooks" in manifest:
        bad(f"{name}: plugin.json declares hooks inline — move them to hooks/hooks.json "
            f"(the canonical auto-discovered layout)")
    else:
        ok(f"{name}: no inline hooks key")

    hooks_dir = pj.parent.parent / "hooks"
    if hooks_dir.is_dir():
        hj = hooks_dir / "hooks.json"
        if hj.is_file():
            try:
                json.loads(hj.read_text())
                ok(f"{name}: hooks/hooks.json parses")
            except json.JSONDecodeError as e:
                bad(f"{name}: hooks/hooks.json invalid JSON ({e})")
        else:
            bad(f"{name}: ships hooks/ but no hooks/hooks.json — hooks will not register")

for name in manifests:
    if name not in entries:
        bad(f"plugins/{name} has a manifest but no marketplace.json entry")

for msg in passed:
    print(f"  ok  - {msg}")
for msg in errors:
    print(f"  FAIL - {msg}")
print(f"\nmarketplace sync: {len(passed)} passed, {len(errors)} failed")
sys.exit(1 if errors else 0)
PY
