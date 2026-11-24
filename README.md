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
| 9.7.0.27 | 2 |
| 9.7.1.13 | 2, 3 |
| 9.7.1.110 | 2 |
| 9.8.0.33 | 2, 4, 5, 6 |
| 9.8.1.5 | 2, 4, 6, 7 |
| 9.8.1.108 | 2, 4, 6 |
| 9.8.1.201 | 2, 4, 6 |
| 9.8.2.12 | 2, 4 |
| Any other 9.8.x.x below 9.8.3.103 (e.g. 9.8.3.1) | 4 |
| 9.8.3.203 | 8 |
| 10.0.x.x | 9 |
| 10.2.1.205 | 10 |
| 10.3.0.18 | 11 |
| Any other version | none |

For MiCollab 6.0 - 9.7 and MiVB-X, manually select **option 1** for the correct CVE-2024-41713 patch file (this is not auto-preselected).

## Menu options

Options are listed in version order, by the first version each one applies to.

| # | Description |
|---|---|
| 1 | 6.0 to 9.8 SP1FP2 + MiVB-X (6.0.206.0 - 9.8.1.201) - CVE-2024-41713 |
| 2 | 9.7 to 9.8 SP2 (9.7.0.27 - 9.8.2.12) - CVE-2024-41713 |
| 3 | 9.7 SP1 (9.7.1.13) - CVE-2024-41714 |
| 4 | 9.8 (9.8.x.x below 9.8.3.103) - CVE-2025-52914 (MISA-2025-0008) |
| 5 | 9.8 GA (9.8.0.33) - CVE-2024-41714 & CVE-2024-35287 |
| 6 | 9.8 GA to 9.8 SP1FP2 (9.8.0.33 - 9.8.1.201) - CVE-2024-47223 — **reboot required** |
| 7 | 9.8 SP1 (9.8.1.5) - CVE-2024-41714 & CVE-2024-35287 |
| 8 | 9.8 SP3FP1 (9.8.3.203) - MISA-2026-0006 |
| 9 | 10.0 (10.0.x.x) - CVE-2025-52914 (MISA-2025-0008) |
| 10 | 10.2 SP1FP2 (10.2.1.205) - MISA-2026-0006 |
| 11 | 10.3 (10.3.0.18) - MISA-2026-0012 (MTLVULN-1861, 1862, 1863, 1864, 1877) |

## Notes
- Requires `curl` (used to download the script and the patch files).
- Requires `dialog` to be installed on the server; the script will exit with an error if it's not found.
## Installed checks

