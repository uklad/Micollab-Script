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
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

print_info "Changing directory to /tmp/"
cd /tmp/ || { print_error "Failed to change directory to /tmp/"; exit 1; }

print_info "Downloading micollabpatch.tar from Google Drive"
(
    if wget --no-check-certificate 'https://github.com/uklad/Micollab-Script/raw/main/micollabpatch.tar' -O micollabpatch.tar; then
        print_success "Download completed successfully"
    else
        print_error "Failed to download micollabpatch.tar"
        exit 1
    fi
) &
show_working $!

print_info "Extracting micollabpatch.tar"
(
    if tar -xvf micollabpatch.tar; then
        print_success "Extraction completed successfully"
    else
        print_error "Failed to extract micollabpatch.tar"
        exit 1
    fi
) &
show_working $!

print_info "Renaming existing views.py and feedback.py"
mv /etc/e-smith/web/django/servermanager/ucdiag/tdc/views.py /etc/e-smith/web/django/servermanager/ucdiag/tdc/views_old.py || print_error "Failed to rename views.py"
mv /usr/ucs/feedback/feedback.py /usr/ucs/feedback/feedback_old.py || print_error "Failed to rename feedback.py"

print_info "Copying new views.py and feedback.py"
cp /tmp/views.py /etc/e-smith/web/django/servermanager/ucdiag/tdc/ || { print_error "Failed to copy views.py"; exit 1; }
cp /tmp/feedback.py /usr/ucs/feedback/ || { print_error "Failed to copy feedback.py"; exit 1; }

print_info "Extracting NPM-4630_Fix_Patch_20.8.tar.gz"
(
    if tar -zxvf NPM-4630_Fix_Patch_20.8.tar.gz; then
        print_success "Extraction completed successfully"
    else
        print_error "Failed to extract NPM-4630_Fix_Patch_20.8.tar.gz"
        exit 1
    fi
) &
show_working $!

print_info "Running patcher.sh"
print_info "Script may pause for a few seconds until complete"
(
    if sh patcher.sh; then
        print_success "Patcher executed successfully"
    else
        print_error "Failed to execute patcher.sh"
        exit 1
    fi
) &
show_working $!

print_success "Script completed successfully"

