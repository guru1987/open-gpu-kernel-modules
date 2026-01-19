# P2P Benchmark Results

## Test System

- **CPU:** AMD EPYC (48 cores)
- **Memory:** DDR4
- **GPUs:** 8x NVIDIA GeForce RTX 3090 (24GB GDDR6X each)
- **PCIe Topology:** 4x Microsemi/Switchtec PCIe switches, 2 GPUs per switch
- **Driver:** NVIDIA 580.105.08 (patched open kernel modules)
- **Kernel:** Linux 6.14.0-33-generic

## GPU Topology

```
nvidia-smi topo -m

        GPU0  GPU1  GPU2  GPU3  GPU4  GPU5  GPU6  GPU7
GPU0     X    PIX   NODE  NODE  NODE  NODE  NODE  NODE
GPU1    PIX    X    NODE  NODE  NODE  NODE  NODE  NODE
GPU2   NODE  NODE    X    PIX   NODE  NODE  NODE  NODE
GPU3   NODE  NODE   PIX    X    NODE  NODE  NODE  NODE
GPU4   NODE  NODE  NODE  NODE    X    PIX   NODE  NODE
GPU5   NODE  NODE  NODE  NODE   PIX    X    NODE  NODE
GPU6   NODE  NODE  NODE  NODE  NODE  NODE    X    PIX
GPU7   NODE  NODE  NODE  NODE  NODE  NODE   PIX    X

Legend:
  PIX  = Same PCIe switch (single bridge)
  NODE = Different switches (multiple bridges, same NUMA node)
```

## P2P Connectivity Matrix

After applying patches, all GPU pairs have P2P enabled:

```
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

## Bandwidth Comparison

### Unidirectional Transfer (256 MB)

| Mode | Bandwidth | Notes |
|------|-----------|-------|
| P2P Disabled | ~10 GB/s | Through CPU/system memory |
| P2P Enabled | ~26 GB/s | Direct GPU-to-GPU |
| **Improvement** | **2.6x** | |

### Bidirectional Transfer (256 MB each direction)

| Mode | Bandwidth | Notes |
|------|-----------|-------|
| P2P Disabled | 4-15 GB/s | Highly variable |
| P2P Enabled | 50-52 GB/s | Consistent |
| **Improvement** | **3-13x** | |

## Latency Comparison

| Mode | Latency | Notes |
|------|---------|-------|
| P2P Disabled | 13-20 us | |
| P2P Enabled | 1.4-1.7 us | |
| **Improvement** | **10-14x faster** | |

## Same-Switch vs Cross-Switch Performance

Testing specific GPU pairs to compare same-switch (PIX) vs cross-switch (NODE) performance:

### Same-Switch Pairs (PIX)

| GPU Pair | Bandwidth |
|----------|-----------|
| 0 <-> 1 | 24.54 GB/s |
| 2 <-> 3 | 24.54 GB/s |
| 4 <-> 5 | 24.54 GB/s |
| 6 <-> 7 | 24.54 GB/s |

### Cross-Switch Pairs (NODE)

| GPU Pair | Bandwidth |
|----------|-----------|
| 1 <-> 2 | 24.53 GB/s |
| 3 <-> 4 | 24.53 GB/s |
| 5 <-> 6 | 24.54 GB/s |
| 7 <-> 0 | 24.53 GB/s |

**Conclusion:** BAR1 P2P provides consistent ~24.5 GB/s bandwidth regardless of PCIe topology. The bottleneck is the BAR1 aperture/mapping, not the switch routing.

## Full Bandwidth Matrix (P2P Enabled)

### Unidirectional P2P Writes (GB/s)

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

### Bidirectional (GB/s total)

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

### P2P Latency Matrix (microseconds)

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

## Test Commands

### NVIDIA CUDA Samples

```bash
# Build
git clone https://github.com/NVIDIA/cuda-samples.git
cd cuda-samples/Samples/5_Domain_Specific/p2pBandwidthLatencyTest
nvcc -o p2pBandwidthLatencyTest p2pBandwidthLatencyTest.cu -I../../../Common

# Run
./p2pBandwidthLatencyTest
```

### PyTorch Quick Test

```python
import torch

# Check P2P capability
for i in range(torch.cuda.device_count()):
    for j in range(torch.cuda.device_count()):
        if i != j:
            result = torch.cuda.can_device_access_peer(i, j)
            print(f"GPU {i} -> GPU {j}: {'YES' if result else 'NO'}")
```

### nvidia-smi Topology

```bash
nvidia-smi topo -p2p r  # P2P read capability
nvidia-smi topo -p2p w  # P2P write capability
nvidia-smi topo -m      # Full topology matrix
```
