{
  lib,
  stdenv,
  stdenvNoCC,
  requireFile,
  fetchurl,
  buildFHSEnv,
  writeShellScript,
  python3,
  autoPatchelfHook,
  bubblewrap,
  ncurses5,
  bc,
  writableTmpDirAsHomeHook,
  gnumake,
  gnutar,
  gzip,
  binutils,
  gcc,
  file,
  gnused,
  gnugrep,
  gawk,
  coreutils,
  findutils,
  patch,
  ksh,
  which,
  zlib,
  libxcrypt-legacy,
  libgcc,
  glibc,
  bash,
  rdma-core,
  libpsm2,
  ucx,
  numactl,
  level-zero,
  libuuid,
  libffi,
  # Components installed from l_HPCKit. `intel.oneapi.lin.ifort-compiler`
  # provides ifort/ifx, `intel.oneapi.lin.dpcpp-cpp-compiler` provides
  # icx/icpx (needed by the HDF5 build below) plus the TBB/DPL runtime.
  hpckitComponents ? [
    "intel.oneapi.lin.ifort-compiler"
    "intel.oneapi.lin.dpcpp-cpp-compiler"
  ],
  # Empty by default: BaseKit is not needed for a Fortran-only toolchain.
  # Marc ships its own MKL in lib_shared/linux64 (getarch sets
  # MARC_MKL=$MARC_LIB_SHARED), so oneAPI MKL is not required. Example if that
  # ever changes: [ "intel.oneapi.lin.mkl.devel" ].
  baseKitComponents ? [ ],
}:

