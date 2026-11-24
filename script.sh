#!/bin/bash

# Function to print colorful messages
print_info() {
    echo -e "\e[34m[INFO]\e[0m $1"
}

print_success() {
    echo -e "\e[32m[SUCCESS]\e[0m $1"
}

print_error() {
    echo -e "\e[31m[ERROR]\e[0m $1"
}

# Function to indicate the script is still running
show_working() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    local temp=${spinstr#?}  # Take substring from second character onward
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        spinstr=$temp${spinstr%"$temp"}  # Recombine the characters
        printf " [%c]  " "$spinstr"
        temp=${spinstr#?}  # Update temp to match the current spin
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Function to fetch a URL to a file with curl
fetch_file() {
  local url="$1"
  local out="$2"
  if ! command -v curl >/dev/null 2>&1; then
    print_error "curl is not installed, cannot download $out"
    return 1
  fi
  curl -fL --insecure "$url" -o "$out"
}

# Function to download and extract patch

download_and_extract() {
  local url="$1"
  local patch_file="${url##*/}"  # Extract the filename from the URL

  print_info "Changing directory to /tmp/"
  cd /tmp/ || { print_error "Failed to change directory to /tmp/"; exit 1; }

  print_info "Downloading patch from $url"
  if fetch_file "$url" "$patch_file"; then
    print_success "Download completed successfully"
  else
    print_error "Failed to download $patch_file"
    exit 1
  fi

  print_info "Extracting $patch_file"
  case "$patch_file" in
    *.tar.gz)
      tar -zxvf "$patch_file" || { print_error "Failed to extract $patch_file"; exit 1; }
      ;;
    *.tar)
      tar -xvf "$patch_file" || { print_error "Failed to extract $patch_file"; exit 1; }
      ;;
    *.zip)
      unzip -o "$patch_file" || { print_error "Failed to extract $patch_file"; exit 1; }
      ;;
    *)
      print_error "Unsupported file format: $patch_file"
      exit 1
      ;;
  esac

  print_success "Extraction of $patch_file completed successfully"
}

# Function to download only
download_patch() {
    local url=$1
    local patch_file="${url##*/}"  # Extract the filename from the URL

    print_info "Changing directory to /tmp/"
    cd /tmp/ || { print_error "Failed to change directory to /tmp/"; exit 1; }

    print_info "Downloading patch from $url"
    if fetch_file "$url" "$patch_file"; then
        print_success "Download completed successfully"
    else
        print_error "Failed to download $patch_file"
        exit 1
    fi
}

# Function to rename and copy files
rename_and_copy_files() {
    print_info "Renaming existing views.py and feedback.py"
    mv -f /etc/e-smith/web/django/servermanager/ucdiag/tdc/views.py /etc/e-smith/web/django/servermanager/ucdiag/tdc/views_old.py || { print_error "Failed to rename views.py"; exit 1; }
    mv -f /usr/ucs/feedback/feedback.py /usr/ucs/feedback/feedback_old.py || { print_error "Failed to rename feedback.py"; exit 1; }

    print_info "Copying new views.py and feedback.py"
    cp -f /tmp/views.py /etc/e-smith/web/django/servermanager/ucdiag/tdc/ || { print_error "Failed to copy views.py"; exit 1; }
    cp -f /tmp/feedback.py /usr/ucs/feedback/ || { print_error "Failed to copy feedback.py"; exit 1; }
}

# Function to run a Mitel patcher.sh with its input from the terminal.
# When this script is run as "curl ... | bash", stdin is the script itself, so
# any prompt in patcher.sh (e.g. "run maintenance from Hard Disk?") would read
# lines of this script as its answer. Reading from /dev/tty lets the user answer.
run_patcher_sh() {
    print_info "When asked to run maintenance from Hard Disk, answer N"
    if ( : </dev/tty ) 2>/dev/null; then
        sh patcher.sh </dev/tty
    else
        # No terminal (e.g. run from cron/automation): give it no input rather
        # than this script's text
        sh patcher.sh </dev/null
    fi
}

