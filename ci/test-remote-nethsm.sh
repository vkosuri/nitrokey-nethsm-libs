#!/usr/bin/env bash
# Native client test. Only an existing operator and signing key are required.
set -euo pipefail
module=$(realpath "${1:?usage: test-remote-nethsm.sh LIBRARY [CONFIG_DIRECTORY]}")
config=$(realpath "${2:-/etc/nethsm-harness}")
export P11NETHSM_CONFIG_FILE="${P11NETHSM_CONFIG_FILE:-$config/p11nethsm.conf}"
token=$(cat "$config/token-label")
key=$(cat "$config/key-label")
fingerprint=$(cat "$config/certificate-sha256")
[[ -s $module && -s $P11NETHSM_CONFIG_FILE && -s $config/public.pem && -n $token && -n $key ]]
fail() { echo "FAIL: $*" >&2; exit 1; }

# The negative TLS test below relies on the configuration pinning exactly
# this fingerprint and never disabling certificate checks.
[[ $fingerprint =~ ^[0-9A-Fa-f:]{64,95}$ ]] || fail "$config/certificate-sha256 is not a SHA-256 fingerprint"
grep -qF -- "$fingerprint" "$P11NETHSM_CONFIG_FILE" ||
    fail "$P11NETHSM_CONFIG_FILE does not pin the fingerprint in $config/certificate-sha256"
if grep -Eiq 'danger_insecure_cert"?[[:space:]]*:[[:space:]]*true' "$P11NETHSM_CONFIG_FILE"; then
    fail "$P11NETHSM_CONFIG_FILE disables TLS certificate checks"
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
p11=(timeout 45 pkcs11-tool --module "$module")

# Each invocation opens the built library and initializes a fresh PKCS#11 client.
"${p11[@]}" --show-info
"${p11[@]}" --list-slots | tee slots
awk -v want="$token" '
    /^[[:space:]]*token label[[:space:]]*:/ {
        v = $0; sub(/^[^:]*:[[:space:]]*/, "", v); sub(/[[:space:]]+$/, "", v)
        if (v == want) found = 1
    }
    END { exit !found }' slots || fail "no slot presents token label '$token'"
"${p11[@]}" --token-label "$token" --list-mechanisms | tee mechanisms
grep -Eq '^[[:space:]]*SHA256-RSA-PKCS([,[:space:]]|$)' mechanisms ||
    fail "token '$token' does not offer SHA256-RSA-PKCS"

sign() { # CONFIG_FILE PIN_VARIABLE OUTPUT
    P11NETHSM_CONFIG_FILE=$1 "${p11[@]}" --token-label "$token" --login --pin "env:$2" \
        --sign --label "$key" --mechanism SHA256-RSA-PKCS --input-file challenge --output-file "$3"
}
expect_rejected() { # DESCRIPTION CONFIG_FILE PIN_VARIABLE
    local rc=0
    sign "$2" "$3" rejected.sig > rejected.log 2>&1 || rc=$?
    (( rc != 0 )) || fail "$1 was accepted"
    (( rc != 124 )) || fail "$1 timed out instead of being rejected"
    echo "Rejected as expected: $1 (exit $rc)"
}

# A pinned public key binds the successful response to the expected test key.
openssl rand -out challenge 32
NETHSM_HARNESS_PIN=$(cat "$config/operator-pin")
[[ -n $NETHSM_HARNESS_PIN ]]
export NETHSM_HARNESS_PIN
sign "$P11NETHSM_CONFIG_FILE" NETHSM_HARNESS_PIN signature
openssl dgst -sha256 -verify "$config/public.pem" -signature signature challenge

# The same request must fail when only the PIN or only the pinned
# certificate differs, proving both checks are enforced.
NETHSM_HARNESS_BAD_PIN=$(openssl rand -hex 16)
export NETHSM_HARNESS_BAD_PIN
expect_rejected 'login with a wrong operator PIN' "$P11NETHSM_CONFIG_FILE" NETHSM_HARNESS_BAD_PIN
unset NETHSM_HARNESS_BAD_PIN
bogus=$(printf '00:%.0s' {1..32}); bogus=${bogus%:}
sed "s|$fingerprint|$bogus|g" "$P11NETHSM_CONFIG_FILE" > wrong-tls-pin.conf
grep -qF -- "$fingerprint" wrong-tls-pin.conf && fail 'could not replace the pinned fingerprint'
expect_rejected 'a server certificate that does not match the pinned fingerprint' \
    "$tmp/wrong-tls-pin.conf" NETHSM_HARNESS_PIN
unset NETHSM_HARNESS_PIN

echo "PASS: token '$token' listed with SHA256-RSA-PKCS; verified remote signature; wrong PIN and wrong TLS pin rejected"
