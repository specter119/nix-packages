# Personal Nix Packages

This flake builds packages that are missing from nixpkgs or need non-default
build options. It defines package outputs only; host configuration and package
installation are managed elsewhere.

## Packages

- `comsol`: COMSOL Multiphysics 6.4.0.293 for Linux, unpacked from the
  installation DVD image and run in an FHS environment. The image is not
  redistributable, so the build needs it in the Nix store:
  `nix-store --add-fixed sha256 COMSOL_Multiphysics_6.4.0.293.iso` (a symlink
  is rejected; pass the real file). `packages/comsol/*.iso` is git-ignored, so a
  symlink to the image can sit there. It installs the core product, every
  module's data, English and Chinese documentation, the Application Library,
  the CAD import kernel and the Chatbot components. It leaves out the other
  platforms, the CUDA runtimes, COMSOL Server and the Windows-only LiveLink
  products. The result is about 19 GB. COMSOL reads its license from
  `$LMCOMSOL_LICENSE_FILE` (a file or `port@host`), else from
  `~/.config/comsol/license.dat`; the license is never stored in the repository.
  The environment bundles Mesa, so OpenGL (radeonsi, iris, llvmpipe) works
  without `nixGL`; NVIDIA GPUs are not covered. Mesa's OpenCL (rusticl) is
  enabled for `radeonsi` through `RUSTICL_ENABLE`, which you can override. If
  3D graphics still fail, `comsol -3drend sw` forces software rendering.
  `.#comsol.shell` opens a shell in the same environment for finding missing
  libraries.
- `damask`: DAMASK solvers and Python tools, built from the upstream 3.1.0 source.
- `llama-cpp`: nixpkgs' llama.cpp built with CUDA for compute capability 7.5
  (Turing). It follows the version in the locked nixpkgs. To target another GPU,
  change `cudaCapabilities` in `flake.nix`. The programs are wrapped to find the
  WSL NVIDIA driver in `/usr/lib/wsl/lib`, since non-NixOS hosts have no
  `/run/opengl-driver/lib`.
- `magpie`: Magpie desktop app and CLI, from the upstream v0.1.1274 Linux release.
  Its desktop entry launches through `nixGL`, which must be available on the
  desktop session's `PATH`. It is updated infrequently.
- `maka`: Apache Maka built from the `rust-preview` branch (pinned commit), for
  WSL. It installs `maka` and `maka-python-worker` (which must sit beside it) and
  is built without the `native-desktop` feature, as upstream does for WSL.
  Computer Use then drives the Windows desktop through a matching Windows
  `maka.exe`; set `MAKA_CUA_WINDOWS_EXECUTABLE` to its WSL path at run time.
  The desktop shell and the Windows-only `maka-service` entry are not built.
  Maka's own V8 build is downloaded from its GitHub release, pinned by hash.
  The npm dependencies are fetched through `registry.yarnpkg.com`, which serves
  the same registry as `registry.npmjs.org` (reachable where the latter is
  not), and fixed-output builds trust the host CA bundle in
  `/etc/ssl/certs/ca-certificates.crt` for networks that re-sign HTTPS.
- `voxtype`: nixpkgs' Voxtype with ONNX support and a PipeWire ALSA plugin path.

The flake currently supports `x86_64-linux`.

## Overlay

`overlays.default` replaces nixpkgs' `voxtype` with a build that enables its
ONNX-backed engines and links `onnxruntime`. Apply it from a consuming flake
with `nixpkgs.overlays = [ inputs.<flake-name>.overlays.default ];`.

The `.#voxtype` package output additionally sets the PipeWire ALSA plugin path
for non-NixOS hosts.

## Build

```sh
nix build .#comsol
nix build .#damask
nix build .#llama-cpp
nix build .#magpie
nix build .#maka
nix build .#voxtype
```

## Inputs and source integrity

- `flake.lock` pins the nixpkgs input. Review lock-file changes when updating it
  with `nix flake update nixpkgs`.
- Upstream source archives use fixed SHA-256 hashes in their package
  definitions. A matching hash verifies the fetched bytes; it does not certify
  the upstream source as safe.
- Packages reuse nixpkgs dependencies where practical. Keep credentials and
  machine-specific configuration out of this repository.
