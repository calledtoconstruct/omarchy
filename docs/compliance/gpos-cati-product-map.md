# GPOS CAT I product map

How Anduril NixOS STIG V1R2, Ubuntu 24.04 LTS STIG, and RHEL 9 STIG V2R9 implement each GPOS SRG V3R3 CAT I row, and what an Omarchy check/fix would be.

This is still an overlay. Product STIG IDs below belong to those vendors. Do not reuse them as Omarchy STIG IDs.

Sources: stigaview SRG-OS rule indexes, stigviewer NixOS V1R2 check text, RHEL-09-271040 from the RHEL 9 STIG. `none` means no CAT I twin showed up for that product on those indexes. NixOS often folds several SRGs into one finding.

NixOS CAT I findings used here: V-268089 (sshd ciphers; also covers 000250 and 000394), V-268130 (password hashes), V-268131 (no telnet), V-268144 (at rest), V-268146 (wireless), V-268154 (require-sigs), V-268157 (nonlocal integrity), V-268159 (transmitted information), V-268168 (FIPS; also 000396), V-268172 (no autologon), V-268176 (strong authenticators).

Machine-readable IDs: `gpos-cati-product-map.csv`. Status values match the overlay catalog.

## V-203603 / SRG-OS-000033-GPOS-00014

Remote access encryption.

- NixOS V-268089: `grep Ciphers /etc/ssh/sshd_config` must be `aes256-ctr,aes192-ctr,aes128-ctr`. Fix is `services.openssh.setting.Ciphers`.
- Ubuntu UBTU-24-100820 / UBTU-24-100840: SSH daemon FIPS 140-3 ciphers and KEX.
- RHEL RHEL-09-671010 FIPS mode plus RHEL-09-255065 DOD SSH ciphers.
- Omarchy check: sshd is off until `omarchy-setup-security-sshd`. When on, stock OpenSSH ciphers are not pinned.
- Omarchy fix: keep sshd off unless required; if on, pin Ciphers/MACs/KexAlgorithms. Status: partial.

## V-203629 / SRG-OS-000073-GPOS-00041

Encrypted password storage.

- NixOS V-268130: shadow hashes only.
- Ubuntu UBTU-24-400220: store only encrypted representations of passwords.
- RHEL RHEL-09-611140 shadow file plus RHEL-09-671015 FIPS hashes.
- Omarchy check: `ENCRYPT_METHOD` / pam_unix uses yescrypt. Not reversible.
- Omarchy fix: leave it. Status: implemented.

## V-203630 / SRG-OS-000074-GPOS-00042

Encrypted password transmission.

- NixOS V-268131: telnet package must not be installed.
- Ubuntu UBTU-24-100030: telnet package must not be installed.
- RHEL RHEL-09-215015: FTP server package must not be installed.
- Omarchy check: telnet/ftp servers are not in the default install; sshd is off.
- Omarchy fix: keep them off. Status: partial (no dedicated remote-auth cipher policy).

## V-203653 / SRG-OS-000125-GPOS-00065

Strong authenticators for nonlocal maintenance.

- NixOS V-268176: multifactor for nonlocal maintenance.
- Ubuntu UBTU-24-500050: strong authenticators for nonlocal maintenance.
- RHEL RHEL-09-255050: PAM interface for SSHD.
- Omarchy check: sshd off; FIDO2 is optional (`omarchy-setup-security-fido2`); MFA is not required.
- Omarchy fix: if sshd is enabled, require FIDO2 or equivalent. Status: gap.

## V-203669 / SRG-OS-000250-GPOS-00093

Integrity of remote access sessions.

- NixOS: folded into V-268089.
- Ubuntu UBTU-24-100830: SSH MACs.
- RHEL RHEL-09-255075: SSH MACs employing FIPS.
- Omarchy check/fix: same as V-203603, pin MACs. Status: partial.

## V-203682 / SRG-OS-000278-GPOS-00108

Crypto protection of audit tools.

- NixOS: not a CAT I.
- Ubuntu UBTU-24-909890: cryptographic integrity of audit tools.
- RHEL: no CAT I twin on stigaview (AIDE/audit hashes live at lower severity).
- Omarchy check: journald is default; no STIG-complete auditd/AIDE.
- Omarchy fix: auditd plus signed tool-integrity. Status: gap.

## V-203695 / SRG-OS-000324-GPOS-00125

Nonprivileged users must not execute privileged functions.

- NixOS: not a CAT I.
- Ubuntu 24: no CAT I twin on stigaview for this SRG.
- RHEL RHEL-09-432010: sudo package installed (RHEL also disables ctrl-alt-del bursts).
- Omarchy check: sudo prompts by default, but `omarchy-sudo-passwordless` can write `NOPASSWD: ALL`.
- Omarchy fix: refuse that command (regulated profile already does). Status: gap on default.

## V-203720 / SRG-OS-000366-GPOS-00153

Signed patches.

- NixOS V-268154: `grep require-sigs /etc/nix/nix.conf` must be true. Fix: `nix.settings.require-sigs = true`.
- Ubuntu UBTU-24-300001: APT must prevent unsigned packages.
- RHEL RHEL-09-214010 / RHEL-09-214025: GPG verification on vendor and all repos.
- Omarchy check: `SigLevel = Required DatabaseOptional` in `default/pacman/pacman-stable.conf`. OPR and Arch are signed. AUR is not.
- Omarchy fix: restricted stream only; no AUR on a regulated host. Status: partial.

## V-203736 / SRG-OS-000393-GPOS-00173

