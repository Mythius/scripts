#!/bin/bash

# Ensure the script is run with sudo
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)."
   exit 1
fi

echo "[!] EMERGENCY LOCKDOWN INITIATED..."

# 1. Reset UFW to clear all existing "allow" rules
echo "y" | ufw reset

# 2. Set strict default policies to block everything
ufw default deny incoming
ufw default deny outgoing
ufw default deny routed

# 3. Enable the firewall
ufw --force enable

echo "[+] SYSTEM IS NOW ISOLATED. All network traffic is blocked."
echo "[+] Status:"
ufw status verbose
