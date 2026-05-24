{
  description = "Franken-llama: Custom llama.cpp package variants with native CPU optimizations, llguidance, and HTTPS/UI support";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    llama-cpp = {
      url = "github:ggml-org/llama.cpp/b9254";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, llama-cpp }@inputs:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      # Expose overlays (default and configurable)
      overlays = {
        # Default overlay (non-parameterized)
        default = final: prev:
          let
            # Apply the upstream official overlay once
            upstream = llama-cpp.overlays.default final prev;

            # Pass llamaPackages to avoid redundant overlay evaluation
            customOverlay = import ./llama-cpp-overlay.nix {
              inputs = inputs // { llama-cpp = llama-cpp; };
              lib = nixpkgs.lib;
              config = {};
              llamaPackages = upstream.llamaPackages;
            };

            customPackages = customOverlay final prev;
          in
          upstream // customPackages;

        # Configurable overlay creator
        configure = configAttrs: final: prev:
          let
            upstream = llama-cpp.overlays.default final prev;

            # Pass llamaPackages to avoid redundant overlay evaluation
            customOverlay = import ./llama-cpp-overlay.nix {
              inputs = inputs // { llama-cpp = llama-cpp; };
              lib = nixpkgs.lib;
              config = configAttrs;
              llamaPackages = upstream.llamaPackages;
            };

            customPackages = customOverlay final prev;
          in
          upstream // customPackages;
      };

      # Declarative NixOS module for easy multi-machine configuration
      nixosModules.default = { config, lib, pkgs, ... }:
        let
          cfg = config.services.franken-llama;
        in
        {
          options.services.franken-llama = {
            enable = lib.mkEnableOption "franken-llama custom LLM inference overlay and configuration";

            acceleration = lib.mkOption {
              type = lib.types.enum [ "cpu" "cuda" "rocm" "vulkan" "dual" ];
              default = "cpu";
              description = "Hardware acceleration backend for llama.cpp. Use 'dual' for combined CUDA + ROCm with dynamic backend loading.";
            };

            nativeCpu = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Optimize compilation for the host's native CPU instruction set.";
            };

            llguidance = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Include llguidance Rust package integration.";
            };

            https = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable HTTPS support and embed Svelte WebUI built from source.";
            };

            cudaPackages = lib.mkOption {
              type = lib.types.nullOr lib.types.attrs;
              default = null;
              description = "Custom cudaPackages attribute set to override CUDA dependencies.";
            };

            cudaCapabilities = lib.mkOption {
              type = lib.types.nullOr (lib.types.listOf lib.types.str);
              default = null;
              description = "List of CUDA compute capabilities to compile for.";
            };

            rocmPackages = lib.mkOption {
              type = lib.types.nullOr lib.types.attrs;
              default = null;
              description = "Custom rocmPackages attribute set to override ROCm dependencies.";
            };

            rocmTargets = lib.mkOption {
              type = lib.types.nullOr (lib.types.listOf lib.types.str);
              default = null;
              description = "List of ROCm architectures to compile for.";
            };

            llamaCppTag = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = "b9305";
              description = "Overridden Git tag/revision of llama.cpp to compile.";
            };

            llamaCppHash = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = "sha256-TsleTV12rW+35OvHxkWJo42Lhp6FkSyozxiK71yjfRg=";
              description = "Nix SHA256 hash for the overridden llamaCppTag.";
            };

            llamaCppSrc = lib.mkOption {
              type = lib.types.nullOr lib.types.package;
              default = null;
              description = "Custom pre-fetched source package to compile llama.cpp from.";
            };

            cudaVersion = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Major and minor version of CUDA to target (e.g. '12.4' or '13.0').";
            };

            cudaPkgAttr = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Specific cudaPackages attribute name to pull from nixpkgs (e.g. 'cudaPackages_12_4').";
            };

            rocmVersion = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Major and minor version of ROCm to target (e.g. '6.0').";
            };

            rocmPkgAttr = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Specific rocmPackages attribute name to pull from nixpkgs (e.g. 'rocmPackages_6').";
            };
          };

          config = lib.mkIf cfg.enable {
            nixpkgs.overlays = [
              (self.overlays.configure {
                inherit (cfg)
                  acceleration
                  nativeCpu
                  llguidance
                  https
                  cudaPackages
                  cudaCapabilities
                  rocmPackages
                  rocmTargets
                  llamaCppTag
                  llamaCppHash
                  llamaCppSrc
                  cudaVersion
                  cudaPkgAttr
                  rocmVersion
                  rocmPkgAttr;
              })
            ];
          };
        };

      # Expose individual packages directly for building and caching
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = [
              self.overlays.default
            ];
          };
        in
        {
          inherit (pkgs)
            llama-cpp-cpu
            llama-cpp-vulkan
            llama-cpp-cuda
            llama-cpp-rocm
            llama-cpp-dual
            llama-cpp-cpu-native
            llama-cpp-vulkan-native
            llama-cpp-cuda-native
            llama-cpp-rocm-native
            llama-cpp-dual-native
            llama-cpp-cpu-llguidance
            llama-cpp-vulkan-llguidance
            llama-cpp-cuda-llguidance
            llama-cpp-rocm-llguidance
            llama-cpp-dual-llguidance
            llama-cpp-cpu-native-llguidance
            llama-cpp-vulkan-native-llguidance
            llama-cpp-cuda-native-llguidance
            llama-cpp-rocm-native-llguidance
            llama-cpp-dual-native-llguidance
            llama-cpp
            llama-cpp-ui;
        }
      );
    };
}
