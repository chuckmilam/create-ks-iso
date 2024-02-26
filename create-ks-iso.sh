#!/usr/bin/bash

### create-ks-iso.sh: A bash script for dynamically creating a STIG-compliant kickstart file with randomly-generated bootstrap user credentials.
### Project home: https://github.com/chuckmilam/create-ks-iso
### Author: @chuckmilam https://github.com/chuckmilam

# Show startup with timestamp on console
echo -e "$0: Starting at $(date)"

####################
## Meta Variables ##
####################

# Set default OS to RHEL
: "${OSTYPE:=RHEL}" # Default if not defined

# Major OS Version number
# ks.cfg command syntax varies between RHEL 8.x and 9.x
: "${MAJOROSVERSION:=9}" # Default if not defined

############################
## ISO Creation Variables ##
############################

# Source files for implantation into new ISO (ks.cfg, etc.)
# This needs to be an absolute path, not a relative path.
# Also serves as the base for all relative paths defined below.
SRCDIR="${SRCDIR:=${PWD}}" # Default is pwd

# Source CONFIG_FILE for variables
. "$SRCDIR"/CONFIG_FILE

# Output directory name
: "${OUTPUTDIR:=$SRCDIR/result}" # Default if not defined

# Create new full boot ISO
: "${CREATEBOOTISO:=false}" # Default if not defined

# Insert ks.cfg in boot ISO (Cases where second OEMDRV ISO may not be an option)
: "${KSINBOOTISO:=false}" # Default if not defined

# Create OEMDRV volume ISO
: "${CREATEOEMDRVISO:=false}" # Default if not defined

# OEMDRV volume ISO output directory
: "${OEMDRVDIR:=$OUTPUTDIR/oemdrv}" # Default if not defined

# OEMDRV ISO File Name
: "${OEMDRVISOFILENAME:=OEMDRV}" # Default if not defined

# Location for generated credentials
: "${CREDSDIR:=$OUTPUTDIR/creds}" # Default if not defined

# Source Media ISO Location
: "${ISOSRCDIR:=$SRCDIR/isosrc}" # Default if not defined

# ISO Result/Output Location
: "${ISORESULTDIR:=$OUTPUTDIR/iso}" # Default if not defined

# OEM Source Media File Name
#: "${OEMSRCISO:=rhel-9.2-x86_64-dvd.iso}" # Default if not defined

# New ISO file prefix
: "${NEWISONAMEPREFIX:=}" # Default if not defined

# File Name for newly-created final ISO file
: "${NEWISONAME:=$NEWISONAMEPREFIX$OEMSRCISO}" # Default if not defined

# Generated kickstart file name, default location is in $SRCDIR
: "${KSCFGSRCFILE:=ks.cfg}" # Default if not defined

# kickstart destination file name
# Best to not change this, some Red Hat internals look for this specific name
: "${KSCFGDESTFILENAME:=ks.cfg}" # Default if not defined

# kickstart file Result/Output Location
: "${KSRESULTDIR:=$OUTPUTDIR/ks}" # Default if not defined

# Kickstart file location passed to bootloader when KSINBOOTISO is set
# Default is on the ISO file, but could be a network locati
: "${KSLOCATION:=cdrom:\/ks.cfg}" # Default if not defined

# Temporary mount point for OEM Source Media
ISOMNTDIR="$SRCDIR/mnt"
ISOTMPMNT="$ISOMNTDIR/iso"

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

# Write SSH keys to files
: "${WRITESSHKEYS:=false}" # Default if not defined

##########################
# User Account Variables #
##########################

# Create two bootstrap accounts: One Ansible service account and 
# one "break glass" emergency admin account. In keeping with the design
# philosophy, additional accounts should be configured with the chosen
# system configuration tools (Ansible, etc.) after kickstart deployment.
# User uids and gids default to above 5000 per Red Hat recommended practice.

# Ansible Service Account
: "${username_01:=svc.ansible}" # Default if not defined
: "${username_01_gecos:=Ansible Service Account}" # Default if not defined
: "${username_01_uid:=5001}" # Default if not defined
: "${username_01_gid:=5001}" # Default if not defined

# "Break Glass" Emergency Admin Account
: "${username_02:=alt.admin}" # Default if not defined
: "${username_02_gecos:=Emergency Admin Account}" # Default if not defined
: "${username_02_uid:=5002}" # Default if not defined
: "${username_02_gid:=5002}" # Default if not defined

