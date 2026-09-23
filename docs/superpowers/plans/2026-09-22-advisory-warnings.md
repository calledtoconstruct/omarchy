# Average-user advisory warnings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a fail-open CLI that reports known CVEs for OPR packages from `omarchy.advisories.json` without blocking install or update.

**Architecture:** New `bin/omarchy-pkg-advisories` reads a sidecar file, matches installed package versions from a list, and prints warnings. Missing sidecar is a warning and exit 0. No pacman transaction hook in this slice.

**Tech Stack:** bash, jq, existing `test/shell.d` harness

**Spec:** `docs/superpowers/specs/2026-09-22-opr-risk-streams-design.md`

## Global Constraints

- Work only in this omarchy worktree on `feat/advisory-warnings`
- Do not change `config/omarchy/shell.json` default `idle.lock` 300
- Do not touch `bin/omarchy-sudo-passwordless`
- Fail-open: missing sidecar, missing row, stale, or error prints a warning and exits 0 unless `--fail-closed` is passed
- Do not call live OSV or arch-audit
- Command metadata must include `# omarchy:summary=`
- Tests go in `test/shell.d/pkg-advisories-test.sh` and must pass under `./test/shell` for that file

## File structure

- Create: `bin/omarchy-pkg-advisories`
- Create: `test/shell.d/pkg-advisories-test.sh`
- Create: `test/shell.d/fixtures/advisories/omarchy.advisories.json`

---

### Task 1: Fail-open advisory CLI

**Files:**
- Create: `bin/omarchy-pkg-advisories`
- Create: `test/shell.d/pkg-advisories-test.sh`
- Create: `test/shell.d/fixtures/advisories/omarchy.advisories.json`

**Interfaces:**
- Consumes: sidecar schema v1 (`schema`, `advisories` keyed by `pkgname:pkgver-pkgrel:arch`)
- Produces: `omarchy-pkg-advisories [--sidecar PATH] [--installed-file PATH] [--json] [--fail-closed]`
  - `--installed-file` lines are `pkgname pkgver-pkgrel arch` (tests never need pacman)
  - stdout human lines by default; `--json` prints an array of finding objects
  - exit 0 fail-open; exit 2 only with `--fail-closed` when sidecar missing or any `scan_status` is `error` or a HIGH/CRITICAL CVE is present

- [ ] **Step 1: Write the failing test**

`test/shell.d/fixtures/advisories/omarchy.advisories.json`:

```json
{
  "schema": 1,
  "channel": "edge",
  "arch": "x86_64",
  "generated_at": "2026-09-22T00:00:00Z",
  "advisories": {
    "mise-bin:2026.9.4-1:x86_64": {
      "pkgname": "mise-bin",
      "pkgver": "2026.9.4",
      "pkgrel": "1",
      "arch": "x86_64",
      "artifact": "mise-bin-2026.9.4-1-x86_64.pkg.tar.zst",
      "cve_ids": ["CVE-2026-4242"],
      "cve_max_severity": "HIGH",
      "severity_scale": "CVSSv3",
      "advisory_as_of": "2026-09-21T00:00:00Z",
      "scanned_at": "2026-09-22T00:00:00Z",
      "scan_source": "osv.dev",
      "scan_status": "ok",
      "note": ""
    },
    "bun-bin:1.0.0-1:x86_64": {
      "pkgname": "bun-bin",
      "pkgver": "1.0.0",
      "pkgrel": "1",
      "arch": "x86_64",
      "artifact": "bun-bin-1.0.0-1-x86_64.pkg.tar.zst",
      "cve_ids": [],
      "cve_max_severity": "NONE",
      "severity_scale": "",
      "advisory_as_of": "",
      "scanned_at": "2026-09-22T00:00:00Z",
      "scan_source": "osv.dev",
      "scan_status": "missing",
      "note": ""
    }
  }
}
```

`test/shell.d/pkg-advisories-test.sh`:

```bash
#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
require_command jq

cmd="$ROOT/bin/omarchy-pkg-advisories"
sidecar="$ROOT/test/shell.d/fixtures/advisories/omarchy.advisories.json"
installed=$(mktemp)
trap 'rm -f "$installed"' EXIT
cat >"$installed" <<'EOF'
mise-bin 2026.9.4-1 x86_64
bun-bin 1.0.0-1 x86_64
unknown-pkg 1-1 x86_64
EOF

[[ -x $cmd ]] || fail "omarchy-pkg-advisories is executable"

out=$("$cmd" --sidecar "$sidecar" --installed-file "$installed") || status=$?
status=${status:-0}
[[ $status -eq 0 ]] || fail "fail-open exits 0" "exit $status"
grep -q 'CVE-2026-4242' <<<"$out" || fail "prints HIGH CVE for mise-bin"
grep -q 'bun-bin' <<<"$out" || fail "mentions missing bun-bin row status"
grep -q 'unknown-pkg' <<<"$out" || fail "mentions packages with no sidecar row"

"$cmd" --sidecar /no/such/sidecar.json --installed-file "$installed" >/tmp/omarchy-adv-missing.out
[[ $? -eq 0 ]] || fail "missing sidecar is fail-open exit 0"
grep -qi 'sidecar' /tmp/omarchy-adv-missing.out || fail "missing sidecar prints a warning"

"$cmd" --sidecar "$sidecar" --installed-file "$installed" --fail-closed
[[ $? -eq 2 ]] || fail "fail-closed exits 2 when a HIGH CVE is present"

json=$("$cmd" --sidecar "$sidecar" --installed-file "$installed" --json)
jq -e '.[] | select(.pkgname=="mise-bin" and .cve_ids[0]=="CVE-2026-4242")' <<<"$json" >/dev/null \
  || fail "json includes mise-bin CVE"

pass "pkg advisories fail-open CLI"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash test/shell.d/pkg-advisories-test.sh`

