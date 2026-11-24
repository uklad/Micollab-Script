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
    if sh patcher.sh; then
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
    if sh patcher.sh; then
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
install_rpm() {
    local rpm_path=$1
    local rpm_file="${rpm_path##*/}"   # basename, for display/query
    local rpm_name="${rpm_file%.rpm}"
    RPM_INSTALLED=0   # set to 1 only when a package is actually installed

    # Check if RPM is already installed
    if rpm -q "$rpm_name" >/dev/null 2>&1; then
        print_info "RPM package $rpm_file is already installed. Skipping."
        return 0
    fi

    print_info "Installing RPM package: $rpm_file"
    if rpm -Uvh --noscripts "$rpm_path"; then
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
    PRESELECTED="4"
    ;;
  "9.7.1.13")
    PRESELECTED="1 4"
    ;;
  "9.7.1.110")
    PRESELECTED="4"
    ;;
  "9.8.0.33")
    PRESELECTED="2 4 5"
    ;;
  "9.8.1.5")
    PRESELECTED="3 4 5"
    ;;
  "9.8.1.108")
    PRESELECTED="4 5"
    ;;    
  "9.8.1.201")
    PRESELECTED="4 5"
    ;;
  "9.8.2.12")
    PRESELECTED="4"
    ;;
  "9.8.3.203")
    PRESELECTED="7"
    ;;
  "10.2.1.205")
    PRESELECTED="8"
    ;;
  "10.3.0.18")
    PRESELECTED="9"
    ;;
  *)
    PRESELECTED=""
    ;;
esac

# RPM-based patches: menu option -> package installed by that option.
# Keep in sync with the install_rpm calls further down.
declare -A RPM_PATCH=(
  [5]='awc-web-9.8.1.103-1.i386'
  [7]='awc-audio-newupg-9.8.3.202-2.i386'
  [8]='awc-audio-newupg-10.3.0.7-1.x86_64'
  [9]='awc-audio-newupg-10.3.0.8-1.x86_64'
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
    PRESELECTED="${PRESELECTED//$opt/}"
  fi
done

# Check whether the CVE-2024-41713 patch (options 4 and 6) is applied.
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
  for opt in 4 6; do
    TAG[$opt]=" [INSTALLED ${installed_date:-date unknown}]"
    PRESELECTED="${PRESELECTED//$opt/}"
  done
  print_info "CVE-2024-41713 patch (options 4 and 6) was applied on ${cve_41713_installed_on:-unknown date}"
fi

# Menu labels, one per option
MENU_LABELS=(
  [1]="9.7 SP1 (9.7.1.13) CVE-2024-41714"
  [2]="9.8 GA (9.8.0.33) CVE-2024-41714 & CVE-2024-35287"
  [3]="9.8 SP1 (9.8.1.5) CVE-2024-41714 & CVE-2024-35287"
  [4]="9.7 to 9.8 SP2 (9.7.0.27 - 9.8.2.12) CVE-2024-41713"
  [5]="9.8 GA to 9.8 SP1FP2 (9.8.0.33 - 9.8.1.201) CVE-2024-47223 - ** Reboot Required **"
  [6]="6.0 to 9.8 SP1FP2 + MiVB-X (6.0.206.0 - 9.8.1.201) CVE-2024-41713"
  [7]="9.8 SP3FP1 (9.8.3.203) MISA-2026-0006"
  [8]="10.2 SP1FP2 (10.2.1.205) MISA-2026-0006"
  [9]="10.3 (10.3.0.18) MISA-2026-0012"
)

# Colour each item (dialog --colors: \Zb bold, \Z1 red, \Z2 green, \Z3 yellow,
# \Zn reset). Bold gives the bright variant, which reads well on black:
#   green  = already installed
#   red    = recommended for this version (preselected)
#   yellow = not required for this version
MENU_ITEMS=()
for opt in 1 2 3 4 5 6 7 8 9; do
  if [ -n "${TAG[$opt]}" ]; then
    colour='\Zb\Z2'; state=off
  elif [[ "$PRESELECTED" == *$opt* ]]; then
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
"Choose the patch version(s): Micollab Version Detected : $MasVersion\n\Zb\Z1Red\Zn = recommended (preselected)   \Zb\Z2Green\Zn = already installed   \Zb\Z3Yellow\Zn = not required for this version" 21 150 9 \
    "${MENU_ITEMS[@]}" \
    3>&1 1>&2 2>&3 3>&-)
