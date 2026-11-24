#!/bin/bash

# MiCollab Patch Installer - bump this when the script changes
SCRIPT_VERSION="2.2.1"

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
# The originals are kept as views_old.py / feedback_old.py. An existing backup
# is never overwritten, so re-running can't replace the original with a
# patched copy.
rename_and_copy_files() {
    local f
    for f in /etc/e-smith/web/django/servermanager/ucdiag/tdc/views.py /usr/ucs/feedback/feedback.py; do
        if [ -e "${f%.py}_old.py" ]; then
            print_info "Keeping existing backup ${f%.py}_old.py"
        else
            print_info "Renaming ${f##*/} to ${f##*/}_old.py"
            mv -f "$f" "${f%.py}_old.py" || { print_error "Failed to rename ${f##*/}"; exit 1; }
        fi
    done

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

print_info "MiCollab Patch Installer v$SCRIPT_VERSION"
print_success "MasVersion Detected as: $MasVersion"

# Determine the preselected options based on MasVersion
case "$MasVersion" in
  "9.7.0.27")
    PRESELECTED="1"
    ;;
  "9.7.1.13")
    PRESELECTED="1 2"
    ;;
  "9.7.1.110")
    PRESELECTED="1"
    ;;
  "9.8.0.33")
    PRESELECTED="1 4 5"
    ;;
  "9.8.1.5")
    PRESELECTED="1 5 6"
    ;;
  "9.8.1.108")
    PRESELECTED="1 5"
    ;;    
  "9.8.1.201")
    PRESELECTED="1 5"
    ;;
  "9.8.2.12")
    PRESELECTED="1"
    ;;
  "9.8.3.203")
    PRESELECTED="7"
    ;;
  "10.2.1.205")
    PRESELECTED="9"
    ;;
  "10.3.0.18")
    PRESELECTED="10"
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
# 10.1 (10.1.0.10); patches exist for 9.8.x.x (option 3) and 10.0.x.x (option 8)
case "$MasVersion" in
  9.8.*)  version_lt "$MasVersion" "9.8.3.103" && PRESELECTED="$PRESELECTED 3" ;;
  10.0.*) PRESELECTED="$PRESELECTED 8" ;;
esac
# What Mitel recommends for this version, before the checks change PRESELECTED
# (used by the status report at the end)
RECOMMENDED="$PRESELECTED"

# ---------------------------------------------------------------------------
# Installed-patch checks
#
# Each check looks at what the patch actually changes on the server (files,
# config, packages), not just whether it was run once. Every check_* function
# returns:
#   0 = installed       (CHECK_WHEN = when, if known)
#   1 = not installed
#   2 = incomplete      (CHECK_MISSING = which parts are missing)
#   3 = superseded      (RPMs only: a newer version is installed, CHECK_NEWER)
# ---------------------------------------------------------------------------
declare -A TAG PARTIAL
CHECK_WHEN=""; CHECK_MISSING=""; CHECK_NEWER=""

md5_of() { [ -f "$1" ] && md5sum < "$1" | awk '{print $1}'; }
file_date() { date -r "$1" '+%Y-%m-%d %H:%M' 2>/dev/null; }

