echo "Let an empty Intel RAID-mode SATA controller runtime-suspend"

# See install/hardware/intel/empty-ahci-idle.sh. The script leaves an
# already-idle controller alone, and it does nothing when a disk is present
# or NVMe is remapped behind the controller.

source "$OMARCHY_PATH/install/hardware/intel/empty-ahci-idle.sh"
