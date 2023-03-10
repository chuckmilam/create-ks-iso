#!/usr/bin/bash

### create-ks-iso.sh: A bash script for dynamically creating a STIG-compliant kickstart file with randomly-generated bootstrap user credentials.
#
### Author: @chuckmilam 
###         https://github.com/chuckmilam
#
### Project home: https://github.com/chuckmilam/create-ks-iso

# Show startup with timestamp on console
echo -e "$0: Starting at $(date)"

############################
## ISO Creation Variables ##
############################

# Source files for implantation into new ISO (ks.cfg, etc.)
# This needs to be an absolute path, not a relative path.
# Also serves as the base for all relative paths defined below.
SRCDIR="${SRCDIR:=${PWD}}" # Default is pwd

# Source CONFIG_FILE for variables
. "$SRCDIR/CONFIG_FILE"

# Create new full boot ISO
: "${CREATEBOOTISO:=false}" # Default if not defined

# Create OEMDRV volume ISO
: "${CREATEOEMDRVISO:=false}" # Default if not defined

# OEMDRV volume ISO source directory
: "${OEMDRVDIR:=$SRCDIR/oemdrv}" # Default if not defined

# OEMDRV ISO File Name
: "${OEMDRVISOFILENAME:=OEMDRV}" # Default if not defined

# Location for generated credentials
: "${CREDSDIR:=$SRCDIR/creds}" # Default if not defined

# Source Media ISO Location
: "${ISOSRCDIR:=$SRCDIR/isosrc}" # Default if not defined

# ISO Result/Output Location
: "${ISORESULTDIR:=$SRCDIR/result}" # Default if not defined

# OEM Source Media File Name
: "${OEMSRCISO:=CentOS-Stream-9-latest-x86_64-dvd1.iso}" # Default if not defined

# New ISO file prefix
: "${NEWISONAMEPREFIX:=Random_Creds-}" # Default if not defined

# File Name for newly-created final ISO file
: "${NEWISONAME:=$NEWISONAMEPREFIX$OEMSRCISO}" # Default if not defined

# Kickstart config file, locate in $SRCDIR
: "${KSCFGSRCFILE:=ks.cfg}" # Default if not defined

# Best to not change this, some Red Hat internals look for this specific name
: "${KSCFGDESTFILENAME:=ks.cfg}" # Default if not defined

# Temporary mount point for OEM Source Media
ISOTMPMNT="$SRCDIR/mnt/iso"

# No need to change this, not a permanent file
SCRATCHISONAME="NEWISO.iso"

# Ensure these directories are mounted where 4GB+ files are allowed, /tmp may not support this
SCRATCHDIR="$SRCDIR/tmp"
WORKDIRNAME="iso-workdir"
WORKDIR=$SCRATCHDIR/$WORKDIRNAME

###################################
# Credential Generation Variables #
###################################

# Write plaintext passwords to files
: "${WRITEPASSWDS:=false}" # Default if not defined

## User Account Variables
# Create two bootstrap accounts: One Ansible service account and 
# one "break glass" emergency admin account.

# Ansible Service Account
: "${username_01:=svc.ansible}" # Default if not defined
: "${username_01_gecos:=Ansible Service Account}" # Default if not defined 

# "Break Glass" Emergency Admin Account
: "${username_02:=alt.admin}" # Default if not defined
: "${username_02_gecos:=Emergency Admin Account}" # Default if not defined 

# Password length in bytes 
# Note: The python secrets module output is Base64 encoded, so on average each byte 
# results in approximately 1.3 characters. 
# Source: https://docs.python.org/3/library/secrets.html
: "${passwd_len:=16}" # Default if not defined

#######################
# Kickstart Variables #
#######################

