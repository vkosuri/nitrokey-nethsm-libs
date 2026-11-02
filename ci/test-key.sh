#!/usr/bin/env bash
# Run inside the target OS sharing a fresh test simulator's network namespace.
set -euo pipefail
module=$(realpath "${1:?pass the staged shared library}")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
api=https://127.0.0.1:8443/api/v1
request=(curl -kfsS --connect-timeout 3 --max-time 60)
for ((i=0; i<30; i++)); do
    if "${request[@]}" "$api/health/state" > state; then break; fi
    sleep 1
done
grep -q '"Unprovisioned"' state
"${request[@]}" -H 'Content-Type: application/json' -X POST "$api/provision" \
    -d "{\"unlockPassphrase\":\"unlock-test-only\",\"adminPassphrase\":\"admin-test-only\",\"systemTime\":\"$(date -u +%FT%TZ)\"}"
"${request[@]}" -u admin:admin-test-only -H 'Content-Type: application/json' \
    -X PUT "$api/users/operator" -d '{"realName":"CI","role":"Operator","passphrase":"operator-test-only"}'

export P11NETHSM_CONFIG_FILE="$tmp/p11nethsm.conf"
cat > "$P11NETHSM_CONFIG_FILE" <<EOF
slots:
  - label: CI
    operator: {username: operator, password: operator-test-only}
    administrator: {username: admin, password: admin-test-only}
    instances:
      - url: $api
        danger_insecure_cert: true
EOF
p11=(pkcs11-tool --module "$module" --slot 0)
"${p11[@]}" --keypairgen --key-type rsa:2048 --label cikey --usage-sign --usage-decrypt
printf 'NetHSM artifact test\n' > message
"${p11[@]}" --sign --mechanism SHA256-RSA-PKCS --label cikey \
    --input-file message --output-file signature
"${p11[@]}" --read-object --type pubkey --label cikey --output-file public.der
openssl pkey -pubin -inform DER -in public.der -out public.pem
openssl dgst -sha256 -verify public.pem -signature signature message

# Encrypt binary input outside the module and decrypt it through PKCS#11.
printf '\000\377NetHSM\000payload\n' > plaintext
openssl pkeyutl -encrypt -pubin -inkey public.pem -pkeyopt rsa_padding_mode:pkcs1 \
    -in plaintext -out ciphertext
"${p11[@]}" --decrypt --mechanism RSA-PKCS --label cikey \
    --input-file ciphertext --output-file recovered
sha256sum plaintext | sed 's/  plaintext$/  recovered/' > expected.sha256
sha256sum -c expected.sha256

# Destroy the token key, then check visibility from a new session.
"${p11[@]}" --list-objects --type privkey > before-delete
grep -Eq 'label:[[:space:]]+cikey[[:space:]]*$' before-delete
"${p11[@]}" --delete-object --type privkey --label cikey
"${p11[@]}" --list-objects --type privkey > after-delete
if grep -Eq 'label:[[:space:]]+cikey[[:space:]]*$' after-delete; then
    echo 'Deleted private key is still visible in a new session' >&2
    exit 1
fi
