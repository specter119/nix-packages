{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  dpkg,
  bash,
  alsa-lib,
  at-spi2-core,
  gtk3,
  libnotify,
  libsecret,
  libgbm,
  libXScrnSaver,
  libXtst,
  nss,
  util-linux,
  xdg-utils,
}:

stdenvNoCC.mkDerivation {
  pname = "lody-desktop";
  version = "0.104.0";

  src = fetchurl {
    url = "https://updates.lody.ai/production/Lody-0.104.0-amd64.deb";
    hash = "sha256-XczMk9D5+jHYXN9uJGKe/BQVdZCfFJwFz2PlRSxZH/c=";
  };

  dontUnpack = true;
  dontBuild = true;

  nativeBuildInputs = [
    autoPatchelfHook
    dpkg
  ];

  buildInputs = [
    alsa-lib
    at-spi2-core
    gtk3
    libnotify
    libsecret
    libgbm
    libXScrnSaver
    libXtst
    nss
    util-linux
  ];

  installPhase = ''
    runHook preInstall

    dpkg-deb -x "$src" "$out"
    mv "$out/usr/share" "$out/share"
    rmdir "$out/usr"

    # Electron uses xdg-open for shell.openExternal() on Linux.  A Nix
    # dependency does not add its binaries to PATH, so the wrapper below
    # makes xdg-open and xdg-mime available to the app and to its auth flow.
    install -d "$out/bin"
    cat > "$out/bin/lody" <<'EOF'
#!${bash}/bin/bash
set -euo pipefail

flags_file="''${XDG_CONFIG_HOME:-$HOME/.config}/lody-flags.conf"
flags=()
if [[ -r "$flags_file" ]]; then
  while IFS= read -r flag || [[ -n "$flag" ]]; do
    [[ -z "$flag" || "$flag" == \#* ]] && continue
    flags+=("$flag")
  done < "$flags_file"
fi

export PATH="${xdg-utils}/bin''${PATH:+:$PATH}"

# Keep the lody:// callback as argv[1] so Electron can handle a cold-start
# deep link even when optional Chromium flags are configured.
if (( $# > 0 )) && [[ "$1" == lody://* ]]; then
  exec "${placeholder "out"}/opt/Lody/lodyDesktop" "$@" "''${flags[@]}"
else
  exec "${placeholder "out"}/opt/Lody/lodyDesktop" "''${flags[@]}" "$@"
fi
EOF
    chmod 0755 "$out/bin/lody"

    desktop_file="$out/share/applications/ai.lody.desktop.desktop"
    substituteInPlace "$desktop_file" \
      --replace-fail '/opt/Lody/lodyDesktop' "$out/bin/lody" \
      --replace-fail 'Icon=lodyDesktop' 'Icon=lody'

    mv "$out/share/icons/hicolor/512x512/apps/lodyDesktop.png" \
      "$out/share/icons/hicolor/512x512/apps/lody.png"

    rm -rf "$out/share/doc"

    install -Dm644 "$out/opt/Lody/LICENSE.electron.txt" \
      "$out/share/licenses/$pname/LICENSE.electron.txt"
    install -Dm644 "$out/opt/Lody/LICENSES.chromium.html" \
      "$out/share/licenses/$pname/LICENSES.chromium.html"

    runHook postInstall
  '';

  meta = {
    description = "Development platform for parallel AI agent workflows";
    homepage = "https://lody.ai";
    license = lib.licenses.unfree;
    mainProgram = "lody";
    platforms = [ "x86_64-linux" ];
  };
}
