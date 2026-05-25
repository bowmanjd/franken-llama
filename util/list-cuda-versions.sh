#!/usr/bin/env bash
# List available CUDA versions in nixpkgs and show how to use them with franken-llama

set -euo pipefail

echo "Querying nixpkgs for available CUDA versions..."
echo

# Get the default version first
default_ver=$(nix eval --impure --raw --expr '(import <nixpkgs> {}).cudaPackages.cudaMajorMinorPatchVersion' 2>/dev/null || echo "unknown")

echo "Available CUDA versions:"
echo

# Query each package individually to handle removed versions gracefully
for attr in cudaPackages_12_6 cudaPackages_12_8 cudaPackages_12_9 cudaPackages_13_0 cudaPackages_13_1 cudaPackages_13_2; do
  ver=$(nix eval --impure --raw --expr "(import <nixpkgs> {}).${attr}.cudaMajorMinorPatchVersion" 2>/dev/null || echo "")
  if [[ -n "$ver" ]]; then
    if [[ "$ver" == "$default_ver" ]]; then
      echo "  $attr -> $ver (default)"
    else
      echo "  $attr -> $ver"
    fi
  fi
done

echo
echo "Aliases:"
echo "  cudaPackages    -> $default_ver (default)"
echo "  cudaPackages_12 -> $(nix eval --impure --raw --expr '(import <nixpkgs> {}).cudaPackages_12.cudaMajorMinorPatchVersion' 2>/dev/null || echo 'unknown')"
echo "  cudaPackages_13 -> $(nix eval --impure --raw --expr '(import <nixpkgs> {}).cudaPackages_13.cudaMajorMinorPatchVersion' 2>/dev/null || echo 'unknown')"

cat << 'EOF'

Removed from nixpkgs: 12.0-12.5, 12.7 (deprecated upstream)

Usage in franken-llama:

  1. NixOS module:
     services.franken-llama = {
       enable = true;
       acceleration = "cuda";
       cudaVersion = "12.9";      # or "13.2" for latest
     };

  2. Overlay configuration:
     overlays = [
       (franken-llama.overlays.configure {
         acceleration = "cuda";
         cudaVersion = "13.2";
       })
     ];

  3. Using cudaPkgAttr:
     cudaPkgAttr = "cudaPackages_13_2";

  4. Passing custom cudaPackages:
     cudaPackages = pkgs.cudaPackages_13_2;
EOF
