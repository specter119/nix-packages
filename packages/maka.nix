{
  lib,
  rustPlatform,
  fetchgit,
  fetchurl,
  fetchNpmDeps,
  npmHooks,
  nodejs_24,
  pkg-config,
  openssl,
  zstd,
  fontconfig,
  freetype,
  libxcb,
  libxkbcommon,
}:

let
  # The Cargo.lock git dependencies come from two repositories; every crate of
  # a repository shares one hash.
  cuaHash = "sha256-kApjskVl2JfyoIFlHrJLiEUTEhQ/M8Kw8jAoOz1IfUw=";
  mxcHash = "sha256-yk/ZeqN0hnpLeTzb2v8Oa+tkKZmdiMgHQ/ZXDrq1H5Q=";

  # Maka's own V8 build, pinned by sha256 in scripts/rust/v8-prebuilts.json of
  # the source. The v8 crate links it through RUSTY_V8_ARCHIVE instead of
  # downloading its own prebuilt.
  v8 = fetchurl {
    url = "https://github.com/apache/maka/releases/download/deps-v8-150.4.0-35e4d3471/v8-x86_64-unknown-linux-gnu-a0f69e4d9fd07e74aef7d310960378f95cb87e3445feeb767633b0a85a050ccc.tar.gz";
    sha256 = "398f2f1e9bbc5fee01889aed30a93b5fbc5132584d2e294491a8825aa5eb9bd4";
  };

  # Branch rust-preview of https://github.com/apache/maka.
  src = fetchgit {
    url = "https://github.com/apache/maka";
    rev = "3f60d59d54525788f16a68e2b8086a658b0263f1";
    hash = "sha256-7vLw0bUVS6oG3IAVKJfojDJ6Qafk1DC5jg4SrPblzWY=";
  };

  # registry.npmjs.org is not reachable from some networks (it is blocked in
  # mainland China). registry.yarnpkg.com serves the same registry, so the
  # fetcher downloads from there; the cache entries stay keyed by the lockfile's
  # original URLs, which is what `npm ci --offline` looks up. Fetcher version 2
  # is needed because the lockfile has workspaces.
  npmDeps = fetchNpmDeps {
    inherit src;
    name = "maka-npm-deps";
    hash = "sha256-u8fe/2Now2kGY3Suz0MYN/0nFp37xELuNzJcevSDVH8=";
    fetcherVersion = 2;
    npmRegistryOverridesString = builtins.toJSON {
      "registry.npmjs.org" = "https://registry.yarnpkg.com";
    };
    # This host's network re-signs HTTPS traffic with a corporate CA that is in
    # the host bundle. Fixed-output builds see that bundle at this path (Nix
    # mounts its `ssl-cert-file` there) but get SSL_CERT_FILE pointing at a
    # missing file, so the fetcher would reject the certificates.
    preBuild = ''
      if [ -e /etc/ssl/certs/ca-certificates.crt ]; then
        export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
      fi
    '';
  };
in
rustPlatform.buildRustPackage {
  pname = "maka";
  version = "0.2.0-unstable-2026-10-28";

  inherit src;

  cargoLock = {
    lockFile = "${src}/Cargo.lock";
    outputHashes = {
      "cua-cursor-motion-0.38.0" = cuaHash;
      "cua-driver-contract-0.38.0" = cuaHash;
      "cua-driver-core-0.38.0" = cuaHash;
      "cua-driver-sdk-0.38.0" = cuaHash;
      "cursor-overlay-0.38.0" = cuaHash;
      "nom-1.2.4" = cuaHash;
      "pip-preview-0.38.0" = cuaHash;
      "platform-linux-0.38.0" = cuaHash;
      "platform-macos-0.38.0" = cuaHash;
      "platform-windows-0.38.0" = cuaHash;
      "mxc-sdk-1.0.1" = mxcHash;
    };
  };

  # WSL scope: the CLI without the Linux desktop driver (Computer Use reaches
  # the Windows desktop through a matching Windows maka.exe, which the user
  # points to at run time with MAKA_CUA_WINDOWS_EXECUTABLE), plus the Python
  # Code Mode worker that must sit beside the executable. The desktop shell and
  # the Windows-only maka-service entry are not built.
  buildNoDefaultFeatures = true;
  cargoBuildFlags = [
    "-p"
    "maka-cli"
    "--bin"
    "maka"
    "-p"
    "maka-python-runtime"
    "--bin"
    "maka-python-worker"
  ];

  inherit npmDeps;

  nativeBuildInputs = [
    nodejs_24
    npmHooks.npmConfigHook
    pkg-config
    # libsqlite3-sys generates its bindings with bindgen, which needs libclang.
    rustPlatform.bindgenHook
  ];

  buildInputs = [
    openssl
    zstd
    # zed-font-kit links fontconfig and freetype.
    fontconfig
    freetype
    # Even without native-desktop, maka-cli links the terminal workbench, which
    # pulls in gpui's Linux backend; the linker needs these three libraries.
    libxcb
    libxkbcommon
  ];

  env = {
    RUSTY_V8_ARCHIVE = "/build/v8/librusty_v8.a";
    RUSTY_V8_SRC_BINDING_PATH = "/build/v8/src_binding.rs";
  };

  postUnpack = ''
    mkdir -p /build/v8
    tar -xzf ${v8} -C /build/v8
  '';

  # npmConfigHook has installed ./node_modules without lifecycle scripts, so
  # run the postinstall step that applies the repository's dependency patches.
  # maka-cli/build.rs runs `node products/maka/bundle/scripts/build.mjs` from
  # the source root, which resolves its npm packages from ./node_modules.
  #
  # deno_core records the JavaScript of its extensions (deno_webidl, deno_web)
  # by absolute source path and reads it again when the plugin VM starts, since
  # Maka does not use a startup snapshot. That path is inside the build
  # directory and is gone after the build, so the Host fails with "plugin VM:
  # VM is stopped". Embedding the files into the binary instead is deno_core's
  # other mode for the same macros.
  preBuild = ''
    node scripts/apply-dependency-patches.mjs

    substituteInPlace "$NIX_BUILD_TOP/cargo-vendor-dir/deno_core-0.413.0/extensions.rs" \
      --replace-fail '__extension_include_js_files_inner!(mode=loaded,' \
                     '__extension_include_js_files_inner!(mode=included,'
  '';

  doCheck = false;

  meta = {
    description = "Agent workspace that keeps a complete record of what it did (Apache Maka, rust-preview)";
    homepage = "https://github.com/apache/maka";
    license = lib.licenses.asl20;
    mainProgram = "maka";
    platforms = [ "x86_64-linux" ];
  };
}
