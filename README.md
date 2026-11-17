# Micollab Patch Installer
A simple bash script to quickly apply CVE-2024-35287, CVE-2024-41713, CVE-2024-41714, CVE-2024-47223, MISA-2026-0006 and MISA-2026-0012 to MiCollab servers running 6.0 - 10.3 software.

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
| 9.8.0.33 | 2, 4, 5 |
| 9.8.1.5 | 3, 4, 5 |
| 9.8.1.108 | 4, 5 |
| 9.8.1.201 | 4, 5 |
| 9.8.2.12 | none |
| 9.8.3.203 | 7 |
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
| 4 | 9.7 to 9.8 SP1FP2 (9.7.0.27 - 9.8.1.201) - CVE-2024-41713 |
| 5 | 9.8 GA to 9.8 SP1FP2 (9.8.0.33 - 9.8.1.201) - CVE-2024-47223 — **reboot required** |
| 6 | 6.0 to 9.8 SP1FP2 + MiVB-X (6.0.206.0 - 9.8.1.201) - CVE-2024-41713 |
| 7 | 9.8 SP3FP1 (9.8.3.203) - MISA-2026-0006 |
| 8 | 10.2 SP1FP2 (10.2.1.205) - MISA-2026-0006 |
| 9 | 10.3 (10.3.0.18) - MISA-2026-0012 (MTLVULN-1861, 1862, 1863, 1864, 1877) |

## Notes
- Requires `curl` (used to download the script and the patch files).
- Requires `dialog` to be installed on the server; the script will exit with an error if it's not found.
- There is no check for whether a patch has already been applied — reapplying an already-installed patch is not automatically prevented, except for RPM-based options (5, 7, 8, 9), which will skip installation if the RPM package is already present.
- The script may pause for a few seconds at points during installation. No user interaction is required once the patching process has started.
- The patch for CVE-2024-47223 (option 5) requires a reboot to take effect.
- Options 7 and 8 (MISA-2026-0006) each download a zip containing two RPM versions; the script installs only the intended version (9.8.3.202 for 9.8 SP3FP1, 10.3.0.7 for 10.2 SP1FP2) and leaves the other file extracted but unused.
- Option 9 (MISA-2026-0012) downloads `AWV-11322_FixPatch_MAS_10.3_HF1.zip` and installs `awc-audio-newupg-10.3.0.8-1.x86_64.rpm`. The GA `awc-audio-newupg-10.3.0.7-1.x86_64.rpm` is also extracted to `/tmp` for rollback.
- **Options 7, 8 and 9 restart AWV automatically.** Once all selected patches are installed, the script stops and then starts the 11 AWV services using `/sbin/e-smith/service`, the same wrapper the AWV admin page uses. It does this once, even if several AWV options are selected, and only if an RPM was actually installed. **This drops every active audio, web and video conference**, so run it in a maintenance window. On Mitel 5000 / Axxess integrations (detected from `db awcconf get SWITCH_NAME`), `sipcfgmgr` and `sipserver` are restarted too. If any service reports an error, the script says so and exits non-zero; check the services in Server Manager.
- **To revert option 9** to the 10.3 GA version, run the following from `/tmp`, then stop/start the AWV services in Server Manager (reverting is manual and not done by the script):
  ```
  rpm -Uvh --noscripts --oldpackage awc-audio-newupg-10.3.0.7-1.x86_64.rpm
  ```
- Systems on MiCollab 10.2 or earlier should upgrade to 10.3 (10.3.0.18) before applying the MISA-2026-0012 patch.
