# Corporate regulated profile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Opt-in regulated profile that sets a 15-minute lock, refuses passwordless sudo, and emits a fail-closed exposure report.

**Architecture:** A marker file under `$OMARCHY_CONFIG_HOME` (default `~/.config/omarchy`) named `profile` with contents `regulated`. Apply/status/disable are one CLI. Passwordless sudo checks the marker. Risk report reuses sidecar schema v1 and fails closed when the marker is present.

**Tech Stack:** bash, jq, existing shell test harness

**Spec:** `docs/superpowers/specs/2026-09-22-opr-risk-streams-design.md`

## Global Constraints

- Work only in this omarchy worktree on `feat/corporate-regulated-profile`
- Do not change packaged `config/omarchy/shell.json` default `idle.lock` 300
- Do not push
- Profile is opt-in. Apply edits the user `shell.json` copy, never the packaged default
- Marker path: `${OMARCHY_CONFIG_HOME:-$HOME/.config/omarchy}/profile`
- Snapshot previous `idle.lock` to `${OMARCHY_CONFIG_HOME:-$HOME/.config/omarchy}/profile.regulated.prev.json` so disable can restore
- `omarchy-sudo-passwordless` must refuse when marker is `regulated`, even if gum would confirm
- Risk report `--fail-closed` is implied when the marker is `regulated`

## File structure

- Create: `bin/omarchy-profile-regulated`
- Create: `bin/omarchy-risk-report`
- Create: `test/shell.d/profile-regulated-test.sh`
- Create: `test/shell.d/risk-report-test.sh`
- Modify: `bin/omarchy-sudo-passwordless`
- Modify: `test/shell.d/nopasswd-sudo-expiry-test.sh` only if a new refusal case belongs there; prefer the new profile test file

---

### Task 1: Profile apply/status/disable and 15-minute lock

**Files:**
- Create: `bin/omarchy-profile-regulated`
- Create: `test/shell.d/profile-regulated-test.sh`

**Interfaces:**
- Consumes: user shell.json at `${OMARCHY_CONFIG_HOME:-$HOME/.config/omarchy}/shell.json` (create `{"version":1,"idle":{"lock":300}}` if missing)
- Produces:
  - `omarchy-profile-regulated apply|status|disable`
  - apply writes marker `regulated`, sets `.idle.lock` to 900, snapshots previous lock
  - status prints `regulated` or `default` and the current lock
  - disable removes marker and restores snapshot lock

- [ ] **Step 1: Write the failing test**

```bash
#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
require_command jq

cmd="$ROOT/bin/omarchy-profile-regulated"
[[ -x $cmd ]] || fail "omarchy-profile-regulated is executable"

home=$(mktemp -d)
trap 'rm -rf "$home"' EXIT
export HOME="$home"
export OMARCHY_CONFIG_HOME="$home/.config/omarchy"
mkdir -p "$OMARCHY_CONFIG_HOME"
cat >"$OMARCHY_CONFIG_HOME/shell.json" <<'EOF'
{"version":1,"idle":{"screensaver":150,"lock":300}}
EOF

"$cmd" status | grep -q default || fail "status starts default"

"$cmd" apply
[[ $(cat "$OMARCHY_CONFIG_HOME/profile") == regulated ]] || fail "apply writes regulated marker"
[[ $(jq -r '.idle.lock' "$OMARCHY_CONFIG_HOME/shell.json") == 900 ]] || fail "apply sets idle.lock 900"
[[ $(jq -r '.idle.lock' "$OMARCHY_CONFIG_HOME/profile.regulated.prev.json") == 300 ]] || fail "apply snapshots previous lock"
[[ $(jq -r '.idle.screensaver' "$OMARCHY_CONFIG_HOME/shell.json") == 150 ]] || fail "apply leaves other idle keys"

"$cmd" status | grep -q regulated || fail "status is regulated after apply"

"$cmd" disable
[[ ! -e $OMARCHY_CONFIG_HOME/profile ]] || fail "disable removes marker"
[[ $(jq -r '.idle.lock' "$OMARCHY_CONFIG_HOME/shell.json") == 300 ]] || fail "disable restores lock 300"

pass "regulated profile apply status disable"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash test/shell.d/profile-regulated-test.sh`

Expected: FAIL `omarchy-profile-regulated is executable`

- [ ] **Step 3: Write minimal implementation**

`bin/omarchy-profile-regulated`:

```bash
#!/bin/bash
# omarchy:summary=Opt in to the corporate regulated profile (15-minute lock, no passwordless sudo).
# omarchy:args=<apply|status|disable>

set -euo pipefail

cfg="${OMARCHY_CONFIG_HOME:-$HOME/.config/omarchy}"
marker="$cfg/profile"
prev="$cfg/profile.regulated.prev.json"
shell="$cfg/shell.json"

usage() { echo "Usage: omarchy-profile-regulated <apply|status|disable>"; }

ensure_shell() {
  mkdir -p "$cfg"
  if [[ ! -f $shell ]]; then
    printf '%s\n' '{"version":1,"idle":{"lock":300}}' >"$shell"
  fi
}

case ${1:-} in
status)
  if [[ -f $marker && $(<"$marker") == regulated ]]; then
    echo "regulated"
  else
    echo "default"
  fi
  if [[ -f $shell ]]; then
    echo "idle.lock=$(jq -r '.idle.lock // empty' "$shell")"
  fi
  ;;
apply)
  ensure_shell
  mkdir -p "$cfg"
  jq '{idle:{lock:(.idle.lock // 300)}}' "$shell" >"$prev"
  tmp=$(mktemp)
  jq '.idle.lock = 900' "$shell" >"$tmp"
  mv "$tmp" "$shell"
  printf 'regulated\n' >"$marker"
  echo "Regulated profile on. idle.lock=900. Passwordless sudo is refused until you disable this."
  ;;
disable)
  if [[ -f $prev && -f $shell ]]; then
    old=$(jq -r '.idle.lock' "$prev")
    tmp=$(mktemp)
    jq --argjson lock "$old" '.idle.lock = $lock' "$shell" >"$tmp"
    mv "$tmp" "$shell"
  fi
  rm -f "$marker" "$prev"
  echo "Regulated profile off."
  ;;
*)
  usage >&2
  exit 1
  ;;
esac
```