## Logical volume sizes
# / filesystem logical volume size
: "${LOGVOLSIZEROOT:=4096}" # Default if not defined
# /tmp filesystem logical volume size
: "${LOGVOLSIZETMP:=2048}" # Default if not defined
# /home filesystem logical volume size
: "${LOGVOLSIZEHOME:=2048}" # Default if not defined
# /var filesystem logical volume size
: "${LOGVOLSIZEVAR:=8092}" # Default if not defined
# /var/log filesystem logical volume size
: "${LOGVOLSIZEVARLOG:=2048}" # Default if not defined
# /var/tmp filesystem logical volume size
: "${LOGVOLSIZEVARTMP:=2048}" # Default if not defined
# /var/log/audit filesystem logical volume size
# RHEL 8 STIG requires 10.0G of storage space for /var/log/audit
: "${LOGVOLSIZEVARLOGAUDIT:=10240}" # Default if not defined
# Third-party tools and agents require free space in /opt
: "${LOGVOLSIZEOPT:=8192}" # Default if not defined
# Swap defaults to OS recommended values
: "${LOGVOLSIZESWAP:=recommended}" # Default if not defined

## System Time Settings
# Timezone (required)
# NOTE: Timezone names are sourced from the python pytz.all_timezones list
: "${TIMEZONE:=America/Chicago}" # Default if not defined
# System assumes the hardware clock is set to UTC (Greenwich Mean) time
: "${HWCLOCKUTC:=true}"
# NTP servers as they should show in the ks.cfg file
: "${NTP_SERVERS:=0.us.pool.ntp.org,1.us.pool.ntp.org,2.us.pool.ntp.org,3.us.pool.ntp.org}"
# This is either --utc for system hwclock set to utc, or empty for not.
: "${UTCSWITCH:=--utc}"

########################
# Function Definitions #
########################

generate_random_passwd () {
  (passwd_len=$passwd_len python3 -c 'import os; import sys; import secrets; import string; print("".join(secrets.token_urlsafe(int(os.environ["passwd_len"]))))')
}

encrypt_random_passwd () {
  (python3 -c "import crypt,getpass; print(crypt.crypt('$1', crypt.mksalt(crypt.METHOD_SHA512)))") # SHA512 should be FIPS-compliant, also OK on non-FIPS systems
}

generate_ssh_keys () { 
  case $ENABLEFIPS in
  true)
    ssh-keygen -t ecdsa-sha2-nistp521 -b 521 -N "" -f "$CREDSDIR"/"${1}".id_rsa -q -C "${1} kickstart-generated bootstrapping key" # FIPS-compatible 
    ;;
  *)
    ssh-keygen -N "" -f "$CREDSDIR"/"${1}".id_rsa -q -C "${1} kickstart-generated bootstrapping key" # Non-FIPS system defaults
  esac
}

check_dependency () {
  if ! command -v $1 &> /dev/null
  then
      echo "$1 is a required dependency and was not found. Exiting."
      exit 1
  fi
}

### Check for required files and directories

if [ "$CREATEBOOTISO" = "true" ]; then
  # Check for required root privileges, needed to mount and extract OEM ISO
  if [ "$EUID" -ne 0 ]
    then echo "$0: In order to create the boot ISO, this script need root privileges for the \"mount\" command. Please run with sudo or su."
    exit
  fi
fi

if [ "$CREATEBOOTISO" = "true" ] || [ "$CREATEOEMDRVISO" = "true" ]; then
  # Create ISO Result Location if it does not exist (check for either directory or symlink existence)
    if [[ ! -d "$ISORESULTDIR" ]] && [[ ! -h "$ISORESULTDIR" ]]; then
    echo "$0: ISO result directory $ISOSRCDIR not found. Creating."
    mkdir -p "$ISORESULTDIR"
    echo -e "$0: Setting ownership of $ISORESULTDIR."
    chown "$SUDO_UID":"$SUDO_GID" "$ISORESULTDIR"
  fi
fi

