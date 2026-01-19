# Enabling PCIe P2P (Peer-to-Peer) on NVIDIA RTX 3090 with Driver 580.x

This guide documents how to enable GPU-to-GPU P2P memory transfers on consumer NVIDIA GPUs (RTX 3090) using NVIDIA's open-source kernel modules with minimal patches.

## Background

NVIDIA artificially disables P2P on consumer GPUs (GeForce series), reserving this feature for datacenter GPUs (A100, H100, etc.). However, the hardware fully supports it. This guide patches the open-source NVIDIA kernel modules to enable BAR1 P2P transfers.

**Based on:** [tinygrad/open-gpu-kernel-modules](https://github.com/tinygrad/open-gpu-kernel-modules) P2P patches, ported to driver version 580.105.08.

## Test System

- **CPU:** AMD EPYC (48 cores)
- **GPUs:** 8x NVIDIA GeForce RTX 3090 (24GB each)
- **Topology:** 4 PCIe switches (Microsemi/Switchtec), 2 GPUs per switch
- **Driver:** NVIDIA 580.105.08 (open kernel modules)
- **Kernel:** Linux 6.14.0-33-generic
- **OS:** Ubuntu

## Prerequisites

### BIOS Settings

| Setting | Value | Notes |
|---------|-------|-------|
| **IOMMU / AMD-Vi / Intel VT-d** | **Disabled** | Critical - blocks P2P if enabled |
| **Above 4G Decoding** | Enabled | Required for large BAR |
| **Resizable BAR** | Enabled | Recommended |
| **ACS (Access Control Services)** | Disabled | If available; blocks P2P routing |
| **ARI (Alternative Routing ID)** | Enabled | Helps with device enumeration |
| **SR-IOV** | Disabled | Not needed, can interfere |
| **PCIe Link Speed** | Auto/Gen4 | For best bandwidth |

### Kernel Boot Parameters

Your `/etc/default/grub` should have (adjust to your setup):

```bash
GRUB_CMDLINE_LINUX_DEFAULT="pci=realloc pci=hpmmioprefsize=128G nvidia.NVreg_OpenRmEnableUnsupportedGpus=1 nvidia.NVReg_EnableResizableBar=1"
```

Optional if BIOS ACS disable doesn't work:
```bash
pcie_acs_override=downstream,multifunction
```

Run `sudo update-grub` after changes.

## Patch Instructions

### 1. Clone NVIDIA Open Kernel Modules

```bash
cd /home/server
git clone --depth 1 --branch 580.105.08 https://github.com/NVIDIA/open-gpu-kernel-modules.git nvidia-open-580.105.08
cd nvidia-open-580.105.08
```

### 2. Apply P2P Patches

Three files need to be modified:

#### File 1: `src/nvidia/src/kernel/gpu/bif/kernel_bif.c`

Find the `kbifInit` function (around line 755) and change:

```c
// BEFORE:
pKernelBif->p2pOverride = BIF_P2P_NOT_OVERRIDEN;

// AFTER:
pKernelBif->p2pOverride = 0x11;  // Enable P2P read + write
```

```c
// BEFORE:
pKernelBif->forceP2PType = NV_REG_STR_RM_FORCE_P2P_TYPE_DEFAULT;

// AFTER:
pKernelBif->forceP2PType = NV_REG_STR_RM_FORCE_P2P_TYPE_PCIEP2P;  // Force PCIe P2P
```

```c
// BEFORE:
pKernelBif->pcieP2PType = NV_REG_STR_RM_PCIEP2P_TYPE_DEFAULT;

// AFTER:
pKernelBif->pcieP2PType = NV_REG_STR_RM_PCIEP2P_TYPE_BAR1;  // Use BAR1 P2P
```

#### File 2: `src/nvidia/generated/g_kern_bus_nvoc.c`

Find the following 5 function pointer assignments and change them to always use GH100 implementations:

```c
// Change these assignments (around lines 1047-1140):

// kbusGetBar1P2PDmaInfo
pThis->__kbusGetBar1P2PDmaInfo__ = &kbusGetBar1P2PDmaInfo_GH100;

// kbusCreateP2PMappingForBar1P2P
pThis->__kbusCreateP2PMappingForBar1P2P__ = &kbusCreateP2PMappingForBar1P2P_GH100;

// kbusRemoveP2PMappingForBar1P2P
pThis->__kbusRemoveP2PMappingForBar1P2P__ = &kbusRemoveP2PMappingForBar1P2P_GH100;

// kbusHasPcieBar1P2PMapping
pThis->__kbusHasPcieBar1P2PMapping__ = &kbusHasPcieBar1P2PMapping_GH100;

// kbusIsPcieBar1P2PMappingSupported
pThis->__kbusIsPcieBar1P2PMappingSupported__ = &kbusIsPcieBar1P2PMappingSupported_GH100;
```

Remove the conditional `if` statements and always assign the `_GH100` versions.

#### File 3: `src/nvidia/src/kernel/gpu/bus/arch/pascal/kern_bus_gp100.c`

Add BAR1 P2P connection type handling in two functions:

In `kbusCreateP2PMapping_GP100` (around line 68), add:

```c
// After the _PCIE check, add:
if (FLD_TEST_DRF(_P2PAPI, _ATTRIBUTES, _CONNECTION_TYPE, _PCIE_BAR1, attributes))
{
    return kbusCreateP2PMappingForBar1P2P_HAL(pGpu0, pKernelBus0, pGpu1, pKernelBus1, attributes);
}
```

In `kbusRemoveP2PMapping_GP100` (around line 635), add:

```c
// After the _PCIE check, add:
if (FLD_TEST_DRF(_P2PAPI, _ATTRIBUTES, _CONNECTION_TYPE, _PCIE_BAR1, attributes))
{
    return kbusRemoveP2PMappingForBar1P2P_HAL(pGpu0, pKernelBus0, pGpu1, pKernelBus1, attributes);
}
```

### 3. Build and Install

```bash
# Unload existing modules (stop any GPU processes first)
sudo systemctl stop nvidia-persistenced
sudo rmmod nvidia_uvm nvidia_drm nvidia_modeset nvidia

# Build
make modules -j$(nproc)

# Install
sudo make modules_install
sudo depmod -a

# Load new modules
sudo modprobe nvidia
sudo modprobe nvidia_uvm
sudo systemctl start nvidia-persistenced
```

### 4. Verify P2P is Working

```bash
# Quick test
python3 -c "import torch; print('P2P 0->1:', torch.cuda.can_device_access_peer(0, 1))"

# Full matrix
nvidia-smi topo -p2p r
nvidia-smi topo -p2p w
```

Expected output: All GPU pairs show `OK` for both read and write.

## Benchmark Results

Tested with NVIDIA CUDA Samples `p2pBandwidthLatencyTest`:

### Bandwidth (GB/s)

| Mode | P2P Disabled | P2P Enabled | Improvement |
|------|--------------|-------------|-------------|
| Unidirectional | ~10 GB/s | ~26 GB/s | **2.6x** |
| Bidirectional | ~4-15 GB/s | ~50-52 GB/s | **3-13x** |

### Latency (microseconds)

| Mode | P2P Disabled | P2P Enabled | Improvement |
|------|--------------|-------------|-------------|
| GPU-to-GPU | 13-20 μs | 1.4-1.7 μs | **10-14x faster** |

### Full P2P Connectivity Matrix

```
P2P Connectivity Matrix (1 = P2P enabled)
     D\D     0     1     2     3     4     5     6     7
     0       1     1     1     1     1     1     1     1
     1       1     1     1     1     1     1     1     1
     2       1     1     1     1     1     1     1     1
     3       1     1     1     1     1     1     1     1
     4       1     1     1     1     1     1     1     1
     5       1     1     1     1     1     1     1     1
     6       1     1     1     1     1     1     1     1
     7       1     1     1     1     1     1     1     1
```

### Unidirectional P2P=Enabled Bandwidth Matrix (GB/s)

```
   D\D     0      1      2      3      4      5      6      7
     0 832.89  26.40  25.17  26.39  25.75  26.39  25.75  26.39
     1  26.39 835.11  25.33  26.39  25.85  26.39  25.80  26.39
     2  25.80  26.39 835.11  26.40  25.17  26.30  25.86  26.39
     3  25.85  26.39  26.40 833.78  25.14  26.39  25.86  26.39
     4  25.82  26.39  25.77  26.39 836.90  26.40  25.54  26.39
     5  25.99  26.39  25.90  26.39  26.40 836.01  25.32  26.39
     6  25.86  26.39  25.79  26.39  25.77  26.39 836.01  26.40
     7  25.10  26.39  25.73  26.39  25.80  26.39  26.40 835.56
```

### Bidirectional P2P=Enabled Bandwidth Matrix (GB/s)

```
   D\D     0      1      2      3      4      5      6      7
     0 839.15  51.98  50.43  51.18  50.29  51.20  50.21  51.21
     1  51.98 838.93  49.54  51.21  50.28  51.20  50.08  51.21
     2  50.49  51.20 839.15  51.99  49.63  51.21  50.30  51.21
     3  50.11  51.22  51.98 838.70  49.90  51.21  50.50  51.21
     4  50.21  51.22  50.64  51.21 838.48  51.99  49.59  51.22
     5  50.37  51.22  50.18  51.23  51.98 839.60  49.92  51.21
     6  50.53  51.22  50.15  51.21  50.23  51.21 839.60  51.99
     7  49.48  51.22  50.36  51.21  50.19  51.22  51.98 838.25
```

### P2P=Enabled Latency Matrix (μs)

```
   GPU     0      1      2      3      4      5      6      7
     0   1.68   1.50   1.66   1.70   1.66   1.66   1.72   1.72
     1   1.48   1.56   1.61   1.59   1.64   1.66   1.63   1.63
     2   1.54   1.57   1.57   1.41   1.65   1.56   1.54   1.56
     3   1.60   1.59   1.38   1.58   1.61   1.64   1.60   1.63
     4   1.68   1.66   1.67   1.68   1.52   1.50   1.66   1.67
     5   1.71   1.74   1.72   1.70   1.45   1.59   1.65   1.65
     6   1.59   1.63   1.56   1.59   1.61   1.59   1.55   1.40
     7   1.64   1.63   1.62   1.62   1.63   1.66   1.48   1.54
```

## Troubleshooting

### P2P still shows as disabled

1. **Check IOMMU:** `dmesg | grep -i iommu` - should not show "Translated" mode
2. **Check ACS:** `sudo setpci -s <switch_bdf> ECAP_ACS+6.w` - should be `0000`
3. **Verify module loaded:** `modinfo nvidia | grep version` - should match patched version

### Build errors

- Ensure kernel headers match running kernel: `apt install linux-headers-$(uname -r)`
- Clean and rebuild: `make clean && make modules -j$(nproc)`

### Module won't unload

```bash
sudo systemctl stop nvidia-persistenced
sudo fuser -v /dev/nvidia*  # Shows processes using GPU
# Kill those processes, then retry rmmod
```

## Technical Details

### What the patches do

1. **`p2pOverride = 0x11`**: Sets bits for P2P read (0x01) and write (0x10) enable
2. **`forceP2PType = PCIEP2P`**: Forces PCIe-based P2P instead of default
3. **`pcieP2PType = BAR1`**: Uses BAR1 memory mapping for P2P (instead of mailbox)
4. **GH100 function pointers**: Uses Hopper-class BAR1 P2P implementations which are fully functional, instead of stub functions that return "not supported"
5. **Connection type handlers**: Routes `_PCIE_BAR1` connection requests to the correct HAL functions

### Why this works

NVIDIA's open kernel modules contain full P2P implementation (used on datacenter GPUs like H100). Consumer GPUs are blocked by:
- Default registry values that disable P2P
- Function pointer tables that route to stub functions
- Missing connection type handlers

The patches bypass these artificial restrictions by:
- Setting registry defaults to enable P2P
- Routing to working implementations (GH100)
- Adding the missing connection type handlers

## Credits

- [tinygrad](https://github.com/tinygrad/open-gpu-kernel-modules) - Original P2P patches for 570.x
- [geohot](https://github.com/geohot) - Initial P2P mod research
- NVIDIA - For open-sourcing the kernel modules

## Disclaimer

This modification is for educational and research purposes. Use at your own risk. This may void warranties and is not supported by NVIDIA.

## License

Patches are provided under the same license as NVIDIA's open-gpu-kernel-modules (MIT/GPL dual license).
