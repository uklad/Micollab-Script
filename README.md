# Micollab Patch Installer
A simple bash script to quickly apply CVE-2024-35287, CVE-2024-41713, CVE-2024-41714, CVE-2024-47223, CVE-2025-52914 (MISA-2025-0008), MISA-2026-0006 and MISA-2026-0012 to MiCollab servers running 6.0 - 10.3 software.

## Installation
Script will check the current MiCollab version and preselect the recommended patch(es).
```
curl -fsSL https://github.com/uklad/Micollab-Script/raw/main/script.sh | bash
```
The MiCollab version is checked automatically via `config getprop sysconfig MasVersion`, and the appropriate patch(es) are pre-selected in the checklist. You can still tick/untick options manually before confirming.

## Preselection by version

| MiCollab Version | Preselected Option(s) |
|---|---|
| 9.7.0.27 | 4 |
| 9.7.1.13 | 1, 4 |
| 9.7.1.110 | 4 |
| 9.8.0.33 | 2, 4, 5, 10 |
| 9.8.1.5 | 3, 4, 5, 10 |
| 9.8.1.108 | 4, 5, 10 |
| 9.8.1.201 | 4, 5, 10 |
| 9.8.2.12 | 4, 10 |
| Any other 9.8.x.x below 9.8.3.103 (e.g. 9.8.3.1) | 10 |
| 9.8.3.203 | 7 |
| 10.0.x.x | 11 |
| 10.2.1.205 | 8 |
| 10.3.0.18 | 9 |
| Any other version | none |

For MiCollab 6.0 - 9.7 and MiVB-X, manually select **option 6** for the correct CVE-2024-41713 patch file (this is not auto-preselected).

## Menu options

| # | Description |
|---|---|
| 1 | 9.7 SP1 (9.7.1.13) - CVE-2024-41714 |
| 2 | 9.8 GA (9.8.0.33) - CVE-2024-41714 & CVE-2024-35287 |
| 3 | 9.8 SP1 (9.8.1.5) - CVE-2024-41714 & CVE-2024-35287 |
| 4 | 9.7 to 9.8 SP2 (9.7.0.27 - 9.8.2.12) - CVE-2024-41713 |
| 5 | 9.8 GA to 9.8 SP1FP2 (9.8.0.33 - 9.8.1.201) - CVE-2024-47223 — **reboot required** |
| 6 | 6.0 to 9.8 SP1FP2 + MiVB-X (6.0.206.0 - 9.8.1.201) - CVE-2024-41713 |
| 7 | 9.8 SP3FP1 (9.8.3.203) - MISA-2026-0006 |
| 8 | 10.2 SP1FP2 (10.2.1.205) - MISA-2026-0006 |
| 9 | 10.3 (10.3.0.18) - MISA-2026-0012 (MTLVULN-1861, 1862, 1863, 1864, 1877) |
| 10 | 9.8 (9.8.x.x below 9.8.3.103) - CVE-2025-52914 (MISA-2025-0008) |
| 11 | 10.0 (10.0.x.x) - CVE-2025-52914 (MISA-2025-0008) |

## Notes
- Requires `curl` (used to download the script and the patch files).
- Requires `dialog` to be installed on the server; the script will exit with an error if it's not found.
- **RPM-based options (5, 7, 8, 9)** are checked before the menu opens. If the patch's RPM is already installed, the option is shown in green, labelled with its install date from the RPM database (e.g. `[INSTALLED 2026-11-17]`, or `[ALREADY INSTALLED]` if the date can't be read), and is not preselected. Menu colours: green = already installed, red = recommended for this version, yellow = not required. If you tick it anyway, the install is skipped.
- **Options 4 and 6 (CVE-2024-41713)** are checked the same way, using the NPM Revision file `/usr/vm/config/Revision` (the same record `sinfo` shows). If the latest entry is `Patch notes: CVE-2024-41713 : Path Traversal Combined Fix Patch`, both options are shown green with the date it was applied, and are skipped if ticked. If the patch was later removed with `patcher.sh -r` (a `REVERSED` entry), it counts as not applied. Mitel notes this patch also corrects CVE-2025-52913 (MISA-2025-0007).
- Options 1, 2 and 3 (file-based patches) have no such check, so reapplying them is not prevented.
- The script may pause for a few seconds at points during installation. Options 2, 3, 4 and 6 run a Mitel `patcher.sh` that asks whether to run maintenance from Hard Disk: answer **N**.
- The patch for CVE-2024-47223 (option 5) requires a reboot to take effect.
- Options 7 and 8 (MISA-2026-0006) each download a zip containing two RPMs: the patch, and the original version for reverting. The script installs only the patch, as in Mitel's instructions:
  - Option 7 (9.8.3.203): `rpm -Uvh --noscripts awc-audio-newupg-9.8.3.202-2.i386.rpm`
  - Option 8 (10.2.1.205): `rpm -Uvh --noscripts --oldpackage awc-audio-newupg-10.3.0.7-1.x86_64.rpm`

  To verify, run `rpm -q awc-audio-newupg`. `9.8.3.202-2` or `10.3.0.7-1` means the patch is installed; `9.8.3.201-1` or `10.2.1.201-1` means it is not. MISA-2026-0006 affects 10.0 (10.0.0.26) to 10.2 SP1 FP2 and 9.8.3.203 and earlier, but patches only exist for 10.2.1.205 and 9.8.3.203: other versions should upgrade to 10.3 (10.3.0.18).
