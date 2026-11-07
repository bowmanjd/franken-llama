# franken-llama

Custom llama.cpp Nix flake with native CPU optimizations, llguidance support, and multi-GPU backends including dual CUDA+ROCm builds.

## Features

- llguidance integration for structured output
- Multiple acceleration backends: CPU, Vulkan, CUDA, ROCm, dual (CUDA+ROCm)
- HTTPS support with embedded Svelte WebUI
- Configurable with parameters

## Usage

### NixOS Module

```nix
# flake.nix
{
  inputs.franken-llama.url = "github:bowmanjd/franken-llama";
  inputs.franken-llama.inputs.nixpkgs.follows = "nixpkgs";
}

# configuration.nix
{
  imports = [ inputs.franken-llama.nixosModules.default ];

  services.franken-llama = {
    enable = true;
    acceleration = "dual";  # cpu, cuda, rocm, vulkan, dual
    nativeCpu = true;
    llguidance = true;
    cudaCapabilities = ["86"];   # RTX 3080 Ti (Ampere)
    rocmTargets = ["gfx906"];    # MI50 (Vega 20)
  };
}
```

### Overlay Only

```nix
{
  nixpkgs.overlays = [
    (inputs.franken-llama.overlays.configure {
      acceleration = "cpu";
      nativeCpu = true;
      llguidance = true;
      https = true;
    })
  ];
}
```

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `acceleration` | enum | `"cpu"` | Backend: `cpu`, `cuda`, `rocm`, `vulkan`, `dual` |
| `flavor` | enum | `"upstream"` | Source for `llama-cpp`: `upstream` (ggml-org) or `mx` (mx-llama.cpp fork) |
| `nativeCpu` | bool | `true` | Optimize for host CPU instruction set |
| `llguidance` | bool | `false` | Enable llguidance structured output |
| `https` | bool | `true` | HTTPS support + embedded WebUI |
| `cudaCapabilities` | list | `null` | CUDA architectures (e.g., `["86"]` for RTX 3080 Ti) |
| `rocmTargets` | list | `null` | ROCm architectures (e.g., `["gfx906"]` for MI50) |
| `llamaCppTag` | string | `null` | Override llama.cpp version tag |
| `llamaCppHash` | string | `null` | SHA256 hash for custom tag |
| `cudaVersion` | string | `null` | CUDA version (e.g., `"12.9"`) |
| `rocmVersion` | string | `null` | ROCm version (e.g., `"7.2"`) |

## Available Packages

The overlay provides these package variants:

- `llama-cpp` (alias for configured default)
- `llama-cpp-cpu`, `llama-cpp-vulkan`, `llama-cpp-cuda`, `llama-cpp-rocm`, `llama-cpp-dual`
- `*-native` variants with CPU optimization
- `*-llguidance` variants with structured output
- `*-native-llguidance` combined variants
- `*-mx` variants of all of the above, built from the mx-llama.cpp fork (see below)

### Container Packages (x86_64-linux only)

- `*-slim` - Portable packages with Nix store references stripped
- `*-container` - OCI container images
- `*-modal` - Container images with Python/Modal support for modal.com deployment

## Building Containers

Edit `config.json` to set your target GPU and CUDA version:

```json
{
  "cudaVersion": "12.9",
  "cudaCapabilities": ["89"],
  "includeModal": true
}
```

Build and load:

```bash
nix build .#container
podman load < result
```

That's it. The image is tagged automatically (e.g., `ghcr.io/bowmanjd/llama-cpp:b9310-cuda12.9-sm89`).

**Common GPU architectures:**

| GPU | Architecture | Capability/Target |
|-----|--------------|-------------------|
| RTX 3080/3090 | Ampere | `86` |
| RTX 4080/4090 | Ada Lovelace | `89` |
| L40S | Ada Lovelace | `89` |
| H100 | Hopper | `90` |
| A100 | Ampere | `80` |
| MI50/MI60 | Vega 20 (ROCm) | `gfx906` |
| Radeon VII | Vega 20 (ROCm) | `gfx906` |