# Password length 
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
# NTP servers will be used
: "${USENTP:=true}" # Default if not defined
# NTP servers
: "${NTP_SERVERS:=0.us.pool.ntp.org 1.us.pool.ntp.org 2.us.pool.ntp.org 3.us.pool.ntp.org}" # Default if not defined

## Network Configuration Settings 
: "${NETWORK_ONBOOT:=true}" # Default if not defined
# Do not use IPV6 unless specifically requested
: "${USEIPV6:=false}" # Default if not defined

## Installer Behavior Options
# Disable interactive installer prompts
: "${FIRSTBOOT:=false}" # Default if not defined

########################
# Function Definitions #
########################

generate_random_passwd () {
  (passwd_len=$passwd_len openssl rand -base64 32 | tr -d /=+ | cut -c -"$passwd_len")
}

encrypt_random_passwd () {
  (openssl passwd -6 "$1") # SHA512 should be FIPS-compliant, also OK on non-FIPS systems
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
  if ! command -v "$1" &> /dev/null
  then
      echo "$1 is a required dependency and was not found. Exiting."
      exit 1
  fi
}

csv_format_options () {
  IFS=" " read -r -a CSV_ARRAY <<< "$1" # Safer method for expanding var in array
  # Initialize empty string
  csv_output=""
  # Iterate over each element in the array
  for element in "${CSV_ARRAY[@]}"
  do
      # Append the element to the csv_output string
      csv_output+="$element,"
  done
  # Remove trailing comma
  csv_output=${csv_output%,}
}

### Set required variables for ISO creation
## Ensure major OS type and major OS version number matches OEM ISO file
if [[ "$CREATEBOOTISO" = "true" || -n "$OEMSRCISO" ]]; then
  # Capture output from blkid and load into variables. ($LABEL needed for mkisofs later.)
  # ISO Volume Name must match or boot will fail
  eval "$(blkid -o export "$ISOSRCDIR"/"$OEMSRCISO")"
  OSTYPE=$(echo "$LABEL" | grep -oP '^(.*?)(?=\-)') # Match first text field, "-" as delimiter
  MAJOROSVERSION=$(echo "$LABEL" | grep -oP '(\d{1,2})' | head -n 1) # Match only first 1 or 2 digits, return only first result
  if [ -n "$OEMSRCISO" ]; then
    echo "$0: Source ISO OS is $OSTYPE $MAJOROSVERSION."
  fi
  if [ "$DEBUG" = "true" ]; then
    echo "$0: ===================================================="
    echo "$0: DEBUG: Values from blkid of $ISOSRCDIR"/"$OEMSRCISO:"
    echo "$0: DEBUG: DEVNAME=$DEVNAME"
    echo "$0: DEBUG: BLOCK_SIZE=$BLOCK_SIZE"
    echo "$0: DEBUG: UUID=$UUID"
    echo "$0: DEBUG: LABEL=$LABEL"
    echo "$0: DEBUG: TYPE=$TYPE"
    echo "$0: DEBUG: PTUUID=$PTUUID"
    echo "$0: DEBUG: PTTYPE=$PTTYPE"
    echo "$0: ===================================================="
  fi
fi

## Set prefixes on new boot ISO file dynamically if not defined
if [ "$CREATEBOOTISO" = "true" ]; then
  if [ -z "$NEWISONAMEPREFIX" ]; then
    if [ "$ENABLEFIPS" = "true" ]; then
      NEWISONAMEPREFIX="FIPS-"
    fi
    if [ "$KSINBOOTISO" = "true" ]; then
      NEWISONAMEPREFIX+="Embedded-kickstart-"
    fi
    NEWISONAME=$NEWISONAMEPREFIX$OEMSRCISO
  fi
fi 

## Network Configuration Logic

# Start of network configuration line in ks.cfg
network_config="network" 
# Add options as defined by variables

if [ -n "$KS_HOSTNAME" ]; then
  # Get only hostname portion if using a FQDN
  short_hostname=${KS_HOSTNAME%%"."*}
  hostname_length=${#short_hostname}
  # Check hostname is not greater than 64 characters
  if [ "$hostname_length" -gt '64' ]; then
    echo "$0: kickstart limitation: Hostname cannot exceed 64 characters. Exiting."
    exit 1 
  fi
  network_config+=" --hostname $KS_HOSTNAME"
fi

# Enable network on boot
case $NETWORK_ONBOOT
  in true)
    network_config+=" --onboot yes"
    ;;
esac  

