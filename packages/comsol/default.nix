{
  lib,
  stdenvNoCC,
  requireFile,
  libarchive,
  gnutar,
  xz,
  findutils,
  buildFHSEnv,
  writeShellScript,
  mesa,
}:

let
  mesaOpencl = mesa.opencl;

  version = "6.4.0.293";
  isoName = "COMSOL_Multiphysics_${version}.iso";

  # Archives in the DVD that are not needed on x86_64 Linux, plus the CUDA
  # runtimes (no NVIDIA GPU here), COMSOL Server and the installer's own files.
  # Platform-neutral and *_maclnx archives are kept.
  excludeRegex = lib.concatStringsSep "|" [
    "(win64|maci64|macarm64|macosx|glnxarm64|_ckl_|_nockl_)"
    "^(server_|flserver|clusterserver)"
    "^ll_(ac|creop|inv|revit|se|sw|excel)"
    "^(fl_cud|fl_dnncuda)"
    "^(fl_setup|runtime_installer_base)"
    "^ja_JP"
  ];

  unwrapped = stdenvNoCC.mkDerivation {
    pname = "comsol-unwrapped";
    inherit version;

    src = requireFile {
      name = isoName;
      hash = "sha256-LMh4GIqZP5vjJBEZOTEtwdv1QmSPndXH405B6IFntFg=";
      message = ''
        COMSOL is not redistributable. Put the COMSOL Multiphysics ${version}
        installation DVD image in the Nix store with:

          nix-store --add-fixed sha256 /path/to/${isoName}
      '';
    };

    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;
    # About 20 GB of prebuilt files; patching or stripping them is pointless here.
    dontFixup = true;

    nativeBuildInputs = [
      libarchive
      gnutar
      xz
      findutils
    ];

    installPhase = ''
      runHook preInstall

      mkdir -p "$out"
      cd "$out"

      # The DVD keeps each component as an xz-compressed tar in archives/*.isa.
      # --no-same-permissions keeps directories writable while archives that
      # share directories are unpacked in parallel.
      bsdtar -tf "$src" 'archives/*.isa' \
        | sed -E 's#^archives/##; s#\.isa$##' \
        | grep -Ev '${excludeRegex}' \
        | sort > "$TMPDIR/archives"
      echo "unpacking $(wc -l < "$TMPDIR/archives") archives"

      xargs -a "$TMPDIR/archives" -P "$NIX_BUILD_CORES" -I{} \
        bash -o pipefail -c \
          'bsdtar -xOf "$1" "archives/$2.isa" | xz -dc | tar -x --no-same-owner --no-same-permissions' \
          _ "$src" {}

      bsdtar -xOf "$src" bin/glnxa64/comsol.png \
        | install -Dm644 /dev/stdin share/icons/hicolor/512x512/apps/comsol.png

      runHook postInstall
    '';

    meta.license = lib.licenses.unfree;
  };

  mkFhsEnv =
    {
      name,
      runScript,
      extraInstallCommands ? "",
    }:
    buildFHSEnv {
      inherit name runScript extraInstallCommands;
      inherit version;

      targetPkgs =
        pkgs: with pkgs; [
          # COMSOL's launcher scripts and the Java/SWT desktop.
          bash
          coreutils
          findutils
          gawk
          gnugrep
          gnused
          hostname
          procps
          util-linux
          which
          glib
          gtk3
          gdk-pixbuf
          cairo
          pango
          at-spi2-core
          dbus
          fontconfig
          freetype
          libxkbcommon
          alsa-lib
          nss
          nspr
          cups
          # Native solver, graphics and MPI libraries shipped by COMSOL link
          # against these.
          zlib
          libxcrypt-legacy
          libuuid
          expat
          ncurses5
          openssl
          krb5
          stdenv.cc.cc.lib
          libGL
          libGLU
          # The host's Mesa lives in /usr/lib, which the FHS root hides, so
          # ship the GL/EGL drivers (radeonsi, iris, llvmpipe) with the env.
          mesa
          mesa.opencl
          libglvnd
          ocl-icd
          libx11
          libxext
          libxrender
          libxtst
          libxi
          libxrandr
          libxcursor
          libxfixes
          libxcomposite
          libxdamage
          libxxf86vm
          libxcb
          libdrm
          # Intel MPI (ext/impi) loads its fabric providers against these.
          numactl
          hwloc
          rdma-core
        ];
    };

  comsolRun = writeShellScript "comsol-run" ''
    # Keep a license the user already points at; otherwise read the license
    # from the user's config directory. COMSOL's own default would be inside
    # the read-only store.
    if [ -z "''${LMCOMSOL_LICENSE_FILE:-}" ]; then
      export LMCOMSOL_LICENSE_FILE="''${XDG_CONFIG_HOME:-$HOME/.config}/comsol/license.dat"
    fi

    # Mesa's OpenCL (rusticl) is off by default and needs naming the driver.
    # The ICD file sits in the store, not in the FHS root's /etc.
    export OCL_ICD_VENDORS="''${OCL_ICD_VENDORS:-${mesaOpencl}/etc/OpenCL/vendors}"
    export RUSTICL_ENABLE="''${RUSTICL_ENABLE:-radeonsi}"
    exec ${unwrapped}/bin/comsol "$@"
  '';
in
(mkFhsEnv {
  name = "comsol";
  runScript = comsolRun;
  extraInstallCommands = ''
    install -Dm644 ${unwrapped}/share/icons/hicolor/512x512/apps/comsol.png \
      "$out/share/icons/hicolor/512x512/apps/comsol.png"
    mkdir -p "$out/share/applications"
    cat > "$out/share/applications/comsol.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=COMSOL Multiphysics
Comment=Multiphysics simulation software
Exec=$out/bin/comsol %f
Icon=comsol
Categories=Education;Science;Engineering;
Terminal=false
EOF
  '';
}).overrideAttrs
  (old: {
    passthru = (old.passthru or { }) // {
      inherit unwrapped;
      # Same environment with a shell, for finding missing libraries.
      shell = mkFhsEnv {
        name = "comsol-shell";
        runScript = "bash";
      };
    };

    meta = (old.meta or { }) // {
      description = "COMSOL Multiphysics finite element simulation software";
      homepage = "https://www.comsol.com";
      license = lib.licenses.unfree;
      mainProgram = "comsol";
      platforms = [ "x86_64-linux" ];
    };
  })
