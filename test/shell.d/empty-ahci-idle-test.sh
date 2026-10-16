#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/intel/empty-ahci-idle.sh"
migration="$ROOT/migrations/1792148300.sh"
all="$ROOT/install/hardware/all.sh"

bash -n "$leaf" || fail "the empty AHCI idle script has valid syntax"
bash -n "$migration" || fail "the empty AHCI idle migration has valid syntax"
grep -q 'run_logged .*hardware/intel/empty-ahci-idle.sh' "$all" ||
  fail "hardware setup lets an empty Intel RAID SATA controller idle"
! grep -q 'xps-9360-ahci-idle' "$leaf" "$migration" "$all" ||
  fail "the empty controller idle setting is not tied to a laptop model"
pass "the empty AHCI idle setting is valid and runs during hardware setup"

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin" "$scratch/rules" "$scratch/pci"

cat >"$scratch/bin/omarchy-hw-match" <<'SH'
#!/bin/bash
name=${TEST_PRODUCT_NAME:-}
family=${TEST_PRODUCT_FAMILY:-}
[[ ${name,,} == *"${1,,}"* || ${family,,} == *"${1,,}"* ]]
SH
cat >"$scratch/bin/sudo" <<'SH'
#!/bin/bash
exec "$@"
SH
cat >"$scratch/bin/udevadm" <<'SH'
#!/bin/bash
printf 'udevadm %s\n' "$*" >>"$CALL_LOG"
SH
chmod +x "$scratch/bin"/*

export CALL_LOG="$scratch/calls"
export PATH="$scratch/bin:$PATH"
export OMARCHY_PATH="$ROOT"
export OMARCHY_UDEV_RULES_DIR="$scratch/rules"
export OMARCHY_PCI_DEVICES_ROOT="$scratch/pci"
export TEST_PRODUCT_NAME="XPS 13 9360"
export TEST_PRODUCT_FAMILY="XPS"

rule="$scratch/rules/71-omarchy-empty-ahci-idle.rules"
rule_line='ACTION=="bind|change", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0x282a", ATTR{remapped_nvme}=="0", ATTR{power/control}="auto"'

controller() {
  local remap=$1 class=$2
  local dev="$scratch/pci/0000:00:17.0"
  rm -rf "$dev"
  mkdir -p "$dev/power" "$dev/ata1/link1/dev1.0/ata_device/dev1.0"
  printf '0x8086\n' >"$dev/vendor"
  printf '0x282a\n' >"$dev/device"
  printf '%s\n' "$remap" >"$dev/remapped_nvme"
  printf 'on\n' >"$dev/power/control"
  printf '%s\n' "$class" >"$dev/ata1/link1/dev1.0/ata_device/dev1.0/class"
}

run_leaf() {
  bash -eE -c 'source "$1"' bash "$leaf"
}

run_migration() {
  bash -euo pipefail "$migration" >/dev/null
}

reset() {
  : >"$CALL_LOG"
  rm -rf "$scratch/rules" "$scratch/pci"
  mkdir -p "$scratch/rules" "$scratch/pci"
}

reset
controller 1 unknown
run_leaf
[[ ! -e $rule && $(<"$scratch/pci/0000:00:17.0/power/control") == "on" && ! -s $CALL_LOG ]] ||
  fail "a remapped NVMe keeps the SATA controller awake"
pass "a remapped NVMe keeps the SATA controller awake"

reset
controller 0 ata
run_leaf
[[ ! -e $rule && $(<"$scratch/pci/0000:00:17.0/power/control") == "on" && ! -s $CALL_LOG ]] ||
  fail "a controller with a disk stays awake"
pass "a controller with a disk stays awake"

reset
run_leaf
[[ ! -e $rule && ! -s $CALL_LOG ]] || fail "a machine without the RAID controller is left alone"
pass "a machine without the RAID controller is left alone"

reset
controller 0 unknown
run_leaf
grep -qx "$rule_line" "$rule" || fail "hardware setup installs the runtime-suspend rule"
[[ $(<"$scratch/pci/0000:00:17.0/power/control") == "auto" ]] ||
  fail "hardware setup lets the empty controller runtime-suspend"
grep -q 'udevadm control --reload' "$CALL_LOG" || fail "hardware setup reloads udev"
: >"$CALL_LOG"
before=$(sha256sum "$rule")
run_leaf
[[ $(sha256sum "$rule") == "$before" && ! -s $CALL_LOG ]] ||
  fail "running hardware setup again leaves an idle controller alone"
run_migration
[[ ! -s $CALL_LOG ]] || fail "the migration leaves an idle controller alone"
pass "an empty Intel RAID SATA controller is allowed to runtime-suspend once"
