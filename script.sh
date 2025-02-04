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

# Function to download and extract patch

download_and_extract() {
  local url="$1"
  local patch_file="${url##*/}"  # Extract the filename from the URL

  print_info "Changing directory to /tmp/"
  cd /tmp/ || { print_error "Failed to change directory to /tmp/"; exit 1; }

  print_info "Downloading patch from $url"
  if wget --no-check-certificate "$url" -O "$patch_file"; then
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
    if wget --no-check-certificate "$url" -O "$patch_file"; then
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
install_rpm() {
    local rpm_file=$1
    local rpm_name="${rpm_file%.rpm}"

    # Check if RPM is already installed
    if rpm -q "$rpm_name" >/dev/null 2>&1; then
        print_info "RPM package $rpm_file is already installed. Skipping."
        return 0
    fi

    print_info "Installing RPM package: $rpm_file"
    if rpm -Uvh --noscripts "$rpm_file"; then
        print_success "RPM installed successfully: $rpm_file"
    else
        print_error "Failed to install RPM: $rpm_file"
        exit 1
    fi
}

# Check if dialog is installed
if ! command -v dialog &> /dev/null; then
    print_error "dialog command could not be found, please install it to continue."
    exit 1
fi

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
    PRESELECTED=""
    ;;
  *)
    PRESELECTED=""
    ;;
esac

# Display the dialog with preselected options
CHOICES=$(dialog --backtitle "Patch Selector" --title "Select an Option" --checklist \
"Choose the patch version(s): Micollab Version Detected : $MasVersion preselected recommended patches " 15 150 5 \
    1 "9.7 SP1 (9.7.1.13) CVE-2024-41714 " $( [[ "$PRESELECTED" == *1* ]] && echo "on" || echo "off" ) \
    2 "9.8 GA (9.8.0.33) CVE-2024-41714 & CVE-2024-35287 " $( [[ "$PRESELECTED" == *2* ]] && echo "on" || echo "off" ) \
    3 "9.8 SP1 (9.8.1.5) CVE-2024-41714 & CVE-2024-35287 " $( [[ "$PRESELECTED" == *3* ]] && echo "on" || echo "off" ) \
    4 "9.7 to 9.8 SP1FP2 (9.7.0.27 - 9.8.1.201) CVE-2024-41713 " $( [[ "$PRESELECTED" == *4* ]] && echo "on" || echo "off" ) \
    5 "9.8 GA to 9.8 SP1FP2 (9.8.0.33 - 9.8.1.201) CVE-2024-47223 - ** Reboot Required **" $( [[ "$PRESELECTED" == *5* ]] && echo "on" || echo "off" ) \
	6 "6.0 to 9.8 SP1FP2 + MiVB-X (6.0.206.0 - 9.8.1.201) CVE-2024-41713 " $( [[ "$PRESELECTED" == *6* ]] && echo "on" || echo "off" ) \
    3>&1 1>&2 2>&3 3>&-)

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
        4)
            download_patch 'https://github.com/uklad/Micollab-Script/raw/refs/heads/main/CVE-2024-41713/security_CVE-2024-41713_MiCollab.tar.gz'
            run_patcher_CVE-2024-41713
            ;;
        5)
            download_and_extract 'https://github.com/uklad/Micollab-Script/raw/refs/heads/main/CVE-2024-47223/patch.zip'
            install_rpm 'awc-web-9.8.1.103-1.i386.rpm'
            ;;
        4)
            download_patch 'https://github.com/uklad/Micollab-Script/raw/refs/heads/main/CVE-2024-41713/security_CVE-2024-41713_MiCollab.tar.gz'
            run_patcher_CVE-2024-41713
            ;;		
		*)
            print_error "Invalid choice. Skipping."
            ;;
    esac
done

print_success "Script completed successfully"
