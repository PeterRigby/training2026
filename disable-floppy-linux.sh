#!/usr/bin/env bash
#
# Disable the Linux floppy driver on virtual Red Hat and SUSE servers.
#
# This addresses repeated kernel messages such as:
#   blk_update_request: I/O error, dev fd0, sector 0
#
# Supported targets:
#   - Red Hat Enterprise Linux and compatible distributions
#   - SUSE Linux Enterprise Server and openSUSE
#
# Run as root. A reboot is recommended after this script completes.

set -euo pipefail

BLACKLIST_FILE="/etc/modprobe.d/blacklist-floppy.conf"
DRACUT_FILE="/etc/dracut.conf.d/omit-floppy.conf"
OS_FAMILY="unknown"
OS_PRETTY_NAME="unknown Linux"

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        echo "ERROR: This script must be run as root." >&2
        echo "Try: sudo $0" >&2
        exit 1
    fi
}

load_os_release() {
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_PRETTY_NAME="${PRETTY_NAME:-unknown Linux}"

        local ids=" ${ID:-} ${ID_LIKE:-} "
        case "${ids,,}" in
            *rhel*|*redhat*|*centos*|*fedora*|*rocky*|*alma*|*ol*)
                OS_FAMILY="redhat"
                ;;
            *suse*|*opensuse*|*sles*)
                OS_FAMILY="suse"
                ;;
        esac
    fi

    if [[ "${OS_FAMILY}" == "unknown" && -r /etc/redhat-release ]]; then
        OS_FAMILY="redhat"
        OS_PRETTY_NAME="$(< /etc/redhat-release)"
    fi

    if [[ "${OS_FAMILY}" == "unknown" && -r /etc/SuSE-release ]]; then
        OS_FAMILY="suse"
        OS_PRETTY_NAME="SUSE Linux"
    fi
}

warn_if_unknown_os() {
    if [[ "${OS_FAMILY}" == "unknown" ]]; then
        echo "WARNING: This host does not look like a Red Hat or SUSE family system." >&2
        echo "Detected OS: ${OS_PRETTY_NAME}" >&2
    else
        echo "Detected ${OS_FAMILY} family system: ${OS_PRETTY_NAME}"
    fi
}

write_file_if_changed() {
    local target_file="$1"
    local desired_content="$2"
    local temp_file

    temp_file="$(mktemp)"
    printf "%s\n" "${desired_content}" > "${temp_file}"

    if [[ -f "${target_file}" ]] && cmp -s "${temp_file}" "${target_file}"; then
        echo "Already configured: ${target_file}"
        rm -f "${temp_file}"
        return
    fi

    install -m 0644 "${temp_file}" "${target_file}"
    rm -f "${temp_file}"
    echo "Updated: ${target_file}"
}

blacklist_floppy_module() {
    write_file_if_changed "${BLACKLIST_FILE}" "# Disable floppy probing on virtual Linux servers.
blacklist floppy
install floppy /bin/false"
}

omit_floppy_from_boot_image() {
    mkdir -p "$(dirname "${DRACUT_FILE}")"
    write_file_if_changed "${DRACUT_FILE}" "# Keep floppy out of initramfs/initrd images.
omit_drivers+=\" floppy \""
}

regenerate_with_dracut() {
    echo "Regenerating initramfs/initrd with dracut..."
    if dracut --help 2>&1 | grep -q -- "--regenerate-all"; then
        dracut -f --regenerate-all
    else
        dracut -f
    fi
}

regenerate_with_mkinitrd() {
    echo "Regenerating initrd with mkinitrd..."
    mkinitrd
}

regenerate_boot_image() {
    if command -v dracut >/dev/null 2>&1; then
        regenerate_with_dracut
        return
    fi

    if command -v mkinitrd >/dev/null 2>&1; then
        regenerate_with_mkinitrd
        return
    fi

    echo "WARNING: Neither dracut nor mkinitrd was found; boot image was not regenerated." >&2
}

unload_floppy_module() {
    if ! lsmod | awk '{print $1}' | grep -qx "floppy"; then
        echo "floppy module is not currently loaded."
        return
    fi

    echo "Attempting to unload floppy module..."
    if modprobe -r floppy; then
        echo "Unloaded floppy module."
    else
        echo "WARNING: Could not unload floppy module. Reboot to complete disablement." >&2
    fi
}

print_next_steps() {
    cat <<'EOF'

Done. Recommended next steps:
  1. Remove or disable the virtual floppy device in the hypervisor settings if present.
  2. Reboot the server.
  3. After reboot, verify that the floppy module is absent and fd0 errors stopped:
       lsmod | grep -w floppy
       dmesg | grep -i 'dev fd0'

If the fd0 errors continue after reboot, check the VM hardware settings for a
remaining virtual floppy controller/device.
EOF
}

main() {
    require_root
    load_os_release
    warn_if_unknown_os
    blacklist_floppy_module
    omit_floppy_from_boot_image
    regenerate_boot_image
    unload_floppy_module
    print_next_steps
}

main "$@"
