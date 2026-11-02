# Shared helpers for deploy/<os>/*.sh. Source this file; do not run it.
# shellcheck shell=bash
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

log() { printf '\n==> %s\n' "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

as_root() {
    if (( EUID == 0 )); then "$@"; else sudo "$@"; fi
}

# require_os ID VERSION: stop unless this host matches the folder's OS.
require_os() {
    local want_id=$1 want_version=$2 file=${OS_RELEASE_FILE:-/etc/os-release}
    [[ $(uname -m) == x86_64 ]] || die "x86-64 only (found $(uname -m))"
    # shellcheck disable=SC1090
    ID=$(. "$file"; echo "$ID"); VERSION_ID=$(. "$file"; echo "$VERSION_ID")
    [[ $ID == "$want_id" && ( $VERSION_ID == "$want_version" || $VERSION_ID == "$want_version".* ) ]] ||
        die "this script is for $want_id $want_version; this host is $ID $VERSION_ID. Use deploy/<your-os>/ instead."
}

# CentOS 7 is end of life: point yum at the frozen vault (same as ci/build-inside.sh).
centos7_vault_repos() {
    as_root sed -Ei -e 's|^mirrorlist=|#mirrorlist=|' \
        -e 's@^#baseurl=https?://mirror\.centos\.org/centos/(\$releasever|7)@baseurl=https://vault.centos.org/7.9.2009@' \
        /etc/yum.repos.d/CentOS-*.repo
}

# centos7_devtoolset: GCC 11 from Software Collections, for builds that need C11.
centos7_devtoolset() {
    centos7_vault_repos
    as_root yum -y install centos-release-scl
    centos7_vault_repos
    as_root yum -y --disablerepo=centos-sclo-sclo \
        --setopt='centos-sclo-rh.baseurl=https://vault.centos.org/7.9.2009/sclo/$basearch/rh/' \
        install devtoolset-11-gcc devtoolset-11-gcc-c++ devtoolset-11-make
    export PATH="/opt/rh/devtoolset-11/root/usr/bin:$PATH"
}


# show_help: print the calling script's header comment and exit on -h/--help.
show_help() {
    case ${1:-} in -h|--help) ;; *) return 0 ;; esac
    sed -n '2,/^set -/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//'
    exit 0
}