# Exit if ISO source location does not exist, required for creation of bootable ISO
# Note: Don't create this automatically to avoid potentially clobbering a large ISO store
if [ "$CREATEBOOTISO" = "true" ]; then
  if [[ ! -d "$ISOSRCDIR" ]] && [[ ! -h "$ISOSRCDIR" ]]; then
    echo "$0: ISO source directory $ISOSRCDIR not found, please correct. Exiting."
    exit 1
  fi
fi 

# Exit if ISO source file does not exist, required for creation of bootable ISO
if [ "$CREATEBOOTISO" = "true" ]; then
  if [[ ! -f "$ISOSRCDIR/$OEMSRCISO" ]] ; then
    echo "$0: ISO source file $ISOSRCDIR/$OEMSRCISO not found, please correct. Exiting."
    exit 1
  fi
fi

echo "$0: Required files and directory checks passed."

### Check for required packages

# If passwords are not defined, they'll be generated with python3
if [[ -z "$password" || -z "$password_username_01" || -z "$password_username_02" ]] ; then
  check_dependency python3
fi

if [[ -z "$ssh_pub_key_username_01" || -z "$ssh_pub_key_username_02" ]] ; then
  check_dependency ssh-keygen
fi

# If ISOs are to be created mkisofs is a dependency
if [ "$CREATEBOOTISO" = "true" ] || [ "$CREATEOEMDRVISO" = "true" ]; then
  check_dependency mkisofs
fi

# If the bootable ISO is to be created, check for required tools
if [ "$CREATEBOOTISO" = "true" ] ; then
  check_dependency blkid
  check_dependency isohybrid
  check_dependency implantisomd5
fi

# Create directory for creds if it does not exist
mkdir -p "$CREDSDIR"

## FIPS Mode Switch
: "${ENABLEFIPS:=false}" # Default if not defined

# Show if FIPS mode is enabled on console
case $ENABLEFIPS in
  true)
    echo -e "$0: FIPS mode is ENABLED."
  ;;
*)
    echo -e "$0: FIPS mode NOT enabled."
esac

### Password Generation

# If passwords not defined, generate passwords of either $passwd_len or a default 16 characters using python
# Change the number at the end of the python-one liner to set password length
: "${password:=$( generate_random_passwd )}" || { echo "$0: root password generation ERROR, exiting..."; exit 1; }
: "${password_username_01:=$( generate_random_passwd )}" || { echo "$0: $username_01 password generation ERROR, exiting..."; exit 1; }
: "${password_username_02:=$( generate_random_passwd )}" || { echo "$0: $username_02 password generation ERROR, exiting..."; exit 1; }

# grub2 bootloader password
: "${grub2_passwd:=$( generate_random_passwd )}" || { echo "$0: grub2 bootloader password generation ERROR, exiting..."; exit 1; }

# Remove any old password files
rm -f "$CREDSDIR"/password*.txt

case $WRITEPASSWDS in
  true)
  # Write passwords to files for testing/pipeline use 
  # Obviously insecure in the long run, change these if used on a long-lived system.
  echo "$0: Writing plaintext passwords to $CREDSDIR."
  echo "$password" > "$CREDSDIR"/password.txt
  echo "$password_username_01" > "$CREDSDIR"/password_"${username_01}".txt
  echo "$password_username_02" > "$CREDSDIR"/password_"${username_02}".txt
  echo "$grub2_passwd" > "$CREDSDIR"/password_grub2.txt
  ;;
*)
    echo "$0: Plaintext passwords NOT written to $CREDSDIR."
esac

# Whether generated or defined, encrypt the passwords using python with a FIPS-compliant cypher
encrypted_password=$( encrypt_random_passwd "$password" ) || { echo "$0: root password encryption ERROR, exiting..."; exit 1; }
encrypted_password_username_01=$( encrypt_random_passwd "$password_username_01"  ) || { echo "$0: $username_01 password encryption ERROR, exiting..."; exit 1; }
encrypted_password_username_02=$( encrypt_random_passwd "$password_username_02" ) || { echo "$0: $username_02 password encryption ERROR, exiting..."; exit 1; }

