#!/usr/bin/env bash
#
# Disable the Linux floppy driver on a virtual SUSE server.
#
# This addresses repeated kernel messages such as:
#   blk_update_request: I/O error, dev fd0, sector 0
#
# Intended for SUSE Linux Enterprise Server and openSUSE systems.
# Run as root. A reboot is recommended after this script completes.

set -euo pipefail

BLACKLIST_FILE="/etc/modprobe.d/50-blacklist-floppy.conf"
DRACUT_FILE="/etc/dracut.conf.d/90-omit-floppy.conf"

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        echo "ERROR: This script must be run as root." >&2
        echo "Try: sudo $0" >&2
        exit 1
    fi
}

require_suse_like() {
    if [[ -r /etc/os-release ]] && grep -Eiq '(^ID=|^ID_LIKE=).*(suse|opensuse|sles)' /etc/os-release; then
        return
    fi

    if [[ -r /etc/SuSE-release ]]; then
        return
    fi

    echo "WARNING: This host does not look like SUSE Linux Enterprise Server or openSUSE." >&2
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
    write_file_if_changed "${BLACKLIST_FILE}" "# Disable floppy probing on virtual SUSE servers.
blacklist floppy
install floppy /bin/false"
}

omit_floppy_from_initrd() {
    mkdir -p "$(dirname "${DRACUT_FILE}")"
    write_file_if_changed "${DRACUT_FILE}" "# Keep floppy out of initrd images.
omit_drivers+=\" floppy \""
}

regenerate_initrd() {
    if command -v dracut >/dev/null 2>&1; then
        echo "Regenerating initrd with dracut..."
        if dracut --help 2>&1 | grep -q -- "--regenerate-all"; then
            dracut -f --regenerate-all
        else
            dracut -f
        fi
        return
    fi

    if command -v mkinitrd >/dev/null 2>&1; then
        echo "Regenerating initrd with mkinitrd..."
        mkinitrd
        return
    fi

    echo "WARNING: Neither dracut nor mkinitrd was found; initrd was not regenerated." >&2
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
    require_suse_like
    blacklist_floppy_module
    omit_floppy_from_initrd
    regenerate_initrd
    unload_floppy_module
    print_next_steps
}

main "$@"
