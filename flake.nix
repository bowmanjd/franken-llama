{
  description = "Franken-llama: Custom llama.cpp package variants with native CPU optimizations, llguidance, and HTTPS/UI support";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    llama-cpp = {
      url = "github:ggml-org/llama.cpp/b9310";
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
              default = "b9310";
              description = "Overridden Git tag/revision of llama.cpp to compile.";
            };

            llamaCppHash = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = "sha256-XJwh8bPrbhckZkwiS6i3tNGW5Ujeh7hqU3YL6HiS1Ro=";
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
              description = ''
                Major and minor version of CUDA to target (e.g. '12.9' or '13.2').
                Available in nixpkgs: 12.6, 12.8, 12.9 (default), 13.0, 13.1, 13.2 (latest).
                Note: CUDA 12.0-12.5 and 12.7 have been removed from nixpkgs.
              '';
            };

            cudaPkgAttr = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Specific cudaPackages attribute name (e.g. 'cudaPackages_12_9', 'cudaPackages_13_2').";
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

            # Container options
            container = {
              enable = lib.mkEnableOption "Build OCI container images for llama.cpp";

              imageName = lib.mkOption {
                type = lib.types.str;
                default = "ghcr.io/bowmanjd/llama-cpp";
                description = "Container image name/registry path.";
              };

              imageTag = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Container image tag. Defaults to '<version>-<acceleration>'.";
              };

              includeModal = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Include Python and Modal dependencies for deployment on modal.com.";
              };
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
          # Read container config from config.json
          containerCfg = builtins.fromJSON (builtins.readFile ./config.json);

          # Base pkgs for standard packages
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = [
              self.overlays.default
            ];
          };

          # Configured pkgs using config.json settings
          configuredPkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = [
              (self.overlays.configure {
                acceleration = "cuda";
                llguidance = true;
                https = true;
                cudaVersion = containerCfg.cudaVersion or null;
                cudaCapabilities = containerCfg.cudaCapabilities or null;
              })
            ];
          };

          # Import container utilities
          containerUtils = import ./container.nix {
            inherit pkgs;
            lib = nixpkgs.lib;
            config = {};
          };

          configuredContainerUtils = import ./container.nix {
            pkgs = configuredPkgs;
            lib = nixpkgs.lib;
            config = {};
          };

          # Helper to safely build containers (only on Linux x86_64)
          mkContainer = llamaPkg: containerUtils.makeContainerPair {
            llamaPackage = llamaPkg;
            cudaPackages = pkgs.cudaPackages;
            rocmPackages = pkgs.rocmPackages or null;
          };

          mkContainerModal = llamaPkg: containerUtils.makeContainerPair {
            llamaPackage = llamaPkg;
            cudaPackages = pkgs.cudaPackages;
            rocmPackages = pkgs.rocmPackages or null;
            includeModal = true;
          };

          # Only build containers on x86_64-linux (Docker images are Linux-specific)
          isLinuxX86 = system == "x86_64-linux";

          # The main "container" target using config.json
          configuredContainer = configuredContainerUtils.makeContainerPair {
            llamaPackage = configuredPkgs.llama-cpp;
            cudaPackages = configuredPkgs.cudaPackages;
            includeModal = containerCfg.includeModal or false;
            imageTag = let
              version = llama-cpp.shortRev or "latest";
              cuda = containerCfg.cudaVersion or "cuda";
              arch = builtins.head (containerCfg.cudaCapabilities or ["unknown"]);
            in "${version}-cuda${cuda}-sm${arch}";
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
        # Container packages (x86_64-linux only)
        // nixpkgs.lib.optionalAttrs isLinuxX86 {
          # Slim packages (portable, no container)
          llama-cpp-cpu-slim = (mkContainer pkgs.llama-cpp-cpu).slim;
          llama-cpp-cuda-slim = (mkContainer pkgs.llama-cpp-cuda).slim;
          llama-cpp-rocm-slim = (mkContainer pkgs.llama-cpp-rocm).slim;
          llama-cpp-vulkan-slim = (mkContainer pkgs.llama-cpp-vulkan).slim;

          # Container images
          llama-cpp-cpu-container = (mkContainer pkgs.llama-cpp-cpu).container;
          llama-cpp-cuda-container = (mkContainer pkgs.llama-cpp-cuda).container;
          llama-cpp-rocm-container = (mkContainer pkgs.llama-cpp-rocm).container;
          llama-cpp-vulkan-container = (mkContainer pkgs.llama-cpp-vulkan).container;

          # With llguidance
          llama-cpp-cuda-llguidance-slim = (mkContainer pkgs.llama-cpp-cuda-llguidance).slim;
          llama-cpp-cuda-llguidance-container = (mkContainer pkgs.llama-cpp-cuda-llguidance).container;

          # Modal-ready containers (includes Python)
          llama-cpp-cuda-modal = (mkContainerModal pkgs.llama-cpp-cuda).container;
          llama-cpp-cuda-llguidance-modal = (mkContainerModal pkgs.llama-cpp-cuda-llguidance).container;

          # Simple targets using config.json
          container = configuredContainer.container;
          slim = configuredContainer.slim;
        }
      );
    };
}
