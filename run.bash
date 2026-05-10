#!/usr/bin/env bash
#
# QEMU Systemd wrapper
#

vmName="$1"
configRepo="$2"

if [[ -z "$vmName" ]]; then
    echo "[ERROR] VM Hostname was not defined. EX: bash run.bash <hostname> <config repo>"
fi

if [[ -z "$configRepo" ]]; then
    echo "[ERROR] VM Hostname was not defined. EX: bash run.bash <hostname>  <config repo>"
fi

nixos-rebuild build-vm  --refresh  --flake "${configRepo}#${vmName}" || exit 1

echo "Starting QEMU VM [${vmName}]. Port forwarding set for [$QEMU_NET_OPTS]."

QEMU_KERNEL_PARAMS=console=ttyS0 result/bin/run-${vmName}-vm 
