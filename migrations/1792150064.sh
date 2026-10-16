echo "Install the S0ix fallback sleep hook"

# systemd only runs hooks from /usr/lib/systemd/system-sleep. The source ships
# in the settings package's default tree; install it there when that tree
# already contains it. A hook already at the destination that is not ours is
# left alone. Ours is replaced when the shipped copy changes.

hook_src="${OMARCHY_S0IX_HOOK_SRC:-$OMARCHY_PATH/default/systemd/system-sleep/omarchy-s0ix-fallback}"
hook_dst="${OMARCHY_S0IX_HOOK_DST:-/usr/lib/systemd/system-sleep/omarchy-s0ix-fallback}"

[[ -f $hook_src ]] || exit 0

if [[ -e $hook_dst ]]; then
  cmp -s "$hook_src" "$hook_dst" && exit 0
  grep -q 'omarchy-s0ix-fallback' "$hook_dst" || exit 0
fi

sudo install -Dm755 "$hook_src" "$hook_dst"
