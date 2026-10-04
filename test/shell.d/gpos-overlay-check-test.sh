#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

cmd="$ROOT/bin/omarchy-gpos-overlay"
[[ -f $cmd ]] || fail "omarchy-gpos-overlay exists"

fix=$(mktemp -d)
trap 'rm -rf "$fix"' EXIT

mkdir -p \
  "$fix/etc/pam.d" \
  "$fix/etc/sudoers.d" \
  "$fix/etc/ssh" \
  "$fix/usr/bin" \
  "$fix/var/lib/pacman/local/bluez-5.85-1" \
  "$fix/config/omarchy" \
  "$fix/proc/sys/crypto"

printf '%s\n' 'ENCRYPT_METHOD YESCRYPT' >"$fix/etc/login.defs"
printf '%s\n' 'password sufficient pam_unix.so yescrypt' >"$fix/etc/pam.d/system-auth"
printf '%s\n' 'cryptroot UUID=abc none luks' >"$fix/etc/crypttab"
cat >"$fix/etc/pacman.conf" <<'EOF'
[options]
SigLevel = Required DatabaseOptional
[omarchy]
Server = https://pkgs.omarchy.org/stable/$arch
EOF
printf '%s\n' 'auth include system-login' >"$fix/etc/pam.d/sddm-autologin"
: >"$fix/usr/bin/omarchy-sudo-passwordless"
: >"$fix/usr/bin/omarchy-update"
printf '%s\n' '{"idle":{"lock":300}}' >"$fix/config/omarchy/shell.json"
printf '%s\n' 0 >"$fix/proc/sys/crypto/fips_enabled"

snapshot=$(find "$fix" -printf '%p %T@\n' | sort)
out=$(mktemp)
err=$(mktemp)

"$cmd" --root "$fix" >"$out" 2>"$err"
after=$(find "$fix" -printf '%p %T@\n' | sort)
[[ $snapshot == "$after" ]] || fail "checker does not write under --root"

grep -q 'not a STIG' "$err" || fail "report says it is not a STIG"
grep -qi 'omarchy STIG' "$err" && fail "report must not claim an Omarchy STIG"

expect_row() {
  local id=$1 catalog=$2 observed=$3
  grep -q "^${id} catalog=${catalog} observed=${observed} " "$out" ||
    fail "$id is ${catalog}/${observed}" "$(grep "^${id} " "$out" || true)"
}

expect_row V-203603 partial partial
expect_row V-203629 implemented implemented
expect_row V-203630 partial partial
expect_row V-203653 gap gap
expect_row V-203669 partial partial
expect_row V-203682 gap gap
expect_row V-203695 gap gap
expect_row V-203720 partial partial
expect_row V-203736 partial partial
expect_row V-203737 partial partial
expect_row V-203739 gap gap
expect_row V-203745 implemented implemented
expect_row V-203746 implemented implemented
expect_row V-203748 partial partial
expect_row V-203749 partial partial
expect_row V-203776 gap gap
expect_row V-203782 gap gap
expect_row V-252688 gap gap
expect_row V-259333 partial partial
expect_row V-278977 partial partial
expect_row V-203599 partial partial

row_count=$(grep -c '^V-' "$out")
[[ $row_count -eq 21 ]] || fail "text report has 21 rows" "$row_count"
grep -q 'idle.lock is 300 seconds' "$out" || fail "lock note names 300 seconds"
grep -q 'omarchy-sudo-passwordless is on this image' "$out" || fail "passwordless note names the command"
grep -q 'FIPS is out of this slice' "$out" || fail "FIPS stays out of this slice"

set +e
"$cmd" --root "$fix" --fail-on-gap >/dev/null 2>&1
fail_status=$?
set -e
[[ $fail_status -eq 2 ]] || fail "fail-on-gap exits 2 when a row is a gap" "$fail_status"

# Kernel FIPS flag does not close the overlay gap.
printf '%s\n' 1 >"$fix/proc/sys/crypto/fips_enabled"
"$cmd" --root "$fix" --json >"$out" 2>/dev/null
jq -e 'length == 21' "$out" >/dev/null || fail "json report has 21 rows"
jq -e 'any(.[]; .vuln_id == "V-203776" and .observed == "gap" and (.note | contains("out of this slice")))' "$out" >/dev/null ||
  fail "FIPS flag still leaves V-203776 a gap"
jq -e 'any(.[]; .vuln_id == "V-203739" and .observed == "gap")' "$out" >/dev/null ||
  fail "NSA crypto stays a gap when the kernel flag is on"

# Drift the fixture away from the stock image.
mkdir -p "$fix/etc/systemd/system/multi-user.target.wants"
ln -s /usr/lib/systemd/system/sshd.service "$fix/etc/systemd/system/multi-user.target.wants/sshd.service"
mkdir -p "$fix/var/lib/pacman/local/vsftpd-3.0.5-1"
printf '%s\n' '%wheel ALL=(ALL) NOPASSWD: ALL' >"$fix/etc/sudoers.d/99-omarchy-nopasswd-user"
cat >"$fix/etc/pacman.conf" <<'EOF'
[options]
SigLevel = Optional TrustAll
[omarchy]
Server = http://pkgs.omarchy.org/edge/$arch
EOF
rm -f "$fix/etc/crypttab" "$fix/etc/pam.d/sddm-autologin" "$fix/usr/bin/omarchy-update"
printf '%s\n' '{"idle":{"lock":1800}}' >"$fix/config/omarchy/shell.json"

"$cmd" --root "$fix" >"$out" 2>/dev/null
expect_row V-203603 partial gap
expect_row V-203630 partial gap
expect_row V-203695 gap gap
expect_row V-203720 partial gap
expect_row V-203745 implemented gap
expect_row V-203748 partial gap
expect_row V-203776 gap gap
expect_row V-203782 gap partial
expect_row V-259333 partial gap
expect_row V-278977 partial gap
expect_row V-203599 partial gap
grep -q 'NOPASSWD ALL drop-in is present' "$out" || fail "active passwordless drop-in is named"
grep -q 'idle.lock is 1800 seconds' "$out" || fail "lock over 15 minutes is named"

# A gov-shaped root: no autologin file, no passwordless command, lock at 900, stable https.
rm -f "$fix/etc/sudoers.d/99-omarchy-nopasswd-user" "$fix/usr/bin/omarchy-sudo-passwordless"
rm -rf "$fix/etc/systemd/system/multi-user.target.wants" "$fix/var/lib/pacman/local/vsftpd-3.0.5-1"
printf '%s\n' 'cryptroot UUID=abc none luks' >"$fix/etc/crypttab"
cat >"$fix/etc/pacman.conf" <<'EOF'
[options]
SigLevel = Required DatabaseOptional
[omarchy]
Server = https://pkgs.omarchy.org/stable/$arch
EOF
: >"$fix/usr/bin/omarchy-update"
printf '%s\n' '{"idle":{"lock":900}}' >"$fix/config/omarchy/shell.json"

"$cmd" --root "$fix" >"$out" 2>/dev/null
expect_row V-203695 gap partial
expect_row V-203782 gap partial
expect_row V-203599 partial partial
grep -q 'no passwordless sudo drop-in' "$out" || fail "missing passwordless command is partial"
grep -q 'no sddm autologin file in this root' "$out" || fail "missing autologin file is not implemented"
grep -q 'idle.lock is 900 seconds' "$out" || fail "900 second lock stays inside 15 minutes"

pass "gpos overlay checker"
