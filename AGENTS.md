# Working on nitrokey-nethsm-libs

This repository builds the Ubuntu PKCS#11 client module and tests it against three NetHSM server hosts. It also packages client modules for applications running on CentOS 7 and Rocky Linux 8. Use the [maintainer workflows](SKILLS.md) for task-specific commands and the [numbered lab guide](docs/00-START-HERE.md) for host setup.

## Preserve the lab topology

- Run the native harness on **one Ubuntu 22.04 x86-64 client**. Build the module once and exercise that same artifact against the CentOS 7, Rocky Linux 8 and Ubuntu 22.04 servers.
- Start the lab-supplied native service on the selected server. Run PKCS#11 initialization, slot discovery, login and signing on the Ubuntu client. PKCS#11 enters the local library; HTTPS connects the library to NetHSM.
- Keep the native lab and the disposable simulator separate. Use the simulator for tests that provision an instance, create or delete keys, or change server state. The native lab uses existing operator credentials and a distinct signing key on each server.
- Keep operator PINs, SSH identities and live profiles out of Git, workflow logs and build artifacts. Preserve SSH host-key checks and the per-server TLS certificate and public-key checks.

## Work and verify

1. Check `git status -sb`, `git worktree list` and the intended PR branch before editing. If files appear untracked on `main`, check whether the PR branch already tracks them before staging anything.
2. Change the existing entry point that owns the behavior. Build logic belongs in [ci/build-inside.sh](ci/build-inside.sh); [deploy.sh](deploy.sh) packages its output. The server unit and its installer live in [server/](server/). Native service startup and the readiness check belong in [ci/test-server-flavour.sh](ci/test-server-flavour.sh); PKCS#11 assertions belong in [ci/test-remote-nethsm.sh](ci/test-remote-nethsm.sh).
3. Test the affected path. Report the commit, targets exercised and observed result. Distinguish a simulator pass, a native server signature and a static check. If the lab is unavailable, record the untested targets.
4. For user-visible changes, update the matching numbered guide and the `Unreleased` section of [CHANGELOG.md](CHANGELOG.md). Update [README.md](README.md) when an entry point, supported target or release procedure changes.
