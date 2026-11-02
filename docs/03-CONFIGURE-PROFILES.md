# 03 · Create three client profiles

On the Ubuntu client, run as the account that will execute the harness. Repeat the block for `centos-7`, `rockylinux-8` and `ubuntu-22.04`. Replace the example host, paths and labels with the corresponding server's values. The verified certificate and public key come from step 01.

```bash
target=centos-7
host=hsm-centos7.lab
port=8443
operator=harnessop
key_label=harnessrsa
profile=/etc/nethsm-harness/$target
sudo install -d -m 0700 -o "$(id -un)" -g "$(id -gn)" "$profile"
umask 077
printf '%s\n' "$operator" > "$profile/operator-user"
printf '%s\n' "$target" > "$profile/token-label"
printf '%s\n' "$key_label" > "$profile/key-label"
read -rsp 'NetHSM operator PIN: ' pin; echo
printf '%s\n' "$pin" > "$profile/operator-pin"
unset pin
install -m 0600 "/trusted/$target/public.pem" "$profile/public.pem"
openssl x509 -in "/trusted/$target/server-tls.pem" -noout -fingerprint -sha256 |
  cut -d= -f2 > "$profile/certificate-sha256"
```

For manual testing create a module configuration in the same profile. The token label names the client slot. The operator account determines which namespace and keys the session can access.

```bash
cat > "$profile/p11nethsm.conf" <<EOF
slots:
  - label: "$target"
    operator:
      username: "$operator"
    instances:
      - url: "https://$host:$port/api/v1"
        sha256_fingerprints:
          - "$(cat "$profile/certificate-sha256")"
EOF
openssl pkey -pubin -in "$profile/public.pem" -noout
```

Use a dedicated client account with no unrelated module configurations. In Actions, the harness generates its own configuration from these profile files, the SSH hostname and the environment's NetHSM port. The PIN stays on the client.

Next: [04 · Verify a PKCS#11 session](04-VERIFY-PKCS11.md).
