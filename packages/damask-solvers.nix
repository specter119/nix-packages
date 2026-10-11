{
  lib,
  stdenv,
  fetchurl,
  cmake,
  pkg-config,
  gfortran,
  petsc,
  hdf5-fortran-mpi,
  fftwMpi,
  libfyaml,
  zlib,
  boost,
}:

stdenv.mkDerivation (finalAttrs:
  let
    compilerIncludeFlags = lib.concatStringsSep " " [
      "-I${gfortran.cc}/lib/gcc/${stdenv.hostPlatform.config}/${gfortran.version}/include"
      "-I${hdf5-fortran-mpi.dev}/include"
      "-I${fftwMpi.dev}/include"
    ];
  in {
  pname = "damask-solvers";
  version = "3.1.0";

  src = fetchurl {
    url = "https://damask-multiphysics.org/download/damask-${finalAttrs.version}.tar.xz";
    hash = "sha256-0bploWeqsiHBPwA1B6uhf2Y8U6+U/BzUpHQIAIMp3vE=";
  };

  nativeBuildInputs = [
    cmake
    pkg-config
    gfortran
  ];

  buildInputs = [
    petsc
    hdf5-fortran-mpi
    hdf5-fortran-mpi.dev
    fftwMpi
    fftwMpi.dev
    libfyaml
    zlib
    boost
    boost.dev
  ];

  postPatch = ''
    substituteInPlace CMakeLists.txt \
      --replace-fail " -lz" " -lz -L${fftwMpi}/lib -lfftw3_mpi -lfftw3 -L${hdf5-fortran-mpi}/lib -lhdf5_hl_fortran -lhdf5_fortran -lhdf5_hl -lhdf5"
  '';

  cmakeBuildType = "Performance";
  cmakeFlags = [
    "-DGRID=ON"
    "-DMESH=ON"
    "-DTEST=OFF"
    "-DBoost_NO_BOOST_CMAKE=ON"
    "-DBOOST_INCLUDEDIR=${boost.dev}/include"
    "-DBOOST_LIBRARYDIR=${boost}/lib"
  ];

  preConfigure = ''
    cmakeFlagsArray=(
      $cmakeFlagsArray
      "-DCMAKE_C_FLAGS=${compilerIncludeFlags}"
      "-DCMAKE_CXX_FLAGS=${compilerIncludeFlags}"
      "-DCMAKE_Fortran_FLAGS=${compilerIncludeFlags}"
    )
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/damask_grid" --help
    "$out/bin/damask_mesh" --help
    runHook postInstallCheck
  '';

  meta = {
    description = "Grid and mesh solvers for DAMASK";
    homepage = "https://damask-multiphysics.org";
    license = lib.licenses.agpl3Plus;
    platforms = lib.platforms.linux;
  };
})
