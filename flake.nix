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
    in {
      overlays.default = voxtypeOverlay;

      # Expose package build outputs only; host and user installation are out of scope.
      packages.${system} = {
        inherit damask magpie voxtype;
      };
    };
}
