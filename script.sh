#!/bin/bash
# ==============================================================================
# MiCollab Security Patch Automation Script
# Applies CVE patches: CVE-2024-41713, CVE-2024-41714,
#                      CVE-2024-35287, CVE-2024-47223
# ==============================================================================
 
set -euo pipefail
 
# ------------------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------------------
readonly SCRIPT_VERSION="2.0.0"
readonly TMP_DIR="/tmp/micollab_patches"
readonly LOG_FILE="/var/log/micollab_patch_$(date +%Y%m%d_%H%M%S).log"
readonly GITHUB_BASE="https://github.com/uklad/Micollab-Script/raw/refs/heads/main"
 
# ------------------------------------------------------------------------------
# Logging & Output
# ------------------------------------------------------------------------------
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}
 
print_info() {
    local msg="[INFO] $*"
    echo -e "\e[34m${msg}\e[0m"
    log "$msg"
}
 
print_success() {
    local msg="[SUCCESS] $*"
    echo -e "\e[32m${msg}\e[0m"
    log "$msg"
}
 
print_error() {
    local msg="[ERROR] $*"
    echo -e "\e[31m${msg}\e[0m" >&2
    log "$msg"
}
 
print_warn() {
    local msg="[WARN] $*"
    echo -e "\e[33m${msg}\e[0m"
    log "$msg"
}
 
die() {
    print_error "$*"
    exit 1
}
 
# ------------------------------------------------------------------------------
# Prerequisite Checks
# ------------------------------------------------------------------------------
check_prerequisites() {
    print_info "Checking prerequisites..."
 
    [[ $EUID -eq 0 ]] || die "This script must be run as root."
 
    local missing=()
    for cmd in dialog wget tar unzip rpm; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
 
    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Missing required commands: ${missing[*]}. Please install them and retry."
    fi
 
    mkdir -p "$TMP_DIR" || die "Failed to create working directory: $TMP_DIR"
    print_success "Prerequisites OK. Working directory: $TMP_DIR"
}
 
# ------------------------------------------------------------------------------
# Download & Extract
# ------------------------------------------------------------------------------
download_file() {
    local url="$1"
    local output="${TMP_DIR}/${url##*/}"
 
    print_info "Downloading: ${url##*/}"
    if wget --no-check-certificate -q --show-progress -O "$output" "$url"; then
        print_success "Downloaded: ${output##*/}"
        echo "$output"   # return the path
    else
        die "Failed to download: $url"
    fi
}
 
extract_archive() {
    local archive="$1"
 
    print_info "Extracting: ${archive##*/}"
    case "$archive" in
        *.tar.gz) tar -zxf "$archive" -C "$TMP_DIR" ;;
        *.tar)    tar -xf  "$archive" -C "$TMP_DIR" ;;
        *.zip)    unzip -oq "$archive" -d "$TMP_DIR" ;;
        *)        die "Unsupported archive format: ${archive##*/}" ;;
    esac
    print_success "Extracted: ${archive##*/}"
}
 
download_and_extract() {
    local url="$1"
    local archive
    archive=$(download_file "$url")
    extract_archive "$archive"
}
 
# ------------------------------------------------------------------------------
# Patch Actions
# ------------------------------------------------------------------------------
replace_app_files() {
    print_info "Replacing application files..."
 
    local views_src="$TMP_DIR/views.py"
    local views_dst="/etc/e-smith/web/django/servermanager/ucdiag/tdc/views.py"
    local feedback_src="$TMP_DIR/feedback.py"
    local feedback_dst="/usr/ucs/feedback/feedback.py"
 
    [[ -f "$views_src" ]]    || die "views.py not found in extracted patch."
    [[ -f "$feedback_src" ]] || die "feedback.py not found in extracted patch."
    [[ -f "$views_dst" ]]    || die "Destination views.py not found. Is MiCollab installed?"
    [[ -f "$feedback_dst" ]] || die "Destination feedback.py not found. Is MiCollab installed?"
 
    # Back up originals with timestamps
    local ts
    ts=$(date +%Y%m%d_%H%M%S)
    cp -f "$views_dst"    "${views_dst%.py}_backup_${ts}.py"
    cp -f "$feedback_dst" "${feedback_dst%.py}_backup_${ts}.py"
    print_info "Backups created with timestamp: $ts"
 
    cp -f "$views_src"    "$views_dst"    || die "Failed to copy views.py"
    cp -f "$feedback_src" "$feedback_dst" || die "Failed to copy feedback.py"
 
    print_success "Application files replaced successfully."
}
 