### Other Container Targets

For quick builds without editing config.json:

```bash
nix build .#llama-cpp-cuda-container        # Default CUDA
nix build .#llama-cpp-rocm-container        # ROCm/AMD
nix build .#llama-cpp-cpu-container         # CPU only
nix build .#llama-cpp-cuda-llguidance-modal # CUDA + llguidance + Modal
```

### Container Configuration (NixOS Module)

```nix
services.franken-llama = {
  enable = true;
  acceleration = "cuda";
  llguidance = true;
  
  container = {
    enable = true;
    imageName = "ghcr.io/yourorg/llama-cpp";
    includeModal = true;  # Include Python for modal.com
  };
};
```

## AMD MI50/MI60 (gfx906) Optimizations

ROCm builds automatically include performance optimizations matching the [ML-gfx906](https://github.com/mixa3607/ML-gfx906) project:

- **HIP Graphs** (`-DGGML_HIP_GRAPHS=ON`): +8-10% generation speed via graph capture
- **Dynamic backends** (`-DGGML_BACKEND_DL=ON`): Runtime backend loading
- **CPU variants** (`-DGGML_CPU_ALL_VARIANTS=ON`): Optimized CPU fallback paths

```nix
services.franken-llama = {
  enable = true;
  acceleration = "rocm";
  rocmTargets = ["gfx906"];
};
```

**Note**: For full gfx906 support with ROCm 6.4+, you may need patched ROCm libraries with gfx906 Tensile files (see [mixa3607/ML-gfx906](https://github.com/mixa3607/ML-gfx906) for container images with these patches)

## mx-llama.cpp fork variants

The `mx-llama-cpp` flake input is [mx-llama.cpp](https://github.com/mxxm-t/mx-llama.cpp), an upstream fork with gfx906 work. Every package is also available with an `-mx` suffix (for example `llama-cpp-dual-native-llguidance-mx`). Set `flavor = "mx"` in the module to make the default `llama-cpp` use it.

What matters for a 3080 Ti + MI50 layer split running Qwen3.5/3.8 (qwen35 arch):

- gfx906 weight repack for Q4_K, Q5_K, Q6_K, Q8_0, IQ4_NL, Q5_1, MXFP4 (MI50 only, on by default, `--no-repack` disables)
- New gated-delta-net kernels, which also run on CUDA, so benchmark both GPUs
- Recurrent snapshot ring for cheap MTP draft rollback, plus `LLAMA_ENABLE_MTP_OPT=1`
- Quantized activation reuse (`GGML_CUDA_Q8_1_CACHE=0` disables)

Measured on that setup (b11757, 2026-11-07): no gain over upstream `v0.9.0`. `smart` generation was 3-4% slower and prefill about 9% slower, repack and `LLAMA_ENABLE_MTP_OPT=1` did not help, and with defaults the q8_1 cache crashes the CUDA backend (`GGML_ASSERT` in `ggml_cuda_q8_1_cache_acquire`), so set `GGML_CUDA_Q8_1_CACHE=0` when a CUDA GPU is involved.

The tensor-parallel features (`-sm tensor`, `-tps`, custom AllReduce) need several same-vendor GPUs and do not apply to a mixed CUDA+ROCm pair. See `FEATURES.md` in the fork for details.

Update the fork by editing the tag in the `mx-llama-cpp` input URL, then:

```bash
nix flake lock --update-input mx-llama-cpp
nix build .#llama-cpp-ui-mx.npmDeps   # if it fails, copy the "got:" hash into mxNpmDepsHash in flake.nix
```

## Maintenance

Update llama.cpp version (fetches latest tag if none provided):

```bash
./util/update-llama-version.sh          # auto-fetch latest
./util/update-llama-version.sh b9310    # use specific tag
nix flake lock --update-input llama-cpp
./util/update-llguidance.sh
```

Can also list available CUDA versions in nixpkgs with `util/list-cuda-versions.sh`
