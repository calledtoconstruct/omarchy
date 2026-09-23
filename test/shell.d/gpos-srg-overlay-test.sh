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

map_csv="$ROOT/docs/compliance/gpos-cati-product-map.csv"
map_md="$ROOT/docs/compliance/gpos-cati-product-map.md"
[[ -f $map_csv ]] || fail "product map csv exists"
[[ -f $map_md ]] || fail "product map markdown exists"
grep -qi 'not reuse them as Omarchy STIG IDs' "$map_md" || fail "product map denies minting Omarchy STIG IDs"

map_header=$(head -1 "$map_csv")
[[ $map_header == "gpos_id,srg_id,nixos,ubuntu,rhel,status" ]] || fail "product map csv header" "$map_header"

cati_ids='V-203603 V-203629 V-203630 V-203653 V-203669 V-203682 V-203695 V-203720 V-203736 V-203737 V-203739 V-203745 V-203746 V-203748 V-203749 V-203776 V-203782 V-252688 V-259333 V-278977'
for id in $cati_ids; do
  grep -q "^$id," "$map_csv" || fail "product map csv contains $id"
  grep -q "$id" "$map_md" || fail "product map markdown contains $id"
done

map_count=$(tail -n +2 "$map_csv" | grep -c .)
[[ $map_count -eq 20 ]] || fail "product map csv has 20 CAT I rows" "$map_count"

grep -q '^V-203782,.*,V-268172,.*,RHEL-09-271040,gap$' "$map_csv" || fail "autologon maps to NixOS V-268172 and RHEL-09-271040"
grep -q '^V-203776,.*,V-268168,.*,gap$' "$map_csv" || fail "FIPS stays a gap in the product map"
grep -q 'RHEL-09-graphical-autologon' "$map_csv" && fail "product map must not invent RHEL STIG IDs"

pass "gpos srg overlay packet"