# Function to run NPM-4630 patcher.sh
run_patcher_NPM-4630() {
    print_info "Extracting NPM-4630_Fix_Patch_20.8.tar.gz"
    if tar -zxvf NPM-4630_Fix_Patch_20.8.tar.gz; then
        print_success "Extraction of NPM-4630_Fix_Patch_20.8.tar.gz completed successfully"
    else
        print_error "Failed to extract NPM-4630_Fix_Patch_20.8.tar.gz"
        exit 1
    fi

    print_info "Running patcher.sh"
    print_info "Script may pause for a few seconds until complete"
    if run_patcher_sh; then
        print_success "Patcher executed successfully"
    else
        print_error "Failed to execute patcher.sh"
        exit 1
    fi
}

# Function to run NPM-4699 patcher.sh
run_patcher_CVE-2024-41713() {
    print_info "Extracting security_CVE-2024-41713_MiCollab.tar.gz"
    if tar -zxvf security_CVE-2024-41713_MiCollab.tar.gz; then
        print_success "Extraction of security_CVE-2024-41713_MiCollab.tar.gz completed successfully"
    else
        print_error "Failed to extract security_CVE-2024-41713_MiCollab.tar.gz"
        exit 1
    fi

    print_info "Running patcher.sh"
    print_info "Script may pause for a few seconds until complete"
    if run_patcher_sh; then
        print_success "Patcher executed successfully"
    else
        print_error "Failed to execute patcher.sh"
        exit 1
    fi
}

# Function to install an RPM with -Uvh --noscripts
# Accepts either a bare filename (expected in the current dir) or a relative
# path (e.g. extracted-folder/package.rpm) - rpm -q only wants the package
# name, but -Uvh needs the actual path to the file.
# Any further arguments are passed to rpm as extra flags (e.g. --oldpackage
# where Mitel's instructions include it).
install_rpm() {
    local rpm_path=$1
    shift
    local extra_flags=("$@")
    local rpm_file="${rpm_path##*/}"   # basename, for display/query
    local rpm_name="${rpm_file%.rpm}"
    RPM_INSTALLED=0   # set to 1 only when a package is actually installed

    # Check if RPM is already installed
    if rpm -q "$rpm_name" >/dev/null 2>&1; then
        print_info "RPM package $rpm_file is already installed. Skipping."
        return 0
    fi

    print_info "Installing RPM package: $rpm_file"
    if rpm -Uvh --noscripts "${extra_flags[@]}" "$rpm_path"; then
        print_success "RPM installed successfully: $rpm_file"
        RPM_INSTALLED=1
    else
        print_error "Failed to install RPM: $rpm_file"
        exit 1
    fi
}

# AWV conferencing services, controlled through the MSL service wrapper (the
# same one the AWV admin page's Start/Stop uses). Stop order matches the admin
# page's "Stop All" (watchdog first); start order matches the AWV installer
# (watchdog last).
AWV_STOP_ORDER="tnsdvr-monitor ths mcud ivrd cdr_buffer eocpctl tnsd tnsdvr cpctl muxerd awcwss"
AWV_START_ORDER="mcud cdr_buffer ivrd ths tnsd tnsdvr muxerd eocpctl cpctl awcwss tnsdvr-monitor"

