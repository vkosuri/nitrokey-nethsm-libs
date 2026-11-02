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
"${p11[@]}" --keypairgen --key-type rsa:2048 --label cikey --usage-sign
printf 'NetHSM artifact test\n' > message
"${p11[@]}" --sign --mechanism SHA256-RSA-PKCS --label cikey \
    --input-file message --output-file signature
"${request[@]}" -u operator:operator-test-only "$api/keys/cikey/public.pem" > public.pem
openssl dgst -sha256 -verify public.pem -signature signature message
