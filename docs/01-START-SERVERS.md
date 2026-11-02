# 01 · Start each NetHSM server

On each server, inspect and start the lab's native unit:

```bash
. /etc/os-release
echo "$PRETTY_NAME"
systemctl cat nethsm-native.service
sudo systemctl start nethsm-native.service
systemctl is-active nethsm-native.service
sudo ss -lntp
```

Expect `active` and a listener on an address reachable from the Ubuntu client. Record the DNS name and HTTPS port. If the unit is missing, obtain the native runtime and its service definition from the lab owner before proceeding. For startup failures inspect `sudo journalctl -u nethsm-native.service -n 60`.

From a trusted administration machine with the lab CA or independently verified self-signed certificate, check the endpoint:

```bash
HOST=hsm-centos7.lab
PORT=8443
curl --fail --cacert /path/to/lab-trust.pem "https://$HOST:$PORT/api/v1/health/state"
```

Proceed when the state is `Operational`. Provision a fresh instance or unlock a locked instance through the lab's normal administrative procedure. [NetHSM administration](https://docs.nitrokey.com/nethsm/administration)

On each fresh dedicated lab instance, a trusted administrator can create the following test identity using nitropy with TLS trust configured. Repeat with the correct host and target each time. On an existing instance, reuse an authorized operator and key, respecting its namespace and tag policy.

```bash
target=centos-7
mkdir -p "$target"
nitropy nethsm --host "$HOST:$PORT" add-user --real-name "Harness operator" --role Operator --user-id harnessop
nitropy nethsm --host "$HOST:$PORT" generate-key --type RSA --length 2048 --mechanism RSA_Signature_PKCS1 --key-id harnessrsa
nitropy nethsm --host "$HOST:$PORT" get-key harnessrsa --public-key > "$target/public.pem"
openssl pkey -pubin -in "$target/public.pem" -noout
```

Use a different key pair on each server even if the labels match. Deliver each server's public PEM, independently verified server TLS certificate, and operator credentials to the client administrator. The PEM verifies signatures and the certificate authenticates the server endpoint. [Key operations](https://docs.nitrokey.com/nethsm/operation)

Next: [02 · Install the Ubuntu client](02-INSTALL-CLIENT.md).
