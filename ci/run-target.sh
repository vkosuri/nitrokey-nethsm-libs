#!/usr/bin/env bash
# Linux x86_64 Docker host, run from the repository root.
set -euo pipefail
image=${1:?pass a supported target image}
sim=$(docker run --rm -d nitrokey/nethsm:testing)
trap 'docker rm -fv "$sim" >/dev/null' EXIT
docker run --rm --network "container:$sim" -v "$PWD:/work" -w /work \
    -e SOURCE_DIR=/work/nethsm-pkcs11 -e TEST_KEY=1 "$image" bash deploy.sh
