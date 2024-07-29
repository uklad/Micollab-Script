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

# Function to download and extract patch
download_and_extract() {
    local url=$1
    local patch_file="micollabpatch.tar"

    print_info "Changing directory to /tmp/"
    cd /tmp/ || { print_error "Failed to change directory to /tmp/"; exit 1; }

    print_info "Downloading patch from $url"
    (
        if wget --no-check-certificate "$url" -O "$patch_file"; then
            print_success "Download completed successfully"
        else
            print_error "Failed to download $patch_file"
            exit 1
        fi
    ) &
    show_working $!

    print_info "Extracting $patch_file"
    (
        if tar -xvf "$patch_file"; then
            print_success "Extraction completed successfully"
        else
            print_error "Failed to extract $patch_file"
            exit 1
        fi
    ) &
    show_working $!
}

# Function to rename and copy files
rename_and_copy_files() {
    print_info "Renaming existing views.py and feedback.py"
    mv /etc/e-smith/web/django/servermanager/ucdiag/tdc/views.py /etc/e-smith/web/django/servermanager/ucdiag/tdc/views_old.py || print_error "Failed to rename views.py"
    mv /usr/ucs/feedback/feedback.py /usr/ucs/feedback/feedback_old.py || print_error "Failed to rename feedback.py"

    print_info "Copying new views.py and feedback.py"
    cp /tmp/views.py /etc/e-smith/web/django/servermanager/ucdiag/tdc/ || { print_error "Failed to copy views.py"; exit 1; }
    cp /tmp/feedback.py /usr/ucs/feedback/ || { print_error "Failed to copy feedback.py"; exit 1; }
}

# Function to run patcher.sh
run_patcher() {
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
}

# Present menu to user
print_info "Select an option:"
echo "1. 9.7 SP1 FP1 (9.7.1.110)"
echo "2. 9.8 GA (9.8.0.33)"
echo "3. 9.8 SP1 (9.8.1.5)"
read -n -p "Enter your choice [1-3]: " choice

case $choice in
    1)
        download_and_extract 'https://github.com/uklad/Micollab-Script/raw/main/micollabpatch.tar'
        rename_and_copy_files
        ;;
    2)
        download_and_extract 'https://github.com/uklad/Micollab-Script/raw/main/micollabpatch.tar'
        rename_and_copy_files
        run_patcher
        ;;
    3)
        download_and_extract 'https://github.com/uklad/Micollab-Script/raw/main/micollabpatch9-8-1-5.tar'
        rename_and_copy_files
        run_patcher
        ;;
    *)
        print_error "Invalid choice. Exiting."
        exit 1
        ;;
esac

print_success "Script completed successfully"

