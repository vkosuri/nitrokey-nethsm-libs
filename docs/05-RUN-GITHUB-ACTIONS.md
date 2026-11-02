# 05 · Run the three-server harness in GitHub Actions

Start with three passing manual signatures from step 04. Register a dedicated self-hosted Linux x64 Actions runner on that **same Ubuntu 22.04 client**. Assign only that runner the custom label `nethsm-ubuntu22-client`. Its service account must read the three profiles, reach the servers over SSH and HTTPS, and install build dependencies noninteractively for `deploy.sh`.

Create one repository environment per server:

| Environment | Example `SSH_TARGET` variable |
| --- | --- |
| `nethsm-centos-7` | `labrunner@hsm-centos7.lab` |
| `nethsm-rockylinux-8` | `labrunner@hsm-rocky8.lab` |
| `nethsm-ubuntu-22.04` | `labrunner@hsm-ubuntu22.lab` |

Set `NETHSM_PORT` to the server's HTTPS port (default 8443). Add environment secrets `SSH_KEY` and `SSH_KNOWN_HOSTS` for the SSH identity and independently verified host-key entry. Restrict the environments to the default branch. On each server, `sudo bash server/install-native-unit.sh SSH_ACCOUNT` grants the SSH account noninteractive sudo for `systemctl start nethsm-native.service` only. The workflow uses the same hostname for SSH and HTTPS.

Once `.github/workflows/native-nethsm.yml` is on the default branch, run:

```bash
gh workflow run native-nethsm.yml --ref main
gh run list --workflow native-nethsm.yml --limit 3
gh run watch RUN_ID --exit-status
```

Replace `RUN_ID` with the new run's numeric ID. The first job builds the Ubuntu module once. Each server job checks the remote OS, starts the unit and waits up to `NETHSM_READY_TIMEOUT` seconds (default 120) for `/api/v1/health/state` to report `Operational` over a connection whose certificate matches the pinned fingerprint. A `Locked` or `Unprovisioned` instance fails immediately with the step to take. The job then runs the PKCS#11 harness from Ubuntu. Completion means the build and **all three server jobs** are green, with one verified signature per server. Services remain running after the test.

[Return to the numbered guide](00-START-HERE.md).
