# Compliance overlay packet

This directory is an overlay onto DISA GPOS SRG V3R3 (General Purpose OS SRG, 2025-09-22).
It is not a DISA STIG, not an Arch Linux STIG, and not an authorization to operate.
This packet is not an official STIG.
Submit it as vendor-produced evidence with an Omarchy stable image and the restricted package stream.

Status vocabulary is `implemented`, `partial`, `gap`, and `not-applicable`. Honest gap rows are required; do not invent STIG IDs.

Files:

- `gpos-srg-v3r3-overlay.md` — cover letter and catalog
- `gpos-srg-v3r3-overlay.csv` — machine-readable rows for the same GPOS V-IDs
- `gpos-cati-product-map.md` — CAT I Check/Fix map against NixOS, Ubuntu 24.04, and RHEL 9
- `gpos-cati-product-map.csv` — the same map as IDs only

`omarchy-gpos-overlay` reads this catalog and reports each row against a machine. It does not change `idle.lock`, sudo, or sshd. FIPS and NSA-approved crypto stay gaps in this slice.