# Static IP or DHCP
if [ -n "$IPADDR" ]; then
  network_config+=" --bootproto static"
  network_config+=" --ip=$IPADDR"
  if [ -z ${NETMASK+x} ]; 
    then
    echo "$0: When using static IP, netmask must be defined. Exiting."
    exit 1 
  else
    network_config+=" --netmask=$NETMASK"
  fi
  if [ -n "$GATEWAY" ]; then
    network_config+=" --gateway=$GATEWAY"
  fi
  if [ -n "$DNS_SERVERS" ]; then
  # Get DNS servers into CSV format
  csv_format_options "$DNS_SERVERS"
  network_config+=" --nameserver=$csv_output"
  fi
else
network_config+=" --bootproto dhcp"
  case $USEIPV6
    in false)
      network_config+=" --noipv6"
      ;;
  esac
fi

## timezone kickstart command logic
# RHEL 8 and 9 both use the "timezone" command, but with different options
# Start of timezone configuration line in ks.cfg
timezone_config="timezone $TIMEZONE"

if [ "$HWCLOCKUTC" = "true" ]; then
  timezone_config+=" --utc"
fi

if [ "$USENTP" = "true" ]; then
  case $MAJOROSVERSION in
    8)
      csv_format_options "$NTP_SERVERS"
      timezone_config+=" --ntpservers=$csv_output"
      ;;
    9)
      IFS=" " read -r -a NTP_ARRAY <<< "$NTP_SERVERS" # Safer method for expanding var in array
        prefix="timesource  --ntp-server "
        for ((i=0; i<${#NTP_ARRAY[@]}; i++)); do
          NTP_ARRAY[i]=$prefix${NTP_ARRAY[$i]}
        done
      ;;
    esac
else
  if [ "$MAJOROSVERSION" = "8" ]; then
        timezone_config+=" --nontp"
  fi
fi

### Check for required permissions

if [ "$CREATEBOOTISO" = "true" ]; then
  # Check for required root privileges, needed to mount and extract OEM ISO
  if [ "$EUID" -ne 0 ]
    then echo "$0: In order to create the boot ISO, root privileges are required for the \"mount\" command. Please run with sudo or su."
    exit
  fi
fi

# Report install target
echo "$0: kickstart install target is $OSTYPE $MAJOROSVERSION."

### Check for required files and directories

# Create output location if it does not exist (check for either directory or symlink existence)
if [[ ! -d "$OUTPUTDIR" ]] && [[ ! -h "$OUTPUTDIR" ]]; then
  echo "$0: Output directory $OUTPUTDIR not found. Creating."
  mkdir -p "$OUTPUTDIR"
  chmod -R 750 "$OUTPUTDIR"
  echo -e "$0: Setting ownership of $OUTPUTDIR."
  chown "$SUDO_UID":"$SUDO_GID" "$OUTPUTDIR"
fi

if [ "$CREATEBOOTISO" = "true" ] || [ "$CREATEOEMDRVISO" = "true" ]; then
  # Create ISO Result Location if it does not exist (check for either directory or symlink existence)
    if [[ ! -d "$ISORESULTDIR" ]] && [[ ! -h "$ISORESULTDIR" ]]; then
    echo "$0: ISO result directory $ISORESULTDIR not found. Creating."
    mkdir -p "$ISORESULTDIR"
    chmod -R 750 "$ISORESULTDIR"
    echo -e "$0: Setting ownership of $ISORESULTDIR."
    chown "$SUDO_UID":"$SUDO_GID" "$ISORESULTDIR"
  fi
fi

if [ "$CREATEBOOTISO" = "true" ]; then
  # Exit if ISO source location does not exist, required for creation of bootable ISO
  # Note: Don't create this automatically to avoid potentially clobbering a large ISO store
  if [[ ! -d "$ISOSRCDIR" ]] && [[ ! -h "$ISOSRCDIR" ]]; then
    echo "$0: ISO source directory $ISOSRCDIR not found, please correct. Exiting."
    exit 1
  fi
  # Exit if ISO source file does not exist, required for creation of bootable ISO
  if [[ ! -f "$ISOSRCDIR/$OEMSRCISO" ]] ; then
    echo "$0: ISO source file $ISOSRCDIR/$OEMSRCISO not found, please correct. Exiting."
    exit 1
  fi
  # Check for temporary ISO mount point, create if needed
  if [[ ! -d "$ISOTMPMNT" ]] && [[ ! -h "$ISOTMPMNT" ]]; then
    echo "$0: ISO temporary mount point $ISOTMPMNT not found. Creating."
    mkdir -p "$ISOTMPMNT"
    chmod -R 750 "$ISOTMPMNT"
    echo -e "$0: Setting ownership of $ISOTMPMNT."
    chown -R "$SUDO_UID":"$SUDO_GID" "$ISOTMPMNT"
  fi
  # Check for scratch space directory, create if needed
  if [[ ! -d "$WORKDIR" ]] && [[ ! -h "$WORKDIR" ]]; then
    echo "$0: Scratch space directory $WORKDIR not found. Creating."
    mkdir -p "$WORKDIR"
    chmod -R 750 "$WORKDIR"
    echo -e "$0: Setting ownership of $WORKDIR."
    chown -R "$SUDO_UID":"$SUDO_GID" "$WORKDIR"
  fi
fi 

echo "$0: Required files and directory checks passed."

### Check for required packages
# Required to create grub bootloader password hashes
check_dependency grub2-mkpasswd-pbkdf2

# If passwords are not defined, they'll be generated with openssl, check for openssl
if [[ -z "$password" || -z "$password_username_01" || -z "$password_username_02" ]] ; then
  check_dependency openssl
fi

if [[ -z "$ssh_pub_key_username_01" || -z "$ssh_pub_key_username_02" ]] ; then
  check_dependency ssh-keygen
fi

# If ISOs are to be created, mkisofs is a dependency
if [ "$CREATEBOOTISO" = "true" ] || [ "$CREATEOEMDRVISO" = "true" ]; then
  check_dependency mkisofs
fi

# If the bootable ISO is to be created, check for required tools
if [ "$CREATEBOOTISO" = "true" ] ; then
  check_dependency blkid
  check_dependency isohybrid
  check_dependency implantisomd5
fi

# If kickstart validator checks are set, check for required package
if [ "$KSVALIDATOR_CHECKS" = "true" ] ; then
  check_dependency ksvalidator
fi

# Create directory for creds if required and does not exist
if [ "$WRITEPASSWDS" = "true" ] || [ "$WRITESSHKEYS" = "true" ]; then
  mkdir -p "$CREDSDIR"
fi

# Create directory for kickstart file if it does not exist
mkdir -p "$KSRESULTDIR"

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

# Warn if FIPS mode is set but CREATEBOOTISO is not set
if [ "$ENABLEFIPS" = "true" ] && [ "$CREATEBOOTISO" = "false" ]; then
  echo -e "$0:"
  echo -e "$0: *****************************************************************"
  echo -e "$0: * WARNING: FIPS mode set while CREATEBOOTISO is NOT set.        *" 
  echo -e "$0: * WARNING: Inconsistent FIPS checks will result unless:         *"
  echo -e "$0: * WARNING:  1. System is installed with modified boot ISO.      *"
  echo -e "$0: * WARNING:                    - OR -                            *"
  echo -e "$0: * WARNING:  2. System booted with 'fips=1' bootloader argument. *"
  echo -e "$0: *****************************************************************"
  echo -e "$0:"
fi

### Password Generation

# If passwords not defined, generate passwords of either $passwd_len or a default 16 characters using openssl
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
  echo "$0: Writing plaintext passwords to $CREDSDIR/"
  echo "$password" > "$CREDSDIR"/password.txt
  echo "$password_username_01" > "$CREDSDIR"/password_"${username_01}".txt
  echo "$password_username_02" > "$CREDSDIR"/password_"${username_02}".txt
  echo "$grub2_passwd" > "$CREDSDIR"/password_grub2.txt
  ;;
*)
    echo "$0: Plaintext passwords NOT written to $CREDSDIR/"
esac

# Whether generated or defined, encrypt the passwords using openssl with a FIPS-compliant cypher
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

### Write out header and append required lines to kickstart file

cat <<EOF > "$SRCDIR"/ks.cfg
#################################################
#  Basic Kickstart for STIG-Compliant Installs  #
#################################################
#
# This kickstart configuration defines a minimal foundation
# for STIG-compliant Red Hat-based OS distribution installations.  
# Project home: https://github.com/chuckmilam/create-ks-iso
#
# Main features: 
#   1. FIPS mode option
#   2. Disk encryption as required by RHEL STIG
#   3. STIG-required disk partitions
#   4. Separate /opt partition for required third-party compliance tools and agents
#   5. Dynamically-created bootstrap users credentials
#
# Design Philosopy: 
#   Only minimal system configurations are made here, those required
#   at install time. Further STIG compliance and system configuration
#   should be accomplished with Ansible or similar tools.
#  
# Assumptions: 
#   1. Support infrastucture such as clevis/tang systems are not available.
#   2. System will be a physical or VM system.
#
# Note:
#   Parentheticals such as: "(optional), (required)" refer to 
#   kickstart configuration requirements

## Begin kickstart config:

# Perform installation from the first optical drive on the system. (optional)
#   Use CDROM installation media, NOTE: This requires the full install DVD ISO. 
#   The netboot iso is only for pointing to a remote install repository.
cdrom

# Install method (optional) 
cmdline

EOF

if [ "$FIRSTBOOT" = "true" ]; then
cat <<EOF >> "$SRCDIR"/ks.cfg
# Initial Setup application starts the first time the system is booted. (optional)
#   If enabled, the initial-setup package must be installed in packages section.
#   This allows for network setup prompts at console, which requires interative user input.
firstboot --enabled

EOF
fi

cat <<EOF >> "$SRCDIR"/ks.cfg
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

# Configure network information for target system and activate network devices 
# in the installer environment (optional)
$network_config

# Set the system time zone (required)
$timezone_config
EOF

if [[ "$MAJOROSVERSION" -ge "9" ]] && [[ "$USENTP" = "true" ]]; then
  # Print array values one line at a time
  echo "# NTP Servers " >> "$SRCDIR"/ks.cfg
  for element in "${NTP_ARRAY[@]}"; do
    echo "$element" >> "$SRCDIR"/ks.cfg
  done
fi

if [[ "$MAJOROSVERSION" -ge "9" ]] && [[ "$USENTP" = "false" ]]; then
  echo "# NTP Not Used" >> "$SRCDIR"/ks.cfg
  echo "timesource --ntp-disable" >> "$SRCDIR"/ks.cfg
fi

cat <<EOF >> "$SRCDIR"/ks.cfg

##
##  Begin disk partition information
##

# Partition clearing information (optional)
# Initialize invalid partition tables, destroy disk contents with invalid partition tables.
# Required for EFI booting systems when using cmdline option, above. (optional)
zerombr
# Clear partitions and create default disklabels (optional)
# CAUTION: The --all switch by itself will clear ALL partitions on ALL drives, 
#          including network storage. Use with caution in mixed environments.
clearpart --initlabel --all

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
# Separate Disk Partitions and Filesystem Settings Required by STIG
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
logvol /var/log/audit  --fstype='xfs' --size=$LOGVOLSIZEVARLOGAUDIT --name=varlogaudit --vgname=vg00 --fsoptions='nodev'
# Third-party tools and agents require free space in /opt
logvol /opt  --fstype='xfs' --size=$LOGVOLSIZEOPT --name=opt --vgname=vg00 --fsoptions='nodev'

# Remember to remove/disable swap if hosting K8S, Elasticsearch, etc.
logvol swap  --$LOGVOLSIZESWAP --fstype='swap' --name=swap --vgname=vg00 
## End boot partition information

## Kickstart/anaconda addons
# STIG Requirement: Disable kdump
%addon com_redhat_kdump --disable
%end

EOF

# Each OpenSCAP addon section is slightly different depending on OSTYPE and MAJORVERSION
if [ "$APPLYOPENSCAPSTIG" = "true" ]; then
  case $OSTYPE in 
    RHEL)
      echo -e "$0: OpenSCAP DISA STIG settings for $OSTYPE $MAJOROSVERSION will be applied"
      echo "# Apply STIG Settings with OpenSCAP" >> "$SRCDIR"/ks.cfg
      case $MAJOROSVERSION in
        8)
          echo "%addon org_fedora_oscap" >> "$SRCDIR"/ks.cfg
        ;;
        9)
          echo "%addon org_redhat_oscap" >> "$SRCDIR"/ks.cfg
        ;;
        esac
      echo "content-type = scap-security-guide"                         >> "$SRCDIR"/ks.cfg
      echo "profile = xccdf_org.ssgproject.content_profile_stig"        >> "$SRCDIR"/ks.cfg
      echo "%end"  >> "$SRCDIR"/ks.cfg
      printf "\n" >> "$SRCDIR"/ks.cfg
    ;;
    CentOS)
      echo -e "$0: DISA does NOT provide a STIG for CentOS. Proceed with caution!"
      echo -e "$0: OpenSCAP DISA STIG settings for nearest RHEL version to $OSTYPE $MAJOROSVERSION will be attempted."
      echo "# Apply STIG Settings with OpenSCAP" >> "$SRCDIR"/ks.cfg
      echo "# NOTE: DISA does NOT provide an official STIG for CentOS. Proceed with caution!" >> "$SRCDIR"/ks.cfg
      case $MAJOROSVERSION in
        8)
          echo "%addon org_fedora_oscap"                              >> "$SRCDIR"/ks.cfg
        ;;
        9)
          echo "%addon org_redhat_oscap"                              >> "$SRCDIR"/ks.cfg
        ;;
        esac
      echo "content-type = scap-security-guide"                         >> "$SRCDIR"/ks.cfg
      echo "profile = xccdf_org.ssgproject.content_profile_stig"        >> "$SRCDIR"/ks.cfg
      echo "%end"  >> "$SRCDIR"/ks.cfg
      printf "\n" >> "$SRCDIR"/ks.cfg
    ;;
  esac  
