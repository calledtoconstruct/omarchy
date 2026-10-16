#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/dell/xps-9360-ahci-idle.sh"
migration="$ROOT/migrations/1792148300.sh"
all="$ROOT/install/hardware/all.sh"

bash -n "$leaf" || fail "the XPS 13 9360 AHCI idle script has valid syntax"
bash -n "$migration" || fail "the XPS 13 9360 AHCI idle migration has valid syntax"
grep -q 'run_logged .*hardware/dell/xps-9360-ahci-idle.sh' "$all" ||
  fail "hardware setup lets the XPS 13 9360's empty SATA controller idle"
pass "the XPS 13 9360 AHCI idle setting is valid and runs during hardware setup"

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

rule="$scratch/rules/71-omarchy-xps-9360-ahci-idle.rules"
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

for product in "XPS 13 9310" "XPS 13 9365"; do
  reset
  controller 0 unknown
  TEST_PRODUCT_NAME="$product" run_leaf
  TEST_PRODUCT_NAME="$product" run_migration
  [[ ! -e $rule && $(<"$scratch/pci/0000:00:17.0/power/control") == "on" && ! -s $CALL_LOG ]] ||
    fail "other machines do not idle the SATA controller"
done
pass "other machines do not idle the SATA controller"

TEST_PRODUCT_NAME="XPS 13 9360"

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
pass "an empty XPS 13 9360 SATA controller is allowed to runtime-suspend once"
