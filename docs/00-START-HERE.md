# 00 · Set up the NetHSM lab

One Ubuntu 22.04 x86-64 client loads one PKCS#11 library and signs a fresh challenge on each of three NetHSM servers. SSH starts the server service. PKCS#11 calls enter the Ubuntu library, which contacts the selected server over HTTPS.

| Server OS | Example DNS name | Harness target |
| --- | --- | --- |
| CentOS 7 | hsm-centos7.lab | `centos-7` |
| Rocky Linux 8 | hsm-rocky8.lab | `rockylinux-8` |
| Ubuntu 22.04 | hsm-ubuntu22.lab | `ubuntu-22.04` |

**Prerequisite:** Each server must already have a working native NetHSM runtime and systemd unit supplied by your lab. This repository builds the client module. Nitrokey documents appliance and software-container deployments. A client tarball alone cannot start a NetHSM server. [Upstream deployment options](https://docs.nitrokey.com/nethsm/)

Read in order:

1. [Start each server and prepare a signing key](01-START-SERVERS.md)
2. [Install libraries and tools on the Ubuntu client](02-INSTALL-CLIENT.md)
3. [Create a client profile for each server](03-CONFIGURE-PROFILES.md)
4. [Initialize PKCS#11 and verify a signature](04-VERIFY-PKCS11.md)
5. [Run the harness in GitHub Actions](05-RUN-GITHUB-ACTIONS.md)

Use the checkout containing the native harness workflow and scripts. The client tarball includes the binary and guides. The checkout supplies the test scripts.
