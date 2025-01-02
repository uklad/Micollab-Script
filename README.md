# Micollab Patch Installer

A simple bash script to quickly apply CVE-2024-35287 CVE-2024-41713 CVE-2024-41714 CVE-2024-47223 to Micollab servers running 9.7 - 9.8 SP1 Software


## Installation

Script will check the current Micollab version and preselect the recomended patches

```
wget -qO- https://github.com/uklad/Micollab-Script/raw/main/script.sh | bash
```

The Micollab version is checked and appropriate patched are pre selected.

There is no checks is the patches are allready applied.

Script may pause a few times during installation no user interation is required once the patching process has started.

Patch for CVE-2024-47223 Requires a reboot to enabled.