run_patcher() {
    local patcher_script="$TMP_DIR/patcher.sh"
 
    [[ -f "$patcher_script" ]] || die "patcher.sh not found in: $TMP_DIR"
 
    print_info "Running patcher.sh (this may take a few seconds)..."
    if bash "$patcher_script"; then
        print_success "patcher.sh completed successfully."
    else
        die "patcher.sh failed. Check $LOG_FILE for details."
    fi
}
 
install_rpm() {
    local rpm_file="$TMP_DIR/$1"
 
    [[ -f "$rpm_file" ]] || die "RPM file not found: $rpm_file"
 
    # Extract package name properly using rpm query
    local rpm_name
    rpm_name=$(rpm -qp --queryformat '%{NAME}' "$rpm_file" 2>/dev/null) \
        || die "Unable to read RPM metadata from: ${rpm_file##*/}"
 
    if rpm -q "$rpm_name" &>/dev/null; then
        print_warn "RPM '$rpm_name' is already installed. Skipping."
        return 0
    fi
 
    print_info "Installing RPM: ${rpm_file##*/}"
    if rpm -Uvh --noscripts "$rpm_file"; then
        print_success "RPM installed: $rpm_name"
    else
        die "Failed to install RPM: ${rpm_file##*/}"
    fi
}
 
# ------------------------------------------------------------------------------
# Per-CVE Patch Functions
# ------------------------------------------------------------------------------
apply_cve_41714_97sp1() {
    print_info "=== Applying CVE-2024-41714 patch for 9.7 SP1 ==="
    download_and_extract "${GITHUB_BASE}/CVE-2024-41714/9.7%20SP1%20patch.zip"
    replace_app_files
}
 
apply_cve_41714_98ga() {
    print_info "=== Applying CVE-2024-41714 & CVE-2024-35287 patches for 9.8 GA ==="
    download_and_extract "${GITHUB_BASE}/CVE-2024-41714/9.8%20GA%20patch.zip"
    replace_app_files
    local archive
    archive=$(download_file "${GITHUB_BASE}/CVE-2024-35287/NPM-4630_Fix_Patch_20.8.tar.gz")
    extract_archive "$archive"
    run_patcher
}
 
apply_cve_41714_98sp1() {
    print_info "=== Applying CVE-2024-41714 & CVE-2024-35287 patches for 9.8 SP1 ==="
    download_and_extract "${GITHUB_BASE}/CVE-2024-41714/9.8%20SP1%20patch.zip"
    replace_app_files
    local archive
    archive=$(download_file "${GITHUB_BASE}/CVE-2024-35287/NPM-4630_Fix_Patch_20.8.tar.gz")
    extract_archive "$archive"
    run_patcher
}
 
apply_cve_41713() {
    print_info "=== Applying CVE-2024-41713 patch ==="
    local archive
    archive=$(download_file "${GITHUB_BASE}/CVE-2024-41713/security_CVE-2024-41713_MiCollab.tar.gz")
    extract_archive "$archive"
    run_patcher
}
 
apply_cve_47223() {
    print_info "=== Applying CVE-2024-47223 patch (REBOOT REQUIRED) ==="
    download_and_extract "${GITHUB_BASE}/CVE-2024-47223/patch.zip"
    install_rpm "awc-web-9.8.1.103-1.i386.rpm"
    print_warn "CVE-2024-47223 applied. A SYSTEM REBOOT is required to complete this patch."
}
 
# ------------------------------------------------------------------------------
# Version Detection & Preselection
# ------------------------------------------------------------------------------
detect_version() {
    local version
    version=$(config getprop sysconfig MasVersion 2>/dev/null) \
        || die "Failed to retrieve MasVersion from system config."
 
    [[ -n "$version" ]] || die "MasVersion is empty. Cannot determine patch requirements."
 
    echo "$version"
}
 