rm -f "$DIALOG_THEME"
clear

if [ -z "$CHOICES" ]; then
    print_error "No options selected. Exiting."
    exit 1
fi

# Process the selected options
for CHOICE in $CHOICES; do
    case $CHOICE in
        1)
            download_and_extract 'https://github.com/uklad/Micollab-Script/raw/refs/heads/main/CVE-2024-41714/9.7%20SP1%20patch.zip'
            rename_and_copy_files
            ;;
        2)
            download_and_extract 'https://github.com/uklad/Micollab-Script/raw/refs/heads/main/CVE-2024-41714/9.8%20GA%20patch.zip'
            download_patch 'https://github.com/uklad/Micollab-Script/raw/refs/heads/main/CVE-2024-35287/NPM-4630_Fix_Patch_20.8.tar.gz'
            rename_and_copy_files
            run_patcher_NPM-4630
            ;;
        3)
            download_and_extract 'https://github.com/uklad/Micollab-Script/raw/refs/heads/main/CVE-2024-41714/9.8%20SP1%20patch.zip'
            download_patch 'https://github.com/uklad/Micollab-Script/raw/refs/heads/main/CVE-2024-35287/NPM-4630_Fix_Patch_20.8.tar.gz'
            rename_and_copy_files
            run_patcher_NPM-4630
            ;;
        4|6)
            # Options 4 and 6 apply the same patch; skip it if already applied
            # (re-running it restarts NuPoint for nothing)
            if cve_41713_applied >/dev/null; then
                print_info "CVE-2024-41713 patch is already applied (option $CHOICE). Skipping."
            else
                download_patch 'https://github.com/uklad/Micollab-Script/raw/refs/heads/main/CVE-2024-41713/security_CVE-2024-41713_MiCollab.tar.gz'
                run_patcher_CVE-2024-41713
            fi
            ;;
        5)
            download_and_extract 'https://github.com/uklad/Micollab-Script/raw/refs/heads/main/CVE-2024-47223/patch.zip'
            install_rpm 'awc-web-9.8.1.103-1.i386.rpm'
            ;;
        7)
            download_and_extract 'https://github.com/uklad/Micollab-Script/raw/refs/heads/main/MISA-2026-0006/AWV-11157_FixPatch_MAS_9.8SP3FP1_10July26.zip'
            install_rpm 'AWV-11157_FixPatch_MAS_9.8SP3FP1_10July26/awc-audio-newupg-9.8.3.202-2.i386.rpm'
            [ "$RPM_INSTALLED" = 1 ] && AWV_RESTART_NEEDED=1
            ;;
        8)
            download_and_extract 'https://github.com/uklad/Micollab-Script/raw/refs/heads/main/MISA-2026-0006/AWV-11157_FixPatch_MAS_10.2SP1FP2_14July26.zip'
            install_rpm 'AWV-11157_FixPatch_MAS_10.2SP1FP2_14July26/awc-audio-newupg-10.3.0.7-1.x86_64.rpm'
            [ "$RPM_INSTALLED" = 1 ] && AWV_RESTART_NEEDED=1
            ;;
        9)
            download_and_extract 'https://github.com/uklad/Micollab-Script/raw/refs/heads/main/MISA-2026-0012/AWV-11322_FixPatch_MAS_10.3_HF1.zip'
            install_rpm 'awc-audio-newupg-10.3.0.8-1.x86_64.rpm'
            [ "$RPM_INSTALLED" = 1 ] && AWV_RESTART_NEEDED=1
            ;;
	*)
            print_error "Invalid choice. Skipping."
            ;;
    esac
done

# Restart AWV once, after all selected patches are installed
if [ "$AWV_RESTART_NEEDED" = 1 ]; then
    restart_awv_services || AWV_RESTART_FAILED=1
elif [[ "$CHOICES" =~ [789] ]]; then
    # An AWV patch (7/8/9) was selected but its RPM was already installed
    print_info "AWV restart skipped: the selected AWV patch was already installed, so nothing changed"
fi

if [ "$AWV_RESTART_FAILED" = 1 ]; then
    print_error "Patches installed, but the AWV restart needs checking (see errors above)"
    exit 1
fi

print_success "Script completed successfully"