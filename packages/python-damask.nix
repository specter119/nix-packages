{
  lib,
  buildPythonPackage,
  fetchurl,
  setuptools,
  pandas,
  numpy,
  scipy,
  h5py,
  vtk,
  matplotlib,
  pyyaml,
}:

buildPythonPackage (finalAttrs: {
  pname = "damask";
  version = "3.1.0";
  pyproject = true;

  src = fetchurl {
    url = "https://damask-multiphysics.org/download/damask-${finalAttrs.version}.tar.xz";
    hash = "sha256-0bploWeqsiHBPwA1B6uhf2Y8U6+U/BzUpHQIAIMp3vE=";
  };

  sourceRoot = "damask-${finalAttrs.version}/python";

  build-system = [ setuptools ];

  dependencies = [
    pandas
    numpy
    scipy
    h5py
    vtk
    matplotlib
    pyyaml
  ];

  pythonImportsCheck = [ "damask" ];

  meta = {
    description = "Pre- and post-processing tools for DAMASK";
    homepage = "https://damask-multiphysics.org";
    license = lib.licenses.agpl3Plus;
    platforms = lib.platforms.linux;
  };
})
