#!/usr/bin/env bash
# Native client test. Only an existing operator and signing key are required.
set -euo pipefail
module=$(realpath "${1:?usage: test-remote-nethsm.sh LIBRARY [CONFIG_DIRECTORY]}")
config=$(realpath "${2:-/etc/nethsm-harness}")
export P11NETHSM_CONFIG_FILE="${P11NETHSM_CONFIG_FILE:-$config/p11nethsm.conf}"
token=$(cat "$config/token-label")
key=$(cat "$config/key-label")
[[ -s $module && -s $P11NETHSM_CONFIG_FILE && -s $config/public.pem && -n $token && -n $key ]]
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
p11=(timeout 45 pkcs11-tool --module "$module")

# Each invocation opens the built library and initializes a fresh PKCS#11 client.
"${p11[@]}" --show-info
"${p11[@]}" --list-slots
"${p11[@]}" --token-label "$token" --list-mechanisms

# A pinned public key binds the successful response to the expected test key.
openssl rand -out challenge 32
NETHSM_HARNESS_PIN=$(cat "$config/operator-pin")
[[ -n $NETHSM_HARNESS_PIN ]]
export NETHSM_HARNESS_PIN
"${p11[@]}" --token-label "$token" --login --pin env:NETHSM_HARNESS_PIN --sign --label "$key" \
    --mechanism SHA256-RSA-PKCS --input-file challenge --output-file signature
unset NETHSM_HARNESS_PIN
openssl dgst -sha256 -verify "$config/public.pem" -signature signature challenge
echo "PASS: initialized module, inspected slots/tokens and mechanisms, verified remote signature"
