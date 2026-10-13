#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
require_command jq

cmd="$ROOT/bin/omarchy-pkg-advisories"
sidecar="$ROOT/test/shell.d/fixtures/advisories"
installed=$(mktemp)
trap 'rm -f "$installed"' EXIT
cat >"$installed" <<'EOF'
mise-bin 2026.9.4-1 x86_64
unknown-pkg 1-1 x86_64
EOF

out=$("$cmd" --sidecar "$sidecar" --installed-file "$installed" --action install --quiet-absent) || status=$?
status=${status:-0}
[[ $status -eq 0 ]] || fail "action review stays fail-open" "exit $status"

expected="install: mise-bin 2026.9.4-1 x86_64 status=ok severity=HIGH cves=CVE-2026-4242"
grep -qxF "$expected" <<<"$out" || fail "prints the install line with the known CVE" "$out"
grep -q 'unknown-pkg' <<<"$out" && fail "quiet-absent mentions a package with no sidecar" "$out"

env_out=$(OMARCHY_ADVISORY_DIR="$sidecar" "$cmd" --installed-file "$installed" --action install --quiet-absent) \
  || fail "OMARCHY_ADVISORY_DIR review exits 0"
grep -qxF "$expected" <<<"$env_out" || fail "OMARCHY_ADVISORY_DIR is used when --sidecar is omitted" "$env_out"

pass "advisory action lines stay quiet for packages with no sidecar"
