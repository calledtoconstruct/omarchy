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
bun-bin 1.0.0-1 x86_64
unknown-pkg 1-1 x86_64
EOF

[[ -x $cmd ]] || fail "omarchy-pkg-advisories is executable"

out=$("$cmd" --sidecar "$sidecar" --installed-file "$installed") || status=$?
status=${status:-0}
[[ $status -eq 0 ]] || fail "fail-open exits 0" "exit $status"
grep -q 'CVE-2026-4242' <<<"$out" || fail "prints HIGH CVE for mise-bin"
grep -q 'bun-bin' <<<"$out" || fail "mentions missing bun-bin row status"
grep -q 'unknown-pkg' <<<"$out" || fail "mentions packages with no sidecar row"

set +e
"$cmd" --sidecar /no/such/sidecar.json --installed-file "$installed" >/tmp/omarchy-adv-missing.out
miss=$?
set -e
[[ $miss -eq 0 ]] || fail "missing sidecar is fail-open exit 0"
grep -qi 'advisory directory' /tmp/omarchy-adv-missing.out || fail "missing advisory directory prints a warning"

set +e
"$cmd" --sidecar "$sidecar" --installed-file "$installed" --fail-closed
closed=$?
set -e
[[ $closed -eq 2 ]] || fail "fail-closed exits 2 when a HIGH CVE is present"

json=$("$cmd" --sidecar "$sidecar" --installed-file "$installed" --json)
jq -e '.[] | select(.pkgname=="mise-bin" and .cve_ids[0]=="CVE-2026-4242")' <<<"$json" >/dev/null \
  || fail "json includes mise-bin CVE"

pass "pkg advisories fail-open CLI"