let
  version = "2024.2";
  damaskVersion = "3.0.2";
  hdf5Version = "1.14.6";
  oneapiYear = "2024";
  oneapiMinor = "2";
  oneapiPatch = "0";
  oneapiVersion = "${oneapiYear}.${oneapiMinor}.${oneapiPatch}";

  mediaMsg = name: ''
    Licensed ${name} is not redistributable. Add the original file with:
      nix-store --add-fixed sha256 /path/to/${name}
  '';

  marcMedia = requireFile {
    name = "marc_2024.2_linux64.tar_a.gz";
    hash = "sha256-ob1o8dvUsyb2sv4WMB4p/9Roaoaf3HEoInmVYc82NPI=";
    message = mediaMsg "marc_2024.2_linux64.tar_a.gz";
  };
  marcDocMedia = requireFile {
    name = "marc_2024.2_linux_doc.tar.gz";
    hash = "sha256-1N2ISQ4i2dHTk05k7MgXybdZ1ACsz9zPLUcIPpUjJI0=";
    message = mediaMsg "marc_2024.2_linux_doc.tar.gz";
  };
  baseKitMedia = requireFile {
    name = "l_BaseKit_p_2024.2.0.634_offline.sh";
    hash = "sha256-rpfxtxRvYQwHIy11ysjTf2spmN9BZBG++an2ydI1kaQ=";
    message = mediaMsg "l_BaseKit_p_2024.2.0.634_offline.sh";
  };
  hpcKitMedia = requireFile {
    name = "l_HPCKit_p_2024.2.0.635_offline.sh";
    hash = "sha256-RXoWOZC5GSJ4MmV+QHJEF1QUhPXe8UkaaAN0cA02xSA=";
    message = mediaMsg "l_HPCKit_p_2024.2.0.635_offline.sh";
  };

  hdf5Src = fetchurl {
    url = "https://github.com/HDFGroup/hdf5/releases/download/hdf5_${hdf5Version}/hdf5-${hdf5Version}.tar.gz";
    hash = "sha256-5N77rDD1DWThVWN0qknldEF8nnLGsd56T/iMSxvqbps=";
  };
  damaskSrc = fetchurl {
    url = "https://github.com/damask-multiphysics/DAMASK/archive/refs/tags/v${damaskVersion}.tar.gz";
    hash = "sha256-bbussIk4AKM/T+vDaxZIo4LQKIGOxiPQmbeVPQ0CnJo=";
  };

  oneapiRuntimeLibs = [
    zlib
    rdma-core
    libpsm2
    ucx
    libuuid
    numactl
    level-zero
    libffi
    ncurses5
    libxcrypt-legacy
  ];

  # Current flake nixpkgs ships oneAPI 2026 without classic ifort. Pin 2024.2
  # from the offline kits instead of changing flake.lock: HPCKit must land in
  # the same prefix as BaseKit. Marc's include_linux64 looks for
  # /opt/intel/oneapi/compiler/latest/linux/bin/ifort, while 2024.2 ships
  # ifort at compiler/2024.2/bin/ifort.
  #
  # `--components all` cannot work offline: it pulls
  # intel.oneapi.lin.compiler.fpga, whose 298 MB cupPayload.cup is *not* in the
  # offline kit, so the installer tries to download it and aborts with
  # "Cannot establish internet connection". `--components default` is no
  # workaround either: the BaseKit default set needs ~20.7 GB and fails the
  # disk-space prerequisite. An explicit component list installs only local
  # payloads, so the CDN probe never has to succeed and no __noChroot is
  # needed.
  #
  # Driving the media .sh with -a is enough: the wrapper extracts itself and
  # the bootstrapper finds its own packages/ directory. A separate -x
  # --extract-folder pass plus --package-path/--download-cache only adds a
  # second extraction of a multi-GB kit and silently falls back to the network
  # when the paths are off. Keep HOME inside $TMPDIR: the installer writes
  # ~/intel and must not touch the user's home or license files. Runtime stays
  # in the Marc FHS env, so skip patchelf of the 3G tree.
  oneapiKits =
    lib.optional (baseKitComponents != [ ]) {
      media = baseKitMedia;
      components = baseKitComponents;
      label = "basekit";
    }
    ++ [
      {
        media = hpcKitMedia;
        components = hpckitComponents;
        label = "hpckit";
      }
    ];

  oneapi = stdenv.mkDerivation {
    pname = "intel-oneapi-hpckit";
    version = oneapiVersion;
    dontUnpack = true;
    dontPatchELF = true;
    dontStrip = true;
    # Intel's prebuilt MPI binaries carry a baked-in RPATH element
    # /build/impi/_install/intel64/lib (Intel's own build path) that collides
    # with Nix's $TMPDIR=/build, so the fixup audit treats it as a security bug
    # and fails the build. The tree is only ever consumed through the Marc FHS
    # env, so skip the audit.
    noAuditTmpdir = true;
    nativeBuildInputs = [
      installerEnv
      writableTmpDirAsHomeHook
    ];
    installPhase = ''
      runHook preInstall
      mkdir -p "$out" "$TMPDIR/intel-home" "$TMPDIR/intel-logs"
      export HOME="$TMPDIR/intel-home"
      runInstaller() {
        local kit="$1"
        local components="$2"
        local label="$3"
        local logdir="$TMPDIR/intel-logs/$label"
        rm -rf "$HOME/intel" "$logdir"
        mkdir -p "$logdir"
        echo "=== installing $label: $components ==="
        if ! msc-marc-installer-shell -c '
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
        rm -rf "$HOME/intel"
      }
      ${lib.concatMapStrings (kit: ''
        runInstaller ${kit.media} "${lib.concatStringsSep ":" kit.components}" "${kit.label}"
      '') oneapiKits}
      rm -rf "$out"/logs "$out"/.toolkit_linking_tool
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
      test -x "$out/compiler/latest/bin/ifort"
      msc-marc-installer-shell -c 'set -eu; "$1" -V' _ "$out/compiler/latest/bin/ifort"
      runHook postInstall
    '';
    meta.license = lib.licenses.unfree;
  };

  fhsPkgs =
    pkgs: with pkgs; [
      bash
      coreutils
      findutils
      gawk
      gnugrep
      gnused
      gnutar
      gzip
      file
      hostname
      ksh
      procps
      util-linux
      which
      zlib
      libxcrypt-legacy
      stdenv.cc.cc.lib
      libGL
      libGLU
      mesa
      libx11
      libxext
      libxmu
      libxi
      libxt
      libxrender
      libxcb
      fontconfig
      freetype
      ncurses5
      openssl
      numactl
      python3
      gnumake
      patch
      bc
      # icx/ifort/icpx are compiler drivers only: they exec the system linker
      # and need gcc's crtbegin*.o plus the glibc headers. Without these,
      # HDF5's configure dies with "C compiler cannot create executables"
      # (icx: Executable "ld" doesn't exist! / crtbeginS.o not found /
      # stdio.h not found), and Marc's comp_user cannot build user
      # subroutines either. gcc.cc is the unwrapped compiler because the gcc
      # wrapper's lib dir has no crtbeginS.o for icx to find.
      binutils
      gcc.cc
      glibc.dev
    ];

  mkEnv =
    name: runScript:
    extraBwrapArgs:
    buildFHSEnv {
      inherit name runScript extraBwrapArgs version;
      targetPkgs = fhsPkgs;
    };

  installerEnv = mkEnv "msc-marc-installer-shell" "bash" [ ];



  unwrapped = stdenvNoCC.mkDerivation {
    pname = "msc-marc-unwrapped";
    inherit version;
    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;
    dontFixup = true;
    nativeBuildInputs = [
      installerEnv
      gnutar
      gzip
      python3
      patch
      gnused
      gnugrep
      gawk
      coreutils
      findutils
      file
      gnumake
    ];
    installPhase = ''
      runHook preInstall
      export HOME="$TMPDIR/home"
      mkdir -p "$HOME" "$out" "$TMPDIR/media" "$TMPDIR/damask" "$TMPDIR/hdf5-src"

      tar -xzf ${marcMedia} -C "$TMPDIR/media"
      tar -xzf ${marcDocMedia} -C "$TMPDIR/media"
      tar -xzf ${damaskSrc} -C "$TMPDIR/damask"
      tar -xzf ${hdf5Src} -C "$TMPDIR/hdf5-src"

      chmod -R u+w "$TMPDIR/media"
      msc-marc-installer-shell -c '
        set -eu
        cd "$1"
        chmod +x install.exe utils/*
        ./install.exe -a -i "$2"
        tar -xzf products/common2.gui -C "$2" --no-same-owner --no-same-permissions
        tar -xzf products/common3.gui -C "$2" --no-same-owner --no-same-permissions
      ' _ "$TMPDIR/media" "$out"

      test -f "$out/marc${version}/tools/run_marc"
      test -f "$out/mentat${version}/bin/mentat"

      include="$out/marc${version}/tools/include_linux64"
      if [ -f "$include" ]; then
        sed -i "s|MEMLIMIT=\`free -m|MEMLIMIT=\`LANG=C free -m|g" "$include"
      fi

      # Apply DAMASK patches without compiling Mentat menus (needs a license).
      export MARC_VERSION="${version}"
      export DAMASK_SRC="$TMPDIR/damask/DAMASK-${damaskVersion}"
      python3 - <<'PY'
import glob, os, shutil, subprocess
from pathlib import Path
marc_root = Path(os.environ["out"])
marc_version = os.environ["MARC_VERSION"]
damask_root = Path(os.environ["DAMASK_SRC"])
matches = {
  "Marc_tools": [["comp_user","comp_damask_*mp"],["run_marc","run_damask_*mp"],["include_linux64","include_linux64"]],
  "Mentat_bin": [["edit_window","edit_window"],["submit1","submit?"],["kill1","kill?"]],
  "Mentat_menus": [["job_run.ms","job_run.ms"]],
}
for directory in glob.glob(str(damask_root/"install/MarcMentat"/marc_version/"*")):
    for orig, mods in matches[Path(directory).name]:
        product, subfolder = Path(directory).name.split("_")
        orig_path = marc_root/f"{product.lower()}{marc_version}/{subfolder}/{orig}"
        for patch_file in glob.glob(f"{directory}/{mods}.patch"):
            dest = orig_path.parent/Path(patch_file).stem
            try:
                shutil.copyfile(orig_path, dest)
            except shutil.SameFileError:
                pass
            subprocess.run(["patch", str(dest), patch_file, "--backup", "--forward"], check=False)
            text = dest.read_text(errors="replace").replace("%EDITOR%", "vi")
            dest.write_text(text)
PY

      patch -d "$out" -Np0 -i ${./include_linux64-fallback.patch}

      for file in "$out/mentat${version}/bin"/{encrypt_umt,run_quasar,run_fmu_builder,submit{1,2,3},submit{4,5,6}{,.orig}}; do
        if [ -f "$file" ]; then
          sed -i "s|$NIX_BUILD_TOP||g; s|$out|/opt/MSC.Software|g" "$file" || true
        fi
      done

      # HDF5 lives at $out/hdf5 in the store and at /opt/MSC.Software/hdf5 in the FHS env.
      msc-marc-installer-shell -c '
        set -eu
        export ONEAPI_ROOT="$1"
        export SETVARS_COMPLETED=0
        set +u
        . "$1/setvars.sh" --force >/dev/null
        set -u
        cd "$2/hdf5-$3"
        export FC=ifort CC=icx CXX=icpx
        export FCFLAGS="-fPIC -integer-size 64 -real-size 64 -qopenmp"
        export CFLAGS="-fPIC -qopenmp"
        export LDFLAGS="-Wl,--no-as-needed"
        ./configure --disable-parallel --enable-hl --enable-fortran --enable-fortran2003 \
          --enable-build-mode=production --disable-lto --prefix="$4/hdf5"
        make -j"$NIX_BUILD_CORES"
        make install
      ' _ "${oneapi}" "$TMPDIR/hdf5-src" "${hdf5Version}" "$out"
      test -x "$out/hdf5/bin/h5fc"

      mkdir -p "$out/damask"
      cp -a "$TMPDIR/damask/DAMASK-${damaskVersion}/." "$out/damask/"
      chmod -R u+w "$out/damask"
      find "$out/marc${version}/tools" "$out/mentat${version}/bin" \( -name "*_damask*" -o -name "submit[4-6]*" -o -name "kill[4-6]*" \) | while read -r f; do
        chmod +x "$f" || true
      done

      runHook postInstall
    '';
    meta.license = lib.licenses.unfree;
  };

  extraBwrap = [
    "--ro-bind"
    "${oneapi}"
    "/opt/intel/oneapi"
    "--ro-bind"
    "${unwrapped}"
    "/opt/MSC.Software"
  ];

  run = writeShellScript "msc-marc-run" ''
    export ONEAPI_ROOT=/opt/intel/oneapi
    if [ -f /opt/intel/oneapi/setvars.sh ]; then
      set +u
      . /opt/intel/oneapi/setvars.sh --force >/dev/null 2>&1 || true
      set -u
    fi
    export PATH=/opt/MSC.Software/hdf5/bin:/opt/intel/oneapi/compiler/latest/bin:/opt/intel/oneapi/compiler/latest/linux/bin:$PATH
    export LM_LICENSE_FILE="''${LM_LICENSE_FILE:-27500@localhost}"
    export QT_QPA_PLATFORM="''${QT_QPA_PLATFORM:-xcb}"
    case "''${1:-}" in
      --mentat) shift; exec /opt/MSC.Software/mentat${version}/bin/mentat "$@" ;;
      --shell) shift; exec bash "$@" ;;
      *) exec /opt/MSC.Software/marc${version}/tools/run_marc "$@" ;;
    esac
  '';
in
(mkEnv "msc-marc" run extraBwrap).overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    inherit unwrapped oneapi;
    hdf5 = "${unwrapped}/hdf5";
    damask = "${unwrapped}/damask";
    shell = mkEnv "msc-marc-shell" "bash" extraBwrap;
  };
  meta = (old.meta or { }) // {
    description = "MSC Marc/Mentat 2024.2 with DAMASK 3.0.2 and Intel oneAPI 2024.2 ifort/HDF5";
    homepage = "https://www.hexagon.com/products/marc";
    license = lib.licenses.unfree;
    mainProgram = "msc-marc";
    platforms = [ "x86_64-linux" ];
  };
})