# Latest entry for a patch note in the NPM Revision file (what sinfo shows).
# Mitel patcher.sh scripts write "date" then "Patch notes: <note>"; removing a
# patch (patcher.sh -r) writes "Patch notes: REVERSED <note>".
# Prints the date and returns 0 if the latest entry is an install.
NPM_REV_FILE="/usr/vm/config/Revision"
revision_note_date() {
  [ -r "$NPM_REV_FILE" ] || return 1
  local result
  result=$(awk -v note="$1" '
    /^Patch notes: / && index($0, note) { when = prev; rev = ($0 ~ /REVERSED/) ? 1 : 0; found = 1 }
    { prev = $0 }
    END { if (found) print rev "|" when }' "$NPM_REV_FILE")
  [ -n "$result" ] && [ "${result%%|*}" = 0 ] || return 1
  echo "${result#*|}"
}

# Turn a list of present/missing parts into a status code
#   $1 = number of parts present, $2 = total parts
parts_status() {
  [ "$1" -eq "$2" ] && return 0
  [ "$1" -eq 0 ] && return 1
  return 2
}

# --- Option 1: CVE-2024-41713 (security_CVE-2024-41713_MiCollab.tar.gz)
# patcher.sh writes the Revision note, copies the 26npm-ivr-rewrite template
# and regenerates httpd.conf, which then holds two [R=404] rules. All three
# must be in place: the live httpd.conf rules are the actual protection.
CVE_41713_NOTE="CVE-2024-41713 : Path Traversal Combined Fix Patch"
CVE_41713_TEMPLATE="/etc/e-smith/templates/etc/httpd/conf/httpd.conf/VirtualHosts/26npm-ivr-rewrite"
HTTPD_CONF="/etc/httpd/conf/httpd.conf"
CVE_41713_RULES=('RewriteRule ^/npm-admin/(.*)..; - [R=404]' 'RewriteRule ^/npm-pwg/(.*)..; - [R=404]')
has_all_rules() {  # $1 = file
  local rule
  [ -r "$1" ] || return 1
  for rule in "${CVE_41713_RULES[@]}"; do
    grep -qF -- "$rule" "$1" || return 1
  done
}
# Mitel's own verification for the live config: grep "npm.*404" httpd.conf
# must show both an npm-admin and an npm-pwg rule ("if none or only one are
# seen, the system must be patched")
httpd_conf_secure() {
  local lines
  [ -r "$HTTPD_CONF" ] || return 1
  lines=$(grep "npm.*404" "$HTTPD_CONF")
  grep -q "npm-admin" <<< "$lines" && grep -q "npm-pwg" <<< "$lines"
}
check_cve_41713() {
  local have=0
  CHECK_WHEN=""; CHECK_MISSING=""
  if CHECK_WHEN=$(revision_note_date "$CVE_41713_NOTE"); then have=$((have+1)); else CHECK_MISSING+="Revision note, "; fi
  if has_all_rules "$CVE_41713_TEMPLATE"; then have=$((have+1)); else CHECK_MISSING+="26npm-ivr-rewrite template, "; fi
  if httpd_conf_secure; then have=$((have+1)); else CHECK_MISSING+="httpd.conf npm-admin/npm-pwg 404 rules, "; fi
  CHECK_MISSING="${CHECK_MISSING%, }"
  parts_status "$have" 3
}

# --- Options 2, 4, 6: CVE-2024-41714 (views.py + feedback.py)
# views.py is the same in all three patches; feedback.py differs per version,
# so it decides which option is installed.
TDC_VIEWS="/etc/e-smith/web/django/servermanager/ucdiag/tdc/views.py"
UCS_FEEDBACK="/usr/ucs/feedback/feedback.py"
VIEWS_MD5="1c4aebbfbf3704b0dc49d95d28afae6e"
declare -A FEEDBACK_MD5=(
  [2]='298f126f3d171b1d20eec5b146745860'   # 9.7 SP1 patch.zip
  [4]='2e80d075e3790f62efefcb033805d02d'   # 9.8 GA patch.zip
  [6]='e1fa45988c65331f5d022daaabdf6794'   # 9.8 SP1 patch.zip
)
check_cve_41714() {  # $1 = option
  CHECK_WHEN=""; CHECK_MISSING=""
  # This option's feedback.py isn't there: not installed (another version's
  # patch may be, which is not "incomplete" for this option)
  [ "$(md5_of "$UCS_FEEDBACK")" = "${FEEDBACK_MD5[$1]}" ] || return 1
  CHECK_WHEN=$(file_date "$UCS_FEEDBACK")
  [ "$(md5_of "$TDC_VIEWS")" = "$VIEWS_MD5" ] && return 0
  CHECK_MISSING="patched views.py"
  return 2
}

# --- Options 4 and 6 also apply CVE-2024-35287 (NPM-4630_Fix_Patch_20.8.tar.gz)
# patcher.sh writes the Revision note and replaces /usr/vm/bin/startnpm.
NPM_4630_NOTE="NPM-4630 - Server Console escape to bash as root."
NPM_STARTNPM="/usr/vm/bin/startnpm"
STARTNPM_MD5="5d5b07cda203b607f31e1d13ccb78476"
check_npm_4630() {
  local have=0
  CHECK_WHEN=""; CHECK_MISSING=""
  if CHECK_WHEN=$(revision_note_date "$NPM_4630_NOTE"); then have=$((have+1)); else CHECK_MISSING+="NPM-4630 Revision note, "; fi
  if [ "$(md5_of "$NPM_STARTNPM")" = "$STARTNPM_MD5" ]; then have=$((have+1)); else CHECK_MISSING+="patched startnpm, "; fi
  CHECK_MISSING="${CHECK_MISSING%, }"
  parts_status "$have" 2
}

# Options 4 and 6 = CVE-2024-41714 + CVE-2024-35287
check_41714_and_4630() {  # $1 = option
  local s1 s2 when1 missing1
  check_cve_41714 "$1"; s1=$?; when1="$CHECK_WHEN"; missing1="$CHECK_MISSING"
  # This option's CVE-2024-41714 files aren't there at all: not installed,
  # even if NPM-4630 is (it is shared with the other 9.8 option)
  [ "$s1" -eq 1 ] && return 1
  check_npm_4630; s2=$?
  if [ "$s1" -eq 0 ] && [ "$s2" -eq 0 ]; then CHECK_WHEN="$when1"; return 0; fi
  CHECK_MISSING="${missing1:+$missing1, }$CHECK_MISSING"
  CHECK_MISSING="${CHECK_MISSING%, }"
  CHECK_WHEN="$when1"
  return 2
}

# --- RPM options 5, 7, 9, 10: package name and the version-release the patch
# installs. Keep in sync with the install_rpm_option calls further down.
declare -A RPM_NAME=( [5]='awc-web' [7]='awc-audio-newupg' [9]='awc-audio-newupg' [10]='awc-audio-newupg' )
declare -A RPM_VR=(   [5]='9.8.1.103-1' [7]='9.8.3.202-2' [9]='10.3.0.7-1' [10]='10.3.0.8-1' )
check_rpm() {  # $1 = option
  local installed epoch
  CHECK_WHEN=""; CHECK_MISSING=""; CHECK_NEWER=""
  installed=$(rpm -q --qf '%{VERSION}-%{RELEASE}\n' "${RPM_NAME[$1]}" 2>/dev/null) || return 1
  installed=$(printf '%s\n' "$installed" | sort -V | tail -n1)
  if [ "$installed" = "${RPM_VR[$1]}" ]; then
    epoch=$(rpm -q --qf '%{INSTALLTIME}\n' "${RPM_NAME[$1]}-${RPM_VR[$1]}" 2>/dev/null | head -n1)
    CHECK_WHEN=$(date -d "@$epoch" '+%Y-%m-%d %H:%M' 2>/dev/null)
    return 0
  fi
  if version_lt "${RPM_VR[$1]}" "$installed"; then
    CHECK_NEWER="$installed"
    return 3
  fi
  return 1
}

# Highest MiCollab version each option's vulnerability affects (from Mitel's
# notes). Later releases already include the fix and can share some of the
# patched files (e.g. 9.8.2.12's feedback.py matches a CVE-2024-41714 patch
# file but its views.py is newer), so a partial match there is "not required",
# not "incomplete". Only options whose check can report "incomplete" need this.
declare -A AFFECTED_MAX=(
  [1]='9.8.1.201'  # CVE-2024-41713: 9.8 SP1 FP2 (9.8.1.201) and earlier
  [2]='9.8.1.5'    # CVE-2024-41714: 9.8 SP1 (9.8.1.5) and earlier
  [4]='9.8.1.5'
  [6]='9.8.1.5'
)
# True if this server's version is newer than the last affected version
not_affected() {  # $1 = option
  [ -n "${AFFECTED_MAX[$1]}" ] && version_lt "${AFFECTED_MAX[$1]}" "$MasVersion"
}

# Record a check result for the menu
mark_status() {  # $1 = option, $2 = status, $3 = description
  local short
  # A partial match on a version the issue doesn't affect is not an
  # incomplete patch: treat it as not installed (left as yellow, unticked)
  if [ "$2" = 2 ] && not_affected "$1"; then
    return 0
  fi
  case "$2" in
    0)
      if [ -n "$CHECK_WHEN" ]; then
        # Dates come as "2026-11-17 11:42" or, from the Revision file, as
        # "Fri Dec 13 09:15:22 GMT 2024": show both as YYYY-MM-DD
        short=$(date -d "$CHECK_WHEN" '+%Y-%m-%d' 2>/dev/null) || short="${CHECK_WHEN%% *}"
        TAG[$1]=" [INSTALLED $short]"
        print_info "Option $1 ($3) was installed on $CHECK_WHEN"
      else
        TAG[$1]=" [ALREADY INSTALLED]"
        print_info "Option $1 ($3) is installed (install date unknown)"
      fi
      unpreselect "$1"
      ;;
    3)
      TAG[$1]=" [NEWER ${CHECK_NEWER} INSTALLED]"
      print_info "Option $1 ($3): a newer version (${CHECK_NEWER}) is installed"
      unpreselect "$1"
      ;;
    2)
      TAG[$1]=" [INCOMPLETE - missing: $CHECK_MISSING]"
      PARTIAL[$1]=1
      is_preselected "$1" || PRESELECTED="$PRESELECTED $1"
      print_error "Option $1 ($3) is only partly installed - missing: $CHECK_MISSING"
      ;;
  esac
}

