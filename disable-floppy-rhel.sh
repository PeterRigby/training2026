#!/usr/bin/env bash
#
# Disable the Linux floppy driver on a virtual Red Hat server.
#
# This addresses repeated kernel messages such as:
#   blk_update_request: I/O error, dev fd0, sector 0
#
# Run as root. A reboot is recommended after this script completes.

set -euo pipefail

BLACKLIST_FILE="/etc/modprobe.d/blacklist-floppy.conf"
DRACUT_FILE="/etc/dracut.conf.d/omit-floppy.conf"

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        echo "ERROR: This script must be run as root." >&2
        echo "Try: sudo $0" >&2
        exit 1
    fi
}

require_redhat_like() {
    if [[ ! -r /etc/redhat-release ]]; then
        echo "WARNING: /etc/redhat-release was not found; this may not be a Red Hat server." >&2
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
    write_file_if_changed "${BLACKLIST_FILE}" "# Disable floppy probing on virtual servers.
blacklist floppy
install floppy /bin/false"
}

omit_floppy_from_initramfs() {
    mkdir -p "$(dirname "${DRACUT_FILE}")"
    write_file_if_changed "${DRACUT_FILE}" "# Keep floppy out of initramfs images.
omit_drivers+=\" floppy \""

    if ! command -v dracut >/dev/null 2>&1; then
        echo "WARNING: dracut is not installed or not in PATH; initramfs was not regenerated." >&2
        return
    fi

    echo "Regenerating initramfs with dracut..."
    if dracut --help 2>&1 | grep -q -- "--regenerate-all"; then
        dracut -f --regenerate-all
    else
        dracut -f
    fi
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
  3. After reboot, verify that the floppy module is absent:
       lsmod | grep -w floppy
       dmesg | grep -i 'dev fd0'

If the fd0 errors continue after reboot, check the VM hardware settings for a
remaining virtual floppy controller/device.
EOF
}

main() {
    require_root
    require_redhat_like
    blacklist_floppy_module
    omit_floppy_from_initramfs
    unload_floppy_module
    print_next_steps
}

main "$@"
