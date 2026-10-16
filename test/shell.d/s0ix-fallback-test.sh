#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

hook="$ROOT/default/systemd/system-sleep/omarchy-s0ix-fallback"
migration="$ROOT/migrations/1792150064.sh"

bash -n "$hook" || fail "the S0ix fallback hook has valid syntax"
bash -n "$migration" || fail "the S0ix fallback migration has valid syntax"
[[ -x $hook ]] || fail "the S0ix fallback hook is executable" "mode: $(stat -c '%A' "$hook")"
grep -q 'systemd/system-sleep/omarchy-s0ix-fallback' "$ROOT/docs/file-layout.md" ||
  fail "the file layout documents the S0ix fallback hook"
pass "the S0ix fallback hook is valid, executable, and documented"

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin" "$scratch/conf.d" "$scratch/sys"

cat >"$scratch/bin/sudo" <<'SH'
#!/bin/bash
exec "$@"
SH
chmod +x "$scratch/bin/sudo"

export PATH="$scratch/bin:$PATH"
export OMARCHY_PATH="$ROOT"
export OMARCHY_MEM_SLEEP_FILE="$scratch/sys/mem_sleep"
export OMARCHY_S0IX_RESIDENCY_FILE="$scratch/sys/residency"
export OMARCHY_SUSPEND_SUCCESS_FILE="$scratch/sys/success"
export OMARCHY_BIOS_VERSION_FILE="$scratch/sys/bios"
export OMARCHY_UPTIME_FILE="$scratch/sys/uptime"
export OMARCHY_S0IX_DROP_IN="$scratch/conf.d/omarchy-s0ix-fallback.conf"
export OMARCHY_S0IX_PROBE_FILE="$scratch/probe"
export OMARCHY_S0IX_MIN_SECONDS=30
export OMARCHY_SLEEP_CONF_ROOTS="$scratch/conf.d"
export OMARCHY_S0IX_HOOK_SRC="$hook"
export OMARCHY_S0IX_HOOK_DST="$scratch/installed-hook"
export SYSTEMD_SLEEP_ACTION=suspend

drop_in="$scratch/conf.d/omarchy-s0ix-fallback.conf"

platform() {
  local mode=$1 residency=$2 success=$3 uptime=$4 bios=${5:-2.21.0}
  printf '%s\n' "$mode" >"$scratch/sys/mem_sleep"
  printf '%s\n' "$residency" >"$scratch/sys/residency"
  printf '%s\n' "$success" >"$scratch/sys/success"
  printf '%s 0\n' "$uptime" >"$scratch/sys/uptime"
  printf '%s\n' "$bios" >"$scratch/sys/bios"
}

run_hook() {
  "$hook" "$@"
}

run_migration() {
  bash -euo pipefail "$migration" >/dev/null
}

expected_drop_in() {
  printf '# omarchy-s0ix-fallback bios=%s\n[Sleep]\nMemorySleepMode=deep\n' "$1"
}

platform "[s2idle] deep" 0 3 1000
run_hook pre suspend
platform "[s2idle] deep" 0 4 1005
run_hook post suspend
[[ ! -e $drop_in && ! -e $scratch/probe ]] ||
  fail "a suspend shorter than the minimum does not switch to S3"
pass "a suspend shorter than the minimum does not switch to S3"

platform "[s2idle] deep" 10 4 2000
run_hook pre suspend
platform "[s2idle] deep" 4000000 5 2060
run_hook post suspend
[[ ! -e $drop_in ]] || fail "a suspend whose S0ix counter moved stays on s2idle"
pass "a suspend whose S0ix counter moved stays on s2idle"

platform "[s2idle] deep" 0 5 3000
run_hook pre suspend
platform "[s2idle] deep" 0 5 3100
run_hook post suspend
[[ ! -e $drop_in ]] || fail "a suspend that did not complete does not switch to S3"
pass "a suspend that did not complete does not switch to S3"

platform "s2idle" 0 6 4000
run_hook pre suspend
[[ ! -e $scratch/probe ]] || fail "a platform without ACPI S3 is left on s2idle"
pass "a platform without ACPI S3 is left on s2idle"