check_cve_41713;               mark_status 1 $? "CVE-2024-41713"
check_cve_41714 2;             mark_status 2 $? "CVE-2024-41714"
check_41714_and_4630 4;        mark_status 4 $? "CVE-2024-41714 & CVE-2024-35287"
check_41714_and_4630 6;        mark_status 6 $? "CVE-2024-41714 & CVE-2024-35287"
for opt in 5 7 9 10; do
  check_rpm "$opt";            mark_status "$opt" $? "${RPM_NAME[$opt]}-${RPM_VR[$opt]}"
done

# CVE-2025-52914 (MISA-2025-0008) ChangeSettingsPortlet patch, options 3/8.
# The patch replaces ChangeSettingsPortlet.jar (original kept as .jar.old) and
# restarts tomcat. It counts as applied when the installed jar's MD5 matches
# the patched jar; the install date is the jar's modification time.
CS_JAR="ChangeSettingsPortlet.jar"
declare -A CS_LIB=(
  [3]='/var/lib/tomcat7/webapps/ChangeSettingsPortlet/WEB-INF/lib'
  [8]='/var/lib/tomcat9/webapps/ChangeSettingsPortlet/WEB-INF/lib'
)
declare -A CS_PKG=(
  [3]='Patch_Micollab-9.8_SP3'
  [8]='Patch_Micollab-10.0_SP1_FP1'
)
declare -A CS_MD5=(
  [3]='53953ffab753228139435664ca2e292f'
  [8]='d0485a06226897c0058ffaea27643355'
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

# --- Options 3 and 8: installed when the live jar's MD5 matches the patched jar
check_cs() {  # $1 = option
  CHECK_MISSING=""
  CHECK_WHEN=$(cs_patch_applied "$1")
}
for opt in 3 8; do
  check_cs "$opt"; mark_status "$opt" $? "CVE-2025-52914"
done

# Menu labels, one per option, in version order (by the first version each
# option applies to)
MENU_LABELS=(
  [1]="6.0 to 9.8 SP2 + MiVB-X (6.0.206.0 - 9.8.2.12) CVE-2024-41713"
  [2]="9.7 SP1 (9.7.1.13) CVE-2024-41714"
  [3]="9.8 (9.8.x.x below 9.8.3.103) CVE-2025-52914"
  [4]="9.8 GA (9.8.0.33) CVE-2024-41714 & CVE-2024-35287"
  [5]="9.8 GA to 9.8 SP1FP2 (9.8.0.33 - 9.8.1.201) CVE-2024-47223 - ** Reboot Required **"
  [6]="9.8 SP1 (9.8.1.5) CVE-2024-41714 & CVE-2024-35287"
  [7]="9.8 SP3FP1 (9.8.3.203) MISA-2026-0006"
  [8]="10.0 (10.0.x.x) CVE-2025-52914"
  [9]="10.2 SP1FP2 (10.2.1.205) MISA-2026-0006"
  [10]="10.3 (10.3.0.18) MISA-2026-0012"
)

# Colour each item (dialog --colors: \Zb bold, \Z1 red, \Z2 green, \Z3 yellow,
# \Zn reset). Bold gives the bright variant, which reads well on black:
#   green  = already installed (or superseded by a newer version)
#   red    = recommended for this version, or only partly installed (ticked)
#   yellow = not required for this version
MENU_ITEMS=()
for opt in 1 2 3 4 5 6 7 8 9 10; do
  if [ -n "${PARTIAL[$opt]}" ]; then
    colour='\Zb\Z1'; state=on
  elif [ -n "${TAG[$opt]}" ]; then
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
CHOICES=$(DIALOGRC="$DIALOG_THEME" dialog --colors --backtitle "MiCollab Patch Installer v$SCRIPT_VERSION" --title " Patch Selector v$SCRIPT_VERSION - MiCollab $MasVersion " --checklist \
"Choose the patch version(s): Micollab Version Detected : $MasVersion\n\Zb\Z1Red\Zn = recommended or incomplete (preselected)   \Zb\Z2Green\Zn = already installed   \Zb\Z3Yellow\Zn = not required for this version" 22 150 10 \
    "${MENU_ITEMS[@]}" \
    3>&1 1>&2 2>&3 3>&-)
rm -f "$DIALOG_THEME"
clear
CHOICES="${CHOICES//\"/}"   # some dialog versions quote each tag

# Process the selected options
# Run the installed check for an option (sets CHECK_* and returns its status)
run_check() {
    case "$1" in
        1)         check_cve_41713 ;;
        2)         check_cve_41714 2 ;;
        4|6)       check_41714_and_4630 "$1" ;;
        5|7|9|10)  check_rpm "$1" ;;
        3|8)       check_cs "$1" ;;
        *)         return 1 ;;
    esac
}

