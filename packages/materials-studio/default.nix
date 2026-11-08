{
  lib,
  buildFHSEnv,
  writeShellScript,
}:

let
  launcher = writeShellScript "materials-studio" ''
    set -eu
    usage() {
      echo "Usage: materials-studio install MEDIA_DIR INSTALL_DIR | run EXECUTABLE [ARG...] | shell" >&2
      exit 2
    }
    [ "$#" -gt 0 ] || usage
    command=$1
    shift
    case "$command" in
      install)
        [ "$#" -eq 2 ] || usage
        case "$1:$2" in /*:/*) ;; *) echo "Both paths must be absolute" >&2; exit 2 ;; esac
        [ -f "$1/install" ] || { echo "No installer at $1/install" >&2; exit 1; }
        [ ! -e "$2" ] || { echo "Installation path already exists: $2" >&2; exit 1; }
        [ "$(id -u)" -ne 0 ] || { echo "Run the installer as a regular user" >&2; exit 1; }
        exec "$1/install" --nonroot --installroot="$2" --lproot="$2" \
          --user="$(id -un)" --group="$(id -gn)"
        ;;
      run)
        [ "$#" -gt 0 ] || usage
        case "$1" in /*) ;; *) echo "Executable path must be absolute" >&2; exit 2 ;; esac
        exec "$@"
        ;;
      shell)
        [ "$#" -eq 0 ] || usage
        exec bash
        ;;
      *) usage ;;
    esac
  '';
in
(buildFHSEnv {
  name = "materials-studio";
  version = "2017";
  runScript = launcher;
  targetPkgs = pkgs: with pkgs; [
    bash coreutils findutils gawk gnugrep gnused hostname perl procps util-linux which
    stdenv.cc.cc.lib zlib libxcrypt-legacy libGL libGLU
    libsm libice libx11 libxext libxi libxrender libxt
  ];
}).overrideAttrs (old: {
  meta = (old.meta or { }) // {
    description = "FHS environment for BIOVIA Materials Studio 2017";
    homepage = "https://www.3ds.com/products/biovia/materials-studio";
    license = lib.licenses.unfree;
    mainProgram = "materials-studio";
    platforms = [ "x86_64-linux" ];
  };
})
