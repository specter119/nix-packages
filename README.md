# Personal Nix Packages

This flake builds packages that are missing from nixpkgs or need non-default
build options. It defines package outputs only; host configuration and package
installation are managed elsewhere.

## Packages

- `damask`: DAMASK solvers and Python tools, built from the upstream 3.1.0 source.
- `llama-cpp`: nixpkgs' llama.cpp built with CUDA for compute capability 7.5
  (Turing). It follows the version in the locked nixpkgs. To target another GPU,
  change `cudaCapabilities` in `flake.nix`. The programs are wrapped to find the
  WSL NVIDIA driver in `/usr/lib/wsl/lib`, since non-NixOS hosts have no
  `/run/opengl-driver/lib`.
- `magpie`: Magpie desktop app and CLI, from the upstream v0.1.1274 Linux release.
  Its desktop entry launches through `nixGL`, which must be available on the
  desktop session's `PATH`. It is updated infrequently.
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
nix build .#damask
nix build .#llama-cpp
nix build .#magpie
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
