# Intel oneAPI 2024.2 (classic ifort) — narrowed, offline-safe install.
#
# Why 2024.2: the flake's nixpkgs ships oneAPI 2026, which only has the
# LLVM-based `ifx`. MSC Marc 2024.2 needs the classic `ifort` front end, so we
# pin the 2024.2 offline kits.
#
# Why the component list is explicit: `--components all` pulls
# `intel.oneapi.lin.compiler.fpga`, whose 298 MB `cupPayload.cup` is *not*
# shipped inside the offline kit. The installer then tries to fetch it from
# installer.repos.intel.com and aborts with "Cannot establish internet
# connection" as soon as the Nix sandbox has no network. FPGA support is an
# *optional* dependency of dpcpp-cpp-compiler, so listing the components we
# actually need skips it and the install becomes fully offline.
#
# `--components default` is not a workaround either: the default BaseKit set
# (VTune 1.7 G, Advisor 1.2 G, IPP 4.2 G, DAL 2.0 G, MKL 4.9 G, ...) needs
# 20.7 GB and aborts at the "Not enough disk space" prerequisite check.
#
# Marc only needs a Fortran compiler (and, for the HDF5 build in msc-marc,
# icx/icpx). Both live in HPCKit, so BaseKit is not installed at all by
# default. Set `baseKitComponents` if MKL/TBB from BaseKit is ever required.
{
  lib,
  stdenvNoCC,
  requireFile,
  buildFHSEnv,
  bash,
  bc,
  binutils,
  coreutils,
  file,
  findutils,
  gawk,
  gcc,
  gnugrep,
  gnused,
  gnutar,
  gzip,
  hostname,
  ncurses5,
  patch,
  procps,
  python3,
  util-linux,
  which,
  writableTmpDirAsHomeHook,
  zlib,
  libxcrypt-legacy,
  # Components installed from l_HPCKit. `intel.oneapi.lin.ifort-compiler`
  # provides ifort/ifx, `intel.oneapi.lin.dpcpp-cpp-compiler` provides
  # icx/icpx (needed by msc-marc's HDF5 build) plus TBB/DPL runtime.
  hpckitComponents ? [
    "intel.oneapi.lin.ifort-compiler"
    "intel.oneapi.lin.dpcpp-cpp-compiler"
  ],
  # Empty by default: BaseKit is not needed for a Fortran-only toolchain.
  # Example if MKL is wanted: [ "intel.oneapi.lin.mkl.devel" ].
  baseKitComponents ? [ ],
  # Copying the installer logs into $out makes the output non-reproducible
  # (they carry timestamps), so turn this off once the package is integrated.
  keepInstallLogs ? true,
}:

let
  version = "2024.2";
  oneapiYear = "2024";
  oneapiMinor = "2";
  oneapiPatch = "0";
  oneapiVersion = "${oneapiYear}.${oneapiMinor}.${oneapiPatch}";

  mediaMsg = name: ''
    Licensed ${name} is not redistributable. Add the original file with:
      nix-store --add-fixed sha256 /path/to/${name}
  '';

  baseKitMedia = requireFile {
    name = "l_BaseKit_p_2024.2.0.634_offline.sh";
    hash = "sha256-rpfxtxRvYQwHIy11ysjTf2spmN9BZBG++an2ydI1kaQ=";
    message = mediaMsg "l_BaseKit_p_2024.2.0.634_offline.sh";
  };
  hpckitMedia = requireFile {
    name = "l_HPCKit_p_2024.2.0.635_offline.sh";
    hash = "sha256-RXoWOZC5GSJ4MmV+QHJEF1QUhPXe8UkaaAN0cA02xSA=";
    message = mediaMsg "l_HPCKit_p_2024.2.0.635_offline.sh";
  };

  # BaseKit must land in the same prefix as HPCKit, and before it.
  kits =
    lib.optional (baseKitComponents != [ ]) {
      media = baseKitMedia;
      components = baseKitComponents;
    }
    ++ [
      {
        media = hpckitMedia;
        components = hpckitComponents;
      }
    ];

  installerPkgs =
    pkgs: with pkgs; [
      bash
      bc
      binutils
      coreutils
      file
      findutils
      gawk
      gcc
      gnugrep
      gnused
      gnutar
      gzip
      hostname
      ncurses5
      patch
      procps
      python3
      util-linux
      which
      zlib
      libxcrypt-legacy
    ];

  # The Intel bootstrapper is a normal FHS binary and its custom actions are
  # /bin/sh scripts, so it needs an FHS environment even for a silent install.
  installerShell = buildFHSEnv {
    name = "oneapi-2024-installer-shell";
    targetPkgs = installerPkgs;
    runScript = "bash";
    inherit version;
  };