# After installing, run the same check again to confirm the patch is in place
verify_option() {
    run_check "$1"
    case $? in
        0|3) print_success "Verified: option $1 is installed${CHECK_WHEN:+ ($CHECK_WHEN)}"
             RUN_RESULT[$1]="Installed" ;;
        *)   print_error "Verification FAILED for option $1 - ${CHECK_MISSING:-patch not detected}"
             RUN_RESULT[$1]="Failed"
             VERIFY_FAILED="$VERIFY_FAILED $1" ;;
    esac
}

# ---------------------------------------------------------------------------
# Status report, printed when the script finishes (also after an error exit).
# CSV, one row per option that was selected, is installed, or is recommended
# for this version, so it can be pasted into a spreadsheet.
# ---------------------------------------------------------------------------
declare -A RUN_RESULT
CURRENT_CHOICE=""

csv_row() {
    local out="" f
    for f in "$@"; do
        f="${f//\"/\"\"}"
        out+="${out:+,}\"$f\""
    done
    printf '%s\n' "$out"
}

print_report() {
    local host today opt status when notes run selected
    host=$(hostname 2>/dev/null)
    today=$(date '+%Y-%m-%d %H:%M')
    # Exited part-way through an install (download or patcher error)
    if [ -n "$CURRENT_CHOICE" ] && [ -z "${RUN_RESULT[$CURRENT_CHOICE]}" ]; then
        RUN_RESULT[$CURRENT_CHOICE]="Failed"
    fi

    echo
    echo "==================== PATCH STATUS REPORT (CSV) ===================="
    csv_row "Hostname" "MiCollab version" "Report date" "Option" "Patch" "Status" "Installed on" "This run" "Notes"
    for opt in 1 2 3 4 5 6 7 8 9 10; do
        selected=0; [[ " $CHOICES " == *" $opt "* ]] && selected=1
        run_check "$opt"
        case $? in
            0) status="Installed" ;;
            3) status="Newer version installed" ;;
            2) if not_affected "$opt"; then status="Not required"; else status="Incomplete"; fi ;;
            *) if [[ " $RECOMMENDED " == *" $opt "* ]]; then status="Not installed"; else status="Not required"; fi ;;
        esac
        # Leave out options this server doesn't need and that weren't touched
        [ "$status" = "Not required" ] && [ "$selected" = 0 ] && continue

        when=""
        case "$status" in Installed|Incomplete) when="$CHECK_WHEN" ;; esac
        # One date format for every row (the Revision file uses "Fri Dec 13 ...")
        [ -n "$when" ] && when=$(date -d "$when" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$when")
        notes=""
        case "$status" in
            Incomplete)                notes="Missing: $CHECK_MISSING" ;;
            "Newer version installed") notes="${RPM_NAME[$opt]}-$CHECK_NEWER" ;;
            "Not installed")           notes="Recommended for $MasVersion" ;;
        esac
        if [ "$opt" = 5 ] && [ "${RUN_RESULT[5]}" = "Installed" ]; then
            notes="${notes:+$notes; }Reboot required"
        fi
        if [[ " 7 9 10 " == *" $opt "* ]] && [ "${RUN_RESULT[$opt]}" = "Installed" ] && [ "$AWV_SVC_FAILED" = 1 ]; then
            notes="${notes:+$notes; }Check AWV services restarted"
        fi

        run="${RUN_RESULT[$opt]}"
        [ -z "$run" ] && { [ "$selected" = 1 ] && run="Not run" || run="Not selected"; }

        csv_row "$host" "$MasVersion" "$today" "$opt" "${MENU_LABELS[$opt]}" "$status" "$when" "$run" "$notes"
    done
    echo "==================================================================="
}

