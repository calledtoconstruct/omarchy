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

sidecar="$ROOT/test/shell.d/fixtures/advisories"
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

# Machine facts come from a --root fixture. A clean sidecar keeps the exit code
# on those facts alone. The ISO writes /etc/sddm.conf.d/autologin.conf with User=.
# The passwordless command the profile refuses is /usr/bin/omarchy-sudo-passwordless.
clean_sidecar=$(mktemp -d)
clean_installed=$(mktemp)
machine=$(mktemp -d)
trap 'rm -rf "$home" "$clean_sidecar" "$machine"' EXIT
: >"$clean_installed"
mkdir -p "$machine/usr/bin" "$machine/etc/sddm.conf.d"
printf '#!/bin/bash\n' >"$machine/usr/bin/omarchy-sudo-passwordless"
printf '[Autologin]\nUser=reviewer\nSession=omarchy.desktop\n' >"$machine/etc/sddm.conf.d/autologin.conf"
printf '[Theme]\nCurrent=omarchy\n' >"$machine/etc/sddm.conf.d/10-theme.conf"

snapshot=$(find "$machine" -printf '%p %T@\n' | sort)
rm -f "$OMARCHY_CONFIG_HOME/profile"

set +e
open_machine=$("$cmd" --sidecar "$clean_sidecar" --installed-file "$clean_installed" --root "$machine")
open_machine_rc=$?
set -e
[[ $open_machine_rc -eq 0 ]] || fail "default report stays open with machine findings" "exit $open_machine_rc"
grep -Fq 'passwordless sudo command is present' <<<"$open_machine" || fail "default report prints the passwordless sudo command"
grep -Fq 'SDDM autologin is enabled' <<<"$open_machine" || fail "default report prints SDDM autologin"
after=$(find "$machine" -printf '%p %T@\n' | sort)
[[ $snapshot == "$after" ]] || fail "risk report does not write under --root"

printf 'regulated\n' >"$OMARCHY_CONFIG_HOME/profile"
set +e
closed_machine=$("$cmd" --sidecar "$clean_sidecar" --installed-file "$clean_installed" --root "$machine" --json)
closed_machine_rc=$?
set -e
[[ $closed_machine_rc -eq 2 ]] || fail "regulated report fails closed on machine findings" "exit $closed_machine_rc"
jq -e '.machine.passwordless_sudo_command == true and .machine.sddm_autologin == true and .closed == true' <<<"$closed_machine" >/dev/null ||
  fail "regulated json names both machine findings" "$closed_machine"

rm -f "$machine/etc/sddm.conf.d/autologin.conf"
set +e
"$cmd" --sidecar "$clean_sidecar" --installed-file "$clean_installed" --root "$machine" >/dev/null
sudo_only_rc=$?
set -e
[[ $sudo_only_rc -eq 2 ]] || fail "regulated report fails closed when the passwordless sudo command is present" "exit $sudo_only_rc"

rm -f "$machine/usr/bin/omarchy-sudo-passwordless"
printf '[Autologin]\nUser=reviewer\nSession=omarchy.desktop\n' >"$machine/etc/sddm.conf.d/autologin.conf"
set +e
"$cmd" --sidecar "$clean_sidecar" --installed-file "$clean_installed" --root "$machine" >/dev/null
auto_only_rc=$?
set -e
[[ $auto_only_rc -eq 2 ]] || fail "regulated report fails closed when SDDM autologin is enabled" "exit $auto_only_rc"

rm -f "$OMARCHY_CONFIG_HOME/profile"
set +e
"$cmd" --sidecar "$clean_sidecar" --installed-file "$clean_installed" --root "$machine" --fail-closed >/dev/null
flag_rc=$?
set -e
[[ $flag_rc -eq 2 ]] || fail "fail-closed exits 2 when SDDM autologin is enabled" "exit $flag_rc"

rm -f "$machine/etc/sddm.conf.d/autologin.conf"
printf 'regulated\n' >"$OMARCHY_CONFIG_HOME/profile"
set +e
clean_machine=$("$cmd" --sidecar "$clean_sidecar" --installed-file "$clean_installed" --root "$machine")
clean_machine_rc=$?
set -e
[[ $clean_machine_rc -eq 0 ]] || fail "missing machine files stay clean under regulated" "exit $clean_machine_rc"
grep -Fq 'passwordless sudo command is present' <<<"$clean_machine" && fail "missing passwordless command is not a finding"
grep -Fq 'SDDM autologin is enabled' <<<"$clean_machine" && fail "missing SDDM autologin is not a finding"
grep -Eqi 'error|not found' <<<"$clean_machine" && fail "missing machine files are not an error" "$clean_machine"

pass "risk report observes passwordless sudo and SDDM autologin"
