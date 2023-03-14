# create-ks-iso
Dynamically creates a STIG-compliant kickstart file with randomly-generated bootstrap user credentials for compliance testing in an automation pipeline. Includes options for creating custom install ISO images to enable non-interactive FIPS-compliant installations of RHEL-based Linux distributions.

## Overview
create-ks-iso is intended to be a simple, lightweight, dynamic solution to generate a STIG-compliant kickstart file and installer boot ISO image. Optionally, the user can create an OEMDRV ISO for delivering the kickstart file to the system installer; useful in environments where PXE boot or similar network delivery methods may not be available. Bootstrap user credentials may be either randomly-generated or specifically declared as required to fit operational needs. The kickstart file can be tailored at the point of generation. Default settings are easily changed either by editing the included [CONFIG_FILE](CONFIG_FILE) template or by setting environment variables at runtime, ideally allowing for use in automation pipelines.

### The Challenges of RHEL STIG Compliance
There are two aspects of RHEL STIG compliance efforts that realistically must be addressed at install time: 
1. Setting Federal Information Processing Standard (FIPS) 140-2 mode
2. Configuring whole-disk encryption

This project attempts to address both challenges.

#### FIPS Mode
While FIPS mode can be enabled after the OS install, it is [not the recommended practice](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/security_hardening/assembly_installing-a-rhel-8-system-with-fips-mode-enabled_security-hardening#proc_installing-the-system-with-fips-mode-enabled_assembly_installing-a-rhel-8-system-with-fips-mode-enabled) and can leave the system in an inconsistent state. Anecdotally, inspectors and auditors may ask for proof that the system was installed with FIPS enabled rather than switched on after an install. Therefore, where FIPS mode is required, it is recommended to create the modified boot ISO (set CREATEBOOTISO="true") option here and then use it to install the OS.

#### Whole-Disk Encryption
The RHEL 8 STIG introduced the *de facto* requirement that [all system partitions are encrypted](https://www.stigviewer.com/stig/red_hat_enterprise_linux_8/2021-06-14/finding/V-230224), unless *"...there is a documented and approved reason for not having data-at-rest encryption...."* 

Again, anecdotally, it's easier to comply with the STIG check than try to argue with an inspector or auditor about just what *"documented and approved"* means. 

Without a method to provide the encryption key/passphrase to unlock system partitions, the system will hang at boot waiting for the passphrase to be typed in at the console. If each individual partition is encrypted, then a passphrase must be entered for every one. This project provides a method of "baking in" the keyfile to auto-decrypt the system partitions without the need to set up a clevis/tang environment. By encrypting the LVM physical volume instead of the logical volumes, resize operations can occur while leaving disk encryption in place.

## Requirements
* A Linux system (RHEL/CentOS, Ubuntu, and WSL have all been tested successfully) with these packages installed:
    * bash v4+
    * genisoimage
    * git
    * isomd5sum
    * OpenSSH
    * syslinux
    * python
* When creating a custom boot ISO:
    * RHEL-based full install ISO, readable by the user running the script.
    * root/sudo permissions in order to mount the ISO image.
    * Sufficient disk space for ISO creation. Enough is needed for the source OEM install ISO, temporary space for the extracted OEM install ISO, and then the final custom boot ISO. Consider that RHEL 8 and 9 boot ISOs are between 9-12G in size, so plan on at least triple that.

## Installation
No installation is required, and this can be run directly from a user home directory.
To use create-ks-iso, simply clone the GitHub repository:
```
git clone https://github.com/chuckmilam/create-ks-iso
```
Once the repository is cloned, change into the project directory and run the script with default settings:
```
cd create-ks-iso
./create-ks-iso.sh
```
The default settings will generate a kickstart file (ks.cfg) in the current working directory, as well as some SSH keys in the "creds" directory. 
No ISOs are created unless the default settings are changed.

## Usage
create-ks-iso attempts to be flexible to fit various use cases. Some examples follow.

### Customize Script Settings
Variables can be set by editing the [CONFIG_FILE](CONFIG_FILE) directly, or by using environment variables. 

### Generate a kickstart file
To generate a kickstart file, simply run the script:
```
./create-ks-iso.sh
```
This command will generate a kickstart file in the current directory. Note FIPS mode is not enabled by default, and may not meet STIG compliance requirements.

### Generate an OEMDRV volume ISO
This ISO volume allows the kickstart file to be detected and run by the system installer with no manual intervention required. In the most common cases, the system install ISO is attached to the machine in the first CD/DVD drive. 
```Shell
CREATEOEMDRVISO="true" ./create-ks-iso.sh
```
Attach this OEMDRV ISO to the machine to be installed in a second CD/DVD drive and boot from the first CD/DVD drive. It should load and run the kickstart install automatically.

### Generate a Custom RHEL Boot ISO with FIPS mode enabled
Note the use of `sudo -E` to ensure the environment variables are passed into the sudo session.
```Shell
CREATEBOOTISO="true" ENABLEFIPS="true" sudo -E ./create-ks-iso.sh
```

### Sanitize the working directories
Run the sanitize script to remove any generated user credential, kickstart, and ISO files.
```Shell
./sanitize-create-ks-iso.sh
```
Be sure to specify the same configuration/environment variables if any were used to change default path names in the initial run of `create-ks-iso.sh`.

## Roadmap
Things to implement/improve:
- [ ] Make configurable as variables in ks.cfg:
    - [x] Disk partition sizes
    - [ ] NTP configuration
    - [ ] Network settings
- [ ] DOCKERFILE for portability
    - [ ] Investigate use of Docker .env file instead of CONFIG_FILE
- [ ] Complete CONFIG_FILE template with available variables
- [ ] STIG oscap/anaconda plugin logic based on OS distribution and version
- [x] Checks for required packages for ISO creation
- [ ] ksvalidator checks
- [ ] Change ntpserver kickstart statement per major OS version (8.x vs 9.x)
- [ ] Utilize "light" installer ISO for network-based installs
- [x] Option to create FIPS-enabled boot ISO without baked-in kickstart file
- [ ] Option to specify a different kickstart location (HTTP/S, NFS, etc.)

## History
This script harkens back to when I first started using kickstart around 2007-2008 to automate the deployment of 200+ Linux workstations where systems had to be wiped and redeployed frequently. Later, adding requirements for STIG compliance brought on additional challenges. The increased pace of rapid prototyping and testing helped streamline it further. Now I'm looking to use it for automated pipeline testing in places where containers don't quite make sense yet.

## Acknowledgments
This project utilized the following resources:
* [How to create a modified Red Hat Enterprise Linux ISO with kickstart file or modified installation media](https://access.redhat.com/solutions/60959)
* [Appendix B. Kickstart commands and options reference](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/performing_an_advanced_rhel_9_installation/kickstart-commands-and-options-reference_installing-rhel-as-an-experienced-user)
* [How to configure a keyfile in kickstart](https://access.redhat.com/solutions/4349431)
* [Configuring manual enrollment of LUKS-encrypted volumes using a TPM 2.0 policy](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/security_hardening/configuring-automated-unlocking-of-encrypted-volumes-using-policy-based-decryption_security-hardening#configuring-manual-enrollment-of-volumes-using-tpm2_configuring-automated-unlocking-of-encrypted-volumes-using-policy-based-decryption)
* [Making a Kickstart file available on a local volume for automatic loading](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/performing_an_advanced_rhel_9_installation/making-kickstart-files-available-to-the-installation-program_installing-rhel-as-an-experienced-user#making-a-kickstart-file-available-on-a-local-volume-for-automatic-loading_making-kickstart-files-available-to-the-installation-program)
* [DVD embedded Kickstart for RHEL 7 utilizing SCAP Security Guide (SSG) as a hardening script.](https://github.com/RedHatGov/ssg-el7-kickstart/blob/master/createiso.sh)
* [The ShellCheck plugin for Visual Studio Code](https://github.com/vscode-shellcheck/vscode-shellcheck)
