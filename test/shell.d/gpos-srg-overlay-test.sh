#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

csv="$ROOT/docs/compliance/gpos-srg-v3r3-overlay.csv"
md="$ROOT/docs/compliance/gpos-srg-v3r3-overlay.md"
readme="$ROOT/docs/compliance/README.md"

[[ -f $csv ]] || fail "overlay csv exists"
[[ -f $md ]] || fail "overlay markdown exists"
[[ -f $readme ]] || fail "compliance README exists"

grep -qi 'not an official STIG' "$readme" || fail "README denies STIG status"
grep -qi 'GPOS SRG' "$readme" || fail "README names GPOS SRG"
grep -qiE 'omarchy STIG|official STIG of Arch' "$readme" && fail "README must not claim an Omarchy or Arch STIG"

header=$(head -1 "$csv")
[[ $header == "vuln_id,severity,title,status,omarchy_mechanism,evidence,gap,srg_id" ]] || fail "csv header matches contract" "$header"

ids='V-203603 V-203629 V-203630 V-203653 V-203669 V-203682 V-203695 V-203720 V-203736 V-203737 V-203739 V-203745 V-203746 V-203748 V-203749 V-203776 V-203782 V-252688 V-259333 V-278977 V-203599'
for id in $ids; do
  grep -q "^$id," "$csv" || fail "csv contains $id"
  grep -q "$id" "$md" || fail "markdown contains $id"
done

row_count=$(tail -n +2 "$csv" | grep -c .)
[[ $row_count -eq 21 ]] || fail "csv has 21 data rows" "$row_count"

while IFS= read -r line; do
  [[ -z $line ]] && continue
  status=$(printf '%s\n' "$line" | cut -d, -f4)
  case $status in
  implemented|partial|gap|not-applicable) ;;
  *) fail "status vocabulary" "$status" ;;
  esac
done < <(tail -n +2 "$csv")

grep -q '^V-203782,.*,gap,' "$csv" || fail "autologin remains a gap"
grep -q '^V-203776,.*,gap,' "$csv" || fail "FIPS remains a gap"
grep -q '^V-203739,.*,gap,' "$csv" || fail "NSA crypto remains a gap"

pass "gpos srg overlay packet"