Expected: FAIL `omarchy-pkg-advisories is executable`

- [ ] **Step 3: Write minimal implementation**

`bin/omarchy-pkg-advisories`:

```bash
#!/bin/bash
# omarchy:summary=Show known CVEs for installed OPR packages from the advisory sidecar.
# omarchy:args=[--sidecar PATH] [--installed-file PATH] [--json] [--fail-closed]

set -euo pipefail

SIDECAR=""
INSTALLED_FILE=""
JSON=0
FAIL_CLOSED=0

while [[ $# -gt 0 ]]; do
  case $1 in
  --sidecar) SIDECAR=$2; shift 2 ;;
  --installed-file) INSTALLED_FILE=$2; shift 2 ;;
  --json) JSON=1; shift ;;
  --fail-closed) FAIL_CLOSED=1; shift ;;
  -h|--help) echo "Usage: omarchy-pkg-advisories [--sidecar PATH] [--installed-file PATH] [--json] [--fail-closed]"; exit 0 ;;
  *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z $SIDECAR ]]; then
  for candidate in \
    /var/lib/pacman/sync/omarchy.advisories.json \
    /usr/share/omarchy/advisories/omarchy.advisories.json; do
    [[ -f $candidate ]] && SIDECAR=$candidate && break
  done
fi

if [[ -z $SIDECAR || ! -f $SIDECAR ]]; then
  echo "advisory sidecar not found; skipping CVE warnings (fail-open)" >&2
  echo "advisory sidecar not found; skipping CVE warnings (fail-open)"
  if [[ $FAIL_CLOSED -eq 1 ]]; then
    exit 2
  fi
  exit 0
fi

# Read installed list. Each line: name version arch
# version is pkgver-pkgrel.
load_installed() {
  if [[ -n $INSTALLED_FILE ]]; then
    cat "$INSTALLED_FILE"
    return
  fi
  pacman -Q --info 2>/dev/null | awk '
    $1=="Name" && $2==":" {name=$3}
    $1=="Version" && $2==":" {ver=$3}
    $1=="Architecture" && $2==":" {print name, ver, $3}
  '
}

findings_json=$(mktemp)
echo '[]' >"$findings_json"
trap 'rm -f "$findings_json"' EXIT

closed_hit=0
while read -r name ver arch; do
  [[ -z ${name:-} ]] && continue
  key="${name}:${ver}:${arch}"
  row=$(jq -c --arg k "$key" '.advisories[$k] // null' "$SIDECAR")
  if [[ $row == null ]]; then
    closed_hit=1
    if [[ $JSON -eq 0 ]]; then
      echo "warning: no OPR advisory row for $key"
    fi
    jq --arg pkg "$name" --arg ver "$ver" --arg arch "$arch" \
      '. + [{pkgname:$pkg, pkgver:$ver, arch:$arch, scan_status:"absent", cve_ids:[], cve_max_severity:"NONE"}]' \
      "$findings_json" >"$findings_json.new" && mv "$findings_json.new" "$findings_json"
    continue
  fi
  status=$(jq -r '.scan_status' <<<"$row")
  sev=$(jq -r '.cve_max_severity // "NONE"' <<<"$row")
  cves=$(jq -r '.cve_ids // [] | join(" ")' <<<"$row")
  if [[ $status == error || $sev == HIGH || $sev == CRITICAL ]]; then
    closed_hit=1
  fi
  if [[ $JSON -eq 0 ]]; then
    echo "$name $ver $arch status=$status severity=$sev cves=${cves:-none}"
  fi
  jq --argjson row "$row" '. + [$row]' "$findings_json" >"$findings_json.new" && mv "$findings_json.new" "$findings_json"
done < <(load_installed)

if [[ $JSON -eq 1 ]]; then
  cat "$findings_json"
fi

if [[ $FAIL_CLOSED -eq 1 && $closed_hit -eq 1 ]]; then
  exit 2
fi
exit 0
```

chmod +x `bin/omarchy-pkg-advisories`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash test/shell.d/pkg-advisories-test.sh`

Expected: `ok - pkg advisories fail-open CLI`

If `set -e` makes the missing-sidecar invocation abort before `[[ $? -eq 0 ]]`, write that case as:

```bash
set +e
"$cmd" --sidecar /no/such/sidecar.json --installed-file "$installed" >/tmp/omarchy-adv-missing.out
miss=$?
set -e
[[ $miss -eq 0 ]] || fail "missing sidecar is fail-open exit 0"
```

Same pattern for `--fail-closed`.

- [ ] **Step 5: Commit**

```bash
git add bin/omarchy-pkg-advisories test/shell.d/pkg-advisories-test.sh test/shell.d/fixtures/advisories/omarchy.advisories.json
git commit -m "feat: fail-open OPR advisory warnings"
```
