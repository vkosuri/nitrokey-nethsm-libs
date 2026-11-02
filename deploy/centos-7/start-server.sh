#!/usr/bin/env bash
# Start (or with --restart, restart) nethsm-native.service on CentOS 7 and
# report the NetHSM API state. Run after install-server.sh.
#
# Usage: bash deploy/centos-7/start-server.sh [--restart]
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$here/../common/lib.sh"
show_help "$@"
require_os centos 7
exec bash "$here/../common/start-server.sh" "$@"
