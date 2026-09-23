#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
require_command jq

cmd="$ROOT/bin/omarchy-profile-regulated"
[[ -x $cmd ]] || fail "omarchy-profile-regulated is executable"

home=$(mktemp -d)
trap 'rm -rf "$home"' EXIT
export HOME="$home"
export OMARCHY_CONFIG_HOME="$home/.config/omarchy"
mkdir -p "$OMARCHY_CONFIG_HOME"
cat >"$OMARCHY_CONFIG_HOME/shell.json" <<'EOF'
{"version":1,"idle":{"screensaver":150,"lock":300}}
EOF

"$cmd" status | grep -q default || fail "status starts default"

"$cmd" apply
[[ $(cat "$OMARCHY_CONFIG_HOME/profile") == regulated ]] || fail "apply writes regulated marker"
[[ $(jq -r '.idle.lock' "$OMARCHY_CONFIG_HOME/shell.json") == 900 ]] || fail "apply sets idle.lock 900"
[[ $(jq -r '.idle.lock' "$OMARCHY_CONFIG_HOME/profile.regulated.prev.json") == 300 ]] || fail "apply snapshots previous lock"
[[ $(jq -r '.idle.screensaver' "$OMARCHY_CONFIG_HOME/shell.json") == 150 ]] || fail "apply leaves other idle keys"

"$cmd" status | grep -q regulated || fail "status is regulated after apply"

"$cmd" disable
[[ ! -e $OMARCHY_CONFIG_HOME/profile ]] || fail "disable removes marker"
[[ $(jq -r '.idle.lock' "$OMARCHY_CONFIG_HOME/shell.json") == 300 ]] || fail "disable restores lock 300"

pass "regulated profile apply status disable"
