# franken-llama

Custom llama.cpp Nix flake with native CPU optimizations, llguidance support, HTTPS/WebUI, and multi-GPU backends including dual CUDA+ROCm builds.

## Features

- Native CPU optimization (`-march=native`)
- llguidance integration for structured output
- HTTPS support with embedded Svelte WebUI
- Multiple acceleration backends: CPU, Vulkan, CUDA, ROCm, dual (CUDA+ROCm)
- Dynamic backend loading for multi-GPU systems
- Configurable CUDA/ROCm architecture targets

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

## Maintenance

After updating the llama-cpp input, sync llguidance:

```bash
nix flake lock --update-input llama-cpp
./util/update-llguidance.sh
```
