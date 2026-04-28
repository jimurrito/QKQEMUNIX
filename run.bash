#!/usr/bin/env bash
#
# QEMU Systemd wrapper
#

VM_NAME="$1"

if [[ -z "$VM_NAME" ]]; then
    echo "[ERROR] VM Hostname was not defined. EX: bash run.bash <hostname>"
fi

nixos-rebuild build-vm  --refresh  --flake git+https://forgejo.immerhouse.com/jimurrito/nixos-config#${VM_NAME}

echo "Starting QEMU VM [${VM_NAME}]. Port forwarding set for [$QEMU_NET_OPTS]."

QEMU_KERNEL_PARAMS=console=ttyS0 result/bin/run-${VM_NAME}-vm 
