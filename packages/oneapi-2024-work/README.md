# Intel oneAPI 2024.2 (classic `ifort`) — work package

Scratch package used to get a working **pre-2025 classic `ifort`** out of the
2024.2 offline kits, because the flake's nixpkgs ships oneAPI 2026 which only
has the LLVM-based `ifx`, and MSC Marc 2024.2 needs `ifort`.

Nothing outside `packages/oneapi-2024-work/` is modified. This directory is
self-contained: `flake.nix`, `packages/msc-marc` and shared files are untouched.

## Build

```sh
nix build --no-link --impure --expr '
  let f = builtins.getFlake "/path/to/nix-packages";
      pkgs = import f.inputs.nixpkgs { system = "x86_64-linux"; config.allowUnfree = true; };
  in pkgs.callPackage ./packages/oneapi-2024-work { }'
```

The derivation is not wired into `flake.nix` on purpose. Media are the same
`requireFile` fixed-output paths `msc-marc` already uses:

| media | sha256 |
| --- | --- |
| `l_BaseKit_p_2024.2.0.634_offline.sh` | `sha256-rpfxtxRvYQwHIy11ysjTf2spmN9BZBG++an2ydI1kaQ=` |
| `l_HPCKit_p_2024.2.0.635_offline.sh` | `sha256-RXoWOZC5GSJ4MmV+QHJEF1QUhPXe8UkaaAN0cA02xSA=` |

## What was actually broken

Four independent problems. The first two are the ones that were reported; the
last two only show up once the installer gets past them.

### 1. `--components all` downloads the FPGA support package

`intel.oneapi.lin.compiler.fpga` is the only package in either offline kit whose
payload is **not shipped locally**:

```
$ python3 -c '...walk every packages/*/manifest.json, diff payloads against files on disk...'
==================== base/l_BaseKit_p_2024.2.0.634_offline
intel.oneapi.lin.compiler.fpga                MISSING 1: [("cupPayload.cup", 298756431)]
==================== hpc/l_HPCKit_p_2024.2.0.635_offline
intel.oneapi.lin.compiler.fpga                MISSING 1: [("cupPayload.cup", 298756431)]
```

The kit only carries that package's `manifest.json` and its five shell scripts;
the 298 MB `cupPayload.cup` is fetched from
`https://installer.repos.intel.com/oneapi/compiler/lin/intel.oneapi.lin.compiler.fpga,v=2024.2.0%2B981/cupPayload.cup`.
With no network the install dies:

```
DEBUG : <PayloadCollector>: download 'https://installer.repos.intel.com/oneapi/compiler/lin/intel.oneapi.lin.compiler.fpga,v=2024.2.0%2B981/cupPayload.cup' to '.../cupPayload.cup'.
DEBUG : DownloadManager check connection: [ERROR]
ERROR : DownloadManager stop execution due to connection error
MESSAGE : Cannot establish internet connection with current settings.
ERROR : Download failed.
MESSAGE : Failed to establish internet connection. Check your connection settings.
Installer completed with code 1
```

`compiler.fpga` is declared `"type": "optional"` in
`intel.oneapi.lin.dpcpp-cpp-compiler`'s manifest, so it can simply be left out
of `--components`. See `logs/01-components-all-offline.*`.

### 2. `--components default` on BaseKit fails the disk-space prerequisite