in
stdenvNoCC.mkDerivation {
  pname = "intel-oneapi-2024.2";
  inherit version;

  dontUnpack = true;
  # ~3 GB tree of prebuilt binaries: never patchelf/strip it.
  dontPatchELF = true;
  dontStrip = true;
  # Intel's prebuilt MPI binaries carry a baked-in RPATH element
  # /build/impi/_install/intel64/lib (Intel's own build path). It happens to
  # collide with Nix's $TMPDIR=/build, so the fixup audit hook treats it as a
  # security bug and fails the build. The tree is only ever consumed through an
  # FHS env, so skip the audit.
  noAuditTmpdir = true;

  nativeBuildInputs = [
    installerShell
    writableTmpDirAsHomeHook
  ];

  # NOTE: no `__noChroot`. Nix rejects it while `sandbox = true`, and it is not
  # needed once the component list is narrowed: every payload the installer
  # touches is present in the offline kit, so the CDN probe never has to
  # succeed.

  installPhase = ''
    runHook preInstall

    mkdir -p "$out" "$TMPDIR/intel-home" "$TMPDIR/intel-logs"
    export HOME="$TMPDIR/intel-home"

    # Keep every installer log in the output so a failed/rolled-back run can be
    # diagnosed after the fact instead of vanishing with $TMPDIR.
    collectLogs() {
      local from="$1"
      local to="$2"
      mkdir -p "$to"
      find "$from" -type f -exec cp -a {} "$to/" \; 2>/dev/null || true
    }

    runInstaller() {
      local kit="$1"
      local components="$2"
      local label="$3"
      local logdir="$TMPDIR/intel-logs/$label"

      rm -rf "$HOME/intel" "$logdir"
      mkdir -p "$logdir"

      echo "=== installing $label: $components ==="
      # Driving the media .sh with -a is enough: the wrapper extracts itself and
      # the bootstrapper finds its own packages/ directory. No -x + --package-path
      # dance is needed (and a wrong --package-path silently falls back to the
      # network). --download-cache is left at its default so payloads are copied
      # out of the local packages/ dir into $HOME.
      if ! oneapi-2024-installer-shell -c '
        set -eu
        bash "$1" -a --silent --eula accept \
          --components "$2" \
          --install-dir "$3" \
          --log-dir "$4"
      ' _ "$kit" "$components" "$out" "$logdir"; then
        # A failed build discards $out, so the only way to keep the rollback
        # logs is to put them on stderr, where `nix log` retains them.
        echo "oneAPI installer failed for $label; full installer logs follow" >&2
        find "$logdir" -type f | sort | while read -r f; do
          echo "===== $f =====" >&2
          cat "$f" >&2 || true
        done
        exit 1
      fi
      if [ ${if keepInstallLogs then "1" else "0"} = 1 ]; then
        collectLogs "$logdir" "$out/share/oneapi-install-logs/$label"
      fi
      rm -rf "$HOME/intel"
    }

    ${lib.concatMapStrings (kit: ''
      runInstaller ${kit.media} "${lib.concatStringsSep ":" kit.components}" "${
        if kit.media == baseKitMedia then "basekit" else "hpckit"
      }"
    '') kits}

    # The installer leaves its own bookkeeping behind; keep the tree clean.
    rm -rf "$out"/logs "$out"/.toolkit_linking_tool

    # MSC Marc's include_linux64 looks for the compiler at
    # compiler/latest/linux/bin/ifort, which 2024.2 does not create.
    if [ -d "$out/compiler/${oneapiYear}.${oneapiMinor}" ]; then
      ln -sfn ${oneapiYear}.${oneapiMinor} "$out/compiler/latest"
    fi
    if [ -d "$out/compiler/latest/bin" ]; then
      mkdir -p "$out/compiler/latest/linux/bin/intel64"
      for tool in ifort ifx icx icpx icc; do
        if [ -x "$out/compiler/latest/bin/$tool" ]; then
          ln -sfn ../../bin/$tool "$out/compiler/latest/linux/bin/$tool"
          ln -sfn ../../../bin/$tool "$out/compiler/latest/linux/bin/intel64/$tool"
        fi
      done
    fi

    # --- verification -----------------------------------------------------
    test -x "$out/compiler/latest/bin/ifort"
    test -x "$out/compiler/latest/linux/bin/intel64/ifort"

    cat > "$TMPDIR/hello.f90" <<'EOF'
program hello
  implicit none
  integer :: i
  real(8) :: x
  x = 0.0d0
  do i = 1, 10
    x = x + real(i, 8)**2
  end do
  print '(A,F10.1)', 'sum of squares 1..10 = ', x
end program hello
EOF

    oneapi-2024-installer-shell -c '
      set -eu
      export ONEAPI_ROOT="$1"
      export SETVARS_COMPLETED=0
      set +u
      . "$1/setvars.sh" --force >/dev/null
      set -u
      echo "--- ifort -V ---"
      ifort -V
      echo "--- minimal Fortran build ---"
      ifort -O2 -qopenmp -diag-disable=10448 "$2/hello.f90" -o "$2/hello"
      "$2/hello" | tee "$2/hello.out"
      grep -q "385.0" "$2/hello.out"
    ' _ "$out" "$TMPDIR"

    runHook postInstall
  '';

  meta = {
    description = "Intel oneAPI 2024.2 HPC Toolkit (classic ifort) for MSC Marc";
    homepage = "https://www.intel.com/content/www/us/en/developer/tools/oneapi/toolkits.html";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
  };
}
