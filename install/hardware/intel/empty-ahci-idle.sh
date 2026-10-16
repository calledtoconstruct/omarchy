# Some machines leave an Intel RAID-mode SATA controller enabled with no
# disks behind it. ahci keeps that function in D0. Runtime suspend stays off
# when a port has a device or when NVMe is remapped behind the controller.

rules_dir=${OMARCHY_UDEV_RULES_DIR:-/etc/udev/rules.d}
pci_root=${OMARCHY_PCI_DEVICES_ROOT:-/sys/bus/pci/devices}
rule="$rules_dir/71-omarchy-empty-ahci-idle.rules"
rule_line='ACTION=="bind|change", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0x282a", ATTR{remapped_nvme}=="0", ATTR{power/control}="auto"'

empty_rst_devices() {
  local dev
  shopt -s nullglob
  for dev in "$pci_root"/*; do
    [[ -f $dev/vendor && -f $dev/device ]] || continue
    [[ $(<"$dev/vendor") == "0x8086" && $(<"$dev/device") == "0x282a" ]] || continue
    printf '%s\n' "$dev"
  done
  shopt -u nullglob
}

empty_rst_is_idle_candidate() {
  local dev class_file class found=0
  while IFS= read -r dev; do
    found=1
    [[ -f $dev/remapped_nvme && $(<"$dev/remapped_nvme") == "0" ]] || return 1
    shopt -s nullglob
    for class_file in "$dev"/ata*/link*/dev*/ata_device/*/class; do
      class=$(<"$class_file")
      [[ $class == "unknown" || -z $class ]] || {
        shopt -u nullglob
        return 1
      }
    done
    shopt -u nullglob
  done < <(empty_rst_devices)
  (( found > 0 ))
}

empty_rst_already_idle() {
  local dev
  [[ -f $rule ]] || return 1
  grep -qx "$rule_line" "$rule" || return 1
  while IFS= read -r dev; do
    [[ -f $dev/power/control && $(<"$dev/power/control") == "auto" ]] || return 1
  done < <(empty_rst_devices)
}

if ! empty_rst_already_idle && empty_rst_is_idle_candidate; then
  sudo install -Dm644 /dev/stdin "$rule" <<'EOF'
# The Intel RAID-mode SATA controller has no disks. Let it runtime-suspend
# while NVMe is not remapped behind it.
ACTION=="bind|change", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0x282a", ATTR{remapped_nvme}=="0", ATTR{power/control}="auto"
EOF
  while IFS= read -r dev; do
    [[ -f $dev/power/control ]] || continue
    printf 'auto\n' | sudo tee "$dev/power/control" >/dev/null
  done < <(empty_rst_devices)
  sudo udevadm control --reload
  sudo udevadm trigger --subsystem-match=pci --attr-match=vendor=0x8086 --attr-match=device=0x282a
fi
