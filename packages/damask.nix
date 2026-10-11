{
  lib,
  symlinkJoin,
  damask-solvers,
  python-damask,
}:

symlinkJoin {
  pname = "damask";
  version = damask-solvers.version;
  paths = [
    damask-solvers
    python-damask
  ];

  meta = {
    description = "DAMASK crystal plasticity simulation package";
    homepage = "https://damask-multiphysics.org";
    license = lib.licenses.agpl3Plus;
    platforms = lib.platforms.linux;
  };
}