chmod +x.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash test/shell.d/profile-regulated-test.sh`

Expected: `ok - regulated profile apply status disable`

- [ ] **Step 5: Commit**

```bash
git add bin/omarchy-profile-regulated test/shell.d/profile-regulated-test.sh
git commit -m "feat: opt-in regulated profile with 15-minute lock"
```

---

### Task 2: Refuse passwordless sudo while regulated

**Files:**
- Modify: `bin/omarchy-sudo-passwordless`
- Modify: `test/shell.d/profile-regulated-test.sh` (add a second assertion block in the same file or a new function run after the first pass)

**Interfaces:**
- Consumes: same marker path as Task 1
- Produces: `omarchy-sudo-passwordless` prints an error to stderr and exits 1 without calling gum when marker is `regulated`

- [ ] **Step 1: Write the failing test**

Append to `test/shell.d/profile-regulated-test.sh` before the final `pass`, using a subshell HOME:

After disable in the existing test, re-apply, then:

```bash
export PATH="/usr/bin:/bin"
set +e
err=$("$ROOT/bin/omarchy-sudo-passwordless" 2>&1)
rc=$?
set -e
[[ $rc -eq 1 ]] || fail "passwordless sudo refused under regulated" "exit $rc"
grep -qi 'regulated' <<<"$err" || fail "refusal names the regulated profile"
```

Do not mock gum for this case. If the script reaches gum, the test should fail.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash test/shell.d/profile-regulated-test.sh`

Expected: FAIL `passwordless sudo refused under regulated`

- [ ] **Step 3: Write minimal implementation**

Near the top of `bin/omarchy-sudo-passwordless`, after `set`/usage parsing and before any gum confirm:

```bash
profile_marker="${OMARCHY_CONFIG_HOME:-$HOME/.config/omarchy}/profile"
if [[ -f $profile_marker && $(<"$profile_marker") == regulated ]]; then
  echo "Passwordless sudo is disabled while the regulated profile is on. Run omarchy-profile-regulated disable first." >&2
  exit 1
fi
```

Do not change expiry, tmpfiles, or the warning text for the default path.

- [ ] **Step 4: Run tests**

Run: `bash test/shell.d/profile-regulated-test.sh` and `bash test/shell.d/nopasswd-sudo-expiry-test.sh`

Expected: both pass.

- [ ] **Step 5: Commit**

```bash
git add bin/omarchy-sudo-passwordless test/shell.d/profile-regulated-test.sh
git commit -m "feat: refuse passwordless sudo under regulated profile"
```

---

### Task 3: Exposure report, fail-closed when regulated

**Files:**
- Create: `bin/omarchy-risk-report`
- Create: `test/shell.d/risk-report-test.sh`
- Reuse: `test/shell.d/fixtures/advisories/omarchy.advisories.json` if present; otherwise create the same fixture as the advisory-warnings plan (copy the JSON from that plan verbatim)

**Interfaces:**
- Consumes: `--sidecar PATH`, `--installed-file PATH`, `--arch-audit-file PATH` (optional JSON array of `{ "name": "openssl", "cve": "CVE-...", "severity": "High" }`)
- Produces: human summary plus `--json`. Exit 2 when fail-closed and any HIGH/CRITICAL CVE, sidecar missing, or scan_status error. Fail-closed is on if `--fail-closed` or marker is `regulated`. Default (no marker) exits 0.

- [ ] **Step 1: Write the failing test**

Create the sidecar fixture if missing (same JSON as advisory-warnings plan).

```bash
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

sidecar="$ROOT/test/shell.d/fixtures/advisories/omarchy.advisories.json"
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash test/shell.d/risk-report-test.sh`

Expected: FAIL `omarchy-risk-report is executable`

- [ ] **Step 3: Write minimal implementation**

`bin/omarchy-risk-report` reads sidecar like the advisory CLI, plus optional arch-audit file. JSON shape:

```json
{"profile":"regulated","opr":[],"arch":[],"closed":true}
```

Human output lists OPR HIGH rows and arch-audit HIGH rows.

Exit 2 if closed and (`opr` has HIGH/CRITICAL or missing sidecar or `arch` has High/Critical).

chmod +x. Include `# omarchy:summary=`.

- [ ] **Step 4: Run tests**

Run: `bash test/shell.d/risk-report-test.sh && bash test/shell.d/profile-regulated-test.sh`

Expected: both pass.

- [ ] **Step 5: Commit**

```bash
git add bin/omarchy-risk-report test/shell.d/risk-report-test.sh test/shell.d/fixtures/advisories/omarchy.advisories.json
git commit -m "feat: corporate risk report fail-closed under regulated profile"
```
