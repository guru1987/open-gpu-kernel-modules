# NVIDIA Open GPU Kernel Modules - P2P Enabled

Fork of [NVIDIA/open-gpu-kernel-modules](https://github.com/NVIDIA/open-gpu-kernel-modules) with patches to enable PCIe BAR1 P2P (Peer-to-Peer) memory transfers on consumer GPUs (RTX 3090, RTX 4090, etc.).

## What This Does

Enables direct GPU-to-GPU memory transfers without going through system RAM:

| Metric | Without P2P | With P2P | Improvement |
|--------|-------------|----------|-------------|
| Bandwidth (unidirectional) | ~10 GB/s | ~26 GB/s | **2.6x** |
| Bandwidth (bidirectional) | ~15 GB/s | ~52 GB/s | **3.5x** |
| Latency | 15-20 μs | 1.5 μs | **10-14x** |

## Quick Start

### 1. Install NVIDIA Driver (userspace only)

```bash
# Download driver
wget https://us.download.nvidia.com/XFree86/Linux-x86_64/580.105.08/NVIDIA-Linux-x86_64-580.105.08.run
chmod +x NVIDIA-Linux-x86_64-580.105.08.run

# Install WITHOUT kernel modules
sudo ./NVIDIA-Linux-x86_64-580.105.08.run \
    --no-kernel-modules \
    --silent \
    --accept-license \
    --no-x-check \
    --no-cc-version-check
```

### 2. Build & Install P2P Kernel Modules

```bash
git clone --branch 580.105.08-p2p \
    https://github.com/YOUR_USERNAME/open-gpu-kernel-modules.git
cd open-gpu-kernel-modules
./install.sh
```

### 3. Verify P2P Works

```bash
nvidia-smi topo -p2p r
# All pairs should show "OK"

python3 -c "import torch; print('P2P:', torch.cuda.can_device_access_peer(0, 1))"
# Should print: P2P: True
```

## BIOS Requirements

| Setting | Value |
|---------|-------|
| **IOMMU / AMD-Vi / VT-d** | **Disabled** |
| Above 4G Decoding | Enabled |
| Resizable BAR | Enabled |
| ACS | Disabled (if available) |

## Kernel Boot Parameters

Add to `/etc/default/grub`:

```
GRUB_CMDLINE_LINUX_DEFAULT="pci=realloc pci=hpmmioprefsize=128G nvidia.NVreg_OpenRmEnableUnsupportedGpus=1"
```

Then run `sudo update-grub` and reboot.

## Tested Configurations

| Driver | GPU | Status |
|--------|-----|--------|
| 580.105.08 | RTX 3090 (8x) | ✅ Working |
| 580.105.08 | RTX 4090 | Should work (untested) |

## What's Changed

Three files patched from upstream NVIDIA:

1. **`src/nvidia/src/kernel/gpu/bif/kernel_bif.c`**
   - `p2pOverride = 0x11` (enable P2P read/write)
   - `forceP2PType = PCIEP2P`
   - `pcieP2PType = BAR1`

2. **`src/nvidia/generated/g_kern_bus_nvoc.c`**
   - Route BAR1 P2P functions to GH100 implementations

3. **`src/nvidia/src/kernel/gpu/bus/arch/pascal/kern_bus_gp100.c`**
   - Add `_PCIE_BAR1` connection type handlers

## Benchmark Results

Tested on 8x RTX 3090 with 4 PCIe switches:

```
Unidirectional P2P Bandwidth (GB/s):
   GPU     0      1      2      3      4      5      6      7
     0     -   26.40  25.17  26.39  25.75  26.39  25.75  26.39
     1  26.39     -   25.33  26.39  25.85  26.39  25.80  26.39
     ...

Bidirectional P2P Bandwidth (GB/s):
   GPU     0      1      2      3      4      5      6      7
     0     -   51.98  50.43  51.18  50.29  51.20  50.21  51.21
     ...

P2P Latency (μs):
   GPU     0      1      2      3      4      5      6      7
     0  1.68   1.50   1.66   1.70   1.66   1.66   1.72   1.72
     ...
```

## Credits

- [tinygrad](https://github.com/tinygrad/open-gpu-kernel-modules) - Original P2P research
- [geohot](https://github.com/geohot) - Initial patch concept

## License

Same as upstream: MIT/GPL dual license

## Disclaimer

For research and educational purposes. Not supported by NVIDIA. Use at your own risk.
