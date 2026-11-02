#!/usr/bin/env bash
# Deploy to remote machines over SSH, from your workstation or the harness client.
# For each host it detects the OS, copies this repository to the host and runs
# the matching deploy/<os>/ script there. You never pick the folder yourself.
#
# Usage: bash deploy/remote.sh ACTION [-e VAR=value]... [user@]host...
#
#   detect   print each host's OS, architecture and matching deploy folder
#   server   build, install and start the native NetHSM server (install-server.sh)
#   start    start the server service; add -e RESTART=1 to restart (start-server.sh)
#   client   install the PKCS#11 module and tools (install-client.sh). A local
#            -e CLIENT_TARBALL=<file> is uploaded and installed instead of building.
#   -e VAR=value   setting for the remote script (see deploy/README.md); repeatable
#
# Examples:
#   bash deploy/remote.sh detect admin@hsm-centos7.lab admin@hsm-rocky8.lab admin@hsm-ubuntu22.lab
#   bash deploy/remote.sh server -e NETHSM_REF=v5.0 -e SSH_ACCOUNT=labrunner admin@hsm-rocky8.lab
#   bash deploy/remote.sh client admin@app01.example.org
#
# SSH uses your ~/.ssh/config, keys and host-key checks. The remote account needs
# sudo; when you run this from a terminal you are prompted for a sudo password if
# the host asks for one. Files go to ~/nethsm-libs on each host (set REMOTE_DIR).
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$here/.." && pwd)
remote_dir=${REMOTE_DIR:-nethsm-libs}

usage() { sed -n '2,/^set -/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//'; exit "${1:-0}"; }
[[ $# -ge 1 ]] || usage 2
case $1 in -h|--help) usage ;; detect|server|start|client) action=$1 ;; *) echo "Unknown action: $1" >&2; usage 2 ;; esac
shift
settings=() hosts=()
while (( $# )); do
    case $1 in
        -e) [[ ${2:-} == [A-Z_]*=* ]] || { echo "-e needs VAR=value" >&2; exit 2; }; settings+=("$2"); shift 2 ;;
        -h|--help) usage ;;
        -*) echo "Unknown option $1" >&2; exit 2 ;;
        *) hosts+=("$1"); shift ;;
    esac
done
(( ${#hosts[@]} )) || { echo 'Name at least one [user@]host' >&2; exit 2; }
[[ $remote_dir =~ ^[A-Za-z0-9._/-]+$ ]] || { echo "REMOTE_DIR must be a simple path" >&2; exit 2; }

command -v ssh >/dev/null || { echo "ssh client not found; install openssh-client" >&2; exit 2; }
ssh_opts=(-o ConnectTimeout=15)
tty_opt=(); [[ -t 0 && -t 1 ]] && tty_opt=(-t)

# os_folder HOST: print the deploy/<os> folder for the host, or fail.
os_folder() {
    local info id version arch
    info=$(ssh "${ssh_opts[@]}" "$1" 'uname -m; . /etc/os-release; echo "$ID"; echo "$VERSION_ID"') || return 1
    { read -r arch; read -r id; read -r version; } <<<"$info"
    [[ $arch == x86_64 ]] || { echo "$1: unsupported architecture $arch" >&2; return 1; }
    case "$id:$version" in
        ubuntu:22.04) echo ubuntu-22.04 ;;
        rocky:8|rocky:8.*) echo rockylinux-8 ;;
        centos:7|centos:7.*) echo centos-7 ;;
        *) echo "$1: no deploy folder for $id $version (supported: Ubuntu 22.04, Rocky Linux 8, CentOS 7)" >&2; return 1 ;;
    esac
}

# upload HOST: copy the tracked repository files (and a local client tarball).
upload() {
    local files
    if (cd "$repo" && git rev-parse --is-inside-work-tree) >/dev/null 2>&1; then  # no git -C: CentOS 7 has git 1.8
        files=$(cd "$repo" && git ls-files -co --exclude-standard)
    else
        files=$(cd "$repo" && find . -type f ! -path './dist/*' ! -path './.git/*')
    fi
    (cd "$repo" && tr '\n' '\0' <<<"$files" | tar --null -T - -czf -) |
        ssh "${ssh_opts[@]}" "$1" "rm -rf '$remote_dir.new' && mkdir -p '$remote_dir.new' && tar -xzf - -C '$remote_dir.new' && rm -rf '$remote_dir' && mv '$remote_dir.new' '$remote_dir'"
    if [[ -n $local_tarball ]]; then
        ssh "${ssh_opts[@]}" "$1" "cat > '$remote_dir/$(basename "$local_tarball")'" < "$local_tarball"
    fi
}

local_tarball=
remote_settings=()
for s in "${settings[@]}"; do
    if [[ $action == client && $s == CLIENT_TARBALL=* && -f ${s#*=} ]]; then
        local_tarball=${s#*=}
        s="CLIENT_TARBALL=$(basename "$local_tarball")"  # relative to $remote_dir, where the script runs
    fi
    remote_settings+=("$(printf '%q' "$s")")
done

failed=() summary=()
for host in "${hosts[@]}"; do
    echo; echo "######## $host"
    if ! os=$(os_folder "$host"); then failed+=("$host"); summary+=("$host: OS detection failed"); continue; fi
    echo "$host runs $os"
    if [[ $action == detect ]]; then summary+=("$host: deploy/$os"); continue; fi
    case $action in
        server) script=install-server.sh args='' ;;
        client) script=install-client.sh args='' ;;
        start)  script=start-server.sh args=''
                for s in "${settings[@]}"; do [[ $s == RESTART=1 ]] && args=--restart; done ;;
    esac
    if upload "$host" &&
       ssh "${ssh_opts[@]}" "${tty_opt[@]}" "$host" \
           "cd '$remote_dir' && env ${remote_settings[*]} bash deploy/$os/$script $args"; then
        summary+=("$host: deploy/$os/$script succeeded")
    else
        failed+=("$host"); summary+=("$host: deploy/$os/$script FAILED")
    fi
done

echo; echo '######## Summary'
printf '%s\n' "${summary[@]}"
(( ${#failed[@]} == 0 ))
