#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

write_advisory_logger() {
  local bin_dir=$1
  cat >"$bin_dir/omarchy-pkg-advisories" <<'EOF'
#!/bin/bash
printf 'advisory %s\n' "$*" >>"$TEST_TMP/order"
{
  printf '%s\n' "$*"
  args=("$@")
  for ((i = 0; i < ${#args[@]}; i++)); do
    if [[ ${args[$i]} == "--installed-file" ]]; then
      cat "${args[$((i + 1))]}"
    fi
  done
} >>"$TEST_TMP/advisory.log"
exit 2
EOF
  chmod +x "$bin_dir/omarchy-pkg-advisories"
}

write_sudo() {
  local bin_dir=$1
  cat >"$bin_dir/sudo" <<'EOF'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$TEST_TMP/order"
"$@"
EOF
  chmod +x "$bin_dir/sudo"
}

line_no() {
  local pattern=$1
  local file=$2
  grep -n "$pattern" "$file" | head -n 1 | cut -d: -f1 || true
}

add_bin="$test_tmp/add-bin"
mkdir -p "$add_bin"
cat >"$add_bin/pacman" <<'EOF'
#!/bin/bash
printf 'pacman %s\n' "$*" >>"$TEST_TMP/order"
if [[ $1 == "-Si" && $2 == "mise-bin" ]]; then
  printf '%s\n' "Version         : 2026.9.4-1" "Architecture    : x86_64"
  exit 0
fi
if [[ $1 == "-Si" ]]; then
  exit 1
fi
if [[ $1 == "-Q" ]]; then
  if [[ -f $TEST_TMP/installed ]]; then
    exit 0
  fi
  exit 1
fi
if [[ $1 == "-S" ]]; then
  touch "$TEST_TMP/installed"
  exit 0
fi
exit 0
EOF
chmod +x "$add_bin/pacman"
write_sudo "$add_bin"
write_advisory_logger "$add_bin"
: >"$test_tmp/order"

PATH="$add_bin:$ROOT/bin:$PATH" TEST_TMP="$test_tmp" \
  "$ROOT/bin/omarchy-pkg-add" mise-bin unknown-pkg
[[ -f $test_tmp/advisory.log ]] || fail "install review was invoked" "$(<"$test_tmp/order")"
add_log=$(<"$test_tmp/advisory.log")
grep -qF -- '--action install' <<<"$add_log" || fail "install review records --action install" "$add_log"
grep -qF 'mise-bin 2026.9.4-1 x86_64' <<<"$add_log" || fail "install review records the pacman -Si row" "$add_log"
grep -qF 'unknown-pkg' <<<"$add_log" && fail "a failed version lookup is left out of the review" "$add_log"
add_review=$(line_no 'advisory --action install' "$test_tmp/order")
add_install=$(line_no 'pacman -S --noconfirm --needed -- mise-bin unknown-pkg' "$test_tmp/order")
[[ -n $add_review && -n $add_install && $add_review -lt $add_install ]] ||
  fail "pacman -S still runs after a non-zero advisory review" "$(<"$test_tmp/order")"
pass "package add reviews mise-bin and still installs"

rm -f "$test_tmp/advisory.log" "$test_tmp/order" "$test_tmp/installed"

drop_bin="$test_tmp/drop-bin"
mkdir -p "$drop_bin"
cat >"$drop_bin/pacman" <<'EOF'
#!/bin/bash
printf 'pacman %s\n' "$*" >>"$TEST_TMP/order"
if [[ $1 == "-Qq" ]]; then
  printf '%s\n' mise-bin
  exit 0
fi
if [[ $1 == "-Q" && $2 == "--info" ]]; then
  printf '%s\n' "Version         : 2026.9.4-1" "Architecture    : x86_64"
  exit 0
fi
exit 0
EOF
chmod +x "$drop_bin/pacman"
write_sudo "$drop_bin"
write_advisory_logger "$drop_bin"
: >"$test_tmp/order"

PATH="$drop_bin:$ROOT/bin:$PATH" TEST_TMP="$test_tmp" \
  "$ROOT/bin/omarchy-pkg-drop" mise-bin
[[ -f $test_tmp/advisory.log ]] || fail "remove review was invoked" "$(<"$test_tmp/order")"
drop_log=$(<"$test_tmp/advisory.log")
grep -qF -- '--action remove' <<<"$drop_log" || fail "remove review records --action remove" "$drop_log"
grep -qF 'mise-bin 2026.9.4-1 x86_64' <<<"$drop_log" || fail "remove review records the installed row" "$drop_log"
drop_review=$(line_no 'advisory --action remove' "$test_tmp/order")
drop_remove=$(line_no 'pacman -Rns --noconfirm mise-bin' "$test_tmp/order")
[[ -n $drop_review && -n $drop_remove && $drop_review -lt $drop_remove ]] ||
  fail "pacman -Rns still runs after a non-zero advisory review" "$(<"$test_tmp/order")"
pass "package drop reviews mise-bin and still removes"

rm -f "$test_tmp/advisory.log" "$test_tmp/order"

update_bin="$test_tmp/update-bin"
mkdir -p "$update_bin"
cat >"$update_bin/pacman" <<'EOF'
#!/bin/bash
printf 'pacman %s\n' "$*" >>"$TEST_TMP/order"
exit 0
EOF
chmod +x "$update_bin/pacman"
cat >"$update_bin/omarchy-update-pacman" <<'EOF'
#!/bin/bash
printf 'omarchy-update-pacman %s\n' "$*" >>"$TEST_TMP/order"
exit 0
EOF
chmod +x "$update_bin/omarchy-update-pacman"
write_sudo "$update_bin"
write_advisory_logger "$update_bin"
: >"$test_tmp/order"

set +e
PATH="$update_bin:$ROOT/bin:$PATH" TEST_TMP="$test_tmp" \
  "$ROOT/bin/omarchy-update-system-pkgs" >/dev/null
update_status=$?
set -e
[[ $update_status -eq 0 ]] || fail "update exits 0 when the advisory command exits 2" "exit $update_status"
[[ -f $test_tmp/advisory.log ]] || fail "update review was invoked" "$(<"$test_tmp/order")"
update_log=$(<"$test_tmp/advisory.log")
grep -qF -- '--action update' <<<"$update_log" || fail "update review records --action update" "$update_log"
grep -qF -- '--quiet-absent' <<<"$update_log" || fail "update review is quiet for packages with no sidecar" "$update_log"
update_syu=$(line_no 'omarchy-update-pacman -Syu --noconfirm --overwrite /usr/share/omarchy/\*' "$test_tmp/order")
update_review=$(line_no 'advisory --action update --quiet-absent' "$test_tmp/order")
[[ -n $update_syu && -n $update_review && $update_syu -lt $update_review ]] ||
  fail "update review runs only after pacman -Syu succeeds" "$(<"$test_tmp/order")"
pass "system package update reviews after a successful upgrade"

rm -f "$test_tmp/advisory.log" "$test_tmp/order"

conflict_bin="$test_tmp/conflict-bin"
mkdir -p "$conflict_bin"
cat >"$conflict_bin/pacman" <<'EOF'
#!/bin/bash
printf 'pacman %s\n' "$*" >>"$TEST_TMP/order"
exit 0
EOF
chmod +x "$conflict_bin/pacman"
cat >"$conflict_bin/omarchy-update-pacman" <<'EOF'
#!/bin/bash
printf 'omarchy-update-pacman %s\n' "$*" >>"$TEST_TMP/order"
exit 0
EOF
chmod +x "$conflict_bin/omarchy-update-pacman"
write_sudo "$conflict_bin"
write_advisory_logger "$conflict_bin"
: >"$test_tmp/order"

PATH="$conflict_bin:$ROOT/bin:$PATH" TEST_TMP="$test_tmp" \
  OMARCHY_UPDATE_CONFLICT=1 OMARCHY_UPDATE_INTERACTIVE=1 \
  "$ROOT/bin/omarchy-update-system-pkgs" >/dev/null
[[ ! -e $test_tmp/advisory.log ]] || fail "conflict path does not review advisories" "$(<"$test_tmp/advisory.log")"
grep -qF 'omarchy-update-pacman -Syu --overwrite /usr/share/omarchy/*' "$test_tmp/order" ||
  fail "conflict path still runs pacman" "$(<"$test_tmp/order")"
pass "conflict path skips the advisory review"

rm -f "$test_tmp/order" "$test_tmp/installed"
ln -s "$ROOT/bin/omarchy-pkg-missing" "$add_bin/omarchy-pkg-missing"
rm -f "$add_bin/omarchy-pkg-advisories"
: >"$test_tmp/order"

PATH="$add_bin:$PATH" TEST_TMP="$test_tmp" \
  "$ROOT/bin/omarchy-pkg-add" mise-bin >/dev/null 2>&1
grep -qF 'pacman -S --noconfirm --needed -- mise-bin' "$test_tmp/order" ||
  fail "install continues when the advisory review command is absent" "$(<"$test_tmp/order")"
pass "package add still installs when the advisory review command is absent"

rm -f "$test_tmp/order" "$test_tmp/installed" "$add_bin/omarchy-pkg-missing"
: >"$test_tmp/order"
PATH="$add_bin:$ROOT/bin:$PATH" TEST_TMP="$test_tmp" \
  "$ROOT/bin/omarchy-pkg-add" mise-bin >"$test_tmp/add-out" 2>/dev/null
grep -qF 'pacman -S --noconfirm --needed -- mise-bin' "$test_tmp/order" ||
  fail "install continues when no advisory sidecar is installed" "$(<"$test_tmp/order")"
grep -q 'advisory directory not found' "$test_tmp/add-out" ||
  fail "a missing sidecar tells the person the warning was skipped" "$(<"$test_tmp/add-out")"
pass "package add still installs when the advisory sidecar is missing"

rm -f "$test_tmp/order" "$test_tmp/installed"
: >"$test_tmp/order"
PATH="$add_bin:$ROOT/bin:$PATH" TEST_TMP="$test_tmp" \
  OMARCHY_ADVISORY_DIR="$ROOT/test/shell.d/fixtures/advisories" \
  "$ROOT/bin/omarchy-pkg-add" mise-bin >"$test_tmp/add-out"
grep -qxF 'install: mise-bin 2026.9.4-1 x86_64 status=ok severity=HIGH cves=CVE-2026-4242' "$test_tmp/add-out" ||
  fail "install prints the sidecar CVE before pacman -S" "$(<"$test_tmp/add-out")"
grep -qF 'pacman -S --noconfirm --needed -- mise-bin' "$test_tmp/order" ||
  fail "install continues after printing a HIGH advisory" "$(<"$test_tmp/order")"
pass "package add prints the sidecar CVE and still installs"
