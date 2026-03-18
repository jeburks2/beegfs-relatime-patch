#!/bin/bash

# BeeGFS Relatime Patch Installer/Uninstaller
# This script applies or removes the BeeGFS relatime patch to/from the client source code.

set -euo pipefail

# Global variables
UNINSTALL_MODE=false
NO_REBUILD=false
BEEGFS_VERSION=""
BEEGFS_MAJOR_VERSION=""
BEEGFS_CLIENT_DIR=""
PATCH_FILE=""
IN_CHROOT=false
IN_CONTAINER=false
SERVICE_WAS_RUNNING=false

show_help() {
    cat << EOF
BeeGFS Relatime Patch Installer/Uninstaller

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --help          Show this help message and exit
    --uninstall     Remove the relatime patch instead of applying it
    --norebuild     Skip automatic rebuild of BeeGFS client module

DESCRIPTION:
    This script applies or removes the BeeGFS relatime patch for the installed
    BeeGFS client version. It automatically detects the BeeGFS version and
    applies the appropriate patch file.

REQUIREMENTS:
    - Must be run as root
    - RHEL-based distribution (RHEL, CentOS, Fedora, etc.)
    - BeeGFS client must be installed
    - Appropriate patch file must exist in current directory

EXAMPLES:
    $0                  # Apply the relatime patch
    $0 --uninstall      # Remove the relatime patch
    $0 --norebuild      # Apply patch but skip client rebuild

EOF
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Error: Please run as root"
        exit 1
    fi
}

check_compatibility() {
    echo "Checking system compatibility..."
    source /etc/os-release

    if [[ "$ID_LIKE" == *"rhel"* || "$ID_LIKE" == *"centos"* || "$ID_LIKE" == *"fedora"* ]]; then
        echo "✓ Detected RHEL-based distribution: $ID"
    else
        echo "Error: Unsupported distribution: $ID"
        echo "This script is intended for RHEL-based distributions. If you would like to support other distributions, please submit a pull request with the necessary adjustments."
        exit 1
    fi
}

detect_beegfs() {
    echo "Detecting BeeGFS client version..."
    if ! BEEGFS_VERSION="$(rpm -q beegfs-client --qf '%{version}\n' 2>/dev/null)"; then
        echo "Error: BeeGFS client is not installed. Please install the BeeGFS client before running this script."
        exit 1
    fi

    BEEGFS_MAJOR_VERSION=$(echo "$BEEGFS_VERSION" | cut -d. -f1)
    PATCH_FILE="beegfs-${BEEGFS_VERSION}-relatime.patch"
    echo "✓ Found BeeGFS client version: $BEEGFS_VERSION"

    echo "Locating BeeGFS client source directory..."
    if [[ "$BEEGFS_MAJOR_VERSION" -eq 8 ]] && [ -d /opt/beegfs/src/client/client_module_8 ]; then
        echo "✓ BeeGFS client version 8 detected"
        BEEGFS_CLIENT_DIR="/opt/beegfs/src/client/client_module_8"
    elif [[ "$BEEGFS_MAJOR_VERSION" -eq 7 ]] && [ -d /opt/beegfs/src/client/client_module_7 ]; then
        echo "✓ BeeGFS client version 7 detected"
        BEEGFS_CLIENT_DIR="/opt/beegfs/src/client/client_module_7"
    else
        echo "Error: Unsupported BeeGFS client version: $BEEGFS_VERSION"
        exit 1
    fi
}

detect_environment() {
    # Detect if running in chroot or container environment
    IN_CHROOT=false
    IN_CONTAINER=false

    # Check for chroot environment
    if [ "$(stat -c %d:%i /)" != "$(stat -c %d:%i /proc/1/root/ 2>/dev/null)" ]; then
        IN_CHROOT=true
        echo "ℹ Detected chroot environment"
    fi

    # Check for container environment
    if [ -f /.dockerenv ] || [ -f /run/.containerenv ] || grep -q container=podman /proc/1/environ 2>/dev/null || grep -qE '/(docker|lxc|podman)/' /proc/1/cgroup 2>/dev/null; then
        IN_CONTAINER=true
        echo "ℹ Detected container/podman environment"
    fi

    # Check if service is currently running
    SERVICE_WAS_RUNNING=false
    if systemctl is-active --quiet beegfs-client 2>/dev/null; then
        echo "✓ BeeGFS client service is currently running"
        SERVICE_WAS_RUNNING=true
    else
        echo "ℹ BeeGFS client service is not running"
    fi
}