Before the menu opens, every option is checked against what its patch actually changes on the server. The same check runs again just before an option is installed (so a patch applied by an earlier choice isn't applied twice), and once more afterwards to **verify** it. If verification fails, the script lists the missing parts and exits with an error.

| Option(s) | Patch | Counts as installed when |
|---|---|---|
| 1, 2 | CVE-2024-41713 | **All three** are present: the latest `/usr/vm/config/Revision` entry (what `sinfo` shows) is `CVE-2024-41713 : Path Traversal Combined Fix Patch` and not `REVERSED`; the `26npm-ivr-rewrite` template holds both `[R=404]` rules for `/npm-admin` and `/npm-pwg`; and the live `/etc/httpd/conf/httpd.conf` holds both rules |
| 3, 5, 7 | CVE-2024-41714 | The installed `views.py` and `feedback.py` match the patched files by MD5. `feedback.py` differs per version, so it decides which of the three options is installed |
| 5, 7 | + CVE-2024-35287 (NPM-4630) | The latest Revision entry is `NPM-4630 - Server Console escape to bash as root.` and `/usr/vm/bin/startnpm` matches the patched file by MD5 |
| 6, 8, 10, 11 | RPMs | The exact package version is installed, **or a newer version** of the same package is (shown as `[NEWER x INSTALLED]`; the option is skipped so the package is never downgraded) |
| 4, 9 | CVE-2025-52914 | The live `ChangeSettingsPortlet.jar` matches the patched jar by MD5 |

Menu colours:
- **Green:** installed, with the date (e.g. `[INSTALLED 2026-11-17]`), or superseded by a newer version. Not ticked, and skipped if you tick it.
- **Red:** recommended for this version, or **incomplete**. An option where only some parts are found is labelled `[INCOMPLETE - missing: …]` and ticked, so running the script completes it. Options 5 and 7 then install only the missing part.
- **Yellow:** not required for this version.

Mitel notes the CVE-2024-41713 patch also corrects CVE-2025-52913 (MISA-2025-0007).

## More notes
- The CVE-2024-41714 options keep the original files as `views_old.py` and `feedback_old.py`. An existing backup is never overwritten, so the original survives a re-run.
- The script may pause for a few seconds at points during installation. Options 1, 2, 5 and 7 run a Mitel `patcher.sh` that asks whether to run maintenance from Hard Disk: answer **N**.
- The patch for CVE-2024-47223 (option 6) requires a reboot to take effect.
- Options 8 and 10 (MISA-2026-0006) each download a zip containing two RPMs: the patch, and the original version for reverting. The script installs only the patch, as in Mitel's instructions:
  - Option 8 (9.8.3.203): `rpm -Uvh --noscripts awc-audio-newupg-9.8.3.202-2.i386.rpm`
  - Option 10 (10.2.1.205): `rpm -Uvh --noscripts --oldpackage awc-audio-newupg-10.3.0.7-1.x86_64.rpm`

  To verify, run `rpm -q awc-audio-newupg`. `9.8.3.202-2` or `10.3.0.7-1` means the patch is installed; `9.8.3.201-1` or `10.2.1.201-1` means it is not. MISA-2026-0006 affects 10.0 (10.0.0.26) to 10.2 SP1 FP2 and 9.8.3.203 and earlier, but patches only exist for 10.2.1.205 and 9.8.3.203: other versions should upgrade to 10.3 (10.3.0.18).
- **To revert option 8 or 10**, from the extracted folder in `/tmp` (`AWV-11157_FixPatch_MAS_9.8SP3FP1_10July26` or `AWV-11157_FixPatch_MAS_10.2SP1FP2_14July26`) run the matching command, then stop/start the AWV services in Server Manager (reverting is manual and not done by the script):
  ```
  rpm -Uvh --noscripts --oldpackage awc-audio-newupg-9.8.3.201-1.i386.rpm
  rpm -Uvh --noscripts --oldpackage awc-audio-newupg-10.2.1.201-1.x86_64.rpm
  ```
- Option 11 (MISA-2026-0012) downloads `AWV-11322_FixPatch_MAS_10.3_HF1.zip` and installs `awc-audio-newupg-10.3.0.8-1.x86_64.rpm`. The GA `awc-audio-newupg-10.3.0.7-1.x86_64.rpm` is also extracted to `/tmp` for rollback.
- **Options 8, 10 and 11 restart AWV automatically.** Once all selected patches are installed, the script stops and then starts the 11 AWV services using `/sbin/e-smith/service`, the same wrapper the AWV admin page uses. It does this once, even if several AWV options are selected, and only if an RPM was actually installed. **This drops every active audio, web and video conference**, so run it in a maintenance window. On Mitel 5000 / Axxess integrations (detected from `db awcconf get SWITCH_NAME`), `sipcfgmgr` and `sipserver` are restarted too. If any service reports an error, the script says so and exits non-zero; check the services in Server Manager.
- **To revert option 11** to the 10.3 GA version, run the following from `/tmp`, then stop/start the AWV services in Server Manager (reverting is manual and not done by the script):
  ```
  rpm -Uvh --noscripts --oldpackage awc-audio-newupg-10.3.0.7-1.x86_64.rpm
  ```
- Systems on MiCollab 10.2 or earlier should upgrade to 10.3 (10.3.0.18) before applying the MISA-2026-0012 patch.
- **Options 4 and 9 (CVE-2025-52914 / MISA-2025-0008)** replace `ChangeSettingsPortlet.jar` in `/var/lib/tomcat7/webapps/ChangeSettingsPortlet/WEB-INF/lib` (9.8, option 4) or `/var/lib/tomcat9/...` (10.0, option 9). The original is renamed to `ChangeSettingsPortlet.jar.old` (an existing `.old` is kept), the patched jar's MD5 is verified before it is copied in, and tomcat is restarted once at the end (Mitel: no user impact). The patch counts as applied when the installed jar's MD5 matches the patched jar; the date shown is the jar's modification time. If the lib folder for the option doesn't exist (wrong option for this version), it is skipped with an error. The issue is fixed without a patch in 9.8 SP3 FP1 (9.8.3.103) and 10.1 (10.1.0.10) and later.
- **To revert option 4 or 9**, in the lib folder above rename `ChangeSettingsPortlet.jar` to `ChangeSettingsPortlet.jar.new`, rename `ChangeSettingsPortlet.jar.old` to `ChangeSettingsPortlet.jar`, then run `service tomcat restart` (reverting is manual and not done by the script).