fi


cat <<EOF >> "$SRCDIR"/ks.cfg
%packages
# Specify an entire environment to be installed as a line starting with the @^ symbols.
# Note: Only a single environment should be specified in the Kickstart file. 
# If more environments are specified, only the last specified environment is used.
# Define a minimal system environment
@^minimal-environment
# Initial Setup application starts the first time the system is booted, required
# when firstboot option is set above. 
initial-setup
# Provides 'needs-restarting,' used for post-install check if reboot required
dnf-utils
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

## Bootloader section
# Specify how the bootloader should be installed (required)
# This password hash must be generated by: grub2-mkpasswd-pbkdf2
EOF

case $ENABLEFIPS in
  true)
cat <<EOF >> "$SRCDIR"/ks.cfg
bootloader --append "fips=1" --iscrypted --password=$grub2_encrypted_passwd

EOF
  ;;
*)
cat <<EOF >> "$SRCDIR"/ks.cfg
bootloader --iscrypted --password=$grub2_encrypted_passwd

EOF
esac

cat <<EOF >> "$SRCDIR"/ks.cfg
# Set the system's root password (required)
rootpw --iscrypted $encrypted_password

# user (optional)
# User Notes: Users in group wheel can sudo and elevate. Direct root login is only allowed from console.
user --name=$username_01 --groups=wheel --gecos='$username_01_gecos' --uid=$username_01_uid --gid=$username_01_gid --password=$encrypted_password_username_01 --iscrypted
user --name=$username_02 --groups=wheel --gecos='$username_02_gecos' --uid=$username_02_uid --gid=$username_02_gid --password=$encrypted_password_username_02 --iscrypted

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