Integrity of nonlocal maintenance communications.

- NixOS V-268157.
- Ubuntu 24 / RHEL 9: no CAT I twin on stigaview (folded into SSH FIPS).
- Omarchy: treat sshd as the maintenance channel; apply V-203603 pins. Status: partial.

## V-203737 / SRG-OS-000394-GPOS-00174

Confidentiality of nonlocal maintenance communications.

- NixOS: folded into V-268089.
- Ubuntu 24 / RHEL 9: none on stigaview.
- Omarchy: same as V-203736. Status: partial.

## V-203739 / SRG-OS-000396-GPOS-00176

NSA-approved crypto for classified.

- NixOS: folded into V-268168 (FIPS, not Type-1).
- Ubuntu 24: none as CAT I (FIPS is UBTU-24-600030 under 000478).
- RHEL RHEL-09-215105: FIPS 140-3 systemwide crypto policy.
- Omarchy: stock Arch OpenSSL; no Type-1 or FIPS module. Status: gap. Do not claim classified suitability.

## V-203745 / SRG-OS-000404-GPOS-00183

At-rest integrity.

- NixOS V-268144.
- Ubuntu UBTU-20-010444 (24.04 not listed on stigaview for this SRG).
- RHEL 9: none as CAT I here (RHEL-09-231190 lives under 000405).
- Omarchy check: ISO requires LUKS on encrypted installs.
- Omarchy fix: gov image stays LUKS-mandatory. Status: implemented.

## V-203746 / SRG-OS-000405-GPOS-00184

At-rest confidentiality.

- NixOS V-268144.
- Ubuntu UBTU-20-010445.
- RHEL RHEL-09-231190: LUKS on local disk partitions.
- Omarchy: same LUKS check. Status: implemented.

## V-203748 / SRG-OS-000423-GPOS-00187

Protect transmitted information.

- NixOS V-268159.
- Ubuntu UBTU-24-100800 SSH installed; UBTU-24-100810 use SSH.
- RHEL RHEL-09-255010 / RHEL-09-255015: SSH installed and used.
- Omarchy: openssh is installed; sshd is off; mirrors are HTTPS.
- Omarchy fix: keep HTTPS; if remote admin is required, enable sshd with V-203603 pins. Status: partial.

## V-203749 / SRG-OS-000424-GPOS-00188

Crypto during transmission unless PDS.

- NixOS: folded into V-268089 / V-268159.
- Ubuntu 24 / RHEL 9: none on stigaview.
- Omarchy: same as V-203748. Status: partial.

## V-203776 / SRG-OS-000478-GPOS-00223

NIST FIPS-validated cryptography.

- NixOS V-268168: FIPS-validated cryptography (Satisfies 000478 and 000396).
- Ubuntu UBTU-24-600030.
- RHEL RHEL-09-671010 enable FIPS mode; RHEL-09-215105 crypto-policies.
- Omarchy check: no `fips=1` cmdline; no crypto-policies package.
- Omarchy fix: out of this overlay. Status: gap.

## V-203782 / SRG-OS-000480-GPOS-00229

No automatic logon.

- NixOS V-268172: `grep -iR autologon.user /etc/nixos` must not define a user. Fix: `services.xserver.displayManager.autologon.user = null`.
- Ubuntu UBTU-24-300031: no automatic login via SSH (graphical autologon is a separate Ubuntu rule).
- RHEL RHEL-09-271040: `AutomaticLoginEnable` in GNOME display manager must be false. V-258018 on stigviewer.
- Omarchy check: ISO/SDDM autologin on default encrypted installs; `/etc/pam.d/sddm-autologin` is in play.
- Omarchy fix: gov image sets SDDM `AutologinEnable=false` and drops sddm-autologin. Status: gap on default.

## V-252688 / SRG-OS-000481-GPOS-00481

Wireless peripherals.

- NixOS V-268146: wireless access encryption.
- Ubuntu UBTU-24-600230: disable all wireless network adapters.
- RHEL 9: no CAT I twin on stigaview.
- Omarchy check: bluetooth is in the desktop.
- Omarchy fix: disable bluetooth and Wi-Fi unless the AO approves. Status: gap.

## V-259333 / SRG-OS-000439-GPOS-00195

Updates within 30 days.

- NixOS: not a CAT I.
- Ubuntu UBTU-24-700400: vendor-supported release (stigaview indexes this ID here).
- RHEL 9: no CAT I twin on stigaview for this SRG.
- Omarchy check: `omarchy-update` exists; sidecar plus arch-audit is not yet the evidence.
- Omarchy fix: timer plus sidecar/arch-audit. Status: partial.

## V-278977 / SRG-OS-000830-GPOS-00300

Vendor-supported version.

- NixOS: not a CAT I.
- Ubuntu UBTU-24-700400 (same rule stigaview also lists under 000439).
- RHEL RHEL-09-211010: must be a vendor-supported release.
- Omarchy check: stable is the supported train; edge/rc/dev are not.
- Omarchy fix: gov image stays on stable. Status: partial.

## How to use this with DISA

Take `gpos-srg-v3r3-overlay.csv` plus this map. Check/Fix text is Omarchy-specific (pacman, SDDM, Hyprland lock, OPR sidecar). NixOS/Ubuntu/RHEL IDs are evidence that the same GPOS row is implementable. Submit via the [Vendor STIG Intent Form](https://forms.osi.apps.mil/r/pcgHzmn9KC) with a Department of War sponsor. Until DISA publishes a product STIG, this remains an overlay.
