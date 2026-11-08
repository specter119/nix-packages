# Installer-log excerpts for the two failing component selections.
#
# Both were produced by driving the *original* offline media .sh, i.e. the same
# way packages/msc-marc/default.nix does it:
#
#   bash l_HPCKit_p_2024.2.0.635_offline.sh -a --silent --eula accept \
#     --components <SELECTION> --install-dir ... --log-dir ...
#
# Lines are verbatim; only the leading "MM/DD/YYYY HH:MM:SS:mmm : pid : " prefix
# was stripped.

================================================================================
[A] --components all  (HPCKit), network blocked
    reproduced with --proxy http://127.0.0.1:9 so the CDN probe fails the same
    way it does inside the Nix sandbox.
    full stdout: 01-components-all-offline.stdout.log
================================================================================

intel.oneapi.lin.compiler.fpga,v=2024.2.0+981, Enabled, Selected, Not Installed
MESSAGE : <ChecksumWorker>: Correct local source file is found: '.../packages/intel.oneapi.lin.compiler.fpga,v=2024.2.0+981/manifest.json'. Copying it to '.../downloadcache/intel.oneapi.lin.compiler.fpga,v=2024.2.0+981/manifest.json'.
MESSAGE : <ChecksumWorker>: Destination '.../downloadcache/intel.oneapi.lin.compiler.fpga,v=2024.2.0+981/dpcpp_compiler_post_install.sh' does not exist or checksum is incorrect. Check local source '.../packages/intel.oneapi.lin.compiler.fpga,v=2024.2.0+981/dpcpp_compiler_post_install.sh'.
DEBUG : <PayloadCollector>: download 'https://installer.repos.intel.com/oneapi/compiler/lin/intel.oneapi.lin.compiler.fpga,v=2024.2.0%2B981/cupPayload.cup' to '.../downloadcache/intel.oneapi.lin.compiler.fpga,v=2024.2.0+981/cupPayload.cup'.
DEBUG : DownloadManager check connection: [ERROR]
ERROR : DownloadManager stop execution due to connection error
MESSAGE : Cannot establish internet connection with current settings.
ERROR : Download failed.
MESSAGE : Failed to establish internet connection. Check your connection settings.
Installer completed with code 1

  -> the only payload missing from the offline kit is
     intel.oneapi.lin.compiler.fpga/cupPayload.cup (298756431 bytes).
     compiler.fpga is "type": "optional" in dpcpp-cpp-compiler's manifest.

================================================================================
[B] --components default  (BaseKit), 16.2 GB free in /tmp
    Captured on this machine while /tmp (tmpfs, 24 G) had 16.2 GB available.
    The check is a pure size computation, so the numbers are the whole story.
================================================================================

Error:
Failed to check prerequisites.
Not enough disk space. Drive /tmp has 16.2 GB available. 20.7 GB is required.
Please free up disk space or change the installation directory.
Installer completed with code 1

  -> `default` expands to VTune 1.7G + Advisor 1.2G + IPP 4.2G + DAL 2.0G
     + MKL 4.9G + DPC++ compiler 2.5G + oneDNN + FPGA 2.2G + ... = 20.7 GB.
     nix build's $TMPDIR is also on /tmp, so a sandboxed build hits the same
     limit.

================================================================================
[C] post-install fixup failure (independent of the component selection)
    See 04-fixup-audit-tmpdir.build.log
================================================================================

audit-tmpdir> RPATH of binary .../mpi/2021.13/bin/impi_info contains a forbidden reference to /build/
audit-tmpdir> Some binaries contain forbidden references to /build/. Check the error above!

  -> actual RPATH: $ORIGIN/../lib/release:/build/impi/_install/intel64/lib
     /build/impi/_install is Intel's own build path baked into their prebuilt
     MPI binaries; it only collides with Nix's $TMPDIR=/build by coincidence.
     Fixed with noAuditTmpdir = true.