declare -A CVE_41714_ZIP=( [2]='9.7%20SP1%20patch.zip' [4]='9.8%20GA%20patch.zip' [6]='9.8%20SP1%20patch.zip' )

# From here on, print the status report however the script ends
trap print_report EXIT

# Nothing ticked (or Cancel): no changes, just the report of what's installed
if [ -z "$CHOICES" ]; then
    print_info "No options selected. Nothing installed."
    exit 0
fi

for CHOICE in $CHOICES; do
    RPM_INSTALLED=0
    CURRENT_CHOICE="$CHOICE"

    # Check again right before installing (an earlier choice may have applied
    # the same files, e.g. NPM-4630 is shared by options 4 and 6)
    run_check "$CHOICE"
    case $? in
        0) print_info "Option $CHOICE is already installed. Skipping."
           RUN_RESULT[$CHOICE]="Skipped (already installed)"; continue ;;
        3) print_info "Option $CHOICE: a newer version (${CHECK_NEWER}) is already installed. Skipping, so it isn't downgraded."
           RUN_RESULT[$CHOICE]="Skipped (newer installed)"; continue ;;
    esac

    case $CHOICE in
        2)
            download_and_extract "https://github.com/uklad/Micollab-Script/raw/refs/heads/main/CVE-2024-41714/${CVE_41714_ZIP[2]}"
            rename_and_copy_files
            ;;
        4|6)
            # Install only the part(s) that are missing
            if check_cve_41714 "$CHOICE"; then
                print_info "CVE-2024-41714 files already in place (option $CHOICE)"
            else
                download_and_extract "https://github.com/uklad/Micollab-Script/raw/refs/heads/main/CVE-2024-41714/${CVE_41714_ZIP[$CHOICE]}"
                rename_and_copy_files
            fi
            if check_npm_4630; then
                print_info "CVE-2024-35287 (NPM-4630) already in place (option $CHOICE)"
            else
                download_patch 'https://github.com/uklad/Micollab-Script/raw/refs/heads/main/CVE-2024-35287/NPM-4630_Fix_Patch_20.8.tar.gz'
                run_patcher_NPM-4630
            fi
            ;;
        1)
            download_patch 'https://github.com/uklad/Micollab-Script/raw/refs/heads/main/CVE-2024-41713/security_CVE-2024-41713_MiCollab.tar.gz'
            run_patcher_CVE-2024-41713
            ;;
        5)
            # Mitel: the same awc-web-9.8.1.103 RPM patches all 9.8 GA - SP1FP2
            # systems. patch.zip also holds the revert RPMs (9.8.1.102 for
            # SP1FP2, 9.8.0.8 for GA/SP1), which are left in /tmp unused.
            download_and_extract 'https://github.com/uklad/Micollab-Script/raw/refs/heads/main/CVE-2024-47223/patch.zip'
            install_rpm 'awc-web-9.8.1.103-1.i386.rpm'
            [ "$RPM_INSTALLED" = 1 ] && REBOOT_NEEDED=1
            ;;
        7)
            download_and_extract 'https://github.com/uklad/Micollab-Script/raw/refs/heads/main/MISA-2026-0006/AWV-11157_FixPatch_MAS_9.8SP3FP1_10July26.zip'
            install_rpm 'AWV-11157_FixPatch_MAS_9.8SP3FP1_10July26/awc-audio-newupg-9.8.3.202-2.i386.rpm'
            [ "$RPM_INSTALLED" = 1 ] && AWV_RESTART_NEEDED=1
            ;;
        9)
            download_and_extract 'https://github.com/uklad/Micollab-Script/raw/refs/heads/main/MISA-2026-0006/AWV-11157_FixPatch_MAS_10.2SP1FP2_14July26.zip'
            # Mitel's 10.2.1.205 instructions use --oldpackage
            install_rpm 'AWV-11157_FixPatch_MAS_10.2SP1FP2_14July26/awc-audio-newupg-10.3.0.7-1.x86_64.rpm' --oldpackage
            [ "$RPM_INSTALLED" = 1 ] && AWV_RESTART_NEEDED=1
            ;;
        10)
            download_and_extract 'https://github.com/uklad/Micollab-Script/raw/refs/heads/main/MISA-2026-0012/AWV-11322_FixPatch_MAS_10.3_HF1.zip'
            install_rpm 'awc-audio-newupg-10.3.0.8-1.x86_64.rpm'
            [ "$RPM_INSTALLED" = 1 ] && AWV_RESTART_NEEDED=1
            ;;
        3|8)
            install_cs_patch "$CHOICE" || { RUN_RESULT[$CHOICE]="Skipped (wrong version)"; continue; }
            ;;
	*)
            print_error "Invalid choice. Skipping."
            RUN_RESULT[$CHOICE]="Skipped (invalid)"
            continue
            ;;
    esac

    verify_option "$CHOICE"
done
CURRENT_CHOICE=""

# Restart AWV once, after all selected patches are installed
if [ "$AWV_RESTART_NEEDED" = 1 ]; then
    restart_awv_services || { AWV_RESTART_FAILED=1; AWV_SVC_FAILED=1; }
elif [[ " $CHOICES " =~ \ (7|9|10)\  ]]; then
    # An AWV patch (7/9/10) was selected but its RPM was already installed
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

if [ "$REBOOT_NEEDED" = 1 ]; then
    # Not done automatically: Mitel says to reboot when convenient to the customer
    print_info "CVE-2024-47223 (option 5) needs a reboot to take effect. Reboot the MiCollab server when convenient."
fi

if [ -n "$VERIFY_FAILED" ]; then
    print_error "These options could not be verified as installed:$VERIFY_FAILED (see errors above)"
fi
if [ "$AWV_RESTART_FAILED" = 1 ]; then
    print_error "Patches installed, but a service restart needs checking (see errors above)"
fi
if [ -n "$VERIFY_FAILED" ] || [ "$AWV_RESTART_FAILED" = 1 ]; then
    exit 1
fi

print_success "Script completed successfully"