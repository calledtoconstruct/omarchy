echo "Let the Dell XPS 13 9360's empty SATA controller runtime-suspend"

# See install/hardware/dell/xps-9360-ahci-idle.sh. The script leaves an
# already-idle controller alone, so a second user does not write the rule again.

omarchy-hw-match "XPS 13 9360" || exit 0

source "$OMARCHY_PATH/install/hardware/dell/xps-9360-ahci-idle.sh"
