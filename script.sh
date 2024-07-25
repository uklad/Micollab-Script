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

print_info "Changing directory to /tmp/"
cd /tmp/

print_info "Downloading micollabpatch.tar from Google Drive"
if wget --no-check-certificate 'https://docs.google.com/uc?export=download&id=1gHZszzqlV2_vfp72SETdhMSrMfRzyBXb' -O micollabpatch.tar; then
    print_success "Download completed successfully"
else
    print_error "Failed to download micollabpatch.tar"
    exit 1
fi

print_info "Extracting micollabpatch.tar"
if tar -xvf micollabpatch.tar; then
    print_success "Extraction completed successfully"
else
    print_error "Failed to extract micollabpatch.tar"
    exit 1
fi

print_info "Renaming existing views.py and feedback.py"
mv /etc/e-smith/web/django/servermanager/ucdiag/tdc/views.py /etc/e-smith/web/django/servermanager/ucdiag/tdc/views_old.py
mv /usr/ucs/feedback/feedback.py /usr/ucs/feedback/feedback_old.py

print_info "Copying new views.py and feedback.py"
cp /tmp/views.py /etc/e-smith/web/django/servermanager/ucdiag/tdc/
cp /tmp/feedback.py /usr/ucs/feedback/

print_info "Extracting NPM-4630_Fix_Patch_20.8.tar.gz"
if tar -zxvf NPM-4630_Fix_Patch_20.8.tar.gz; then
    print_success "Extraction completed successfully"
else
    print_error "Failed to extract NPM-4630_Fix_Patch_20.8.tar.gz"
    exit 1
fi

print_info "Running patcher.sh"
if sh patcher.sh; then
    print_success "Patcher executed successfully"
else
    print_error "Failed to execute patcher.sh"
    exit 1
fi

print_success "Script completed successfully"
