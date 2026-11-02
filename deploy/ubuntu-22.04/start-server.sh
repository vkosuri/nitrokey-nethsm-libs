#!/usr/bin/env bash
# Start (or with --restart, restart) nethsm-native.service on Ubuntu 22.04 and
# report the NetHSM API state. Run after install-server.sh.
#
# Usage: bash deploy/ubuntu-22.04/start-server.sh [--restart]
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$here/../common/lib.sh"
show_help "$@"
require_os ubuntu 22.04
exec bash "$here/../common/start-server.sh" "$@"