# Function to stop then start the AWV services after an AWV patch.
# Note: this drops every active audio, web and video conference.
restart_awv_services() {
    local svc_cmd=/sbin/e-smith/service
    local stop_list="$AWV_STOP_ORDER"
    local start_list="$AWV_START_ORDER"
    local failed=""

    if [ ! -x "$svc_cmd" ]; then
        print_error "$svc_cmd not found - stop/start the AWV services in Server Manager manually"
        return 1
    fi

    # Mitel 5000 / Axxess integrations also run sipcfgmgr and sipserver
    # (stopped last, started last)
    local switch_name
    switch_name=$(/sbin/e-smith/db awcconf get SWITCH_NAME 2>/dev/null)
    case "${switch_name,,}" in
        *5000*|*axxess*)
            print_info "Switch type '$switch_name' detected - including sipcfgmgr and sipserver"
            stop_list="$stop_list sipcfgmgr sipserver"
            start_list="$start_list sipcfgmgr sipserver"
            ;;
    esac

    print_info "Stopping AWV services (active conferences will be dropped)"
    for svc in $stop_list; do
        # </dev/null: when run as "curl|bash" stdin is this script itself
        "$svc_cmd" "$svc" stop </dev/null || failed="$failed $svc(stop)"
    done

    print_info "Starting AWV services"
    for svc in $start_list; do
        "$svc_cmd" "$svc" start </dev/null || failed="$failed $svc(start)"
    done

    if [ -n "$failed" ]; then
        print_error "Some AWV service commands reported errors:$failed"
        print_error "Check the services in Server Manager (Applications > Audio, Web and Video Conferencing)"
        return 1
    fi
    print_success "AWV services restarted"
}

# Check if dialog is installed
if ! command -v dialog &> /dev/null; then
    print_error "dialog command could not be found, please install it to continue."
    exit 1
fi

# Get Micollab version

MasVersion=$(config getprop sysconfig MasVersion)
if [ $? -ne 0 ]; then
  print_error "Failed to retrieve MasVersion: $?"
  exit 1
fi

if [ -z "$MasVersion" ]; then
  print_error "MasVersion is not set or empty"
  exit 1
fi

print_success "MasVersion Detected as: $MasVersion"

# Determine the preselected options based on MasVersion
case "$MasVersion" in
  "9.7.0.27")
    PRESELECTED="2"
    ;;
  "9.7.1.13")
    PRESELECTED="2 3"
    ;;
  "9.7.1.110")
    PRESELECTED="2"
    ;;
  "9.8.0.33")
    PRESELECTED="2 5 6"
    ;;
  "9.8.1.5")
    PRESELECTED="2 6 7"
    ;;
  "9.8.1.108")
    PRESELECTED="2 6"
    ;;    
  "9.8.1.201")
    PRESELECTED="2 6"
    ;;
  "9.8.2.12")
    PRESELECTED="2"
    ;;
  "9.8.3.203")
    PRESELECTED="8"
    ;;
  "10.2.1.205")
    PRESELECTED="10"
    ;;
  "10.3.0.18")
    PRESELECTED="11"
    ;;
  *)
    PRESELECTED=""
    ;;
esac

# Option numbers go above 9, so match whole numbers, never single characters
# (otherwise "10" would also match option 1)
is_preselected() { [[ " $PRESELECTED " == *" $1 "* ]]; }
unpreselect() { local p=" $PRESELECTED "; PRESELECTED="${p// $1 / }"; }
# version_lt A B: true if version A is lower than version B
version_lt() { [ "$1" != "$2" ] && [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" = "$1" ]; }

# CVE-2025-52914 (MISA-2025-0008): fixed in 9.8 SP3 FP1 (9.8.3.103) and
# 10.1 (10.1.0.10); patches exist for 9.8.x.x (option 4) and 10.0.x.x (option 9)
case "$MasVersion" in
  9.8.*)  version_lt "$MasVersion" "9.8.3.103" && PRESELECTED="$PRESELECTED 4" ;;
  10.0.*) PRESELECTED="$PRESELECTED 9" ;;
esac

# RPM-based patches: menu option -> package installed by that option.
# Keep in sync with the install_rpm calls further down.
declare -A RPM_PATCH=(
  [6]='awc-web-9.8.1.103-1.i386'
  [8]='awc-audio-newupg-9.8.3.202-2.i386'
  [10]='awc-audio-newupg-10.3.0.7-1.x86_64'
  [11]='awc-audio-newupg-10.3.0.8-1.x86_64'
)