- **To revert option 7 or 8**, from the extracted folder in `/tmp` (`AWV-11157_FixPatch_MAS_9.8SP3FP1_10July26` or `AWV-11157_FixPatch_MAS_10.2SP1FP2_14July26`) run the matching command, then stop/start the AWV services in Server Manager (reverting is manual and not done by the script):
  ```
  rpm -Uvh --noscripts --oldpackage awc-audio-newupg-9.8.3.201-1.i386.rpm
  rpm -Uvh --noscripts --oldpackage awc-audio-newupg-10.2.1.201-1.x86_64.rpm
  ```
- Option 9 (MISA-2026-0012) downloads `AWV-11322_FixPatch_MAS_10.3_HF1.zip` and installs `awc-audio-newupg-10.3.0.8-1.x86_64.rpm`. The GA `awc-audio-newupg-10.3.0.7-1.x86_64.rpm` is also extracted to `/tmp` for rollback.
- **Options 7, 8 and 9 restart AWV automatically.** Once all selected patches are installed, the script stops and then starts the 11 AWV services using `/sbin/e-smith/service`, the same wrapper the AWV admin page uses. It does this once, even if several AWV options are selected, and only if an RPM was actually installed. **This drops every active audio, web and video conference**, so run it in a maintenance window. On Mitel 5000 / Axxess integrations (detected from `db awcconf get SWITCH_NAME`), `sipcfgmgr` and `sipserver` are restarted too. If any service reports an error, the script says so and exits non-zero; check the services in Server Manager.
- **To revert option 9** to the 10.3 GA version, run the following from `/tmp`, then stop/start the AWV services in Server Manager (reverting is manual and not done by the script):
  ```
  rpm -Uvh --noscripts --oldpackage awc-audio-newupg-10.3.0.7-1.x86_64.rpm
  ```
- Systems on MiCollab 10.2 or earlier should upgrade to 10.3 (10.3.0.18) before applying the MISA-2026-0012 patch.
- **Options 10 and 11 (CVE-2025-52914 / MISA-2025-0008)** replace `ChangeSettingsPortlet.jar` in `/var/lib/tomcat7/webapps/ChangeSettingsPortlet/WEB-INF/lib` (9.8, option 10) or `/var/lib/tomcat9/...` (10.0, option 11). The original is renamed to `ChangeSettingsPortlet.jar.old` (an existing `.old` is kept), the patched jar's MD5 is verified before it is copied in, and tomcat is restarted once at the end (Mitel: no user impact). The patch counts as applied when the installed jar's MD5 matches the patched jar; the date shown is the jar's modification time. If the lib folder for the option doesn't exist (wrong option for this version), it is skipped with an error. The issue is fixed without a patch in 9.8 SP3 FP1 (9.8.3.103) and 10.1 (10.1.0.10) and later.
- **To revert option 10 or 11**, in the lib folder above rename `ChangeSettingsPortlet.jar` to `ChangeSettingsPortlet.jar.new`, rename `ChangeSettingsPortlet.jar.old` to `ChangeSettingsPortlet.jar`, then run `service tomcat restart` (reverting is manual and not done by the script).
