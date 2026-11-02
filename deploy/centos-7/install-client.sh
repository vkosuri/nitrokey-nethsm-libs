#!/usr/bin/env bash
# Install the NetHSM PKCS#11 client module and tools on CentOS 7.
# Builds the module from source with deploy.sh, or unpacks a release tarball.
#
# Usage: [VAR=value ...] bash deploy/centos-7/install-client.sh
#
#   CLIENT_TARBALL=<path>  install this nethsm-pkcs11-*-centos-7-*.tar.gz instead of building
#   CLIENT_LIB=<path>      install location (default /usr/local/lib/nitrokey/libnethsm_pkcs11.so)
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$here/../common/lib.sh"
. "$here/../common/client.sh"
show_help "$@"
require_os centos 7
centos7_vault_repos
log 'Installing PKCS#11 tools'
as_root yum -y install opensc openssl curl tar
install_client centos-7
