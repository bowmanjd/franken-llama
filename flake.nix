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
      # Expose the unified overlay to downstream configurations
      overlays.default = final: prev:
        let
          # Apply the upstream official overlay first to populate upstream llamaPackages
          upstream = llama-cpp.overlays.default final prev;
          
          # Evaluate our custom overlay
          customOverlay = import ./llama-cpp-overlay.nix {
            inputs = inputs // { llama-cpp = llama-cpp; };
            lib = nixpkgs.lib;
          };
          
          customPackages = customOverlay final prev;
        in
        upstream // customPackages;

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
            llama-cpp-cpu-native
            llama-cpp-vulkan-native
            llama-cpp-cuda-native
            llama-cpp-cpu-llguidance
            llama-cpp-vulkan-llguidance
            llama-cpp-cuda-llguidance
            llama-cpp-cpu-native-llguidance
            llama-cpp-vulkan-native-llguidance
            llama-cpp-cuda-native-llguidance
            llama-cpp
            llama-cpp-ui;
        }
      );
    };
}