`default` expands to VTune (1.7 G) + Advisor (1.2 G) + IPP (4.2 G) + DAL (2.0 G)
+ MKL (4.9 G) + DPC++ compiler (~3 G) + oneDNN + FPGA (2.2 G) + … ≈ 20.7 GB
(the sum of every BaseKit package's `installSize` is 22.0 GB):

```
Error:
Failed to check prerequisites.
Not enough disk space. Drive /tmp has 16.2 GB available. 20.7 GB is required.
Please free up disk space or change the installation directory.
Installer completed with code 1
```

Observed on this machine with 16.2 GB free in `/tmp` (tmpfs, 24 G). Note that
`nix build` puts `$TMPDIR` on `/tmp` too, so this is the same limit a sandboxed
build hits. `--components default` is therefore not a workaround for problem 1,
it just fails earlier for a different reason.

### 3. `--package-path` / `--download-cache` in `msc-marc` point at the wrong paths

`msc-marc` pre-extracts with `-x --extract-folder "$dest"`, which creates
`$dest/l_BaseKit_p_2024.2.0.634_offline/`, but then passes
`--package-path "$2/packages"` — one level too high. The correct glob is
`"$2"/*/packages`. It also passes `--download-cache "$2/packages"`, i.e. it
asks the installer to use the read-only extracted media as its download cache.

Both are avoidable entirely: driving the media `.sh` with `-a` already extracts
the kit and the bootstrapper finds its own `packages/` directory, so no `-x`
pre-pass and no `--package-path` are needed. This package does that (one
extraction instead of two, which matters for a 2.5 GB kit on tmpfs).

### 4. `fixupPhase` aborts on Intel's own baked-in RPATH

After a successful install the build still failed:

```
audit-tmpdir> RPATH of binary .../mpi/2021.13/bin/impi_info contains a forbidden reference to /build/
Some binaries contain forbidden references to /build/. Check the error above!
```

The offending RPATH is

```
$ORIGIN/../lib/release:/build/impi/_install/intel64/lib
```

`/build/impi/_install` is **Intel's** build path baked into their prebuilt MPI
binaries — it only collides with Nix's `$TMPDIR=/build` by coincidence. It is
not something this build produced. Fix: `noAuditTmpdir = true` (the tree is only
ever consumed through an FHS env, and MPI is not used by the Marc/HDF5 build).

The same run also emits `patchelf: wrong ELF type` for the 32-bit objects; that
noise comes from the same audit hook and disappears with `noAuditTmpdir`.

## The fix: an explicit component list

`intel.oneapi.lin.ifort-compiler` (ifort/ifx) and
`intel.oneapi.lin.dpcpp-cpp-compiler` (icx/icpx, needed by the HDF5 build in
`msc-marc`, plus TBB/DPL runtime). Both live in **HPCKit**, so BaseKit is not
installed at all — no VTune, no Advisor, no DAL, no IPP, no FPGA, no MKL.

Resulting install (32 packages, 3.0 GB):

```
2024.2 common compiler debugger dev-utilities diagnostics dpl hpckit
licensing mpi setvars.sh support.txt tbb tcm modulefiles-setup.sh
```

`compiler/2024.2/opt/` contains only `compiler`; there is no `oclfpga`, and no
`vtune`/`advisor`/`mkl`/`dal`/`ipp` directory.

Two extra bits the derivation does that `msc-marc` also needs:

* `compiler/latest -> 2024.2` plus `compiler/latest/linux/bin/{ifort,icx,...}`
  and `.../linux/bin/intel64/*` symlinks — 2024.2 does not create the
  `linux/bin/intel64` layout that Marc's `include_linux64` looks for.
* installer logs are copied to `$out/share/oneapi-install-logs/<kit>/`
  (6.7 MB, 35 files) so a rollback can be diagnosed after the build. Set
  `keepInstallLogs = false` when integrating, because the logs carry timestamps
  and make the output non-reproducible.

No `__noChroot` is needed: Nix rejects it while `sandbox = true`, and with the
narrowed list nothing has to be downloaded, so the CDN probe never has to
succeed. The build below ran with the sandbox **on**.

## Verification (sandbox on, `--no-link`)

```
$ nix build --no-link --impure --expr '...pkgs.callPackage ./packages/oneapi-2024-work { }'
/nix/store/xdrc9xnnwdg7zh8qwl3pikrsdn3pnmxh-intel-oneapi-2024.2-2024.2
```

In-build (`installPhase`):

```
--- ifort -V ---
Intel(R) Fortran Intel(R) 64 Compiler Classic for applications running on Intel(R) 64,
Version 2021.13.0 Build 20240602_000000
Copyright (C) 1985-2024 Intel Corporation.  All rights reserved.
--- minimal Fortran build ---
sum of squares 1..10 =      385.0
```

Post-build, sourcing `setvars.sh` from the store path directly (no FHS env):

```
$ . /nix/store/xdrc9xnnwdg7zh8qwl3pikrsdn3pnmxh-intel-oneapi-2024.2-2024.2/setvars.sh --force
$ ifort -V | head -1
Intel(R) Fortran Intel(R) 64 Compiler Classic ... Version 2021.13.0 Build 20240602_000000
$ ifort -O2 -qopenmp -diag-disable=10448 hello.f90 -o hello && ./hello
sum of squares 1..10 =      385.0
$ icx  -O2 t.cpp -o t  && ./t     # icx ok
$ icpx -O2 t.cpp -o t2 && ./t2    # icx ok
```

`keepInstallLogs = false` also builds and has no `share/` directory.

The two-kit path was exercised too, with `baseKitComponents = [ "intel.oneapi.lin.tlt" ]`
(a 374 KB component, to keep the test cheap): BaseKit installs first, HPCKit
second into the same prefix, both log directories are kept, and `ifort`/`icpx`
still work. HPCKit prints

```
Installation directory is not empty.
The product cannot be installed into nonempty directory '<out>'.
```

when it finds BaseKit already there. That is a warning, not a failure — the
run still ends with `Installation has successfully completed`. `msc-marc`
already lives with it today.

## Logs kept in this directory

| file | what it is |
| --- | --- |
| `logs/00-README.logs.md` | annotated excerpts of both failing selections, with provenance |
| `logs/01-components-all-offline.stdout.log` | verbatim stdout of `--components all` with the CDN blocked |
| `logs/03-components-narrowed-hpckit.build.log` | `nix log` of the working build (install + verification) |
| `logs/04-fixup-audit-tmpdir.build.log` | the `fixupPhase` failure caused by Intel's `/build/impi` RPATH |

## Integration into `packages/msc-marc`

The `oneapi` derivation in `packages/msc-marc/default.nix` (lines ~110–165) can
be replaced by this one verbatim, or patched in place. The minimal in-place
change is:

1. Replace `--components all` with
   `--components intel.oneapi.lin.ifort-compiler:intel.oneapi.lin.dpcpp-cpp-compiler`.
   (Do not use `default`: see problem 2.)
2. Drop `-x --extract-folder` / `--package-path` / `--download-cache`
   entirely and drive the media `.sh` with `-a` only (problem 3). If the
   pre-extraction is kept, `--package-path` must be `"$2"/*/packages` and
   `--download-cache` must be a writable scratch dir, not `$2/packages`.
3. Add `noAuditTmpdir = true;` next to `dontPatchELF`/`dontStrip` (problem 4).
4. Remove `__noChroot = true;` — it is rejected when `sandbox = true` and is no
   longer needed once the component list is narrowed.
5. Keep the `compiler/latest/linux/bin/intel64` symlink block; Marc's
   `include_linux64` depends on it.

If Marc turns out to need MKL at runtime, pass
`baseKitComponents = [ "intel.oneapi.lin.mkl.devel" ];` — that installs BaseKit
first (same prefix, as required) with only MKL, adding ~4.9 GB instead of the
20.7 GB of `--components default`.

## Caveats

* The output is 3.0 GB and is never patched (`dontPatchELF`, `dontStrip`); it is
  meant to be consumed through an FHS env like `msc-marc`'s, not from a bare
  `nix shell`.
* `ifort` prints the deprecation remark #10448 on every invocation; pass
  `-diag-disable=10448` to silence it.
* The installer warns `G++ package is not installed` and `operating system
  "Unknown"`; both are cosmetic and do not affect the result.
* `keepInstallLogs = true` (the default here) makes the derivation output
  non-reproducible.
