{
  description = "Personal Nix packages not covered by nixpkgs defaults";

  inputs = {
    # USTC 镜像 (github fetcher 的 codeload 302 超时, 改用镜像 tarball)
    nixpkgs.url = "https://mirrors.ustc.edu.cn/nix-channels/nixpkgs-unstable/nixexprs.tar.xz";
  };

  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      voxtypeOverlay = import ./overlays/voxtype.nix;
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [ voxtypeOverlay ];
      };
      # Separate instance so the CUDA architecture setting stays out of the other packages.
      cudaPkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          cudaCapabilities = [ "7.5" ];
        };
      };
      # nodejs_latest (26.x in the locked nixpkgs) is not in the binary cache and
      # only builds the web UI, so use the cached LTS instead.
      llama-cpp-cuda = cudaPkgs.llama-cpp.override {
        cudaSupport = true;
        nodejs_latest = cudaPkgs.nodejs_22;
      };
      # The CUDA libraries have RUNPATH /run/opengl-driver/lib, which only exists on
      # NixOS. On this WSL host the driver lives in /usr/lib/wsl/lib, and without it
      # no CUDA device is found. Wrapping keeps the cached build; the original
      # binaries still run from their own store path, where ggml finds its backends.
      llama-cpp = pkgs.symlinkJoin {
        name = "llama-cpp-${llama-cpp-cuda.version}";
        paths = [ llama-cpp-cuda ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          for f in $out/bin/*; do
            case "$f" in *.so|*.so.*) continue ;; esac
            [ -x "$f" ] && [ ! -d "$f" ] || continue
            wrapProgram "$f" --suffix LD_LIBRARY_PATH : /usr/lib/wsl/lib
          done
        '';
        inherit (llama-cpp-cuda) meta version;
      };
      damask-solvers = pkgs.callPackage ./packages/damask-solvers.nix { };
      python-damask = pkgs.python3Packages.callPackage ./packages/python-damask.nix { };
      damask = pkgs.callPackage ./packages/damask.nix {
        inherit damask-solvers python-damask;
      };
      magpie = pkgs.callPackage ./packages/magpie.nix { };
      # The overlay enables ONNX engines; retain a PipeWire ALSA path for non-NixOS hosts.
      voxtype-onnx = pkgs.voxtype;
      # On a non-NixOS host the system ALSA config routes `default` to PipeWire,
      # but nix alsa-lib only searches its own store path for that plugin.
      # Wrapping (instead of overriding postFixup) keeps the cached binary.
      voxtype = pkgs.symlinkJoin {
        name = "voxtype-${voxtype-onnx.version}";
        paths = [ voxtype-onnx ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/voxtype \
            --set-default ALSA_PLUGIN_DIR ${pkgs.pipewire}/lib/alsa-lib
        '';
        inherit (voxtype-onnx) meta version;
      };
      # ALSA only searches ALSA_PLUGIN_DIR and never falls back to /usr/lib, so a
      # host whose `default` PCM resolves to PipeWire or PulseAudio needs both
      # plugin sets in one directory. Merging them from this same nixpkgs pin
      # keeps them ABI-compatible with the voxtype build (glibc included).
      voxtype-alsa-plugins = pkgs.buildEnv {
        name = "voxtype-alsa-plugins";
        paths = [ pkgs.pipewire pkgs.alsa-plugins ];
        pathsToLink = [ "/lib/alsa-lib" ];
      };
      # Optional variant for hosts with no system PipeWire plugin path, e.g. WSLg,
      # where the host microphone is only reachable through PulseAudio.
      voxtype-pulse = pkgs.symlinkJoin {
        name = "voxtype-pulse-${voxtype-onnx.version}";
        paths = [ voxtype-onnx ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/voxtype \
            --set-default ALSA_PLUGIN_DIR ${voxtype-alsa-plugins}/lib/alsa-lib
        '';
        inherit (voxtype-onnx) meta version;
      };
    in {
      overlays.default = voxtypeOverlay;

      # Expose package build outputs only; host and user installation are out of scope.
      packages.${system} = {
        inherit damask llama-cpp magpie voxtype voxtype-pulse;
      };
    };
}
