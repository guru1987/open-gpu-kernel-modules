#!/bin/bash
#
# P2P-Enabled NVIDIA Open Kernel Modules Installer
# For RTX 3090/4090 with driver 580.105.08
#
set -e

echo "============================================================"
echo "  NVIDIA Open Kernel Modules - P2P Enabled"
echo "  Driver: 580.105.08"
echo "============================================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if we're in the right directory
if [ ! -f "Makefile" ] || [ ! -d "src/nvidia" ]; then
    echo -e "${RED}Error: Run this script from the open-gpu-kernel-modules directory${NC}"
    exit 1
fi

# Check for kernel headers
if [ ! -d "/lib/modules/$(uname -r)/build" ]; then
    echo -e "${RED}Error: Kernel headers not found. Install them first:${NC}"
    echo "  Ubuntu/Debian: sudo apt install linux-headers-\$(uname -r)"
    echo "  Fedora/RHEL:   sudo dnf install kernel-devel"
    exit 1
fi

# Check for root/sudo
if [ "$EUID" -ne 0 ]; then
    SUDO="sudo"
    echo -e "${YELLOW}Note: Will use sudo for installation steps${NC}"
else
    SUDO=""
fi

echo ""
echo "[1/6] Checking for running NVIDIA processes..."
if lsmod | grep -q nvidia; then
    echo "  Stopping nvidia-persistenced..."
    $SUDO systemctl stop nvidia-persistenced 2>/dev/null || true
    sleep 1

    echo "  Unloading NVIDIA modules..."
    $SUDO rmmod nvidia_uvm 2>/dev/null || true
    $SUDO rmmod nvidia_drm 2>/dev/null || true
    $SUDO rmmod nvidia_modeset 2>/dev/null || true
    $SUDO rmmod nvidia 2>/dev/null || true
    sleep 1

    # Check if unload was successful
    if lsmod | grep -q "^nvidia "; then
        echo -e "${RED}Error: Could not unload NVIDIA modules.${NC}"
        echo "  Check what's using them: sudo lsof /dev/nvidia*"
        exit 1
    fi
fi
echo -e "  ${GREEN}Done${NC}"

echo ""
echo "[2/6] Building kernel modules..."
echo "  This may take 2-5 minutes..."
make modules -j$(nproc) 2>&1 | tee /tmp/nvidia-build.log | tail -5
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo -e "${RED}Build failed! Check /tmp/nvidia-build.log for details${NC}"
    exit 1
fi
echo -e "  ${GREEN}Build complete${NC}"

echo ""
echo "[3/6] Installing kernel modules..."
$SUDO make modules_install 2>&1 | tail -3
echo -e "  ${GREEN}Modules installed${NC}"

echo ""
echo "[4/6] Updating module dependencies..."
$SUDO depmod -a
echo -e "  ${GREEN}Done${NC}"

echo ""
echo "[5/6] Loading NVIDIA modules..."
$SUDO modprobe nvidia
$SUDO modprobe nvidia_uvm
$SUDO modprobe nvidia_modeset
$SUDO modprobe nvidia_drm 2>/dev/null || true
echo -e "  ${GREEN}Modules loaded${NC}"

echo ""
echo "[6/6] Starting nvidia-persistenced..."
$SUDO systemctl start nvidia-persistenced 2>/dev/null || true
echo -e "  ${GREEN}Done${NC}"

echo ""
echo "============================================================"
echo -e "  ${GREEN}Installation Complete!${NC}"
echo "============================================================"
echo ""

# Show GPUs
if command -v nvidia-smi &> /dev/null; then
    echo "Detected GPUs:"
    nvidia-smi -L
    echo ""

    # Test P2P
    echo "Testing P2P access..."
    if command -v python3 &> /dev/null; then
        python3 -c "
import sys
try:
    import torch
    n = torch.cuda.device_count()
    if n >= 2:
        p2p = torch.cuda.can_device_access_peer(0, 1)
        print(f'  P2P GPU 0 <-> GPU 1: {\"YES\" if p2p else \"NO\"}')
        if p2p:
            print('  \033[0;32mP2P is working!\033[0m')
        else:
            print('  \033[0;31mP2P not enabled - check BIOS settings\033[0m')
    else:
        print(f'  Only {n} GPU(s) detected, need 2+ for P2P')
except ImportError:
    print('  (Install PyTorch to test P2P: pip install torch)')
" 2>/dev/null || echo "  (Python test skipped)"
    fi

    echo ""
    echo "Run 'nvidia-smi topo -p2p r' for full P2P matrix"
else
    echo -e "${YELLOW}nvidia-smi not found - install NVIDIA driver userspace components:${NC}"
    echo "  ./NVIDIA-Linux-x86_64-580.105.08.run --no-kernel-modules"
fi