apply_patch() {
    echo "Checking for patch file..."
    if [ ! -e "./$PATCH_FILE" ]; then
        echo "Error: No patch found for BeeGFS version ${BEEGFS_VERSION}"
        echo "Please ensure the correct patch file is in the current directory."
        exit 1
    fi
    echo "✓ Found patch file: $PATCH_FILE"

    echo "Applying BeeGFS relatime patch for version ${BEEGFS_VERSION}..."
    cp "./$PATCH_FILE" "$BEEGFS_CLIENT_DIR"

    # Apply the patch
    cd "$BEEGFS_CLIENT_DIR"
    if patch -p1 --forward --batch < "$PATCH_FILE"; then
        echo "✓ Patch applied successfully"
    else
        echo "Error: Failed to apply patch"
        # Clean up patch file on failure
        rm -f "$PATCH_FILE"
        exit 2
    fi

    # Clean up the patch file
    rm -f "$PATCH_FILE"
    cd - > /dev/null
}

unapply_patch() {
    echo "Checking for patch file..."
    if [ ! -e "./$PATCH_FILE" ]; then
        echo "Error: No patch found for BeeGFS version ${BEEGFS_VERSION}"
        echo "Please ensure the correct patch file is in the current directory."
        exit 1
    fi
    echo "✓ Found patch file: $PATCH_FILE"

    echo "Removing BeeGFS relatime patch for version ${BEEGFS_VERSION}..."
    cp "./$PATCH_FILE" "$BEEGFS_CLIENT_DIR"

    # Reverse the patch
    cd "$BEEGFS_CLIENT_DIR"
    if patch -p1 --reverse --batch < "$PATCH_FILE"; then
        echo "✓ Patch removed successfully"
    else
        echo "Error: Failed to remove patch"
        # Clean up patch file on failure
        rm -f "$PATCH_FILE"
        exit 2
    fi

    # Clean up the patch file
    rm -f "$PATCH_FILE"
    cd - > /dev/null
}

rebuild_client() {
    # Skip rebuild and service operations in chroot/container environments or if --norebuild is specified
    if [ "$IN_CHROOT" = true ] || [ "$IN_CONTAINER" = true ]; then
        echo "ℹ Skipping BeeGFS client rebuild and service operations (chroot/container environment detected)"
        return 0
    fi

    if [ "$NO_REBUILD" = true ]; then
        echo "ℹ Skipping BeeGFS client rebuild (--norebuild specified)"
        return 0
    fi

    echo "Rebuilding the BeeGFS client..."
    if /opt/beegfs/sbin/beegfs-client rebuild; then
        echo "✓ BeeGFS client rebuilt successfully"
    else
        echo "Error: Failed to rebuild BeeGFS client"
        exit 3
    fi
}

manage_service() {
    # Skip service operations in chroot/container environments or if --norebuild is specified
    if [ "$IN_CHROOT" = true ] || [ "$IN_CONTAINER" = true ] || [ "$NO_REBUILD" = true ]; then
        return 0
    fi

    # Restart service only if it was running before
    if [ "$SERVICE_WAS_RUNNING" = true ]; then
        echo "Restarting BeeGFS client service..."
        if systemctl restart beegfs-client; then
            echo "✓ BeeGFS client service restarted successfully"
        else
            echo "Error: Failed to restart BeeGFS client service"
            exit 4
        fi
    else
        echo "ℹ BeeGFS client service was not running, skipping restart"
    fi
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                exit 0
                ;;
            --uninstall)
                UNINSTALL_MODE=true
                shift
                ;;
            --norebuild)
                NO_REBUILD=true
                shift
                ;;
            *)
                echo "Error: Unknown option $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

main() {
    parse_arguments "$@"
    check_root
    check_compatibility
    detect_beegfs
    detect_environment

    if [ "$UNINSTALL_MODE" = true ]; then
        unapply_patch
        rebuild_client
        manage_service
        if [ "$IN_CHROOT" = true ] || [ "$IN_CONTAINER" = true ]; then
            echo "✓ BeeGFS relatime patch removed successfully!"
            echo "Note: You will need to rebuild the client and restart services manually in the target environment."
        else
            echo "✓ BeeGFS relatime patch removal completed successfully!"
        fi
    else
        apply_patch
        rebuild_client
        manage_service
        if [ "$IN_CHROOT" = true ] || [ "$IN_CONTAINER" = true ]; then
            echo "✓ BeeGFS relatime patch applied successfully!"
            echo "Note: You will need to rebuild the client and restart services manually in the target environment."
        else
            echo "✓ BeeGFS relatime patch installation completed successfully!"
        fi
    fi
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi