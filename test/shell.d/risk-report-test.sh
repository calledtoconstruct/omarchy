#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
require_command jq

cmd="$ROOT/bin/omarchy-risk-report"
[[ -x $cmd ]] || fail "omarchy-risk-report is executable"

home=$(mktemp -d)
trap 'rm -rf "$home"' EXIT
export HOME="$home"
export OMARCHY_CONFIG_HOME="$home/.config/omarchy"
mkdir -p "$OMARCHY_CONFIG_HOME"

sidecar="$ROOT/test/shell.d/fixtures/advisories/omarchy.advisories.json"
installed=$(mktemp)
audit=$(mktemp)
cat >"$installed" <<'EOF'
mise-bin 2026.9.4-1 x86_64
EOF
cat >"$audit" <<'EOF'
[{"name":"openssl","cve":"CVE-2026-1","severity":"High"}]
EOF

set +e
"$cmd" --sidecar "$sidecar" --installed-file "$installed" --arch-audit-file "$audit"
open_rc=$?
set -e
[[ $open_rc -eq 0 ]] || fail "default report is fail-open" "exit $open_rc"

printf 'regulated\n' >"$OMARCHY_CONFIG_HOME/profile"
set +e
"$cmd" --sidecar "$sidecar" --installed-file "$installed" --arch-audit-file "$audit"
closed_rc=$?
set -e
[[ $closed_rc -eq 2 ]] || fail "regulated report fails closed on HIGH" "exit $closed_rc"

json=$("$cmd" --sidecar "$sidecar" --installed-file "$installed" --arch-audit-file "$audit" --json || true)
jq -e '.opr[] | select(.pkgname=="mise-bin")' <<<"$json" >/dev/null || fail "json has opr findings"
jq -e '.arch[] | select(.name=="openssl")' <<<"$json" >/dev/null || fail "json has arch-audit findings"

pass "risk report fail-closed under regulated"
