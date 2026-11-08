{
  lib,
  stdenvNoCC,
  requireFile,
  buildFHSEnv,
  writeShellScript,
  writeTextFile,
  libarchive,
  gnutar,
  gzip,
  jdk8,
  version ? "2024",
}:

let
  releases = {
    "6.14-5" = {
      name = "ABAQUS_6.14-5_Win_Linux_x64.iso";
      hash = "sha256-cAEkNdXyTPRs2v1jZk64foUE+MzcjEe9KfNv9fjzWg8=";
      command = "abq6145";
    };
    "2022" = {
      name = "DS.SIMULIA.Suite.2022.Linux64.iso";
      hash = "sha256-uFaOBqXJnL+mnMHJo4reaPDAMAGwPSFWz/tzLpwT9pA=";
      command = "abq2022";
    };
    "2024" = {
      name = "DS.SIMULIA.SUITE.2024.LINX64.tar.gz";
      hash = "sha256-zbsyY8bpB474HySjG58Dtq51vZ4hcEedmy+D7pE0Gtk=";
      command = "abq2024";
    };
  };
  release = releases.${version} or (throw "Unsupported Abaqus version: ${version}");
  isLegacy = version == "6.14-5";
  media = requireFile {
    inherit (release) name hash;
    message = ''
      Abaqus installation media is not redistributable. Add the original media with:
        nix-store --add-fixed sha256 /path/to/${release.name}
    '';
  };

  # Abaqus 2022's installer rejects NixOS when lsb_release reports n/a.
  # Limit this compatibility response to the installation environment.
  lsbReleaseStub = writeTextFile {
    name = "abaqus-installer-lsb-release";
    destination = "/bin/lsb_release";
    executable = true;
    text = ''
      #!/bin/sh
      case "$*" in
        *-si*|*--id*) echo RedHatEnterprise ;;
        *-sd*|*--description*) echo 'Red Hat Enterprise Linux release 8.6 (Ootpa)' ;;
        *-sc*|*--codename*) echo Ootpa ;;
        *) echo 8.6 ;;
      esac
    '';
  };
  # The vendor installers and applications expect a conventional Linux root.
  mkEnv = name: runScript: buildFHSEnv {
    inherit name runScript;
    targetPkgs = pkgs: with pkgs; [
      bash coreutils findutils gawk gnugrep gnused which hostname procps
      util-linux ksh tcsh jdk8 perl zlib libxcrypt-legacy libuuid ncurses5
      stdenv.cc.cc.lib libGL libGLU libx11 libxext libxrender libxtst
      libxi libxrandr libxcursor libxfixes libxcomposite libxdamage
      libxxf86vm libxcb fontconfig freetype glib gtk3 motif
      libjpeg_turbo libpng mesa binutils
    ] ++ lib.optionals (name == "abaqus-installer-shell" && version == "2022") [ lsbReleaseStub ]
      ++ lib.optionals (version == "2024") [ pkgs.file pkgs.libnsl pkgs.lsb-release ];
  };
  installer = mkEnv "abaqus-installer-shell" "bash";
  unwrapped = stdenvNoCC.mkDerivation {
    pname = "abaqus-unwrapped";
    inherit version;
    src = media;
    nativeBuildInputs = [ libarchive gnutar gzip installer ];
    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;
    dontFixup = true;
    installPhase = ''
      runHook preInstall
      mkdir -p "$TMPDIR/media" "$out"
      cd "$TMPDIR/media"
      ${if isLegacy then ''
        bsdtar -xf "$src" --exclude '*/license/*' --exclude 'DSLS/*'
        chmod -R u+rwx .
        sed "s|^USER_INSTALL_DIR=.*|USER_INSTALL_DIR=$out/opt/DassaultSystemes/SIMULIA/EstProducts|" \
          ${./6145/installer.properties} > "$TMPDIR/installer.properties"
        export LANG=C.UTF-8 DSYAuthOS_Arch=1 DSY_Force_OS=linux_a64 IA_DVD_SETUP=true
        abaqus-installer-shell -c 'tcsh "$1/lnx86_64/setup" -jre ${jdk8} -replay "$2"' \
          _ "$PWD" "$TMPDIR/installer.properties"
        test -x "$out/opt/DassaultSystemes/SIMULIA/EstProducts/6.14-5/code/bin/abq6145"
      '' else ''
        ${if version == "2022" then "bsdtar -xf" else "tar -xzf"} "$src" \
          ${if version == "2022" then "4/SIMULIA_EstablishedProducts 5/SIMULIA_EstablishedProducts/Linux64/2 5/SIMULIA_EstablishedProducts_CAA_API" else "5/SIMULIA_EstablishedProducts 6/SIMULIA_EstablishedProducts/Linux64/2 6/SIMULIA_EstablishedProducts_CAA_API"}
        ${lib.optionalString (version == "2022") ''
          # The installer expects both ISO volumes in the same Linux64 directory.
          mv 5/SIMULIA_EstablishedProducts/Linux64/2 4/SIMULIA_EstablishedProducts/Linux64/2
          chmod -R u+rwX,a+rX .
          find . -type f -exec chmod u+x {} +
        ''}
        ${lib.optionalString (version == "2024") ''
          # The second product volume is stored under disc 6.
          mv 6/SIMULIA_EstablishedProducts/Linux64/2 5/SIMULIA_EstablishedProducts/Linux64/2
        ''}
        for f in ${if version == "2022" then ./2022 else ./2024}/UserIntentions_*.xml; do
          sed -e "/name=\"commandsDir\"/s|value=\"/|value=\"$out/|" \
              -e "/name=\"pluginsDir\"/s|value=\"/|value=\"$out/|" \
              -e "/name=\"TARGET_PATH\"/s|value=\"/|value=\"$out/|" \
              "$f" > "$TMPDIR/$(basename "$f")"
        done
        export LANG=C.UTF-8 DSYAuthOS_Arch=1 DSY_Force_OS=linux_a64 NOLICENSECHECK=true${lib.optionalString (version == "2024") " DSY_Skip_CheckPrereq=1 DSY_IgnoreError_CheckPrereq=1"}
        abaqus-installer-shell -c 'sh "$1" --silent "$2"' _ \
          "$PWD/${if version == "2022" then "4" else "5"}/SIMULIA_EstablishedProducts/Linux64/1/StartTUI.sh" "$TMPDIR/UserIntentions_CODE.xml"
        abaqus-installer-shell -c 'sh "$1" --silent "$2"' _ \
          "$PWD/${if version == "2022" then "5" else "6"}/SIMULIA_EstablishedProducts_CAA_API/Linux64/1/StartTUI.sh" "$TMPDIR/UserIntentions_CAA_Additional_${if version == "2022" then "424" else "426"}.xml"
        test -x "$out/opt/DassaultSystemes/SIMULIA/EstProducts/${version}/linux_a64/code/bin/SMALauncher"
      ''}
      runHook postInstall
    '';
    meta.license = lib.licenses.unfree;
  };
  executable = if isLegacy then
    "${unwrapped}/opt/DassaultSystemes/SIMULIA/EstProducts/6.14-5/code/bin/abq6145"
  else
    "${unwrapped}/opt/DassaultSystemes/SIMULIA/EstProducts/${version}/linux_a64/code/bin/SMALauncher";
  run = writeShellScript "abaqus-run" ''
    exec ${executable} "$@"
  '';
in
(mkEnv release.command run).overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    inherit unwrapped;
    shell = mkEnv "${release.command}-shell" "bash";
  };
  meta = (old.meta or { }) // {
    description = "Abaqus finite element analysis software ${version}";
    homepage = "https://www.3ds.com/products/simulia/abaqus";
    license = lib.licenses.unfree;
    mainProgram = release.command;
    platforms = [ "x86_64-linux" ];
  };
})
