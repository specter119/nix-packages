{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  dpkg,
  makeWrapper,
  alsa-lib,
  at-spi2-core,
  cairo,
  cups,
  dbus,
  expat,
  glib,
  gtk3,
  libgbm,
  libglvnd,
  libnotify,
  libpulseaudio,
  libsecret,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxkbcommon,
  libxrandr,
  mesa,
  nspr,
  nss,
  pango,
  systemd,
  xdg-utils,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "pokebonk";
  version = "1.4.0";

  src = fetchurl {
    url = "https://github.com/CharcherGit/pokebonk-app/releases/download/v${finalAttrs.version}/PokeBonk-${finalAttrs.version}-linux-amd64.deb";
    hash = "sha256-DIwYPPzIykgiDVRL0o0mz0XIZZSKvX09t2SWZZr2z+k=";
  };

  dontUnpack = true;
  dontBuild = true;

  nativeBuildInputs = [
    autoPatchelfHook
    dpkg
    makeWrapper
  ];

  buildInputs = [
    alsa-lib
    at-spi2-core
    cairo
    cups
    dbus
    expat
    glib
    gtk3
    libgbm
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxkbcommon
    libxrandr
    nspr
    nss
    pango
    (lib.getLib systemd)
  ];

  # Chromium loads these with dlopen(), so they are not in the NEEDED list.
  # They go into the main binary's RUNPATH instead of LD_LIBRARY_PATH, which
  # would leak Nix libraries into child processes such as the host browser.
  runtimeDependencies = map lib.getLib [
    libglvnd
    libnotify
    libpulseaudio
    libsecret
  ];

  installPhase = ''
    runHook preInstall

    dpkg-deb -x "$src" "$out"
    mv "$out/usr/share" "$out/share"
    rmdir "$out/usr"
    rm -rf "$out/share/doc"

    # The upstream directory name is non-ASCII. Rename it before
    # autoPatchelf runs, since RUNPATH entries use the final path.
    mv "$out/opt/PokéBonk" "$out/opt/PokeBonk"

    install -Dm644 "$out/opt/PokeBonk/LICENSE.electron.txt" \
      "$out/share/licenses/$pname/LICENSE.electron.txt"
    install -Dm644 "$out/opt/PokeBonk/LICENSES.chromium.html" \
      "$out/share/licenses/$pname/LICENSES.chromium.html"

    # nixpkgs' libgbm and libglvnd look for drivers and EGL vendor files under
    # /run/opengl-driver, which does not exist outside NixOS. Without
    # __EGL_VENDOR_LIBRARY_DIRS, glvnd would read the host's Mesa vendor file
    # and try to load it into this Nix-glibc process.
    #
    # --use-angle=gl-egl: on X11, ANGLE defaults to GLX, where glvnd's libGLX
    # cannot find libGLX_mesa (dlopen uses the caller's RUNPATH, not ours) and
    # WebGL is unavailable. EGL is already what ANGLE uses on Wayland.
    makeWrapper "$out/opt/PokeBonk/PokeBonk" "$out/bin/pokebonk" \
      --add-flags --use-angle=gl-egl \
      --prefix PATH : ${xdg-utils}/bin \
      --prefix GBM_BACKENDS_PATH : "${mesa}/lib/gbm:/run/opengl-driver/lib/gbm" \
      --prefix LIBGL_DRIVERS_PATH : "${mesa}/lib/dri:/run/opengl-driver/lib/dri" \
      --prefix __EGL_VENDOR_LIBRARY_DIRS : "${mesa}/share/glvnd/egl_vendor.d:/run/opengl-driver/share/glvnd/egl_vendor.d"

    substituteInPlace "$out/share/applications/pokebonk.desktop" \
      --replace-fail '"/opt/PokéBonk/PokeBonk"' "$out/bin/pokebonk"

    runHook postInstall
  '';

  meta = {
    description = "Desktop client for the PokéBonk 3D Pokémon survivor game";
    homepage = "https://github.com/CharcherGit/pokebonk-app";
    license = lib.licenses.unfree;
    mainProgram = "pokebonk";
    platforms = [ "x86_64-linux" ];
  };
})