get_preselected() {
    local version="$1"
    case "$version" in
        "9.7.0.27")   echo "4" ;;
        "9.7.1.13")   echo "1 4" ;;
        "9.7.1.110")  echo "4" ;;
        "9.8.0.33")   echo "2 4 5" ;;
        "9.8.1.5")    echo "3 4 5" ;;
        "9.8.1.108")  echo "4 5" ;;
        "9.8.1.201")  echo "4 5" ;;
        "9.8.2.12")   echo "" ;;
        *)             echo "" ;;
    esac
}
 
build_dialog_option() {
    local num="$1" label="$2" preselected="$3"
    local state="off"
    [[ " $preselected " == *" $num "* ]] && state="on"
    echo "$num" "$label" "$state"
}
 
# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
main() {
    echo "=================================================="
    echo " MiCollab Security Patch Script v${SCRIPT_VERSION}"
    echo "=================================================="
    echo " Log: $LOG_FILE"
    echo ""
    log "Script started. Version: $SCRIPT_VERSION"
 
    check_prerequisites
 
    local mas_version
    mas_version=$(detect_version)
    print_success "MiCollab version detected: $mas_version"
 
    local preselected
    preselected=$(get_preselected "$mas_version")
 
    if [[ -z "$preselected" ]]; then
        print_warn "No pre-recommended patches for version $mas_version. Please select manually."
    fi
 
    # Build dialog checklist
    local choices
    choices=$(dialog \
        --backtitle "MiCollab Patch Selector v${SCRIPT_VERSION}" \
        --title "Security Patch Selection" \
        --checklist "MiCollab version detected: $mas_version\nRecommended patches are pre-selected.\n\nUse SPACE to toggle, ENTER to confirm." \
        20 160 7 \
        $(build_dialog_option 1 "9.7 SP1  (9.7.1.13)              | CVE-2024-41714"                                 "$preselected") \
        $(build_dialog_option 2 "9.8 GA   (9.8.0.33)              | CVE-2024-41714 + CVE-2024-35287"               "$preselected") \
        $(build_dialog_option 3 "9.8 SP1  (9.8.1.5)               | CVE-2024-41714 + CVE-2024-35287"               "$preselected") \
        $(build_dialog_option 4 "9.7-9.8 SP1FP2 (9.7.0.27-9.8.1.201) | CVE-2024-41713"                            "$preselected") \
        $(build_dialog_option 5 "9.8 GA-SP1FP2  (9.8.0.33-9.8.1.201) | CVE-2024-47223  *** REBOOT REQUIRED ***"   "$preselected") \
        $(build_dialog_option 6 "6.0-9.8 SP1FP2 + MiVB-X           | CVE-2024-41713"                              "$preselected") \
        3>&1 1>&2 2>&3 3>&-) || { print_error "Dialog cancelled. Exiting."; exit 1; }
 
    [[ -n "$choices" ]] || die "No patches selected. Exiting."
 
    print_info "Selected patches: $choices"
    log "User selected choices: $choices"
 
    local reboot_required=false
 
    for choice in $choices; do
        case "$choice" in
            1) apply_cve_41714_97sp1 ;;
            2) apply_cve_41714_98ga  ;;
            3) apply_cve_41714_98sp1 ;;
            4) apply_cve_41713       ;;
            5) apply_cve_47223; reboot_required=true ;;
            6) apply_cve_41713       ;;
            *) print_warn "Unknown option '$choice'. Skipping." ;;
        esac
    done
 
    echo ""
    echo "=================================================="
    print_success "All selected patches applied successfully."
    print_info "Full log saved to: $LOG_FILE"
 
    if $reboot_required; then
        echo ""
        print_warn "======================================================"
        print_warn " REBOOT REQUIRED: CVE-2024-47223 was applied."
        print_warn " Please reboot this system at your earliest convenience."
        print_warn "======================================================"
    fi
 
    # Clean up working directory
    rm -rf "$TMP_DIR"
    print_info "Cleaned up temporary files."
    echo "=================================================="
}
 
main "$@"

