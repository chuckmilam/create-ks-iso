# Create Kickstart and Installation ISOs

[![Container-based CI tests](https://github.com/chuckmilam/create-ks-iso/actions/workflows/create-ks-iso-ci.yml/badge.svg)](https://github.com/chuckmilam/create-ks-iso/actions/workflows/create-ks-iso-ci.yml)

`create-ks-iso.sh` generates a RHEL Kickstart configuration and can package it as a separate OEMDRV volume or embed it in a modified, bootable RHEL installation ISO. It is intended for repeatable bootstrap and provisioning workflows, including organizations that need to create their first Linux system from a Windows workstation.

The project provides configurable bootstrap accounts, optional generated credentials, FIPS-related installer boot settings, and LUKS encryption for the LVM physical volume. It is a starting point for provisioning, not a certification that an installed system meets a particular STIG or organizational policy. Review the generated Kickstart, credential handling, and installed system before deployment.

A common first-machine workflow is to build the installation media from a Windows workstation using WSL or containers, install a server or VM from that media, then use its bootstrap account to bring it under Ansible or another configuration-management system. Keep the matching credentials for initial access, then rotate or replace them as part of onboarding.

## Choose how to run it

| Environment | Suggested approach |
| --- | --- |
| Linux workstation | Run the script directly or use Docker/Podman. |
| Windows workstation without a Linux machine | Use Docker Desktop or WSL 2 with Docker/Podman. WSL is a Linux environment; follow the storage guidance below when building full ISOs. |
| CI pipeline | Use the container image and provide a licensed RHEL installation ISO when building a boot ISO. |

The container route avoids installing the project dependencies on the host. A full boot ISO still needs a RHEL installation DVD ISO and enough disk space for the source, extracted working files, and output.

## Requirements

### Native Linux

For direct script use, install the packages needed by the selected operation:

- Bash 4 or newer, Git, OpenSSH, and OpenSSL
- `genisoimage`, `grub2-tools-minimal`, `isomd5sum`, and `syslinux` for ISO creation
- `xorriso` for RHEL 10 and newer custom boot ISOs
- `mtools` for RHEL 10 and newer custom boot ISOs when enabling FIPS or embedding a Kickstart
- `pykickstart` when running `ksvalidator` checks

Creating a modified boot ISO also requires a readable RHEL full Installation (Binary DVD) ISO and root privileges to mount it. The DVD ISO includes BaseOS and AppStream for offline installation; the smaller Boot ISO requires access to installation repositories. See [RHEL 10 distribution of content](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html/10.0_release_notes/distribution).

### Docker or Podman

The repository includes a container image definition with the required packages. Building a modified boot ISO requires a privileged container so the script can mount the source ISO. Use only a source ISO and container image you trust.

### WSL storage planning

WSL 2 stores its Linux filesystem in an expanding `ext4.vhdx`. Deleting temporary files frees space inside Linux, but the Windows-side VHDX may remain at the larger size it reached during a build. Full ISO builds use substantial temporary space in the container-storage filesystem as well as output space.

For WSL builds:

1. Check both filesystems with `df -h / /mnt/d` (adjust the Windows drive mount as needed).
2. Put the final ISO output on the Windows filesystem, for example `/mnt/d/ISOs`, by setting `TEST_OUTPUT_BASE` when using the test script or mounting a Windows directory as the container output directory.
3. Keep generated passwords and private keys in a private Linux-side directory, not in a shared Windows output folder.
4. Allow at least three times the source ISO size free on the container-storage filesystem, plus the source ISO size and 1 GiB free on the output filesystem. This is a minimum; additional working room is prudent.

To compact a VHDX after cleanup, shut down WSL and compact the distribution's VHDX from Windows. This affects the WSL distribution, so do it only after closing work in all WSL distributions. See Microsoft's guide to [managing WSL disk space](https://learn.microsoft.com/en-us/windows/wsl/disk-space).

## Quick start

Clone the repository and generate a Kickstart:

```bash
git clone https://github.com/chuckmilam/create-ks-iso
cd create-ks-iso
./create-ks-iso.sh
```

By default, this writes `ks.cfg` in the current directory and generated SSH key pairs under `result/creds`. It does not create an installation ISO unless ISO creation is enabled. Review the generated files and protect the credential directory.

The container smoke tests can be run without a RHEL ISO:

```bash
./test-container-build.sh
```

To build and validate a modified ISO as well, see [Testing a full boot ISO](#testing-a-full-boot-iso).

## Usage

Set options in [`CONFIG_FILE`](CONFIG_FILE) or pass them as environment variables. The script supports generating a Kickstart, an OEMDRV ISO, a modified boot ISO, or a modified boot ISO with the Kickstart embedded.

### Generate a Kickstart

```bash
./create-ks-iso.sh
```

FIPS mode is disabled by default. Setting `ENABLEFIPS=true` changes generated Kickstart and boot ISO settings; install-time FIPS requires booting the installer with `fips=1`.

### Create a separate OEMDRV ISO

An OEMDRV ISO contains the Kickstart and can be attached alongside the RHEL installation ISO:

```bash
CREATEOEMDRVISO=true ./create-ks-iso.sh
```

Boot the machine from the installation ISO with the OEMDRV volume attached. Verify that your target installer release detects and uses the Kickstart as expected.

### Create a modified boot ISO

Place a RHEL full Installation ISO in `$SRCDIR/isosrc` (or set `ISOSRCDIR`), then run the script with permission to mount the source ISO:

```bash
CREATEBOOTISO=true ENABLEFIPS=true sudo -E ./create-ks-iso.sh
```

Use the embedded-Kickstart option when only one ISO can be attached:

```bash
CREATEBOOTISO=true KSINBOOTISO=true ENABLEFIPS=true \
  sudo -E ./create-ks-iso.sh
```

`sudo -E` preserves the selected environment variables. The bootloader entry on a FIPS-enabled modified ISO includes `fips=1`; the Kickstart separately configures the installed system. RHEL 10 and newer use `xorriso` to preserve the source ISO's GRUB and hybrid boot metadata.

### Use an existing Kickstart

To build an ISO without regenerating the Kickstart, set `USE_EXISTING_KSCFG=true`. By default, the script reads `ks.cfg` from `SRCDIR`; set `KSCFGSRCFILE` to another filename or path. The source file is preserved and copied to the output directory.

```bash
USE_EXISTING_KSCFG=true KSCFGSRCFILE=ks.cfg \
  CREATEBOOTISO=true KSINBOOTISO=true ENABLEFIPS=true \
  sudo -E ./create-ks-iso.sh
```

This mode requires either `CREATEBOOTISO` or `CREATEOEMDRVISO`. `ENABLEFIPS` changes boot ISO settings, not the supplied Kickstart; ensure the existing file contains the settings required for the intended installation.

### Credentials and sensitive files

Random passwords are used by default. Generated SSH key pairs are written to `CREDSDIR` (by default, `$OUTPUTDIR/creds`). Plaintext password files are not written unless `WRITEPASSWDS=true` is set. Those files include the root, bootstrap-user, and GRUB passwords. Use plaintext output only when needed for testing or initial access, store it somewhere private, and remove or rotate it after use.

The generated credentials are not embedded into the boot ISO. Keep the matching credential files from the same build if you need to log in to the installed system. When using a container, mount a private Linux-side directory for `CREDSDIR` and a separate output directory for the ISO.

### Clean generated files

Run the sanitizer to remove generated credentials, Kickstart, and ISO files:

```bash
./sanitize-create-ks-iso.sh
```

Use the same path-related configuration and environment variables as the original run. The sanitizer operates on the project's configured output locations; it does not securely erase files or shrink a WSL VHDX.

## Container usage

Build the image from the cloned repository:

```bash
podman build -t create-ks-iso .
```

For a full boot ISO build, mount the source ISO directory read-only and an output directory writable. With Podman, use `--privileged` for ISO mounting. This WSL/Linux example writes the ISO to the Windows `D:` drive:

```bash
mkdir -p /mnt/d/ISOs/create-ks-iso-output
mkdir -m 700 -p "$HOME/create-ks-iso-creds"

sudo podman run --rm --privileged \
  --volume /mnt/d/ISOs:/create-ks-iso/isosrc:ro,Z \
  --volume /mnt/d/ISOs/create-ks-iso-output:/create-ks-iso/result:Z \
  --volume "$HOME/create-ks-iso-creds:/create-ks-iso/creds:Z" \
  --env SUDO_UID="$(id -u)" \
  --env SUDO_GID="$(id -g)" \
  --env OEMSRCISO=rhel-10.2-x86_64-dvd.iso \
  --env CREATEBOOTISO=true \
  --env KSINBOOTISO=true \
  --env ENABLEFIPS=true \
  --env CREDSDIR=/create-ks-iso/creds \
  --env WRITEPASSWDS=true \
  create-ks-iso
```

Replace the example source ISO name with a file in `/mnt/d/ISOs`. If credentials are not needed, omit `WRITEPASSWDS=true`; generated SSH keys are still placed in the mounted credentials directory. Docker uses the same mounts and environment variables; use the corresponding Docker commands and ensure the engine permits privileged ISO mounting.

## Testing

### Container smoke tests

Run the image build, Kickstart validation, and OEMDRV ISO content checks:

```bash
./test-container-build.sh
```

### Testing a full boot ISO

Provide a licensed RHEL installation ISO. On a host using rootless Podman, use rootful Podman for the source ISO mount:

```bash
CONTAINER_ENGINE=podman \
CONTAINER_ENGINE_SUDO=true \
RHEL_SOURCE_ISO=/path/to/rhel-10.2-x86_64-dvd.iso \
./test-container-build.sh
```

The script writes results to a unique directory under `$HOME` by default. Choose another existing disk-backed output directory with `TEST_OUTPUT_BASE`. For WSL, direct the ISO output to the Windows filesystem, for example:

```bash
CONTAINER_ENGINE=podman \
CONTAINER_ENGINE_SUDO=true \
RHEL_SOURCE_ISO=/mnt/d/ISOs/rhel-10.2-x86_64-dvd.iso \
TEST_OUTPUT_BASE=/mnt/d/ISOs \
./test-container-build.sh
```

Full builds need at least three times the source ISO size free on `/` for container work files and the source ISO size plus 1 GiB free on the output filesystem. The script checks those locations; if your container engine stores images elsewhere, check that filesystem too. It rejects `/tmp`-style `tmpfs`/`ramfs` output, validates the generated Kickstart and OEMDRV ISO, then verifies the boot ISO checksum and embedded `ks.cfg`. The generated output is retained at the printed path; remove it after testing if it is not needed. CI runs only the container smoke tests and does not require a licensed RHEL ISO.

The test script defaults to not writing plaintext passwords. If you set `WRITEPASSWDS=true`, the generated password files are retained in the test output's `creds/` directory. Do not direct that output to a shared Windows folder if the credentials need to remain private; use the container workflow's separate `CREDSDIR` mount instead.

The RHEL 10.2 build path has been exercised against a DVD ISO: its generated Kickstart passed `ksvalidator`, and the modified ISO passed checksum and embedded-file checks. RHEL 8.8 and 9.3 images have also passed build and content validation. Booting an installer and completing an installation are separate checks and should be tested in a VM or on hardware before deployment.

## FIPS and encryption notes

FIPS behavior varies by RHEL release. For install-time FIPS, the installer must boot with the `fips=1` kernel argument; adding it only to the installed system's bootloader configuration is not equivalent. Red Hat recommends enabling FIPS during installation for RHEL 8 and 9. For RHEL 10, FIPS must be enabled during installation and post-installation switching is unsupported. Consult the current [RHEL 8](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/security_hardening/switching-rhel-to-fips-mode_security-hardening), [RHEL 9](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/security_hardening/switching-rhel-to-fips-mode_security-hardening), and [RHEL 10](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html/security_hardening/switching-rhel-to-fips-mode) Security Hardening Guides and the applicable STIG.

Applicable RHEL STIGs include requirements for protecting data at rest; criteria vary by STIG release. This project encrypts the LVM physical volume and configures a keyfile for automatic unlocking. Review the generated Kickstart and installed system against the current STIG and organization policy. The project does not itself certify a system as compliant.

## Roadmap

- [x] Generate Kickstart files and OEMDRV/boot ISOs
- [x] Support install-time FIPS boot options and embedded Kickstart
- [x] Run Kickstart validation and container smoke tests in CI
- [ ] Support network-hosted Kickstart delivery
- [ ] Add network-based installation using a smaller installer ISO
- [ ] Add a configuration option for non-STIG use cases
- [ ] Store generated credentials in a secrets vault or post-install workflow

## History

The project began as a way to automate repeat deployments of Linux workstations. PXE booting and Kickstart helped scale those deployments; later STIG requirements added install-time FIPS and disk-encryption considerations. The project now also supports containerized and CI-based testing for environments where a dedicated Linux build machine may not be available.

## Acknowledgments

- [How to create a modified Red Hat Enterprise Linux ISO with kickstart file or modified installation media](https://access.redhat.com/solutions/60959)
- [How to generate a SHA-2 hashed password compatible with `/etc/shadow`](https://access.redhat.com/solutions/221403)
- [Kickstart commands and options reference](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/performing_an_advanced_rhel_9_installation/kickstart-commands-and-options-reference_installing-rhel-as-an-experienced-user)
- [How to configure a keyfile in Kickstart](https://access.redhat.com/solutions/4349431)
- [Configuring manual enrollment of LUKS-encrypted volumes using a TPM 2.0 policy](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/security_hardening/configuring-automated-unlocking-of-encrypted-volumes-using-policy-based-decryption_security-hardening#configuring-manual-enrollment-of-volumes-using-tpm2_configuring-automated-unlocking-of-encrypted-volumes-using-policy-based-decryption)
- [Making a Kickstart file available on a local volume](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/performing_an_advanced_rhel_9_installation/making-kickstart-files-available-to-the-installation-program_installing-rhel-as-an-experienced-user#making-a-kickstart-file-available-on-a-local-volume-for-automatic-loading_making-kickstart-files-available-to-the-installation-program)
- [Dynamically adding network parameters to Kickstart](https://access.redhat.com/solutions/2973831)
- [DVD-embedded Kickstart for RHEL 7 using SCAP Security Guide](https://github.com/RedHatGov/ssg-el7-kickstart/blob/master/createiso.sh)
- [ShellCheck](https://github.com/koalaman/shellcheck)
