#!/bin/bash
# One-time SSH key authorization script
# Run this inside the RHEL 9 VM terminal to allow passwordless SSH from Windows

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PUB_KEY_FILE="${SCRIPT_DIR}/host_key.pub"

mkdir -p ~/.ssh
chmod 700 ~/.ssh

if [ -f "$PUB_KEY_FILE" ]; then
    cat "$PUB_KEY_FILE" >> ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    echo "[SUCCESS] Authorized host SSH public key for user: $(whoami)"
else
    echo "[ERROR] Key file not found: $PUB_KEY_FILE"
    exit 1
fi

# Ensure sshd is running
sudo systemctl enable --now sshd 2>/dev/null || true

# Allow current user passwordless sudo for automation
echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee "/etc/sudoers.d/99-${USER}-nopasswd" >/dev/null
sudo chmod 0440 "/etc/sudoers.d/99-${USER}-nopasswd"

echo "[SUCCESS] SSH and sudo configured! Current IP: $(hostname -I | awk '{print $1}')"
echo "[SUCCESS] User: $(whoami)"
