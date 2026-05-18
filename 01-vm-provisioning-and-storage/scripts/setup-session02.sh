#!/bin/bash
# CIS 395 Session 2 Setup Script
# Verifies virtualization features and environment readiness

set -e

SSH_PORT="${SSH_PORT:-2222}"
VM_USER="${VM_USER:-student}"

echo "=== CIS 395 Session 2 Verification ==="
echo ""
echo "This script verifies your CIS 395 VM has virtualization tools installed."
echo ""

# Check if VM is running
echo "[INFO] Checking if VM is running..."
if ! ssh -p "$SSH_PORT" -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$VM_USER@localhost" "echo connected" &>/dev/null; then
    echo "[ERROR] Cannot connect to VM on port $SSH_PORT"
    echo ""
    echo "Make sure the VM is running:"
    echo "  ./provision.sh start cis395-vm"
    echo ""
    echo "Then run this script again."
    exit 1
fi

echo "[OK] VM is running and accessible"
echo ""

# Verify virtualization configuration
echo "[INFO] Verifying virtualization environment..."
ssh -p "$SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$VM_USER@localhost" << 'REMOTE_SCRIPT'

echo "=== Virtualization Features ==="
echo ""

# Check CPU virtualization flags
echo "Checking CPU virtualization support..."
if grep -qE 'vmx|svm' /proc/cpuinfo; then
    echo "[OK] CPU supports hardware virtualization"
    grep -m1 -E 'vmx|svm' /proc/cpuinfo | cut -d: -f1
else
    echo "[INFO] CPU does not show vmx/svm flags"
    echo "      This is normal if running inside a VM without nested virtualization"
    echo "      Your environment is using TCG emulation mode"
fi
echo ""

# Check Docker
echo "Checking Docker installation..."
if command -v docker &>/dev/null; then
    echo "[OK] Docker installed: $(docker --version)"
    if service docker status &>/dev/null; then
        echo "[OK] Docker service is running"
    else
        echo "[WARN] Docker installed but service not running"
        echo "       Starting Docker service..."
        sudo service docker start
    fi
else
    echo "[ERROR] Docker not installed"
    echo "        Run: sudo apk add docker docker-compose"
fi
echo ""

# Check containerd
echo "Checking containerd installation..."
if command -v containerd &>/dev/null; then
    echo "[OK] containerd installed: $(containerd --version | head -1)"
    if service containerd status &>/dev/null; then
        echo "[OK] containerd service is running"
    else
        echo "[WARN] containerd installed but service not running"
        echo "       Starting containerd service..."
        sudo service containerd start
    fi
else
    echo "[ERROR] containerd not installed"
    echo "        Run: sudo apk add containerd"
fi
echo ""

# Check k3s
echo "Checking Kubernetes (k3s) installation..."
if command -v k3s &>/dev/null; then
    echo "[OK] k3s installed: $(k3s --version 2>/dev/null | head -1)"
    echo "[INFO] k3s starts on-demand to conserve resources"
    echo "       To start: sudo service k3s start"
else
    echo "[WARN] k3s not installed"
    echo "       Install if needed: sudo apk add k3s"
fi
echo ""

# Check system utilities
echo "Checking system utilities..."
MISSING=""
for cmd in lscpu dmidecode qemu-img strace tmux; do
    if ! command -v $cmd &>/dev/null; then
        MISSING="$MISSING $cmd"
    fi
done

if [ -n "$MISSING" ]; then
    echo "[WARN] Missing utilities:$MISSING"
    echo "Installing missing packages..."
    sudo apk add --no-cache $MISSING
else
    echo "[OK] All required utilities installed"
fi
echo ""

# Git configuration check
echo "Checking git configuration..."
if [ -z "$(git config --global user.name)" ]; then
    echo "[INFO] Git user.name not set"
    echo "       Run: git config --global user.name \"Your Name\""
else
    echo "[OK] Git user.name: $(git config --global user.name)"
fi

if [ -z "$(git config --global user.email)" ]; then
    echo "[INFO] Git user.email not set"
    echo "       Run: git config --global user.email \"your.email@student.ufv.ca\""
else
    echo "[OK] Git user.email: $(git config --global user.email)"
fi
echo ""

echo "=== Session 2 Verification Complete ==="
echo ""
echo "Your environment is ready for Assignment 1!"
echo ""
echo "Next steps:"
echo "  1. Complete Week 2 activity if not done"
echo "  2. Review Session 2 slides on hypervisor architecture"
echo "  3. Start Assignment 1: VM creation and performance benchmarking"
echo ""

REMOTE_SCRIPT

echo ""
echo "[OK] Session 2 setup verification complete!"
