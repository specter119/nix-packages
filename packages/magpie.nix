{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  gtk3,
  webkitgtk_4_1,
}:

stdenvNoCC.mkDerivation {
  pname = "magpie";
  version = "0.1.410";

  src = fetchurl {
    url = "https://github.com/yetone/magpie-releases/releases/download/v0.1.410/magpie-linux-amd64";
    hash = "sha256-+3KPiboQOWK/i0U1lyRKhWbcP6+WSjZRG8vLkj3uwOQ=";
  };

  dontUnpack = true;
  dontBuild = true;

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [
    gtk3
    webkitgtk_4_1
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/magpie"
    mkdir -p "$out/share/applications"
    cat > "$out/share/applications/magpie.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=magpie
Comment=Every agent's model. One place.
Exec=nixGL $out/bin/magpie %u
TryExec=nixGL
Icon=magpie
Categories=Development;Utility;
MimeType=x-scheme-handler/magpie;
Terminal=false
EOF
    runHook postInstall
  '';

  meta = {
    description = "Desktop app and CLI for managing AI agent models and sessions";
    homepage = "https://usemagpie.ai";
    license = lib.licenses.mit;
    mainProgram = "magpie";
    platforms = [ "x86_64-linux" ];
  };
}