# Modify /etc/issue with provisioning information
cat >> /etc/issue << EOF_issue

INFO: This system was provisioned with kickstart. 
INFO: kickstart file generated using $0 by $USER at $(date).
INFO: Unless specified at the time of kickstart generation: 
INFO: User credentials, including passwords and SSH keys, were randomly generated.

WARNING: This system is in a minimal configuration state. 
WARNING: Further system configuration and security hardening is required.

Remove this message by updating the /etc/issue file.

EOF_issue

## Set password change date to yesterday, prevents SSH access issues once STIGs are applied
chage -d \$(date -d -1days +%Y-%m-%d) root
chage -d \$(date -d -1days +%Y-%m-%d) $username_01
chage -d \$(date -d -1days +%Y-%m-%d) $username_02

## Set up LUKS pv decryption unlock
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

### kickstart install target is: $OSTYPE $MAJOROSVERSION
### Generated with $0 by $USER at $(date)
EOF

# Run optional kickstart validator checks
if [ "$KSVALIDATOR_CHECKS" = "true" ] ; then
  if [ "$OSTYPE" = "RHEL" ] || [ "$KSINBOOTISO" = "CentOS" ]; then
    # Get list of supported kickstart versions from ksvalidator
    readarray -t ksvalidator_supported_versions < <(ksvalidator -l)
    # If ksvalidator supports our target version, run the checks (Use "RHEL" here regardless if target is CentOS)
    if [[ "${ksvalidator_supported_versions[*]}"  == *"RHEL$MAJOROSVERSION"* ]]; then
      echo "$0: Validating kickstart file $SRCDIR/ks.cfg with ksvalidator."
      ksvalidator -v RHEL"$MAJOROSVERSION" "$SRCDIR"/ks.cfg || { echo "$0: ksvalidator checks: FAILED. Exiting."; exit 1; }
      echo "$0: ksvalidator checks: PASSED."
    else
      echo "$0: This version of ksvalidator does not support $OSTYPE $MAJOROSVERSION. Exiting."; exit 1
  fi
      fi
