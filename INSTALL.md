# Complete Installation Guide

This guide covers the full installation of NVIDIA driver 580.105.08 with P2P-enabled open kernel modules on RTX 3090/4090 GPUs.

## Prerequisites

### 1. BIOS Settings

**Required changes:**

| Setting | Value | Notes |
|---------|-------|-------|
| **IOMMU / AMD-Vi / VT-d** | **Disabled** | Critical - blocks P2P if enabled |
| **Above 4G Decoding** | Enabled | Required for large BAR |
| **Resizable BAR** | Enabled | Recommended for performance |
| **ACS (Access Control Services)** | Disabled | If available in BIOS |
| **ARI** | Enabled | Alternative Routing ID |
| **SR-IOV** | Disabled | Not needed |

### 2. Kernel Headers

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install build-essential linux-headers-$(uname -r)

# Fedora/RHEL
sudo dnf install kernel-devel kernel-headers gcc make
```

### 3. Blacklist Nouveau

```bash
# Create blacklist file
sudo tee /etc/modprobe.d/blacklist-nouveau.conf << 'EOF'
blacklist nouveau
options nouveau modeset=0
EOF

# Rebuild initramfs
sudo update-initramfs -u   # Ubuntu/Debian
# sudo dracut --force       # Fedora/RHEL

# Reboot
sudo reboot
```

## Installation Steps

### Step 1: Download NVIDIA Driver

Download the 580.105.08 driver from NVIDIA:

```bash
cd /home/server
wget https://us.download.nvidia.com/XFree86/Linux-x86_64/580.105.08/NVIDIA-Linux-x86_64-580.105.08.run
chmod +x NVIDIA-Linux-x86_64-580.105.08.run
```

Or from NVIDIA's datacenter driver page if using datacenter drivers.

### Step 2: Install NVIDIA Driver WITHOUT Kernel Modules

This installs the userspace components (nvidia-smi, CUDA libraries, etc.) but skips the kernel modules - we'll use our patched ones instead.

```bash
# Stop display manager if running
sudo systemctl stop gdm      # GNOME
sudo systemctl stop sddm     # KDE
sudo systemctl stop lightdm  # Others

# Remove old NVIDIA drivers (if any)
sudo apt remove --purge nvidia-* libnvidia-*  # Ubuntu
# Or if previously installed via .run:
sudo ./NVIDIA-Linux-x86_64-*.run --uninstall

# Install driver WITHOUT kernel modules
sudo ./NVIDIA-Linux-x86_64-580.105.08.run \
    --no-kernel-modules \
    --silent \
    --accept-license \
    --no-x-check \
    --no-cc-version-check \
    --disable-nouveau
```

**Flags explained:**
- `--no-kernel-modules`: Skip kernel module installation (we use patched ones)
- `--silent`: Non-interactive, no prompts
- `--accept-license`: Auto-accept NVIDIA license
- `--no-x-check`: Don't abort if X server is running
- `--no-cc-version-check`: Skip GCC version warning (useful for newer kernels)
- `--disable-nouveau`: Blacklist nouveau driver

### Step 3: Clone and Build Patched Kernel Modules

```bash
# Clone this repo (with P2P patches already applied)
git clone --branch 580.105.08-p2p \
    https://github.com/guru1987/open-gpu-kernel-modules.git
cd open-gpu-kernel-modules

# Build
make modules -j$(nproc)

# Install
sudo make modules_install
sudo depmod -a
```

### Step 4: Load Modules and Verify

```bash
# Load modules
sudo modprobe nvidia
sudo modprobe nvidia_uvm
sudo modprobe nvidia_modeset
sudo modprobe nvidia_drm

# Start persistence daemon
sudo systemctl start nvidia-persistenced

# Verify GPUs are detected
nvidia-smi
```

### Step 5: Verify P2P is Working

```bash
# Quick check
python3 -c "import torch; print('P2P 0->1:', torch.cuda.can_device_access_peer(0, 1))"

# Full matrix
nvidia-smi topo -p2p r
nvidia-smi topo -p2p w
```

Expected output: All GPU pairs show `OK` for both read and write.

## GRUB Configuration (Optional but Recommended)

Add these parameters to `/etc/default/grub`:

```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash pci=realloc pci=hpmmioprefsize=128G nvidia.NVreg_OpenRmEnableUnsupportedGpus=1 nvidia.NVReg_EnableResizableBar=1"
```

Then update GRUB:
```bash
sudo update-grub  # Ubuntu/Debian
# sudo grub2-mkconfig -o /boot/grub2/grub.cfg  # Fedora/RHEL
```

**Parameters explained:**
- `pci=realloc`: Allow kernel to reallocate PCI resources
- `pci=hpmmioprefsize=128G`: Reserve space for large BARs
- `nvidia.NVreg_OpenRmEnableUnsupportedGpus=1`: Enable open modules on consumer GPUs
- `nvidia.NVReg_EnableResizableBar=1`: Enable Resizable BAR support

## Persist Across Reboots

The modules will load automatically on reboot. To ensure nvidia-persistenced starts:

```bash
sudo systemctl enable nvidia-persistenced
```

## Updating to New Driver Versions

When NVIDIA releases a new driver:

1. Check if this repo has a matching branch (e.g., `580.115.00-p2p`)
2. If not, the patch may need updating for new driver version
3. Install new driver with `--no-kernel-modules`
4. Build and install updated patched modules

## Troubleshooting

### P2P still shows disabled

1. **Check IOMMU:**
   ```bash
   dmesg | grep -i iommu
   ```
   Should NOT show "Translated" mode.

2. **Check ACS:**
   ```bash
   sudo setpci -s 01:00.0 ECAP_ACS+6.w
   ```
   Should return `0000`.

3. **Verify patched module loaded:**
   ```bash
   modinfo nvidia | grep version
   ```
   Should show `580.105.08`.

### Module won't load

```bash
# Check for errors
sudo dmesg | tail -50

# Verify module is signed (if secure boot enabled)
modinfo nvidia | grep sig
```

### nvidia-smi not found

The userspace tools weren't installed. Re-run driver installer:
```bash
sudo ./NVIDIA-Linux-x86_64-580.105.08.run --no-kernel-modules
```

## Uninstallation

```bash
# Remove patched modules
sudo rm -rf /lib/modules/$(uname -r)/kernel/drivers/video/nvidia*.ko
sudo depmod -a

# Remove NVIDIA driver
sudo ./NVIDIA-Linux-x86_64-580.105.08.run --uninstall

# Or if installed via apt
sudo apt remove --purge nvidia-*
```
