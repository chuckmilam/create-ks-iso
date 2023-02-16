# create-ks-iso
A bash script for dynamically creating a STIG-compliant kickstart file with randomly-generated bootstrap user credentials. 
Includes options for creating custom install ISO images to enable non-interactive FIPS-compliant installations of RHEL-based Linux distributions.

## Overview
create-ks-iso is a simple script to generate a STIG-compliant kickstart file. Optionally, the user can choose create a custom boot ISO image as well as an OEMDRV ISO for delivering the kickstart file to the system installer; useful in environments where PXE boot or similar network delivery methods may not be available. Bootstrap user credentials may be either randomly-generated or specifically declared as required to fit operational needs. The script can be tailored with default settings easily changed by editing the included CONFIG_FILE template or by setting environment variables at runtime, making it possible to use in automation pipelines.

## History
This script has been around my tool back for a long time, going back to when I first started using kickstart around 2007-2008 to automate the deployment of over 200 Linux workstations in a training center where the systems had to be wiped and reinstalled frequently. Striving for STIG compliance brought additional challenges. Rapid prototyping and testing helped streamline it further. Now I'm looking to use it for automated pipeline testing.

## Features
* Dynamic STIG-compliant kickstart file generation
* Options to create ISOs
* Ability to choose between a variety of criteria, such as:
    * FIPS Mode on/off
    * Declared or random passwords/SSH keys

## Roadmap
Things to implement/improve:
- [ ] Variables in ks.cfg
    - [ ] disk partition sizes
    - [ ] NTP configuration
    - [ ] Network settings
- [ ] Complete CONFIG_FILE with available variables

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
    * Sufficient disk space for ISO creation. Enough is needed for the source OEM install ISO, temporary space for the extracted OEM install ISO, and then the final custom boot ISO. Consider that RHEL 8 and 9 boot ISOs are between 9-12G in size.

## Installation
No installation required, and can be run directly from a user home directory. 
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
This command will generate a kickstart file in the current directory. Note kickstart files generated with default settings will not enable FIPS mode.

### Generate a Custom RHEL Boot ISO with FIPS mode enabled
Using environment variables to override the default settings. Note the use of `sudo -E` to ensure the environment variables are passed into the sudo session.
```Shell
CREATEBOOTISO="true" ENABLEFIPS="true" sudo -E ./create-ks-iso.sh
```

## Acknowledgments
This project relied heavily on the following resources:
1.  [How to create a modified Red Hat Enterprise Linux ISO with kickstart file or modified installation media](https://access.redhat.com/solutions/60959)
2.  [Appendix B. Kickstart commands and options reference](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/performing_an_advanced_rhel_9_installation/kickstart-commands-and-options-reference_installing-rhel-as-an-experienced-user)
3.  [How to configure a keyfile in kickstart](https://access.redhat.com/solutions/4349431)
4.  [Configuring manual enrollment of LUKS-encrypted volumes using a TPM 2.0 policy](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/security_hardening/configuring-automated-unlocking-of-encrypted-volumes-using-policy-based-decryption_security-hardening#configuring-manual-enrollment-of-volumes-using-tpm2_configuring-automated-unlocking-of-encrypted-volumes-using-policy-based-decryption)
5. [The ShellCheck plugin for Visual Studio Code](https://github.com/vscode-shellcheck/vscode-shellcheck)
6. Coffee
7. Procrastination
