# NVIDIA Open GPU Kernel Modules - P2P Enabled

P2P on RTX 3090/4090 with the 580.105.08 driver.

## Results

- **Bandwidth**: 10 GB/s → 26 GB/s (2.6x faster)
- **Latency**: 15-20 μs → 1.5 μs (10x faster)

## BIOS Settings

- **IOMMU / AMD-Vi / VT-d**: Disabled
- **Above 4G Decoding**: Enabled
- **Resizable BAR**: Enabled
- **ACS**: Disabled (if available)

## Kernel Parameters

Add to `/etc/default/grub`:
```bash
GRUB_CMDLINE_LINUX_DEFAULT="pci=realloc pci=hpmmioprefsize=128G"
```

Then run:
```bash
sudo update-grub && sudo reboot
```

## Module Configuration

Create `/etc/modprobe.d/nvidia.conf`:
```bash
options nvidia NVreg_OpenRmEnableUnsupportedGpus=1 NVreg_EnableResizableBar=1
```

## Install

```bash
# Download driver
wget https://us.download.nvidia.com/XFree86/Linux-x86_64/580.105.08/NVIDIA-Linux-x86_64-580.105.08.run

# Install NVIDIA driver without kernel modules
sudo sh NVIDIA-Linux-x86_64-580.105.08.run --no-kernel-modules --silent --accept-license

# Build and install P2P-enabled kernel modules
git clone -b 580.105.08-p2p https://github.com/guru1987/open-gpu-kernel-modules
cd open-gpu-kernel-modules
./install.sh
```

## Verify

```bash
nvidia-smi topo -p2p r   # Should show "OK" for all pairs
```

## Credits

- [tinygrad](https://github.com/tinygrad/open-gpu-kernel-modules) - Original P2P research
- [geohot](https://github.com/geohot) - Initial patch concept
- [guru1987](https://github.com/guru1987) - 580.x port, 12x RTX 3090 testing

### Special Thanks

**Claude Opus 4.5 by Anthropic** - Patch development, debugging, and documentation

---

See [INSTALL.md](INSTALL.md) for detailed instructions and [docs/](docs/) for benchmarks.