# Generate grub2 bootloader password, unfortunately the grub2-mkpasswd-pbkdf2
# command is interactive, so we have to emulate the keypresses:
grub2_encrypted_passwd=$(echo -e "$grub2_passwd\n$grub2_passwd" | grub2-mkpasswd-pbkdf2 | awk '/grub.pbkdf/{print$NF}') || { echo "$0: Grub password generation ERROR, exiting..."; exit 1; }

### SSH Key Generation
## Generated key pairs will be written to $CREDSDIR

if [[ -z "$ssh_pub_key_username_01" || -z "$ssh_pub_key_username_02" ]] ; then
  # Remove old randomly-generated ssh keys
  rm -f "$CREDSDIR"/*.id_rsa "$CREDSDIR"/*.pub
fi

if [[ -z "$ssh_pub_key_username_01" ]] ; then
  # Create ssh key pair for user 1 (Ansible Service Account)
  generate_ssh_keys "$username_01"
  ssh_pub_key_username_01=$(<"$CREDSDIR/${username_01}".id_rsa.pub)
  echo -e "$0: SSH keys for $username_01 created at $(date)"
fi

if [[ -z "$ssh_pub_key_username_02" ]] ; then
  # Create ssh key pairt for user 2 (Emergency Admin Account)
  generate_ssh_keys "$username_02"
  ssh_pub_key_username_02=$(<"$CREDSDIR/${username_02}".id_rsa.pub)
  echo -e "$0: SSH keys for $username_02 created at $(date)"
fi

# Generate a random disk encryption password
random_luks_passwd=$( generate_random_passwd )

# Allow luks auto-decryption for root pv.01
# This comes into play in the post section, also assumes /dev/sda3 is where the root pv will be
LUKSDEV="/dev/sda3"

################
# Main Section #
################

### Write out header and append required lines to kickstart file (ks.cfg)

cat << EOF > "$SRCDIR"/ks.cfg
#################################################
#  Basic Kickstart for STIG-Compliant Installs  #
#################################################
#
# This kickstart configuration defines the bare-minimum framework
# for STIG-compliant Red Hat-based OS distribution installations.  
# Project home: https://github.com/chuckmilam/stig-boot-iso
#
# Main features: 
#   1. FIPS mode option
#   2. Disk encryption as required by RHEL STIG
#   3. STIG-required disk partitions
#   4. Separate /opt partition for required third-party compliance tools and agents
#   5. Dynamically-created bootstrap users credentials
#
# Design Philosopy: 
#   Only minimal system configurations should be made here, those required at 
#   install time. Further STIG compliance should be accomplished with a 
#   system configuration tool such as Ansible.
#  
# Assumptions: 
#   1. PXE boot is NOT an option, requiring use of the ISOs.
#   2. Support infrastucture such as clevis/tang systems are not available.
#   3. System will be a physical or VM system.
#
# Note:
#   Parentheticals such as: "(optional), (required)" refer to 
#   kickstart configuration requirements

# Perform installation from the first optical drive on the system. (optional)
#   Use CDROM installation media, NOTE: This requires the full install DVD ISO. 
#   The boot iso is only for pointing to a remote install repository.
cdrom

# Install method (optional) 
#   Choices here are: graphical (Full GUI), text (TUI), or cmdline (non-interactive)
#   Use "text" below in order to be prompted for LUKS disk encryption passphrase during install
cmdline

# Configure network information for target system and activate network devices 
# in the installer environment (optional)
# --onboot      enable device at a boot time
# --device      device to be activated and / or configured with the network command
# --bootproto   method to obtain networking configuration for device (default dhcp)
# --noipv6      disable IPv6 on this device
#
# To use static IP configuration, "--bootproto=static" must be used. For example:
# network --bootproto=static --ip=10.0.2.15 --netmask=255.255.255.0 --gateway=10.0.2.254 --nameserver 192.168.2.1,192.168.3.1
network --onboot yes --bootproto dhcp --noipv6

# Initial Setup application starts the first time the system is booted. (optional)
#   If enabled, the initial-setup package must be installed in packages section.
#   This allows for network setup prompts at console, which requires interative user input.
# firstboot --enabled

# Agree to EULA (required)
eula --agreed

# Reboot after the installation is complete (optional)
#   --eject attempt to eject CD or DVD media before rebooting
reboot --eject

# Keyboard layouts (required)
keyboard --vckeymap=us --xlayouts=us

# System language (required)
lang en_US.UTF-8

# State of SELinux on the installed system (optional)
# Defaults to enforcing, which is required by STIG
selinux --enforcing

# Set the system time zone (required)
timezone $TIMEZONE $UTCSWITCH --ntpservers=$NTP_SERVERS

# Partition clearing information (optional)
# Initialize invalid partition tables, destroy disk contents with invalid partition tables.
# Required for EFI booting systems when using cmdline option, above. (optional)
zerombr
# Clear partitions and create default disklabels (optional)
# CAUTION: The --all switch by itself will clear ALL partitions on ALL drives, 
#          including network storage. Use with caution in mixed environments.
clearpart --initlabel --all

##
##  Begin disk partition information
##

# Ensure only sda is used for kickstart (optional)
# Without this, /boot ends up on disk 1 (usually sda), and 
# other system partitions end up on disk 2 (usually sdb)
ignoredisk --only-use=sda

# Automatically creates partitions required by the hardware platform. (optional)
# --add-boot - Creates a separate /boot partition in addition to the platform-specific 
# partition created by the base command. (optional)
#  NOTE: Boot partition cannot be encrypted (https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/system_design_guide/assembly_securing-rhel-during-installation-system-design-guide#Disk_partitioning_securing-rhel-during-installation)
reqpart --add-boot

# Create LVM Volume Group for base system. 
# Recommend a MINIMUM 30G of space for STIG and third-party tool requirements.
volgroup vg00 --pesize=4096 pv.01

# Create Logical Volumes
# Separate Disk Partitions Required by STIG
logvol /  --fstype='xfs' --size=$LOGVOLSIZEROOT --name=root --vgname=vg00 
# Ensure /tmp Located On Separate Partition
logvol /tmp  --fstype='xfs' --size=$LOGVOLSIZETMP --name=tmp --vgname=vg00 --fsoptions='nodev,noexec,nosuid'
# Ensure /home Located On Separate Partition
logvol /home  --fstype='xfs' --size=$LOGVOLSIZEHOME --name=home --vgname=vg00 --fsoptions='nodev,noexec'
# Ensure /var Located On Separate Partition
logvol /var  --fstype='xfs' --size=$LOGVOLSIZEVAR --name=var --vgname=vg00 --fsoptions='nodev'
# Ensure /var/log Located On Separate Partition
logvol /var/log  --fstype='xfs' --size=$LOGVOLSIZEVARLOG --name=varlog --vgname=vg00 --fsoptions='nodev'
# Ensure /var/tmp Located On Separate Partition
logvol /var/tmp  --fstype='xfs' --size=$LOGVOLSIZEVARTMP --name=vartmp --vgname=vg00 --fsoptions='nodev,noexec,nosuid'
# Ensure /var/log/audit Located On Separate Partition
logvol /var/log/audit  --fstype='xfs' --size=$LOGVOLSIZEVARLOGAUDIT--name=varlogaudit --vgname=vg00 --fsoptions='nodev'
# Third-party tools and agents require free space in /opt
logvol /opt  --fstype='xfs' --size=$LOGVOLSIZEOPT --name=opt --vgname=vg00 --fsoptions='nodev'

# Remember to remove/disable swap if hosting K8S, Elasticsearch, etc.
logvol swap  --$LOGVOLSIZESWAP --fstype='swap' --name=swap --vgname=vg00 
## End boot partition information

# STIG ID RHEL-08-10670: Disable kdump
%addon com_redhat_kdump --disable
%end

# Apply STIG Settings with OpenSCAP
# %addon com_redhat_oscap
# content-type = scap-security-guide
# profile = xccdf_org.ssgproject.content_profile_stig
# %end

%packages
# Specify an entire environment to be installed as a line starting with the @^ symbols.
# Note: Only a single environment should be specified in the Kickstart file. 
# If more environments are specified, only the last specified environment is used.
# Define a minimal system environment
@^minimal-environment
# Initial Setup application starts the first time the system is booted, required
# when firstboot option is set above. 
initial-setup
# STIG-required packages:
# With STIG oscap profile applied, login will fail unless tmux is installed
tmux
# Various package findings are mitigated with the following. Installed here because oscap
# calls yum to install STIG-required packages, but networking is not yet configured and 
# Red Hat subscriptions have not yet been registered:
audispd-plugins
aide
dnf-automatic
libcap-ng-utils
rsyslog-gnutls
policycoreutils-python-utils
chrony
usbguard
fapolicyd
rng-tools
python3
%end

EOF

## Bootloader section
cat << EOF >> "$SRCDIR"/ks.cfg
# Specify how the bootloader should be installed (required)
# This password hash must be generated by: grub2-mkpasswd-pbkdf2
EOF

case $ENABLEFIPS in
  true)
cat << EOF >> "$SRCDIR"/ks.cfg
bootloader --append "fips=1" --iscrypted --password=$grub2_encrypted_passwd

EOF
  ;;
*)
cat << EOF >> "$SRCDIR"/ks.cfg
bootloader --iscrypted --password=$grub2_encrypted_passwd

EOF
esac

cat << EOF >> "$SRCDIR"/ks.cfg
### Randomly-Generated Cred Section

# Set the system's root password (required)
rootpw --iscrypted $encrypted_password

# user (optional)
#   User Notes:
#     Users in group wheel can sudo and elevate
#     svc.ansible is initial provisioning account using SSH keys
#     alt.admin is "break glass" alternate emergency account
#     alt.admin can login remotely. 
#     Direct root login is only allowed from console.
user --name=$username_01 --groups=wheel --gecos='$username_01_gecos' --password=$encrypted_password_username_01 --iscrypted
user --name=$username_02 --groups=wheel --gecos='$username_02_gecos' --password=$encrypted_password_username_02 --iscrypted

# sshkey (optional)
# Adds SSH key to the authorized_keys file of the specified user
# sshkey --username=user "ssh_key"
sshkey --username=$username_01 "$ssh_pub_key_username_01"
sshkey --username=$username_02 "$ssh_pub_key_username_02"

# Create encrypted LVM pv with all available disk space
partition pv.01 --fstype='lvmpv' --grow --size=1 --encrypted --luks-version=luks2 --passphrase=$random_luks_passwd

%post
# Allow provisioning account to sudo without password for initial 
# systems configuration. Configure per policy once system is provisioned/deployed.
cat >> /etc/sudoers.d/provisioning << EOF_sudoers
### Allow these accounts sudo access with no password until system fully deployed ###
$username_01 ALL=(ALL) NOPASSWD: ALL
$username_02 ALL=(ALL) NOPASSWD: ALL
EOF_sudoers
chown root:root /etc/sudoers.d/provisioning
chmod 0440 /etc/sudoers.d/provisioning

# Create a [long] random key and place it in file
dd bs=512 count=4 if=/dev/urandom of=/crypto_keyfile.bin

# Add the keyfile as a valid unlock password for /
# NOTE: This string must match the passphrase used for the pv partition line above.
echo "$random_luks_passwd" | cryptsetup luksAddKey $LUKSDEV /crypto_keyfile.bin

# Configure dracut to include this keyfile in the initramfs
mkdir -p /etc/dracut.conf.d
echo 'install_items+=" /crypto_keyfile.bin "' > /etc/dracut.conf.d/include_cryptokey.conf

# Configure crypttab to look for the keyfile to auto-unlock all volumes (will use the version stored in the initramfs)
sed -i "s#\bnone\b#/crypto_keyfile.bin#" /etc/crypttab

# Rebuild the initramfs
dracut -f

# Lock everyone out of the keyfile
chmod 000 /crypto_keyfile.bin
%end

### Generated with $0 by $USER at $(date)
EOF

if [ "$CREATEBOOTISO" = "true" ]; then
  # ISO Volume Name must match or boot will fail
  OEMSRCISOVOLNAME=$(blkid -o value "$ISOSRCDIR"/$OEMSRCISO | sed -n 3p)

  # Create temporary mount point for OEM Source Media if it does not exist
  mkdir -p "$ISOTMPMNT"

  # Create scratch space directory
  mkdir -p "$WORKDIR"

  # Mount OEM Install Media ISO
  mount -o ro "$ISOSRCDIR"/"$OEMSRCISO" "$ISOTMPMNT"

  # Extract the ISO image into a working directory
  echo -e "$0: Extracting $OEMSRCISO image into $WORKDIR at $(date)"
  shopt -s dotglob # Be sure to grab dotfiles also
  cp -aRf "$ISOTMPMNT"/* "$WORKDIR"

  # Unmount the OEM ISO
  umount "$ISOTMPMNT"

  # Copy ks.cfg into working dir
  cp "$SRCDIR"/"$KSCFGSRCFILE" "$WORKDIR"/"$KSCFGDESTFILENAME"

  # Modify ISO boot menu and options
  case $ENABLEFIPS in
    true)
    # Modify isolinux.cfg for FIPS mode and ks boot
    sed -i '/rescue/!s/ quiet/ rd.fips fips=1 inst.ks=cdrom:\/ks.cfg quiet/' "$WORKDIR"/isolinux/isolinux.cfg
    # Modify isolinux.cfg menu title
    sed -i 's/menu title Red/menu title RandomCreds FIPS Kickstart Install Red/' "$WORKDIR"/isolinux/isolinux.cfg
    # Modify grub.cfg menu entries to show RandomCreds
    sed -i 's/Install/RandomCreds FIPS Install/' "$WORKDIR"/EFI/BOOT/grub.cfg
    sed -i 's/Test/RandomCreds FIPS Test/' "$WORKDIR"/EFI/BOOT/grub.cfg
    # Modify grub.cfg for ks boot
    sed -i '/rescue/!s/ quiet/ rd.fips fips=1 inst.ks=cdrom:\/ks.cfg quiet/' "$WORKDIR"/EFI/BOOT/grub.cfg
    ;;
  *)
    # Modify isolinux.cfg ks boot
    sed -i '/rescue/!s/ quiet/ inst.ks=cdrom:\/ks.cfg quiet/' "$WORKDIR"/isolinux/isolinux.cfg
    # Modify isolinux.cfg menu title
    sed -i 's/menu title Red/menu title RandomCreds Kickstart Install Red/' "$WORKDIR"/isolinux/isolinux.cfg
    # Modify grub.cfg menu entries to show RandomCreds
    sed -i 's/Install/RandomCreds Install/' "$WORKDIR"/EFI/BOOT/grub.cfg
    sed -i 's/Test/RandomCreds Test/' "$WORKDIR"/EFI/BOOT/grub.cfg
    # Modify grub.cfg for ks boot
    sed -i '/rescue/!s/ quiet/ inst.ks=cdrom:\/ks.cfg quiet/' "$WORKDIR"/EFI/BOOT/grub.cfg
  esac

  # Create new ISO  
  # Note, the relative pathnames in the arguments to mkisofs are required, as per the man page:
  # "The pathname must be relative to the source path..."
  # This is why we do the rather ugly "cd" into the working dir below.
  cd "$WORKDIR" || { echo "$0: Unable to change directory to $WORKDIR, exiting."; exit 1; }
  echo -e "$0: Building new ISO image at $(date)."
  mkisofs -quiet -o ../$SCRATCHISONAME -b isolinux/isolinux.bin -J -R -l -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e images/efiboot.img -no-emul-boot -graft-points -joliet-long -V "$OEMSRCISOVOLNAME" .
  cd "$SRCDIR" || { echo "$0: Unable to change directory to $SRCDIR, exiting."; exit 1; }

  # Build UEFI bootable image
  echo -e "$0: Making $SCRATCHISONAME UEFI bootable at $(date)"
  isohybrid --uefi "$SCRATCHDIR"/$SCRATCHISONAME 2> /dev/null # Suppress warning about more than 1024 cylinders

  # Implant a md5 checksum into the new ISO image
  echo -e "$0: Implanting MD5 checksum into $SCRATCHISONAME at $(date)"
  implantisomd5 "$SCRATCHDIR"/$SCRATCHISONAME

  # Move new iso to ISOs dir
  echo -e "$0: Moving new $SCRATCHISONAME to result directory and renaming to $NEWISONAME at $(date)"
  mv "$SCRATCHDIR"/$SCRATCHISONAME "$ISORESULTDIR"/"$NEWISONAME"

  # Clean up work directory
  echo -e "$0: Cleaning up $WORKDIR at $(date)"
  rm -rf "$WORKDIR"

  # Chown new ISO and other generated files (will be owned by root otherwise)
  echo -e "$0: Setting ownership of $ISOTMPMNT"
  chown "$SUDO_UID":"$SUDO_GID" "$ISOTMPMNT"
  echo -e "$0: Setting ownership of $ISORESULTDIR/$NEWISONAME"
  chown "$SUDO_UID":"$SUDO_GID" "$ISORESULTDIR"/"$NEWISONAME"
  if [[ -f "$ISORESULTDIR"/"$OEMDRVISOFILENAME".iso ]]; then
    chown "$SUDO_UID":"$SUDO_GID" "$ISORESULTDIR"/"$OEMDRVISOFILENAME".iso
  fi
  ## End Boot ISO Creation Section
fi

if [ "$CREATEOEMDRVISO" = "true" ]; then
  echo -e "$0: Creating $OEMDRVISOFILENAME.iso at $(date)"
  mkdir -p "$OEMDRVDIR"
  rm -f "$OEMDRVDIR"/"$KSCFGDESTFILENAME" # Remove old ks.cfg
  cp "$SRCDIR"/"$KSCFGDESTFILENAME" "$OEMDRVDIR"
  mkisofs -quiet -V OEMDRV -o "$ISORESULTDIR"/"$OEMDRVISOFILENAME".iso "$OEMDRVDIR"
  chown "$SUDO_UID":"$SUDO_GID" "$ISORESULTDIR"/"$OEMDRVISOFILENAME".iso
fi # End CREATEBOOTISO conditional

# Chown/chmod password files and ssh keys
chown "$SUDO_UID":"$SUDO_GID" "$CREDSDIR"

if [ "$WRITEPASSWDS" = "true" ]; then
  echo -e "$0: Setting ownership and permissions of password files"
  chown "$SUDO_UID":"$SUDO_GID" "$CREDSDIR"/password*.txt
  chmod 600 "$CREDSDIR"/password*.txt
fi

echo -e "$0: Setting ownership of ssh key files"
chown "$SUDO_UID":"$SUDO_GID" "$CREDSDIR"/*.id_rsa "$CREDSDIR"/*.pub
chmod 700 "$CREDSDIR"

# Notify we're done here
echo -n "$0: Total run time: "
printf '%dd:%dh:%dm:%ds\n' $((SECONDS/86400)) $((SECONDS%86400/3600)) $((SECONDS%3600/60)) \ $((SECONDS%60))
echo -e "$0: Completed with exit code: $? at $(date)"
