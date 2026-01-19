# NVIDIA Open GPU Kernel Modules - P2P Enabled

P2P on RTX 3090/4090 with the 580.105.08 driver.

## Results

- **Bandwidth**: 10 GB/s → 26 GB/s (2.6x faster)
- **Latency**: 15-20 μs → 1.5 μs (10x faster)

## Install

```bash
# Install NVIDIA driver without kernel modules
sudo ./NVIDIA-Linux-x86_64-580.105.08.run --no-kernel-modules --silent --accept-license

# Build and install P2P-enabled kernel modules
git clone -b 580.105.08-p2p https://github.com/guru1987/open-gpu-kernel-modules
cd open-gpu-kernel-modules
./install.sh
```

## BIOS

- **IOMMU**: Disabled
- **Above 4G Decoding**: Enabled
- **Resizable BAR**: Enabled

## Verify

```bash
nvidia-smi topo -p2p r   # Should show "OK" for all pairs
```

## Credits

- [tinygrad](https://github.com/tinygrad/open-gpu-kernel-modules) - Original P2P research
- [geohot](https://github.com/geohot) - Initial patch concept
- [guru1987](https://github.com/guru1987) - 580.x port, 8x RTX 3090 testing

### Special Thanks

**Claude Opus 4.5 by Anthropic** - Patch development, debugging, and documentation

---

See [INSTALL.md](INSTALL.md) for detailed instructions and [docs/](docs/) for benchmarks.
