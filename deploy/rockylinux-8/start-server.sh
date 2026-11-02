#!/usr/bin/env bash
# Start (or with --restart, restart) nethsm-native.service on Rocky Linux 8 and
# report the NetHSM API state. Run after install-server.sh.
#
# Usage: bash deploy/rockylinux-8/start-server.sh [--restart]
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$here/../common/lib.sh"
show_help "$@"
require_os rocky 8
exec bash "$here/../common/start-server.sh" "$@"