# Mark RPM patches that are already installed and untick them
declare -A TAG
for opt in "${!RPM_PATCH[@]}"; do
  if rpm -q "${RPM_PATCH[$opt]}" >/dev/null 2>&1; then
    # When it was installed, from the RPM database (epoch seconds)
    installed_epoch=$(rpm -q --qf '%{INSTALLTIME}' "${RPM_PATCH[$opt]}" 2>/dev/null)
    installed_date=$(date -d "@$installed_epoch" '+%Y-%m-%d %H:%M' 2>/dev/null)
    if [ -n "$installed_date" ]; then
      TAG[$opt]=" [INSTALLED ${installed_date%% *}]"
      print_info "Option $opt (${RPM_PATCH[$opt]}) was installed on $installed_date"
    else
      TAG[$opt]=" [ALREADY INSTALLED]"
      print_info "Option $opt (${RPM_PATCH[$opt]}) is already installed (install date unknown)"
    fi
    unpreselect "$opt"
  fi
done

# Check whether the CVE-2024-41713 patch (options 1 and 2) is applied.
# Its patcher.sh writes "date" then "Patch notes: <note>" to the NPM Revision
# file (this is what sinfo shows); removing it (patcher.sh -r) writes
# "Patch notes: REVERSED <note>". The latest entry wins.
# Prints the install date and returns 0 if applied, otherwise returns 1.
CVE_41713_NOTE="CVE-2024-41713 : Path Traversal Combined Fix Patch"
CVE_41713_REV_FILE="/usr/vm/config/Revision"
cve_41713_applied() {
  [ -r "$CVE_41713_REV_FILE" ] || return 1
  local result reversed when
  result=$(awk -v note="$CVE_41713_NOTE" '
    /^Patch notes: / && index($0, note) { when = prev; rev = ($0 ~ /REVERSED/) ? 1 : 0; found = 1 }
    { prev = $0 }
    END { if (found) print rev "|" when }' "$CVE_41713_REV_FILE")
  [ -n "$result" ] || return 1
  reversed="${result%%|*}"
  when="${result#*|}"
  [ "$reversed" = 0 ] || return 1
  echo "$when"
  return 0
}

if cve_41713_installed_on=$(cve_41713_applied); then
  installed_date=$(date -d "$cve_41713_installed_on" '+%Y-%m-%d' 2>/dev/null)
  for opt in 1 2; do
    TAG[$opt]=" [INSTALLED ${installed_date:-date unknown}]"
    unpreselect "$opt"
  done
  print_info "CVE-2024-41713 patch (options 1 and 2) was applied on ${cve_41713_installed_on:-unknown date}"
fi

# CVE-2025-52914 (MISA-2025-0008) ChangeSettingsPortlet patch, options 4/9.
# The patch replaces ChangeSettingsPortlet.jar (original kept as .jar.old) and
# restarts tomcat. It counts as applied when the installed jar's MD5 matches
# the patched jar; the install date is the jar's modification time.
CS_JAR="ChangeSettingsPortlet.jar"
declare -A CS_LIB=(
  [4]='/var/lib/tomcat7/webapps/ChangeSettingsPortlet/WEB-INF/lib'
  [9]='/var/lib/tomcat9/webapps/ChangeSettingsPortlet/WEB-INF/lib'
)
declare -A CS_PKG=(
  [4]='Patch_Micollab-9.8_SP3'
  [9]='Patch_Micollab-10.0_SP1_FP1'
)
declare -A CS_MD5=(
  [4]='53953ffab753228139435664ca2e292f'
  [9]='d0485a06226897c0058ffaea27643355'
)

# Prints the install date and returns 0 if option $1's patched jar is in place
cs_patch_applied() {
  local f="${CS_LIB[$1]}/$CS_JAR"
  [ -f "$f" ] || return 1
  [ "$(md5sum < "$f" | awk '{print $1}')" = "${CS_MD5[$1]}" ] || return 1
  date -r "$f" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "unknown date"
}

# Install option $1's ChangeSettingsPortlet patch
install_cs_patch() {
  local opt=$1 lib="${CS_LIB[$1]}" pkg="${CS_PKG[$1]}" got
  if cs_patch_applied "$opt" >/dev/null; then
    print_info "CVE-2025-52914 patch is already applied (option $opt). Skipping."
    return 0
  fi
  if [ ! -f "$lib/$CS_JAR" ]; then
    print_error "$lib/$CS_JAR not found - option $opt does not match this MiCollab version. Skipping."
    return 1
  fi

  download_and_extract "https://github.com/uklad/Micollab-Script/raw/refs/heads/main/CVE-2025-52914/$pkg.tar.gz"

  got=$(md5sum < "/tmp/$pkg/$CS_JAR" | awk '{print $1}')
  if [ "$got" != "${CS_MD5[$opt]}" ]; then
    print_error "Checksum mismatch for $pkg/$CS_JAR (got $got). Not installing."
    exit 1
  fi
  print_success "Checksum verified for $pkg/$CS_JAR"

  if [ -e "$lib/$CS_JAR.old" ]; then
    print_info "$CS_JAR.old already exists - keeping it as the original backup"
  else
    print_info "Renaming $CS_JAR to $CS_JAR.old"
    mv "$lib/$CS_JAR" "$lib/$CS_JAR.old" || { print_error "Failed to rename $CS_JAR"; exit 1; }
  fi

  print_info "Copying patched $CS_JAR to $lib"
  cp -f "/tmp/$pkg/$CS_JAR" "$lib/$CS_JAR" || { print_error "Failed to copy $CS_JAR"; exit 1; }
  # Match the original file's owner and permissions
  chown --reference="$lib/$CS_JAR.old" "$lib/$CS_JAR" 2>/dev/null
  chmod --reference="$lib/$CS_JAR.old" "$lib/$CS_JAR" 2>/dev/null
  print_success "CVE-2025-52914 patch installed (option $opt)"
  TOMCAT_RESTART_NEEDED=1
}

for opt in 4 9; do
  if cs_installed_on=$(cs_patch_applied "$opt"); then
    TAG[$opt]=" [INSTALLED ${cs_installed_on%% *}]"
    unpreselect "$opt"
    print_info "CVE-2025-52914 patch (option $opt) was applied on $cs_installed_on"
  fi
done

# Menu labels, one per option, in version order (by the first version each
# option applies to)
MENU_LABELS=(
  [1]="6.0 to 9.8 SP1FP2 + MiVB-X (6.0.206.0 - 9.8.1.201) CVE-2024-41713"
  [2]="9.7 to 9.8 SP2 (9.7.0.27 - 9.8.2.12) CVE-2024-41713"
  [3]="9.7 SP1 (9.7.1.13) CVE-2024-41714"
  [4]="9.8 (9.8.x.x below 9.8.3.103) CVE-2025-52914"
  [5]="9.8 GA (9.8.0.33) CVE-2024-41714 & CVE-2024-35287"
  [6]="9.8 GA to 9.8 SP1FP2 (9.8.0.33 - 9.8.1.201) CVE-2024-47223 - ** Reboot Required **"
  [7]="9.8 SP1 (9.8.1.5) CVE-2024-41714 & CVE-2024-35287"
  [8]="9.8 SP3FP1 (9.8.3.203) MISA-2026-0006"
  [9]="10.0 (10.0.x.x) CVE-2025-52914"
  [10]="10.2 SP1FP2 (10.2.1.205) MISA-2026-0006"
  [11]="10.3 (10.3.0.18) MISA-2026-0012"
)

# Colour each item (dialog --colors: \Zb bold, \Z1 red, \Z2 green, \Z3 yellow,
# \Zn reset). Bold gives the bright variant, which reads well on black:
#   green  = already installed
#   red    = recommended for this version (preselected)
#   yellow = not required for this version
MENU_ITEMS=()
for opt in 1 2 3 4 5 6 7 8 9 10 11; do
  if [ -n "${TAG[$opt]}" ]; then
    colour='\Zb\Z2'; state=off
  elif is_preselected "$opt"; then
    colour='\Zb\Z1'; state=on
  else
    colour='\Zb\Z3'; state=off
  fi
  MENU_ITEMS+=("$opt" "${colour}${MENU_LABELS[$opt]}${TAG[$opt]}\\Zn" "$state")
done

# Dark theme for this menu only, so the red/green/yellow items are readable
# (dialog's default blue screen and grey box make them hard to see).
# Written to a temp file and passed via DIALOGRC; the server's own dialog
# settings are not changed.
DIALOG_THEME=$(mktemp /tmp/micollab-dialogrc.XXXXXX)
cat > "$DIALOG_THEME" <<'EOF'
use_shadow = OFF
use_colors = ON
screen_color = (WHITE,BLACK,OFF)
shadow_color = (BLACK,BLACK,OFF)
dialog_color = (WHITE,BLACK,OFF)
title_color = (CYAN,BLACK,ON)
border_color = (WHITE,BLACK,ON)
button_active_color = (BLACK,CYAN,OFF)
button_inactive_color = (WHITE,BLACK,OFF)
button_key_active_color = (BLACK,CYAN,OFF)
button_key_inactive_color = (CYAN,BLACK,ON)
button_label_active_color = (BLACK,CYAN,OFF)
button_label_inactive_color = (WHITE,BLACK,ON)
position_indicator_color = (CYAN,BLACK,ON)
menubox_color = (WHITE,BLACK,OFF)
menubox_border_color = (WHITE,BLACK,ON)
item_color = (WHITE,BLACK,OFF)
item_selected_color = (WHITE,BLUE,ON)
tag_color = (CYAN,BLACK,ON)
tag_selected_color = (WHITE,BLUE,ON)
tag_key_color = (CYAN,BLACK,ON)
tag_key_selected_color = (WHITE,BLUE,ON)
check_color = (WHITE,BLACK,ON)
check_selected_color = (WHITE,BLUE,ON)
uarrow_color = (CYAN,BLACK,ON)
darrow_color = (CYAN,BLACK,ON)
EOF

# Display the dialog with preselected options
CHOICES=$(DIALOGRC="$DIALOG_THEME" dialog --colors --backtitle "Patch Selector" --title "Select an Option" --checklist \
"Choose the patch version(s): Micollab Version Detected : $MasVersion\n\Zb\Z1Red\Zn = recommended (preselected)   \Zb\Z2Green\Zn = already installed   \Zb\Z3Yellow\Zn = not required for this version" 23 150 11 \
    "${MENU_ITEMS[@]}" \
    3>&1 1>&2 2>&3 3>&-)
rm -f "$DIALOG_THEME"
clear
CHOICES="${CHOICES//\"/}"   # some dialog versions quote each tag

if [ -z "$CHOICES" ]; then
    print_error "No options selected. Exiting."
    exit 1
fi

# Process the selected options
for CHOICE in $CHOICES; do
    case $CHOICE in
        3)
            download_and_extract 'https://github.com/uklad/Micollab-Script/raw/refs/heads/main/CVE-2024-41714/9.7%20SP1%20patch.zip'
            rename_and_copy_files
            ;;
        5)
            download_and_extract 'https://github.com/uklad/Micollab-Script/raw/refs/heads/main/CVE-2024-41714/9.8%20GA%20patch.zip'
            download_patch 'https://github.com/uklad/Micollab-Script/raw/refs/heads/main/CVE-2024-35287/NPM-4630_Fix_Patch_20.8.tar.gz'
            rename_and_copy_files
            run_patcher_NPM-4630
            ;;
        7)
            download_and_extract 'https://github.com/uklad/Micollab-Script/raw/refs/heads/main/CVE-2024-41714/9.8%20SP1%20patch.zip'
            download_patch 'https://github.com/uklad/Micollab-Script/raw/refs/heads/main/CVE-2024-35287/NPM-4630_Fix_Patch_20.8.tar.gz'
            rename_and_copy_files
            run_patcher_NPM-4630
            ;;
        1|2)
            # Options 1 and 2 apply the same patch; skip it if already applied
            # (re-running it restarts NuPoint for nothing)
            if cve_41713_applied >/dev/null; then
                print_info "CVE-2024-41713 patch is already applied (option $CHOICE). Skipping."
            else
                download_patch 'https://github.com/uklad/Micollab-Script/raw/refs/heads/main/CVE-2024-41713/security_CVE-2024-41713_MiCollab.tar.gz'
                run_patcher_CVE-2024-41713
            fi
            ;;
        6)
            download_and_extract 'https://github.com/uklad/Micollab-Script/raw/refs/heads/main/CVE-2024-47223/patch.zip'
            install_rpm 'awc-web-9.8.1.103-1.i386.rpm'
            ;;
        8)
            download_and_extract 'https://github.com/uklad/Micollab-Script/raw/refs/heads/main/MISA-2026-0006/AWV-11157_FixPatch_MAS_9.8SP3FP1_10July26.zip'
            install_rpm 'AWV-11157_FixPatch_MAS_9.8SP3FP1_10July26/awc-audio-newupg-9.8.3.202-2.i386.rpm'
            [ "$RPM_INSTALLED" = 1 ] && AWV_RESTART_NEEDED=1
            ;;
        10)
            download_and_extract 'https://github.com/uklad/Micollab-Script/raw/refs/heads/main/MISA-2026-0006/AWV-11157_FixPatch_MAS_10.2SP1FP2_14July26.zip'
            # Mitel's 10.2.1.205 instructions use --oldpackage
            install_rpm 'AWV-11157_FixPatch_MAS_10.2SP1FP2_14July26/awc-audio-newupg-10.3.0.7-1.x86_64.rpm' --oldpackage
            [ "$RPM_INSTALLED" = 1 ] && AWV_RESTART_NEEDED=1
            ;;
        11)
            download_and_extract 'https://github.com/uklad/Micollab-Script/raw/refs/heads/main/MISA-2026-0012/AWV-11322_FixPatch_MAS_10.3_HF1.zip'
            install_rpm 'awc-audio-newupg-10.3.0.8-1.x86_64.rpm'
            [ "$RPM_INSTALLED" = 1 ] && AWV_RESTART_NEEDED=1
            ;;
        4|9)
            install_cs_patch "$CHOICE"
            ;;
	*)
            print_error "Invalid choice. Skipping."
            ;;
    esac
done

# Restart AWV once, after all selected patches are installed
if [ "$AWV_RESTART_NEEDED" = 1 ]; then
    restart_awv_services || AWV_RESTART_FAILED=1
elif [[ " $CHOICES " =~ \ (8|10|11)\  ]]; then
    # An AWV patch (8/10/11) was selected but its RPM was already installed
    print_info "AWV restart skipped: the selected AWV patch was already installed, so nothing changed"
fi

# Restart tomcat once if the CVE-2025-52914 patch was installed
# (Mitel: no user impact restarting this service)
if [ "$TOMCAT_RESTART_NEEDED" = 1 ]; then
    print_info "Restarting tomcat"
    if service tomcat restart </dev/null; then
        print_success "tomcat restarted"
    else
        print_error "tomcat restart failed - run: service tomcat restart"
        AWV_RESTART_FAILED=1
    fi
fi

if [ "$AWV_RESTART_FAILED" = 1 ]; then
    print_error "Patches installed, but a service restart needs checking (see errors above)"
    exit 1
fi

print_success "Script completed successfully"