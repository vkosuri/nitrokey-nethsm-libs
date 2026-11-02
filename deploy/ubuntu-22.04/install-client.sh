#!/usr/bin/env bash
# Install the NetHSM PKCS#11 client module and tools on Ubuntu 22.04.
# Builds the module from source with deploy.sh, or unpacks a release tarball.
#
# Usage: [VAR=value ...] bash deploy/ubuntu-22.04/install-client.sh
#
#   CLIENT_TARBALL=<path>  install this nethsm-pkcs11-*-ubuntu-22.04-*.tar.gz instead of building
#   CLIENT_LIB=<path>      install location (default /usr/local/lib/nitrokey/libnethsm_pkcs11.so)
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$here/../common/lib.sh"
. "$here/../common/client.sh"
show_help "$@"
require_os ubuntu 22.04
log 'Installing PKCS#11 tools'
as_root apt-get update -qq
# python3 and openssh-client are for the harness client role (docs/02-INSTALL-CLIENT.md).
as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    opensc openssl ca-certificates curl tar python3 openssh-client
install_client ubuntu-22.04
