#!/usr/bin/env bash
# Install the NetHSM PKCS#11 client module and tools on Rocky Linux 8.
# Builds the module from source with deploy.sh, or unpacks a release tarball.
#
# Usage: [VAR=value ...] bash deploy/rockylinux-8/install-client.sh
#
#   CLIENT_TARBALL=<path>  install this nethsm-pkcs11-*-rockylinux-8-*.tar.gz instead of building
#   CLIENT_LIB=<path>      install location (default /usr/local/lib/nitrokey/libnethsm_pkcs11.so)
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$here/../common/lib.sh"
. "$here/../common/client.sh"
show_help "$@"
require_os rocky 8
log 'Installing PKCS#11 tools'
as_root dnf -y install opensc openssl curl tar
install_client rockylinux-8
