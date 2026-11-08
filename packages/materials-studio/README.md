# Materials Studio 2017

This package provides an FHS environment, not the proprietary application or a
license. Build the FHS environment from the repository root:

```sh
nix build .#materials-studio
```

Use your own legitimate, clean 2017 Linux installation media, mounted or
extracted outside the Nix store. Do not put license or crack files on the media
or in this repository or the Nix store. Install as a regular user into a new,
writable absolute path (whose parent already exists):

```sh
./result/bin/materials-studio install /absolute/path/to/media /absolute/path/to/installation
./result/bin/materials-studio run /absolute/path/to/installed/executable [arguments...]
./result/bin/materials-studio shell
```

The install command invokes the media's `install` with the non-root options
used by the original package. The installation remains mutable and outside the
Nix store; Nix does not manage or remove it. Consult the vendor's documentation
for the installed executable and external license server or license-file
configuration; supply that configuration at runtime, outside the store. The
wrapper passes environment variables through and does not provision licenses.

The installer, runtime dependencies, entry point and licensing have not been
verified without the proprietary media and a valid license. The FHS environment
also requires working unprivileged bubblewrap/user namespaces on the host.
