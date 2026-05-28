# File: ./llama-cpp-overlay.nix
#
# This overlay provides a comprehensive set of `llama-cpp` packages using the
# official `llama-cpp` flake. It provides standard builds and versions that are
# additionally optimized for the host CPU's native instruction set (AVX, FMA, etc.).
#
# Supports dual GPU builds (CUDA + ROCm/HIP) with dynamic backend loading.
{
  inputs,
  lib,
  config ? {},
  llamaPackages ? null,
  ...
}: final: prev: let
  system = prev.stdenv.hostPlatform.system;
  # Use provided llamaPackages or evaluate upstream overlay if not passed
  resolvedLlamaPackages =
    if llamaPackages != null then llamaPackages
    else (inputs.llama-cpp.overlays.default final prev).llamaPackages;

  # 1. Source and Version Overrides
  llamaCppSrc =
    if config ? llamaCppSrc && config.llamaCppSrc != null then
      config.llamaCppSrc
    else if config ? llamaCppTag && config.llamaCppTag != null && config ? llamaCppHash && config.llamaCppHash != null then
      prev.fetchFromGitHub {
        owner = "ggml-org";
        repo = "llama.cpp";
        rev = config.llamaCppTag;
        hash = config.llamaCppHash;
      }
    else
      null;

  withSrc = pkg:
    if llamaCppSrc != null then
      pkg.overrideAttrs (old: {
        src = llamaCppSrc;
        version =
          if config ? llamaCppTag && config.llamaCppTag != null
          then config.llamaCppTag
          else old.version + "-custom";
      })
    else
      pkg;

  # 2. CUDA Package and Version Resolution
  # CUDA uses major_minor format: "12.9" -> "cudaPackages_12_9"
  # Available in nixpkgs unstable: 12.6, 12.8, 12.9 (default), 13.0, 13.1, 13.2
  # Note: 12.0-12.5 and 12.7 removed upstream
  cudaPkgAttrFromVersion = if config ? cudaVersion && config.cudaVersion != null then
    "cudaPackages_" + (lib.replaceStrings ["."] ["_"] config.cudaVersion)
    else null;

  resolvedCudaPackages =
    if config ? cudaPackages && config.cudaPackages != null then
      config.cudaPackages
    else if config ? cudaPkgAttr && config.cudaPkgAttr != null && prev ? ${config.cudaPkgAttr} then
      prev.${config.cudaPkgAttr}
    else if cudaPkgAttrFromVersion != null && prev ? ${cudaPkgAttrFromVersion} then
      prev.${cudaPkgAttrFromVersion}
    else
      prev.cudaPackages or null;  # Fall back to default cudaPackages

  # 3. ROCm Package and Version Resolution
  # ROCm uses major-only format: "6.0" -> "rocmPackages_6"
  rocmMajorVersion = if config ? rocmVersion && config.rocmVersion != null then
    builtins.head (lib.splitString "." config.rocmVersion)
    else null;

  rocmPkgAttrFromVersion = if rocmMajorVersion != null then
    "rocmPackages_${rocmMajorVersion}"
    else null;

  resolvedRocmPackages =
    if config ? rocmPackages && config.rocmPackages != null then
      config.rocmPackages
    else if config ? rocmPkgAttr && config.rocmPkgAttr != null && prev ? ${config.rocmPkgAttr} then
      prev.${config.rocmPkgAttr}
    else if rocmPkgAttrFromVersion != null && prev ? ${rocmPkgAttrFromVersion} then
      prev.${rocmPkgAttrFromVersion}
    else
      prev.rocmPackages or null;  # Fall back to default rocmPackages

  # Helper function to apply native CPU optimizations to any llama.cpp package.
  withNativeCpu = pkg:
    pkg.overrideAttrs (old: {
      # Append a suffix for clarity in the Nix store path
      pname = old.pname + "-native";

      # Remove the generic flag and add the native optimization flag.
      cmakeFlags =
        (lib.lists.filter (flag: flag != "-DGGML_NATIVE=false") old.cmakeFlags)
        ++ [
          "-DGGML_NATIVE=ON"
        ];
      NIX_CFLAGS_COMPILE = (old.NIX_CFLAGS_COMPILE or "") + " -O3 -march=native -mtune=native";
      NIX_CXXSTDLIB_COMPILE = (old.NIX_CXXSTDLIB_COMPILE or "") + " -O3 -march=native -mtune=native";
    });

  # Compile the Web UI from source using the pinned llama-cpp input or custom source
  llama-cpp-ui = prev.buildNpmPackage {
    pname = "llama-cpp-ui";
    version = if config ? llamaCppTag && config.llamaCppTag != null then config.llamaCppTag else (inputs.llama-cpp.shortRev or "latest");

    src = if llamaCppSrc != null then llamaCppSrc else inputs.llama-cpp;

    # Set sourceRoot to the path containing package-lock.json so fetchNpmDeps succeeds.
    sourceRoot = "source/tools/ui";

    # In the main build, we relocate the directory inside postUnpack to a writable location under /build
    # and update sourceRoot to keep Svelte/Vite's relative build path (../../build/tools/ui/dist) within that writable folder.
    postUnpack = ''
      mkdir -p /build/ui-build/tools
      cp -r /build/source/tools/ui /build/ui-build/tools/
      sourceRoot="/build/ui-build/tools/ui"
    '';

    npmDepsHash = "sha256-Iyg8FpcTKf2UYHuK7mA3cTAqVaLcQPcS0YCa5Qf01Gc=";

    npmBuildScript = "build";

    installPhase = ''
      mkdir -p $out
      cp -r dist/* $out/
    '';
  };

  # Helper function to enable HTTPS support and embed the WebUI built from source
  withHttps = pkg:
    pkg.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.pkg-config ];
      buildInputs = (old.buildInputs or [ ]) ++ [ prev.openssl ];
      cmakeFlags = (old.cmakeFlags or [ ]) ++ [
        "-DLLAMA_OPENSSL=ON"
        "-DLLAMA_HTTPLIB=ON"
        "-DLLAMA_BUILD_UI=ON"
      ];
      preConfigure = (old.preConfigure or "") + ''
        mkdir -p build/tools/ui/dist
        cp -r ${llama-cpp-ui}/* build/tools/ui/dist/
      '';
    });

  # Build llguidance as a proper Rust package
  llguidance = prev.rustPlatform.buildRustPackage rec {
    pname = "llguidance";
    version = "1.0.1";

    src = prev.fetchFromGitHub {
      owner = "guidance-ai";
      repo = "llguidance";
      rev = "d795912fedc7d393de740177ea9ea761e7905774"; # v1.0.1
      hash = "sha256-LiardZnaXD5kc+p9c+UYBbtBb7+2ycWqEGCp3aaqHBs=";
    };

    cargoHash = "sha256-VyLTa+1iEY/Z3/4DUIAcjHH0MxLMGtlpcsy2zvmg3b8=";

    nativeBuildInputs = [prev.pkg-config];
    buildInputs = [prev.oniguruma prev.openssl];

    env = {
      RUSTONIG_SYSTEM_LIBONIG = true;
    };

    buildAndTestSubdir = ".";
    cargoBuildFlags = ["--package" "llguidance"];

    postInstall = ''
      mkdir -p $out/include
      cp parser/llguidance.h $out/include/
    '';

    doCheck = false;
  };

  # Helper function to enable llguidance support
  withLlguidance = pkg:
    pkg.overrideAttrs (old: {
      pname = old.pname + "-llguidance";

      buildInputs = (old.buildInputs or []) ++ [llguidance];

      cmakeFlags = (old.cmakeFlags or []) ++ ["-DLLAMA_LLGUIDANCE=ON"];

      postPatch = (old.postPatch or "") + ''
        # Replace the entire LLAMA_LLGUIDANCE block with one using pre-built llguidance from Nix
        sed -i '/^if (LLAMA_LLGUIDANCE)/,/^endif()/{
          /^if (LLAMA_LLGUIDANCE)/c\
if (LLAMA_LLGUIDANCE)\
    # Use pre-built llguidance from Nix\
    add_library(llguidance STATIC IMPORTED)\
    set_target_properties(llguidance PROPERTIES IMPORTED_LOCATION ${llguidance}/lib/libllguidance.a)\
    target_include_directories(''${TARGET} PRIVATE ${llguidance}/include)\
    target_link_libraries(''${TARGET} PRIVATE llguidance)\
    target_compile_definitions(''${TARGET} PUBLIC LLAMA_USE_LLGUIDANCE)\
    if (WIN32)\
        target_link_libraries(''${TARGET} PRIVATE ws2_32 userenv ntdll bcrypt)\
    endif()
          /^if (LLAMA_LLGUIDANCE)/!{/^endif()/!d}
        }' common/CMakeLists.txt
      '';
    });

  # Helper function to apply ROCm/HIP performance optimizations for gfx906 (MI50/MI60)
  # Matches the build flags used by mixa3607/ML-gfx906 project
  withRocmOptimizations = rocmPkgs: pkg:
    pkg.overrideAttrs (old: {
      buildInputs = (old.buildInputs or [])
        ++ lib.optionals (rocmPkgs != null && rocmPkgs ? rccl) [ rocmPkgs.rccl ];

      cmakeFlags = (old.cmakeFlags or []) ++ [
        "-DGGML_HIP_GRAPHS=ON"           # +8-10% generation speed via graph capture
        "-DGGML_BACKEND_DL=ON"           # Dynamic backend loading
        "-DGGML_CPU_ALL_VARIANTS=ON"     # Optimized CPU fallback paths
      ] ++ lib.optionals (rocmPkgs != null && rocmPkgs ? rccl) [
        "-DGGML_HIP_RCCL=ON"             # Multi-GPU communication
      ];
    });

  # Helper function for dual GPU builds (CUDA + ROCm/HIP with dynamic backend loading)
  # This enables both backends to be loaded at runtime as separate .so files
  withDualGpu = {
    cudaPkgs,
    rocmPkgs,
    cudaArchitectures ? ["86"],  # Default: sm_86 (RTX 3080 Ti)
    rocmArchitectures ? ["gfx906"],  # Default: gfx906 (MI50)
  }: pkg:
    pkg.overrideAttrs (old: {
      pname = old.pname + "-dual";

      nativeBuildInputs = (old.nativeBuildInputs or [])
        ++ [ cudaPkgs.cuda_nvcc rocmPkgs.clr prev.cmake prev.ninja ];

      buildInputs = (old.buildInputs or [])
        # CUDA dependencies
        ++ [ cudaPkgs.cuda_cudart cudaPkgs.cuda_nvcc cudaPkgs.libcublas cudaPkgs.cuda_cccl ]
        # ROCm/HIP dependencies
        ++ [ rocmPkgs.clr rocmPkgs.hipblas rocmPkgs.rocblas ]
        ++ lib.optionals (rocmPkgs ? rccl) [ rocmPkgs.rccl ];

      # Filter out conflicting flags and add dual GPU configuration
      cmakeFlags = (lib.lists.filter (f:
        !(lib.hasPrefix "-DGGML_CUDA" f) &&
        !(lib.hasPrefix "-DGGML_HIP" f) &&
        !(lib.hasPrefix "-DCMAKE_CUDA_ARCHITECTURES" f) &&
        !(lib.hasPrefix "-DCMAKE_HIP_ARCHITECTURES" f) &&
        !(lib.hasPrefix "-DAMDGPU_TARGETS" f)
      ) (old.cmakeFlags or [])) ++ [
        "-DGGML_BACKEND_DL=ON"
        "-DGGML_CUDA=ON"
        "-DGGML_HIP=ON"
        "-DGGML_HIP_GRAPHS=ON"
        "-DGGML_CPU_ALL_VARIANTS=ON"
        "-DCMAKE_CUDA_ARCHITECTURES=${lib.concatStringsSep ";" cudaArchitectures}"
        "-DCMAKE_HIP_ARCHITECTURES=${lib.concatStringsSep ";" rocmArchitectures}"
        "-DCMAKE_HIP_COMPILER=${rocmPkgs.clr.hipClangPath}/clang++"
      ] ++ lib.optionals (rocmPkgs ? rccl) [
        "-DGGML_HIP_RCCL=ON"
      ];

      # Set HIP environment variables for compilation
      preConfigure = (old.preConfigure or "") + ''
        export HIPCXX="${rocmPkgs.clr.hipClangPath}/clang"
        export HIP_PATH="${rocmPkgs.clr}"
        export ROCM_PATH="${rocmPkgs.clr}"
      '';
    });

  # Parameterized builder function for dynamic targets
  buildLlamaCpp = {
    accel ? "cpu",
    native ? true,
    guidance ? false,
    enableHttps ? true,
    customCudaPackages ? null,
    customRocmPackages ? null,
    customCudaCapabilities ? null,
    customRocmTargets ? null,
  }:
    let
      basePkg = withSrc resolvedLlamaPackages.llama-cpp;

      cudaPkgs = if customCudaPackages != null then customCudaPackages else resolvedCudaPackages;
      rocmPkgs = if customRocmPackages != null then customRocmPackages else resolvedRocmPackages;

      # For dual GPU mode, we use a different build path
      isDual = accel == "dual";

      # Create acceleration overrides for single-backend modes
      accelOverrideAttrs =
        if accel == "cuda" then
          {
            useCuda = true;
            useRocm = false;
            useVulkan = false;
          }
          // (lib.optionalAttrs (cudaPkgs != null) { cudaPackages = cudaPkgs; })
        else if accel == "rocm" then
          {
            useRocm = true;
            useCuda = false;
            useVulkan = false;
          }
          // (lib.optionalAttrs (rocmPkgs != null) { rocmPackages = rocmPkgs; })
        else if accel == "vulkan" then
          {
            useVulkan = true;
            useCuda = false;
            useRocm = false;
          }
        else # cpu (also used as base for dual)
          {
            useCuda = false;
            useRocm = false;
            useVulkan = false;
          };

      # Helper to apply CUDA architectures via cmake flags
      withCudaArch = arches: pkg:
        if arches != null then
          pkg.overrideAttrs (old: {
            cmakeFlags = (lib.lists.filter (f: !(lib.hasPrefix "-DCMAKE_CUDA_ARCHITECTURES" f)) (old.cmakeFlags or []))
              ++ ["-DCMAKE_CUDA_ARCHITECTURES=${lib.concatStringsSep ";" arches}"];
          })
        else pkg;

      # Helper to apply ROCm architectures via cmake flags
      withRocmArch = arches: pkg:
        if arches != null then
          pkg.overrideAttrs (old: {
            cmakeFlags = (lib.lists.filter (f:
              !(lib.hasPrefix "-DAMDGPU_TARGETS" f) && !(lib.hasPrefix "-DGPU_TARGETS" f)
            ) (old.cmakeFlags or []))
              ++ ["-DAMDGPU_TARGETS=${lib.concatStringsSep ";" arches}"];
          })
        else pkg;

      # Build the package with appropriate acceleration
      basePkgWithAccel =
        if isDual then
          # For dual mode, start with CPU base and apply dual GPU overlay
          withDualGpu {
            cudaPkgs = cudaPkgs;
            rocmPkgs = rocmPkgs;
            cudaArchitectures = if customCudaCapabilities != null then customCudaCapabilities else ["86"];
            rocmArchitectures = if customRocmTargets != null then customRocmTargets else ["gfx906"];
          } (basePkg.override { useCuda = false; useRocm = false; useVulkan = false; })
        else
          basePkg.override accelOverrideAttrs;

      # Apply architecture overrides for single-backend modes
      pkgWithAccel =
        if accel == "cuda" then withCudaArch customCudaCapabilities basePkgWithAccel
        else if accel == "rocm" then withRocmArch customRocmTargets basePkgWithAccel
        else basePkgWithAccel;

      # Apply ROCm-specific optimizations (HIP_GRAPHS, RCCL) for ROCm builds
      pkgWithRocmOpts =
        if accel == "rocm" then withRocmOptimizations rocmPkgs pkgWithAccel
        else pkgWithAccel;

      pkgWithHttps = if enableHttps then withHttps pkgWithRocmOpts else pkgWithRocmOpts;
      pkgWithNative = if native then withNativeCpu pkgWithHttps else pkgWithHttps;
      pkgWithGuidance = if guidance then withLlguidance pkgWithNative else pkgWithNative;
    in
    pkgWithGuidance;

  # Instantiate configured package
  customLlamaCpp = buildLlamaCpp {
    accel = config.acceleration or "cpu";
    native = config.nativeCpu or true;
    guidance = config.llguidance or false;
    enableHttps = config.https or true;
    customCudaCapabilities = config.cudaCapabilities or null;
    customRocmTargets = config.rocmTargets or null;
  };
in {
  # --- Base Packages (Portable builds) ---

  # 1. Base CPU-only package
  llama-cpp-cpu = withHttps (withSrc resolvedLlamaPackages.llama-cpp);

  # 2. Base Vulkan-accelerated package
  llama-cpp-vulkan = withHttps ((withSrc resolvedLlamaPackages.llama-cpp).override { useVulkan = true; useRocm = false; useCuda = false; });

  # 3. Base CUDA-accelerated package
  llama-cpp-cuda = withHttps ((withSrc resolvedLlamaPackages.llama-cpp).override ({ useCuda = true; useRocm = false; useVulkan = false; } // (lib.optionalAttrs (resolvedCudaPackages != null) { cudaPackages = resolvedCudaPackages; })));

  # 4. Base ROCm-accelerated package (with HIP_GRAPHS and RCCL optimizations)
  llama-cpp-rocm = withRocmOptimizations resolvedRocmPackages (withHttps ((withSrc resolvedLlamaPackages.llama-cpp).override ({ useRocm = true; useCuda = false; useVulkan = false; } // (lib.optionalAttrs (resolvedRocmPackages != null) { rocmPackages = resolvedRocmPackages; }))));

  # --- Native-Optimized Packages ---

  llama-cpp-cpu-native = withNativeCpu final.llama-cpp-cpu;
  llama-cpp-vulkan-native = withNativeCpu final.llama-cpp-vulkan;
  llama-cpp-cuda-native = withNativeCpu final.llama-cpp-cuda;
  llama-cpp-rocm-native = withNativeCpu final.llama-cpp-rocm;

  # --- LLGuidance-Enabled Packages ---

  llama-cpp-cpu-llguidance = withLlguidance final.llama-cpp-cpu;
  llama-cpp-vulkan-llguidance = withLlguidance final.llama-cpp-vulkan;
  llama-cpp-cuda-llguidance = withLlguidance final.llama-cpp-cuda;
  llama-cpp-rocm-llguidance = withLlguidance final.llama-cpp-rocm;

  # --- Combined: Native + LLGuidance ---

  llama-cpp-cpu-native-llguidance = withLlguidance final.llama-cpp-cpu-native;
  llama-cpp-vulkan-native-llguidance = withLlguidance final.llama-cpp-vulkan-native;
  llama-cpp-cuda-native-llguidance = withLlguidance final.llama-cpp-cuda-native;
  llama-cpp-rocm-native-llguidance = withLlguidance final.llama-cpp-rocm-native;

  # --- Dual GPU Packages (CUDA + ROCm with dynamic backend loading) ---

  # Base dual GPU package (defaults: sm_86 + gfx906)
  llama-cpp-dual = withHttps (withDualGpu {
    cudaPkgs = resolvedCudaPackages;
    rocmPkgs = resolvedRocmPackages;
    cudaArchitectures = ["86"];
    rocmArchitectures = ["gfx906"];
  } (withSrc resolvedLlamaPackages.llama-cpp));

  llama-cpp-dual-native = withNativeCpu final.llama-cpp-dual;
  llama-cpp-dual-llguidance = withLlguidance final.llama-cpp-dual;
  llama-cpp-dual-native-llguidance = withLlguidance final.llama-cpp-dual-native;

  # --- Sensible Dynamic Target and Helpers ---

  llama-cpp = customLlamaCpp;
  llama-cpp-ui = llama-cpp-ui;
  llguidance = llguidance;
}