fi

### Begin ISO modification section

if [ "$CREATEBOOTISO" = "true" ]; then
  # Mount OEM Install Media ISO
  mount -o ro "$ISOSRCDIR"/"$OEMSRCISO" "$ISOTMPMNT"

  # Extract the ISO image into a working directory
  echo -e "$0: Extracting $OEMSRCISO image into $WORKDIR at $(date)"
  shopt -s dotglob # Be sure to grab dotfiles also
  cp -aRf "$ISOTMPMNT"/* "$WORKDIR"

  # Unmount the OEM ISO
  umount "$ISOTMPMNT"

   ## Modify ISO boot menu and options

  # FIPS mode enabled, insert ks.cfg into boot ISO
  if [ "$ENABLEFIPS" = "true" ] && [ "$KSINBOOTISO" = "true" ]; then
    # Modify isolinux.cfg for FIPS mode and ks boot
    echo -e "$0: Setting FIPS mode and ks.cfg location in ISO bootloader (FIPS: ON, kickstart in ISO: ON)"
    sed -i "/rescue/!s/ quiet/ rd.fips fips=1 inst.ks=$KSLOCATION quiet/" "$WORKDIR"/isolinux/isolinux.cfg
    # Modify grub.cfg for FIPS mode and ks boot
    sed -i "/rescue/!s/ quiet/ rd.fips fips=1 inst.ks=$KSLOCATION quiet/" "$WORKDIR"/EFI/BOOT/grub.cfg
    # Modify isolinux.cfg menu title
    sed -i 's/menu label Install/menu label FIPS mode with kickstart Install/' "$WORKDIR"/isolinux/isolinux.cfg
    # Modify grub.cfg menu entries
    sed -i 's/Install/FIPS mode with kickstart Install/' "$WORKDIR"/EFI/BOOT/grub.cfg
    sed -i 's/Test/FIPS mode with kickstart Test/' "$WORKDIR"/EFI/BOOT/grub.cfg
    # Copy ks.cfg into working dir
    cp "$SRCDIR"/"$KSCFGSRCFILE" "$WORKDIR"/"$KSCFGDESTFILENAME"
  fi

  # No FIPS mode, insert ks.cfg into boot ISO
  if [ "$ENABLEFIPS" = "false" ] && [ "$KSINBOOTISO" = "true" ]; then
      # Modify isolinux.cfg ks boot, no FIPS mode
      echo -e "$0: Setting ks.cfg location in ISO bootloader (FIPS: OFF, kickstart in ISO: ON)"
      sed -i "/rescue/!s/ quiet/ inst.ks=$KSLOCATION quiet/" "$WORKDIR"/isolinux/isolinux.cfg
      # Modify grub.cfg for ks boot, no FIPS mode
      sed -i "/rescue/!s/ quiet/ inst.ks=$KSLOCATION quiet/" "$WORKDIR"/EFI/BOOT/grub.cfg
      # Modify isolinux.cfg menu title
      sed -i 's/menu label Install/menu label kickstart Install/' "$WORKDIR"/isolinux/isolinux.cfg
      # Modify grub.cfg menu entries to show RandomCreds
      sed -i 's/Install/kickstart Install/' "$WORKDIR"/EFI/BOOT/grub.cfg
      sed -i 's/Test/kickstart Test/' "$WORKDIR"/EFI/BOOT/grub.cfg
      # Copy ks.cfg into working dir
      cp "$SRCDIR"/"$KSCFGSRCFILE" "$WORKDIR"/"$KSCFGDESTFILENAME"
  fi

  # FIPS mode enabled, do not insert ks.cfg into boot ISO
  if [ "$ENABLEFIPS" = "true" ] && [ "$KSINBOOTISO" = "false" ]; then
      # Modify isolinux.cfg menu title
      echo -e "$0: Setting FIPS mode in ISO bootloader (FIPS: ON, kickstart in ISO: OFF)"
      sed -i 's/menu label Install/menu label FIPS mode Install/' "$WORKDIR"/isolinux/isolinux.cfg
      # Modify grub.cfg for FIPS mode
      sed -i '/rescue/!s/ quiet/ rd.fips fips=1 quiet/' "$WORKDIR"/EFI/BOOT/grub.cfg
      # Modify grub.cfg menu entries to show RandomCreds
      sed -i 's/Install/FIPS mode Install/' "$WORKDIR"/EFI/BOOT/grub.cfg
      sed -i 's/Test/FIPS mode Test/' "$WORKDIR"/EFI/BOOT/grub.cfg
  fi

  # Create new ISO  
  # Note, the relative pathnames in the arguments to mkisofs are required, as per the man page:
  # "The pathname must be relative to the source path..."
  # This is why we do the rather ugly "cd" into the working dir below.
  cd "$WORKDIR" || { echo "$0: Unable to change directory to $WORKDIR, exiting."; exit 1; }
  echo -e "$0: Building modified ISO image at $(date)."
  mkisofs -quiet -o ../$SCRATCHISONAME -b isolinux/isolinux.bin -J -R -l -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e images/efiboot.img -no-emul-boot -graft-points -joliet-long -V "$LABEL" .
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
  echo -e "$0: Cleaning up temporary files at $(date)"
  rm -rf "$WORKDIR"
  rm -rf "$SCRATCHDIR"
  rm -rf "$ISOMNTDIR"

  # Chown new ISO and other generated files (will be owned by root otherwise)
  echo -e "$0: Setting ownership of $ISORESULTDIR/$NEWISONAME"
  chown "$SUDO_UID":"$SUDO_GID" "$ISORESULTDIR"/"$NEWISONAME"
  if [[ -f "$ISORESULTDIR"/"$OEMDRVISOFILENAME".iso ]]; then
    chown "$SUDO_UID":"$SUDO_GID" "$ISORESULTDIR"/"$OEMDRVISOFILENAME".iso
  fi
  ## End Boot ISO Creation Section
fi

if [ "$CREATEOEMDRVISO" = "true" ]; then
  echo -e "$0: Creating $OEMDRVISOFILENAME.iso at $(date)"
  # Create OEMDRV scratch dir
  mkdir -p "$OEMDRVDIR"
  chown "$SUDO_UID":"$SUDO_GID" "$OEMDRVDIR"
  rm -f "$OEMDRVDIR"/"$KSCFGDESTFILENAME" # Remove old ks.cfg
  cp "$SRCDIR"/"$KSCFGDESTFILENAME" "$OEMDRVDIR"
  mkisofs -quiet -V OEMDRV -o "$ISORESULTDIR"/"$OEMDRVISOFILENAME".iso "$OEMDRVDIR"
  chown "$SUDO_UID":"$SUDO_GID" "$ISORESULTDIR"/"$OEMDRVISOFILENAME".iso
  rm -f "$OEMDRVDIR"/"$KSCFGDESTFILENAME" # Remove ks.cfg
  rm -rf "$OEMDRVDIR"
fi # End CREATEBOOTISO conditional

# Chown/chmod kickstart files, pasword files, and ssh keys
if [ -d "$CREDSDIR" ]; then
  echo -e "$0: Setting ownership and permissions on $CREDSDIR"
  chown "$SUDO_UID":"$SUDO_GID" "$CREDSDIR"
  chmod 700 "$CREDSDIR"
fi

if [ "$WRITEPASSWDS" = "true" ]; then
  echo -e "$0: Setting ownership and permissions of password files"
  chown "$SUDO_UID":"$SUDO_GID" "$CREDSDIR"/password*.txt
  chmod 600 "$CREDSDIR"/password*.txt
fi

if compgen -G "${CREDSDIR}/*id_rsa*" > /dev/null ; then
  echo -e "$0: Setting ownership of SSH key files"
  chown "$SUDO_UID":"$SUDO_GID" "$CREDSDIR"/*.id_rsa "$CREDSDIR"/*.pub
fi

echo -e "$0: Setting ownership of kickstart file"
chown "$SUDO_UID":"$SUDO_GID" "$SRCDIR"/"$KSCFGSRCFILE"
chmod 640 "$SRCDIR"/"$KSCFGSRCFILE"
echo -e "$0: Moving kickstart file to $KSRESULTDIR"
mv "$SRCDIR"/"$KSCFGSRCFILE" "$KSRESULTDIR"

# Let everyone know we're done here
echo -n "$0: Total run time: "
printf '%dd:%dh:%dm:%ds\n' $((SECONDS/86400)) $((SECONDS%86400/3600)) $((SECONDS%3600/60)) \ $((SECONDS%60))
echo -e "$0: Completed with exit code: $? at $(date)"