platform "s2idle [deep]" 0 6 4000
run_hook pre suspend
[[ ! -e $scratch/probe ]] || fail "a platform already using S3 is not measured again"
pass "a platform already using S3 is not measured again"

rm -f "$scratch/sys/residency"
platform "[s2idle] deep" 0 6 4000
rm -f "$scratch/sys/residency"
run_hook pre suspend
[[ ! -e $scratch/probe ]] || fail "a platform without an S0ix counter is left alone"
printf '0\n' >"$scratch/sys/residency"
pass "a platform without an S0ix counter is left alone"

platform "[s2idle] deep" 0 7 5000
run_hook pre hibernate
[[ ! -e $scratch/probe ]] || fail "hibernation is not treated as an s2idle measurement"
SYSTEMD_SLEEP_ACTION=hibernate run_hook pre suspend-then-hibernate
[[ ! -e $scratch/probe ]] || fail "the hibernate half of suspend-then-hibernate is not measured"
pass "hibernation is not treated as an s2idle measurement"

platform "[s2idle] deep" 0 8 6000 2.21.0
run_hook pre suspend
platform "[s2idle] deep" 0 9 6100 2.21.0
run_hook post suspend
[[ $(<"$drop_in") == "$(expected_drop_in 2.21.0)" ]] ||
  fail "a completed s2idle with a flat S0ix counter selects ACPI S3"
before=$(sha256sum "$drop_in")
run_hook pre suspend
run_hook post suspend
[[ $(sha256sum "$drop_in") == "$before" && ! -e $scratch/probe ]] ||
  fail "the same BIOS is not measured again after S3 is selected"
pass "a completed s2idle with a flat S0ix counter selects ACPI S3 once per BIOS"

platform "[s2idle] deep" 0 10 7000 2.22.0
run_hook pre suspend
[[ ! -e $drop_in && -f $scratch/probe ]] ||
  fail "a BIOS change clears the S3 choice and measures s2idle again"
platform "[s2idle] deep" 9000000 11 7100 2.22.0
run_hook post suspend
[[ ! -e $drop_in ]] || fail "a BIOS whose s2idle reaches S0ix stays on s2idle"
pass "a BIOS change is measured again and kept on s2idle when the counter moves"

platform "[s2idle] deep" 0 12 8000 2.23.0
run_hook pre suspend
platform "[s2idle] deep" 0 13 8100 2.23.0
run_hook post suspend
[[ $(<"$drop_in") == "$(expected_drop_in 2.23.0)" ]] ||
  fail "a new BIOS whose s2idle misses S0ix selects ACPI S3 again"
pass "a new BIOS whose s2idle misses S0ix selects ACPI S3 again"

printf '[Sleep]\nMemorySleepMode=s2idle\n' >"$scratch/conf.d/local.conf"
platform "[s2idle] deep" 0 14 9000 2.24.0
run_hook pre suspend
[[ ! -e $drop_in && ! -e $scratch/probe ]] ||
  fail "an administrator MemorySleepMode removes the fallback and is not replaced"
rm -f "$scratch/conf.d/local.conf"
pass "an administrator MemorySleepMode is left in place"

printf '# edited\n[Sleep]\nMemorySleepMode=shallow\n' >"$drop_in"
platform "[s2idle] deep" 0 15 10000
run_hook pre suspend
[[ $(<"$drop_in") == "$(printf '# edited\n[Sleep]\nMemorySleepMode=shallow\n')" && ! -e $scratch/probe ]] ||
  fail "an edited fallback file is left alone"
rm -f "$drop_in"
pass "an edited fallback file is left alone"

rm -f "$scratch/installed-hook"
run_migration
cmp -s "$hook" "$scratch/installed-hook" || fail "the migration installs the shipped hook"
run_migration
pass "the migration installs the shipped hook"

printf 'other\n' >"$scratch/installed-hook"
run_migration
[[ $(<"$scratch/installed-hook") == other ]] ||
  fail "the migration leaves a replaced hook alone"
pass "the migration leaves a replaced hook alone"

printf '#!/bin/bash\n# omarchy-s0ix-fallback old\n' >"$scratch/installed-hook"
run_migration
cmp -s "$hook" "$scratch/installed-hook" || fail "the migration refreshes the shipped hook"
pass "the migration refreshes the shipped hook"
